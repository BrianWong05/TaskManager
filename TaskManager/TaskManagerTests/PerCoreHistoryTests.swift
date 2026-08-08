// TaskManagerTests/PerCoreHistoryTests.swift
// Per-core history bookkeeping and CPU graph-mode persistence (per-core
// addendum §3, §4). No kernel calls — samples are handed to the store directly.

import Testing
import Foundation
@testable import TaskManager

private let memory = MemoryRaw(wired: 100, active: 200, inactive: 50, free: 300,
                               compressed: 100, swapUsed: 0, totalPhysical: 1000)

private func sample(perCore: [Double]) -> SystemSample {
    SystemSample(cpuPercent: perCore.reduce(0, +) / Double(max(perCore.count, 1)),
                 perCorePercent: perCore, memory: memory,
                 diskReadRate: 0, diskWriteRate: 0, netDownRate: 0, netUpRate: 0,
                 gpuUtilization: nil, upTimeSeconds: 0)
}

@Suite struct PerCoreHistoryTests {
    @MainActor
    @Test func buffersAreSizedFromTheFirstSample() {
        let store = SystemMetricsStore(topology: CoreTopology.make(coreCount: 4, levels: []))
        #expect(store.perCoreHistory.isEmpty)

        store.apply(sample(perCore: [1, 2, 3, 4]))

        #expect(store.perCoreHistory.count == 4)
        #expect(store.perCoreHistory.allSatisfy { $0.capacity == SystemMetricsStore.historyCapacity })
        #expect(store.perCoreHistory.map(\.latest) == [1, 2, 3, 4])
    }

    @MainActor
    @Test func oneAppendPerCorePerTick() {
        let store = SystemMetricsStore(topology: CoreTopology.make(coreCount: 2, levels: []))
        for tick in 0..<3 {
            store.apply(sample(perCore: [Double(tick), Double(tick) * 10]))
        }

        #expect(store.perCoreHistory.map(\.count) == [3, 3])
        #expect(store.perCoreHistory[0].values == [0, 1, 2])
        #expect(store.perCoreHistory[1].values == [0, 10, 20])
    }

    @MainActor
    @Test func historyStaysWithinTheSixtySecondWindow() {
        let store = SystemMetricsStore(topology: CoreTopology.make(coreCount: 1, levels: []))
        for tick in 0..<70 {
            store.apply(sample(perCore: [Double(tick)]))
        }

        #expect(store.perCoreHistory[0].count == 60)
        #expect(store.perCoreHistory[0].values.first == 10)
        #expect(store.perCoreHistory[0].values.last == 69)
    }
}

/// Serialized: every case wipes and rewrites the same defaults suite.
@Suite(.serialized) struct CPUGraphModePersistenceTests {
    private func defaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "CPUGraphModePersistenceTests")!
        suite.removePersistentDomain(forName: "CPUGraphModePersistenceTests")
        return suite
    }

    @Test func defaultsToOverallUtilization() {
        #expect(CPUGraphMode.stored(in: defaults()) == .overall)
    }

    @Test func roundTripsThroughUserDefaults() {
        let suite = defaults()
        CPUGraphMode.perCore.store(in: suite)

        #expect(suite.string(forKey: CPUGraphMode.defaultsKey) == "perCore")
        #expect(CPUGraphMode.stored(in: suite) == .perCore)

        CPUGraphMode.overall.store(in: suite)
        #expect(CPUGraphMode.stored(in: suite) == .overall)
    }

    @Test func unknownStoredValueFallsBackToOverall() {
        let suite = defaults()
        suite.set("bogus", forKey: CPUGraphMode.defaultsKey)

        #expect(CPUGraphMode.stored(in: suite) == .overall)
    }
}
