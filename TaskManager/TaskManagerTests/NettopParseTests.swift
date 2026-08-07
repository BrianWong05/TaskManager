// TaskManagerTests/NettopParseTests.swift
// nettop CSV parsing with recorded fixtures (spec §8) — the fragile shell-out
// is covered at its parse boundary so no test touches a real nettop.

import Testing
@testable import TaskManager

private let recordedFixture = """
,bytes_in,bytes_out,
launchd.1,0,0,
syslogd.566,0,11817,
apsd.572,17457,14498,
mDNSResponder.658,732359872,48628060,
"""

@Suite struct NettopParseTests {
    @Test func parsesRecordedFixture() {
        let counters = NettopCollector.parse(recordedFixture)
        #expect(counters != nil)
        #expect(counters?.count == 4)
        #expect(counters?[572]?.bytesIn == 17457)
        #expect(counters?[572]?.bytesOut == 14498)
        #expect(counters?[658]?.bytesIn == 732_359_872)
    }

    @Test func failureInputsReturnNil() {
        #expect(NettopCollector.parse(nil) == nil)
        #expect(NettopCollector.parse("") == nil)
        // Header only (no data rows) counts as failure.
        #expect(NettopCollector.parse(",bytes_in,bytes_out,\n") == nil)
    }

    @Test func malformedLinesAreSkipped() {
        let counters = NettopCollector.parse("""
        ,bytes_in,bytes_out,
        good.42,100,200,
        broken-line-no-fields,
        name.notanumber,1,2,
        """)
        #expect(counters?.count == 1)
        #expect(counters?[42]?.bytesIn == 100)
    }

    @Test func namesContainingDotsKeepTheTrailingPid() {
        let counters = NettopCollector.parse("com.apple.Safari.SandboxBroker.703,5,6,\n")
        #expect(counters?[703]?.bytesOut == 6)
    }
}
