// TaskManagerTests/HeatTierTests.swift
// Heat-tier classification (spec §3.3): CPU >5/>15/>40, memory by share.

import Testing
@testable import TaskManager

@Suite struct HeatTierTests {
    /// Single core: the percentages are shares of the machine directly.
    @Test func cpuThresholdsOnOneCore() {
        #expect(cpuHeatTier(percent: 0, coreCount: 1) == .none)
        #expect(cpuHeatTier(percent: 4.9, coreCount: 1) == .none)
        #expect(cpuHeatTier(percent: 5.1, coreCount: 1) == .tier1)
        #expect(cpuHeatTier(percent: 15.1, coreCount: 1) == .tier2)
        #expect(cpuHeatTier(percent: 40.1, coreCount: 1) == .tier3)
        #expect(cpuHeatTier(percent: 99, coreCount: 1) == .tier3)
    }

    /// Thresholds scale with core count so a tier keeps meaning the same share
    /// of the whole machine: on 10 cores the tiers sit at 50/150/400 %.
    @Test func cpuThresholdsScaleWithCoreCount() {
        #expect(cpuHeatTier(percent: 49, coreCount: 10) == .none)
        #expect(cpuHeatTier(percent: 51, coreCount: 10) == .tier1)
        #expect(cpuHeatTier(percent: 151, coreCount: 10) == .tier2)
        #expect(cpuHeatTier(percent: 401, coreCount: 10) == .tier3)
        // One fully-busy core out of 10 is only 10 % of the machine.
        #expect(cpuHeatTier(percent: 100, coreCount: 10) == .tier1)
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
