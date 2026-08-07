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
    private var reducer: ProcessTableReducer
    private var running = false
    private var tickCount = 0
    private var lastNet: [Int32: NetCounters]?

    init(processCollector: any ProcessTableCollecting = LibProcProcessCollector(),
         nettopCollector: any NettopCollecting = NettopCollector(),
         reducer: ProcessTableReducer = ProcessTableReducer()) {
        self.processCollector = processCollector
        self.nettopCollector = nettopCollector
        self.reducer = reducer
    }

    func start(publish: @escaping @MainActor (ProcessSnapshot) -> Void) {
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

    private func tick(publish: @escaping @MainActor (ProcessSnapshot) -> Void) async {
        tickCount += 1
        // 5 s sub-tick: per-process network via nettop (spec §4.2).
        if tickCount % Self.nettopEveryNTicks == 1 || lastNet == nil {
            lastNet = nettopCollector.sample()
        }
        let samples = processCollector.sampleAll()
        let nowUsec = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        let snapshot = reducer.update(
            samples: samples,
            net: lastNet,
            nowUsec: nowUsec,
            coreCount: processCollector.logicalCoreCount(),
            totalMemoryBytes: processCollector.totalMemoryBytes()
        )
        await publish(snapshot)
    }
}
