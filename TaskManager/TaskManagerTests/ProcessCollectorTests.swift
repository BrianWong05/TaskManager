// TaskManagerTests/ProcessCollectorTests.swift
// Integration guard for the one collector that must talk to the live kernel:
// the base-first fallback (spec §4.4/§4.5) has to surface cross-user processes
// with base fields, or the whole elevated-fill path has nothing to gate.
// A bug here silently hid ~25% of the process table (every root/other-user
// process) and left cross-user End task with no rows to act on.

import Testing
import Foundation
@testable import TaskManager

@Suite struct ProcessCollectorTests {
    /// launchd (pid 1) is always root and always running. The unprivileged
    /// collector must still return it — name, path, and uid 0 — via the
    /// sysctl(KERN_PROC) base path, since PROC_PIDTBSDINFO fails cross-user.
    @Test func crossUserProcessesAreVisibleWithBaseFields() throws {
        let samples = LibProcProcessCollector().sampleAll()

        let launchd = try #require(samples.first { $0.pid == 1 },
                                   "launchd (pid 1) missing — cross-user processes are being dropped")
        #expect(launchd.uid == 0)
        #expect(!launchd.name.isEmpty)
        #expect(launchd.path == "/sbin/launchd")

        // At least some process must be owned by root — otherwise the whole
        // table collapsed to same-user only (the regression this guards).
        #expect(samples.contains { $0.uid == 0 })
    }

    /// Same-user processes still get the full task-info path (this test host
    /// runs as the current user), so CPU/memory fields are populated somewhere.
    @Test func sameUserProcessesCarryTaskInfo() {
        let samples = LibProcProcessCollector().sampleAll()
        let mine = samples.filter { $0.uid == getuid() }
        #expect(!mine.isEmpty)
        #expect(mine.contains { $0.residentMemory > 0 })
    }
}
