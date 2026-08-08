// TaskManagerTests/XPCProtocolCodingTests.swift
// TMProcessDetail crosses the XPC boundary via NSSecureCoding. Unsigned fields
// with the high bit set must survive the round-trip — a `nobody`-owned process
// (uid 0xFFFFFFFE) once trapped the decoder and crashed the app the instant
// cross-user rows were filled (spec §4.4).

import Testing
import Foundation
@testable import TaskManager

@Suite struct XPCProtocolCodingTests {
    private func roundTrip(_ detail: TMProcessDetail) throws -> TMProcessDetail {
        let data = try NSKeyedArchiver.archivedData(withRootObject: detail,
                                                    requiringSecureCoding: true)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: TMProcessDetail.self,
                                                             from: data)
        return try #require(decoded)
    }

    @Test func nobodyUidSurvivesRoundTrip() throws {
        let detail = TMProcessDetail(pid: 42, residentMemory: 1 << 40,
                                     cpuNanoseconds: 5_000_000_000, commandLine: "/sbin/x",
                                     diskBytesRead: 0, diskBytesWritten: 0,
                                     uid: 4_294_967_294) // nobody
        let out = try roundTrip(detail)
        #expect(out.uid == 4_294_967_294)
        #expect(out.residentMemory == 1 << 40)
    }

    @Test func fullUnsignedRangeSurvivesRoundTrip() throws {
        let detail = TMProcessDetail(pid: -1, residentMemory: .max,
                                     cpuNanoseconds: UInt64(Int64.max) + 1, commandLine: "",
                                     diskBytesRead: .max, diskBytesWritten: .max,
                                     uid: .max)
        let out = try roundTrip(detail)
        #expect(out.residentMemory == .max)
        #expect(out.cpuNanoseconds == UInt64(Int64.max) + 1)
        #expect(out.diskBytesWritten == .max)
        #expect(out.uid == .max)
    }
}
