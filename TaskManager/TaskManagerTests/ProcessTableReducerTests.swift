// TaskManagerTests/ProcessTableReducerTests.swift
// Pure-logic coverage for the reducer seam (spec §8): PID+start-time
// identity across simulated reuse, rate-delta computation, drop-on-exit,
// App Group aggregation. No real system calls.

import Testing
@testable import TaskManager

private func sample(pid: Int32, startUsec: UInt64 = 1_000_000, name: String = "proc",
                     path: String = "/usr/local/bin/proc", uid: UInt32 = 501,
                     cpuNS: UInt64 = 0, rss: UInt64 = 0,
                     diskRead: UInt64? = nil, diskWritten: UInt64? = nil) -> RawProcessSample {
    RawProcessSample(pid: pid, startUsec: startUsec, name: name, path: path,
                     uid: uid, ppid: 1, rawStatus: 2, cpuNanoseconds: cpuNS,
                     residentMemory: rss, diskBytesRead: diskRead, diskBytesWritten: diskWritten)
}

@Suite struct ProcessTableReducerTests {
    // MARK: CPU rate deltas

    @Test func cpuRateUsesDeltaOverWallTimeOnActivityMonitorScale() {
        var reducer = ProcessTableReducer(currentUid: 501)
        let first = reducer.update(
            samples: [sample(pid: 42, cpuNS: 1_000_000_000)], net: nil,
            nowUsec: 0, coreCount: 4, totalMemoryBytes: 16_000_000_000)
        #expect(first.backgroundProcesses[0].cpuPercent == 0) // first tick has no delta

        let second = reducer.update(
            samples: [sample(pid: 42, cpuNS: 2_000_000_000)], net: nil,
            nowUsec: 1_000_000, coreCount: 4, totalMemoryBytes: 16_000_000_000)
        // Δ1 s of CPU over 1 s of wall = one fully-busy core = 100 %,
        // independent of core count (Activity Monitor's scale).
        #expect(abs(second.backgroundProcesses[0].cpuPercent - 100.0) < 0.001)
    }

    @Test func diskRatesAreCounterDeltas() {
        var reducer = ProcessTableReducer(currentUid: 501)
        _ = reducer.update(samples: [sample(pid: 7, diskRead: 1000, diskWritten: 4000)],
                           net: nil, nowUsec: 0, coreCount: 8, totalMemoryBytes: 1)
        let second = reducer.update(samples: [sample(pid: 7, diskRead: 3000, diskWritten: 10_000)],
                                    net: nil, nowUsec: 2_000_000, coreCount: 8, totalMemoryBytes: 1)
        let record = second.backgroundProcesses[0]
        #expect(abs(record.diskReadRate - 1000) < 0.001)   // 2000 bytes / 2 s
        #expect(abs(record.diskWriteRate - 3000) < 0.001)  // 6000 bytes / 2 s
    }

    // MARK: Identity across PID reuse

    @Test func reusedPidGetsFreshIdentityAndZeroedRates() {
        var reducer = ProcessTableReducer(currentUid: 501)
        _ = reducer.update(samples: [sample(pid: 100, startUsec: 1000, cpuNS: 5_000_000_000)],
                           net: nil, nowUsec: 0, coreCount: 8, totalMemoryBytes: 1)
        // Same PID, different start time = a different process (spec §4.1).
        let second = reducer.update(samples: [sample(pid: 100, startUsec: 2000, cpuNS: 100)],
                                    net: nil, nowUsec: 1_000_000, coreCount: 8, totalMemoryBytes: 1)
        // No delta against the previous occupant: CPU reads 0, not a huge spike.
        #expect(second.backgroundProcesses[0].cpuPercent == 0)
        #expect(second.backgroundProcesses[0].identity.startUsec == 2000)
    }

    @Test func vanishedProcessesAreDroppedImmediately() {
        var reducer = ProcessTableReducer(currentUid: 501)
        _ = reducer.update(samples: [sample(pid: 1), sample(pid: 2)],
                           net: nil, nowUsec: 0, coreCount: 8, totalMemoryBytes: 1)
        let second = reducer.update(samples: [sample(pid: 1)],
                                    net: nil, nowUsec: 1_000_000, coreCount: 8, totalMemoryBytes: 1)
        #expect(second.processCount == 1)
        // The dropped pid's prior counters must not leak into a reuse.
        let third = reducer.update(samples: [sample(pid: 2, startUsec: 999_999, cpuNS: 0)],
                                   net: nil, nowUsec: 2_000_000, coreCount: 8, totalMemoryBytes: 1)
        #expect(third.backgroundProcesses.first { $0.pid == 2 }?.cpuPercent == 0)
    }

    // MARK: App Grouping

