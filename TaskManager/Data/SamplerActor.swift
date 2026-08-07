// Data/SamplerActor.swift
// Dedicated actor performing all sampling serially off the main thread
// (spec §4.3): 1 s master tick, 5 s nettop sub-tick. Publishes one immutable
// ProcessSnapshot per tick to the @MainActor store — one hop per tick.

import Foundation

actor SamplerActor {
    static let tickInterval: TimeInterval = 1
    static let nettopEveryNTicks = 5 // 5 s sub-tick (spec §4.2)

    private let processCollector: any ProcessTableCollecting
    private let nettopCollector: any NettopCollecting
    private let systemCollector: any SystemMetricsCollecting
    private var reducer: ProcessTableReducer
    private var systemReducer = SystemMetricsReducer()
    private var running = false
    private var tickCount = 0
    private var lastNet: [Int32: NetCounters]?

    init(processCollector: any ProcessTableCollecting = LibProcProcessCollector(),
         nettopCollector: any NettopCollecting = NettopCollector(),
         systemCollector: any SystemMetricsCollecting = SystemMetricsCollector(),
         reducer: ProcessTableReducer = ProcessTableReducer()) {
        self.processCollector = processCollector
        self.nettopCollector = nettopCollector
        self.systemCollector = systemCollector
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
                try? await Task.sleep(for: .seconds(Self.tickInterval))
            }
        }
    }

    func stop() {
        running = false
    }

    var isRunning: Bool { running }

    private func tick(publish: @escaping @MainActor (ProcessSnapshot, SystemSample?) -> Void) async {
        tickCount += 1
        // 5 s sub-tick: per-process network via nettop (spec §4.2).
        if tickCount % Self.nettopEveryNTicks == 1 || lastNet == nil {
            lastNet = nettopCollector.sample()
        }
        let samples = processCollector.sampleAll()
        let now = Date()
        let snapshot = reducer.update(
            samples: samples,
            net: lastNet,
            nowUsec: UInt64(now.timeIntervalSince1970 * 1_000_000),
            coreCount: processCollector.logicalCoreCount(),
            totalMemoryBytes: processCollector.totalMemoryBytes()
        )
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
}
