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
    static let selfImpactBudgetPercent = 2.0    // spec §4.2

    private let processCollector: any ProcessTableCollecting
    private let nettopCollector: any NettopCollecting
    private let systemCollector: any SystemMetricsCollecting
    private let elevatedDetailSource: (any ElevatedDetailSource)?
    private var reducer: ProcessTableReducer
    private var systemReducer = SystemMetricsReducer()
    private var running = false
    private var tickCount = 0
    private var lastNet: [Int32: NetCounters]?
    private var nettopConsecutiveFailures = 0
    private var currentInterval: TimeInterval = SamplerActor.tickInterval
    /// Self-impact bookkeeping: own cumulative CPU ns + timestamp.
    private var ownPriorCPU: (ns: UInt64, usec: UInt64)?
    private var overBudgetTicks = 0
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
    /// table and the system metrics frame feeding the Performance tab and
    /// the Mini monitor.
    func start(publish: @escaping @MainActor (ProcessSnapshot, SystemSample?) -> Void) {
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

    var isRunning: Bool { running }
    var sleepInterval: TimeInterval { currentInterval }

    private func tick(publish: @escaping @MainActor (ProcessSnapshot, SystemSample?) -> Void) async {
        tickCount += 1
        checkSelfImpactBudget()
        // 5 s sub-tick: per-process network via nettop (spec §4.2).
        if tickCount % Self.nettopEveryNTicks == 1 || lastNet == nil {
            if let net = nettopCollector.sample() {
                lastNet = net
                nettopConsecutiveFailures = 0
            } else {
                // Stale counters would fake activity: clear while failing;
                // the next 5 s tick retries naturally (spec §4.5).
                lastNet = nil
                nettopConsecutiveFailures += 1
            }
        }
        let samples = processCollector.sampleAll()
        let now = Date()
        var snapshot = reducer.update(
            samples: samples,
            net: lastNet,
            nowUsec: UInt64(now.timeIntervalSince1970 * 1_000_000),
            coreCount: processCollector.logicalCoreCount(),
            totalMemoryBytes: processCollector.totalMemoryBytes()
        )
        // Base-first + batch fill (spec §4.4): one batched XPC round-trip
        // fills cross-user details when the daemon is available; otherwise
        // the base snapshot publishes as-is (degraded mode §6.4).
        if let elevatedDetailSource {
            snapshot = await fillElevatedDetails(snapshot,
                                                 source: elevatedDetailSource,
                                                 nowUsec: UInt64(now.timeIntervalSince1970 * 1_000_000))
        }
        snapshot.networkDegraded = nettopConsecutiveFailures >= Self.nettopFailureNoticeThreshold
        // System metrics share the 1 s master tick (spec §4.2).
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
        let coreCount = max(snapshot.logicalCoreCount, 1)

        func merge(_ record: inout ProcessRecord) {
            guard let detail = byPid[record.pid] else { return }
            record.residentMemory = detail.residentMemory
            record.detailLevel = .elevated
            if let prior = elevatedPrior[record.pid], nowUsec > prior.usec {
                let dtSeconds = Double(nowUsec - prior.usec) / 1_000_000
                if detail.cpuNanoseconds >= prior.cpuNS {
                    record.cpuPercent = Double(detail.cpuNanoseconds - prior.cpuNS)
                        / (dtSeconds * 1_000_000_000) / Double(coreCount) * 100
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

    private func allRecords(in snapshot: ProcessSnapshot) -> [ProcessRecord] {
        var records = snapshot.backgroundProcesses
        for group in snapshot.groups {
            records.append(contentsOf: group.children)
        }
        return records
    }

    // MARK: Self-impact budget (spec §4.2)

    /// Watches this app's own CPU share; if it sustains above the 2 % budget
    /// the master cadence halves to 2 s automatically and logs it.
    private func checkSelfImpactBudget() {
        guard currentInterval == Self.tickInterval else { return } // already degraded
        var task = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let got = withUnsafeMutablePointer(to: &task) { ptr in
            proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, ptr, size)
        }
        let nowUsec = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        guard got == size else { return }
        let cpuNS = task.pti_total_user &+ task.pti_total_system
        defer { ownPriorCPU = (cpuNS, nowUsec) }
        guard let prior = ownPriorCPU, nowUsec > prior.usec else { return }
        let dtSeconds = Double(nowUsec - prior.usec) / 1_000_000
        let ownPercent = Double(cpuNS - prior.ns) / (dtSeconds * 1_000_000_000) * 100
        if ownPercent > Self.selfImpactBudgetPercent {
            overBudgetTicks += 1
        } else {
            overBudgetTicks = 0
        }
        if overBudgetTicks >= 10 {
            currentInterval = Self.degradedTickInterval
            SamplerActor.logger.warning(
                "Sampler self-impact over \(Self.selfImpactBudgetPercent)% budget — cadence halved to \(Self.degradedTickInterval) s")
        }
    }

    private static let logger = Logger(subsystem: "com.brianwong.taskmanager", category: "Sampler")
}