    @Test func appGroupAggregatesChildren() {
        var reducer = ProcessTableReducer(currentUid: 501)
        let snapshot = reducer.update(samples: [
            sample(pid: 10, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari",
                   cpuNS: 0, rss: 1000),
            sample(pid: 11, name: "SafariWebContent",
                   path: "/Applications/Safari.app/Contents/Frameworks/WK/WKWebContent",
                   cpuNS: 0, rss: 3000),
            sample(pid: 12, name: "sshd", path: "/usr/libexec/sshd-keygen-wrapper", cpuNS: 0, rss: 500),
        ], net: nil, nowUsec: 0, coreCount: 8, totalMemoryBytes: 1)

        #expect(snapshot.groups.count == 1)
        let group = snapshot.groups[0]
        #expect(group.bundlePath == "/Applications/Safari.app")
        #expect(group.displayName == "Safari")
        #expect(group.children.count == 2)
        #expect(group.totalMemory == 4000)
        #expect(snapshot.backgroundProcesses.count == 1)
        #expect(snapshot.processCount == 3)
    }

    // MARK: Detail gating

    @Test func crossUserRowsRequireElevation() {
        var reducer = ProcessTableReducer(currentUid: 501)
        let snapshot = reducer.update(samples: [
            sample(pid: 1, uid: 501),
            sample(pid: 2, uid: 0),
        ], net: nil, nowUsec: 0, coreCount: 8, totalMemoryBytes: 1)
        let own = snapshot.backgroundProcesses.first { $0.pid == 1 }
        let root = snapshot.backgroundProcesses.first { $0.pid == 2 }
        #expect(own?.detailLevel == .full)
        #expect(root?.detailLevel == .requiresElevation)
    }

    // MARK: Network fallback

    @Test func missingNettopSampleDegradesNetworkToNil() {
        var reducer = ProcessTableReducer(currentUid: 501)
        _ = reducer.update(samples: [sample(pid: 5)],
                           net: [5: NetCounters(bytesIn: 100, bytesOut: 200)],
                           nowUsec: 0, coreCount: 8, totalMemoryBytes: 1)
        let degraded = reducer.update(samples: [sample(pid: 5)], net: nil,
                                      nowUsec: 1_000_000, coreCount: 8, totalMemoryBytes: 1)
        #expect(degraded.backgroundProcesses[0].netDownRate == nil)
        #expect(degraded.backgroundProcesses[0].netUpRate == nil)
    }
}

@Suite struct NetworkAvailabilityTests {
    private func record(down: Double?, up: Double?) -> ProcessRecord {
        ProcessRecord(
            identity: ProcessIdentity(pid: 1, startUsec: 1),
            name: "p", path: "/p", bundlePath: nil, uid: 501, userName: "me", ppid: 1,
            status: .running, isProtected: false, cpuPercent: 0, residentMemory: 0,
            diskReadRate: 0, diskWriteRate: 0, netDownRate: down, netUpRate: up,
            detailLevel: .full)
    }

    /// Unavailable per-process network must stay nil so the column renders `–`,
    /// not a fabricated 0 B/s (spec §4.5).
    @Test func unavailableNetworkIsNilNotZero() {
        #expect(record(down: nil, up: nil).totalNetRate == nil)
        #expect(record(down: 10, up: 5).totalNetRate == 15)
    }

    /// A group of unavailable children is itself unavailable; a group with any
    /// data sums what it has.
    @Test func groupNetworkIsNilOnlyWhenNoChildHasData() {
        let none = AppGroup(bundlePath: "/A.app", displayName: "A",
                            children: [record(down: nil, up: nil), record(down: nil, up: nil)])
        #expect(none.totalNetRate == nil)

        let some = AppGroup(bundlePath: "/B.app", displayName: "B",
                            children: [record(down: nil, up: nil), record(down: 3, up: 4)])
        #expect(some.totalNetRate == 7)
    }
}

@Suite struct GroupStatusTests {
    private func record(_ status: ProcessStatus) -> ProcessRecord {
        ProcessRecord(
            identity: ProcessIdentity(pid: 1, startUsec: 1),
            name: "p", path: "/p", bundlePath: nil, uid: 501, userName: "me", ppid: 1,
            status: status, isProtected: false, cpuPercent: 0, residentMemory: 0,
            diskReadRate: 0, diskWriteRate: 0, netDownRate: nil, netUpRate: nil,
            detailLevel: .full)
    }

    /// The collapsed group row shows an aggregate status: any transitional or
    /// stopped child dominates over "Running" (spec §3.3).
    @Test func aggregateStatusIsNotableWhenNotAllRunning() {
        let allRunning = AppGroup(bundlePath: "/A.app", displayName: "A",
                                  children: [record(.running), record(.running)])
        #expect(allRunning.aggregateStatus == .running)

        let withStopped = AppGroup(bundlePath: "/B.app", displayName: "B",
                                   children: [record(.running), record(.stopped)])
        #expect(withStopped.aggregateStatus == .stopped)

        let withStarting = AppGroup(bundlePath: "/C.app", displayName: "C",
                                    children: [record(.running), record(.starting)])
        #expect(withStarting.aggregateStatus == .starting)
    }
}
