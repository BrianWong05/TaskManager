// Data/SamplerActor.swift
// Dedicated actor performing all sampling serially off the main thread
// (spec §4.3): 1 s master tick, 5 s nettop sub-tick. Publishes one immutable
// ProcessSnapshot per tick to the @MainActor store — one hop per tick.

import Foundation
import OSLog

actor SamplerActor {
    static let tickInterval: TimeInterval = 1
    static let degradedTickInterval: TimeInterval = 2 // self-impact guard (§4.2)
    static let nettopEveryNTicks = 5 // 5 s sub-tick (spec §4.2)
    static let nettopFailureNoticeThreshold = 3 // spec §4.5
    /// Runaway detector, not a tuning knob: set clear of normal variance so it
    /// only fires on genuinely pathological sampling. Spec §4.2 holds the
    /// canonical measurements and reasoning behind 8 %/6 % — do not re-derive
    /// the numbers here, that duplication is how the copies diverged before.
    static let selfImpactBudgetPercent = 8.0
    /// Recovery mark, deliberately below the budget: dropping to 2 s lowers the
    /// measured percentage by itself, so recovering at the same number would
    /// flap between cadences.
    static let selfImpactRecoveryPercent = 6.0
    /// Ticks skipped at launch before the budget is judged (window setup).
    static let selfImpactWarmUpTicks = 15

    private let processCollector: any ProcessTableCollecting
    private let nettopCollector: any NettopCollecting
    private let systemCollector: any SystemMetricsCollecting
    private let elevatedDetailSource: (any ElevatedDetailSource)?
    private var reducer: ProcessTableReducer
    private var systemReducer = SystemMetricsReducer()
    private var running = false
    private var tickCount = 0
    /// Window hidden AND Mini monitor off: process-level sampling pauses
    /// while system-level sampling continues (spec §4.2).
    private var processSamplingPaused = false
    private var lastNet: [Int32: NetCounters]?
    private var nettopConsecutiveFailures = 0
    /// A detached nettop run is outstanding; prevents overlapping runs since
    /// one run outlives the 5 s sub-tick it was launched from.
    private var nettopSampleInFlight = false
    /// Net rates computed at each successful nettop tick against the real
    /// elapsed time (nettop runs every 5 s — dividing its deltas by the 1 s
    /// master dt would pulse the Network column at 5×, spec §4.2).
    private var netPrior: (counters: [Int32: NetCounters], usec: UInt64)?
    private var netRates: [Int32: (down: Double, up: Double)] = [:]
    private var currentInterval: TimeInterval = SamplerActor.tickInterval
    /// Self-impact bookkeeping: own cumulative CPU ns + timestamp.
    private var ownPriorCPU: (ns: UInt64, usec: UInt64)?
    private var overBudgetTicks = 0
    private var underBudgetTicks = 0
    /// Prior cumulative counters for daemon-filled cross-user rows (by pid).
    private var elevatedPrior: [Int32: (cpuNS: UInt64, diskRead: UInt64, diskWrite: UInt64, usec: UInt64)] = [:]

    init(processCollector: any ProcessTableCollecting = LibProcProcessCollector(),
         nettopCollector: any NettopCollecting = NettopCollector(),
         systemCollector: any SystemMetricsCollecting = SystemMetricsCollector(),
         elevatedDetailSource: (any ElevatedDetailSource)? = nil,
         reducer: ProcessTableReducer = ProcessTableReducer()) {
        self.processCollector = processCollector
        self.nettopCollector = nettopCollector
        self.systemCollector = systemCollector
        self.elevatedDetailSource = elevatedDetailSource
        self.reducer = reducer
    }

    /// One hop per tick publishes both snapshots (spec §4.3): the process
    /// table (nil while process sampling is paused, §4.2) and the system
    /// metrics frame feeding the Performance tab and the Mini monitor.
    func start(publish: @escaping @MainActor (ProcessSnapshot?, SystemSample?) -> Void) {
        guard !running else { return }
        running = true
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self, await self.isRunning else { break }
                await self.tick(publish: publish)
                let interval = await self.sleepInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        running = false
    }

    func setProcessSamplingPaused(_ paused: Bool) {
        processSamplingPaused = paused
    }

    var isRunning: Bool { running }
    var sleepInterval: TimeInterval { currentInterval }

    private func tick(publish: @escaping @MainActor (ProcessSnapshot?, SystemSample?) -> Void) async {
        tickCount += 1
        checkSelfImpactBudget()
        let now = Date()
        let nowUsec = now.wallUsec

        // Process-level section — paused when nothing is visible (spec §4.2).
        var snapshot: ProcessSnapshot? = nil
        if !processSamplingPaused {
            snapshot = await sampleProcesses(now: now, nowUsec: nowUsec)
        }

        // System metrics share the 1 s master tick and never pause (§4.2).
        let systemSample = systemReducer.update(
            cpu: systemCollector.cpuTicks(),
            memory: systemCollector.memory(),
            disk: systemCollector.diskTotals(),
            net: systemCollector.netTotals(),
            gpu: systemCollector.gpuUtilization(),
            upTimeSeconds: systemCollector.upTimeSeconds(),
            now: now
        )
        await publish(snapshot, systemSample)
    }

    /// The full process-table pipeline for one tick: nettop sub-tick,
    /// enumeration, reduction, net rates and the elevated batch fill.
    private func sampleProcesses(now: Date, nowUsec: UInt64) async -> ProcessSnapshot {
        // 5 s sub-tick: per-process network via nettop (spec §4.2).
        // nettop needs ~5 s of wall clock before it emits its first sample, so
        // it runs detached and its result is consumed later by
        // applyNettopSample. Awaiting it inline stalls every master tick — the
        // process table then never publishes at all (§4.2, §4.3).
        // ponytail: one blocked pool thread per run; the in-flight guard caps
        // it at one. Move to a dedicated queue if the pool ever starves.
        if tickCount % Self.nettopEveryNTicks == 1, !nettopSampleInFlight {
            nettopSampleInFlight = true
            let collector = nettopCollector
            Task.detached { [weak self] in
                let net = collector.sample()
                await self?.applyNettopSample(net)
            }
        }
        let samples = processCollector.sampleAll()
        var snapshot = reducer.update(
            samples: samples,
            net: lastNet,
            nowUsec: nowUsec,
            coreCount: processCollector.logicalCoreCount(),
            totalMemoryBytes: processCollector.totalMemoryBytes()
        )
        applyNetRates(&snapshot)
        // Base-first + batch fill (spec §4.4): one batched XPC round-trip
        // fills cross-user details when the daemon is available; otherwise
        // the base snapshot publishes as-is (degraded mode §6.4).
        if let elevatedDetailSource {
            snapshot = await fillElevatedDetails(snapshot,
                                                 source: elevatedDetailSource,
                                                 nowUsec: nowUsec)
        }
        snapshot.networkDegraded = nettopConsecutiveFailures >= Self.nettopFailureNoticeThreshold
        return snapshot
    }

    /// Consumes one detached nettop run. Rates are computed against the
    /// previous completed sample's timestamp — the true interval, which is
    /// nettop's own cost, not the master tick (spec §4.2).
    private func applyNettopSample(_ net: [Int32: NetCounters]?) {
        nettopSampleInFlight = false
        guard let net else {
            // Stale counters would fake activity: clear while failing;
            // the next sub-tick retries naturally (spec §4.5).
            lastNet = nil
            netRates = [:]
            nettopConsecutiveFailures += 1
            return
        }
        let nowUsec = Date().wallUsec
        if let prior = netPrior {
            let dtSeconds = max(Double(nowUsec - prior.usec) / 1_000_000, 0.001)
            var rates: [Int32: (down: Double, up: Double)] = [:]
            for (pid, counters) in net {
                if let before = prior.counters[pid],
                   counters.bytesIn >= before.bytesIn,
                   counters.bytesOut >= before.bytesOut {
                    rates[pid] = (down: Double(counters.bytesIn - before.bytesIn) / dtSeconds,
                                  up: Double(counters.bytesOut - before.bytesOut) / dtSeconds)
                } else {
                    rates[pid] = (down: 0, up: 0) // new or restarted process
                }
            }
            netRates = rates
        }
        netPrior = (net, nowUsec)
        lastNet = net
        nettopConsecutiveFailures = 0
    }

    /// Merge daemon details into cross-user rows: memory + command line
    /// directly; CPU/disk via deltas of the daemon's cumulative counters.
    private func fillElevatedDetails(_ snapshot: ProcessSnapshot,
                                     source: any ElevatedDetailSource,
                                     nowUsec: UInt64) async -> ProcessSnapshot {
        var snapshot = snapshot
        let gatedPids: [Int32] = allRecords(in: snapshot)
            .filter { $0.detailLevel == .requiresElevation }
            .map(\.pid)
        guard !gatedPids.isEmpty else {
            elevatedPrior.removeAll()
            return snapshot
        }
        let details = await source.details(for: gatedPids)
        guard !details.isEmpty else { return snapshot }

        var byPid: [Int32: TMProcessDetail] = [:]
        for detail in details { byPid[detail.pid] = detail }

        func merge(_ record: inout ProcessRecord) {
            guard let detail = byPid[record.pid] else { return }
            record.residentMemory = detail.residentMemory
            record.detailLevel = .elevated
            if let prior = elevatedPrior[record.pid], nowUsec > prior.usec {
                let dtSeconds = Double(nowUsec - prior.usec) / 1_000_000
                if detail.cpuNanoseconds >= prior.cpuNS {
                    record.cpuPercent = cpuPercent(
                        deltaNanoseconds: detail.cpuNanoseconds - prior.cpuNS,
                        overSeconds: dtSeconds)
                }
                if detail.diskBytesRead >= prior.diskRead {
                    record.diskReadRate = Double(detail.diskBytesRead - prior.diskRead) / dtSeconds
                }
                if detail.diskBytesWritten >= prior.diskWrite {
                    record.diskWriteRate = Double(detail.diskBytesWritten - prior.diskWrite) / dtSeconds
                }
            }
            elevatedPrior[record.pid] = (detail.cpuNanoseconds, detail.diskBytesRead,
                                         detail.diskBytesWritten, nowUsec)
            if !detail.commandLine.isEmpty {
                snapshot.elevatedCommandLines[record.pid] = detail.commandLine
            }
        }

        for index in snapshot.backgroundProcesses.indices {
            merge(&snapshot.backgroundProcesses[index])
        }
        for groupIndex in snapshot.groups.indices {
            for childIndex in snapshot.groups[groupIndex].children.indices {
                merge(&snapshot.groups[groupIndex].children[childIndex])
            }
        }
        // Drop prior counters for pids that no longer need filling.
        for pid in elevatedPrior.keys where byPid[pid] == nil {
            elevatedPrior.removeValue(forKey: pid)
        }
        return snapshot
    }

    /// Overwrites the reducer's placeholder net columns with rates computed
    /// over the true nettop interval; rows without counters show `–` (nil).
    private func applyNetRates(_ snapshot: inout ProcessSnapshot) {
        func apply(_ record: inout ProcessRecord) {
            if lastNet != nil, let rate = netRates[record.pid] {
                record.netDownRate = rate.down
                record.netUpRate = rate.up
            } else {
                record.netDownRate = nil
                record.netUpRate = nil
            }
        }
        for index in snapshot.backgroundProcesses.indices {
            apply(&snapshot.backgroundProcesses[index])
        }
        for groupIndex in snapshot.groups.indices {
            for childIndex in snapshot.groups[groupIndex].children.indices {
                apply(&snapshot.groups[groupIndex].children[childIndex])
            }
        }
    }

    private func allRecords(in snapshot: ProcessSnapshot) -> [ProcessRecord] {
        var records = snapshot.backgroundProcesses
        for group in snapshot.groups {
            records.append(contentsOf: group.children)
        }
        return records
    }

    // MARK: Self-impact budget (spec §4.2)

    /// Watches this app's own CPU share; sustained time over budget halves the
    /// master cadence to 2 s, and sustained time comfortably back under it
    /// restores 1 s.
    ///
    /// Both directions matter. This used to be a one-way latch that skipped the
    /// check once degraded, so the launch transient — SwiftUI building the
    /// window costs more than the budget for about the first ten ticks — pinned
    /// every session to 2 s permanently. The warm-up skip below stops that trip
    /// happening at all; recovery stops any later spike from being permanent.
    private func checkSelfImpactBudget() {
        // Launch transient: the first seconds are window construction, not
        // sampling, and measuring them tells us nothing about steady state.
        guard tickCount > Self.selfImpactWarmUpTicks else { return }
        var task = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let got = withUnsafeMutablePointer(to: &task) { ptr in
            proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, ptr, size)
        }
        let nowUsec = Date().wallUsec
        guard got == size else { return }
        let cpuNS = machTimeToNanoseconds(task.pti_total_user &+ task.pti_total_system)
        defer { ownPriorCPU = (cpuNS, nowUsec) }
        guard let prior = ownPriorCPU, nowUsec > prior.usec else { return }
        let dtSeconds = Double(nowUsec - prior.usec) / 1_000_000
        let ownPercent = cpuPercent(deltaNanoseconds: cpuNS - prior.ns,
                                    overSeconds: dtSeconds)
        if ownPercent > Self.selfImpactBudgetPercent {
            overBudgetTicks += 1
            underBudgetTicks = 0
        } else if ownPercent < Self.selfImpactRecoveryPercent {
            underBudgetTicks += 1
            overBudgetTicks = 0
        } else {
            // Between the recovery mark and the budget: hold the current
            // cadence. This gap is what stops 1 s and 2 s flapping, since
            // halving the cadence itself lowers the measured percentage.
            overBudgetTicks = 0
            underBudgetTicks = 0
        }

        if currentInterval == Self.tickInterval, overBudgetTicks >= 10 {
            currentInterval = Self.degradedTickInterval
            SamplerActor.logger.warning(
                "Sampler self-impact over \(Self.selfImpactBudgetPercent)% budget — cadence halved to \(Self.degradedTickInterval) s")
        } else if currentInterval == Self.degradedTickInterval, underBudgetTicks >= 10 {
            currentInterval = Self.tickInterval
            SamplerActor.logger.notice(
                "Sampler self-impact back under \(Self.selfImpactRecoveryPercent)% — cadence restored to \(Self.tickInterval) s")
        }
    }

    private static let logger = Logger(subsystem: "com.brianwong.taskmanager", category: "Sampler")
}

private extension Date {
    /// Wall-clock microseconds — the timestamp unit for all rate math here.
    var wallUsec: UInt64 { UInt64(timeIntervalSince1970 * 1_000_000) }
}
