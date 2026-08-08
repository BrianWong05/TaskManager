// TaskManagerTests/PerCoreDisplayTests.swift
// Logical processors cell logic (per-core addendum §4): segment-meter rungs,
// per-core heat tiers, and CPU graph-mode persistence.

import Testing
import Foundation
@testable import TaskManager

@Suite struct SegmentMeterTests {
    @Test func idleCoreLightsNothing() {
        #expect(litSegments(percent: 0, of: 10) == 0)
    }

    /// The header can read 4 % while the rungs quantise to 10 % steps — but a
    /// core doing work must never be drawn as idle.
    @Test func anyLoadLightsAtLeastOneRung() {
        #expect(litSegments(percent: 0.4, of: 10) == 1)
        #expect(litSegments(percent: 4, of: 10) == 1)
    }

    @Test func rungsTrackThePercentage() {
        #expect(litSegments(percent: 50, of: 10) == 5)
        #expect(litSegments(percent: 74, of: 10) == 7)
        #expect(litSegments(percent: 76, of: 10) == 8)
    }

    @Test func fullCoreLightsEveryRungAndNeverMore() {
        #expect(litSegments(percent: 100, of: 10) == 10)
        #expect(litSegments(percent: 140, of: 10) == 10)
    }
}

@Suite struct CoreHeatTierTests {
    /// Per-core thresholds are 25/50/75 of that one core — deliberately not the
    /// process table's 5/15/40 shares of the whole machine.
    @Test func tiersFollowTheCoreThresholds() {
        #expect(coreHeatTier(percent: 0) == .none)
        #expect(coreHeatTier(percent: 24.9) == .none)
        #expect(coreHeatTier(percent: 25) == .tier1)
        #expect(coreHeatTier(percent: 49.9) == .tier1)
        #expect(coreHeatTier(percent: 50) == .tier2)
        #expect(coreHeatTier(percent: 75) == .tier3)
        #expect(coreHeatTier(percent: 100) == .tier3)
    }

    /// A core at 41 % would be the hottest tier on the machine-share scale;
    /// on the core scale it is only tier 1.
    @Test func coreScaleIsNotTheMachineScale() {
        #expect(cpuHeatTier(percent: 41, coreCount: 1) == .tier3)
        #expect(coreHeatTier(percent: 41) == .tier1)
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
