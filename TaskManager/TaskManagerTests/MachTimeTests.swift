// TaskManagerTests/MachTimeTests.swift
// Guards the Mach-units -> nanoseconds conversion behind every CPU percentage
// (spec §5). Treating proc_taskinfo's pti_total_* as nanoseconds underreports
// CPU by the timebase ratio — 41.67x on Apple Silicon, invisible on Intel.

import Testing
import Foundation
@testable import TaskManager

@Suite struct MachTimeTests {
    /// Measures a real elapsed interval through the conversion: if the raw
    /// Mach delta were passed through as nanoseconds this reads ~41x short on
    /// Apple Silicon and the assertion fails.
    @Test func convertsMachDeltaToWallClockNanoseconds() throws {
        let sleepNS: UInt64 = 100_000_000 // 100 ms

        let startMach = mach_absolute_time()
        try #require(sleepNS < .max)
        Thread.sleep(forTimeInterval: Double(sleepNS) / 1_000_000_000)
        let elapsedNS = machTimeToNanoseconds(mach_absolute_time() - startMach)

        // Generous upper bound: Thread.sleep only guarantees a lower bound and
        // CI machines are noisy. The lower bound is what actually catches a
        // missing conversion.
        #expect(elapsedNS >= sleepNS)
        #expect(elapsedNS < sleepNS * 5)
    }

    @Test func zeroConvertsToZero() {
        #expect(machTimeToNanoseconds(0) == 0)
    }
}
