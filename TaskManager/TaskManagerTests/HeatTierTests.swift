// TaskManagerTests/HeatTierTests.swift
// Heat-tier classification (spec §3.3): CPU >5/>15/>40, memory by share.

import Testing
@testable import TaskManager

@Suite struct HeatTierTests {
    @Test func cpuThresholds() {
        #expect(cpuHeatTier(percent: 0) == .none)
        #expect(cpuHeatTier(percent: 4.9) == .none)
        #expect(cpuHeatTier(percent: 5.1) == .tier1)
        #expect(cpuHeatTier(percent: 15.1) == .tier2)
        #expect(cpuHeatTier(percent: 40.1) == .tier3)
        #expect(cpuHeatTier(percent: 99) == .tier3)
    }

    @Test func memoryTieredByShareOfTotal() {
        let total: UInt64 = 16_000_000_000
        #expect(memoryHeatTier(bytes: 100_000_000, totalBytes: total) == .none)
        #expect(memoryHeatTier(bytes: 900_000_000, totalBytes: total) == .tier1)
        #expect(memoryHeatTier(bytes: 2_500_000_000, totalBytes: total) == .tier2)
        #expect(memoryHeatTier(bytes: 7_000_000_000, totalBytes: total) == .tier3)
        #expect(memoryHeatTier(bytes: 1000, totalBytes: 0) == .none) // guard
    }
}
