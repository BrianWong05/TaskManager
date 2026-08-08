// TaskManagerTests/TerminationGatingTests.swift
// Toolbar termination gating (spec §3.3): the End task and Force Quit
// buttons act on the current selection — disabled with no selection,
// enabled for regular rows, disabled when only protected rows match.

import Testing
@testable import TaskManager

@MainActor
@Suite struct TerminationGatingTests {
    private func record(pid: Int32, name: String, bundlePath: String?,
                        isProtected: Bool = false) -> ProcessRecord {
        ProcessRecord(
            identity: ProcessIdentity(pid: pid, startUsec: 1),
            name: name, path: "/p\(pid)", bundlePath: bundlePath, uid: 501,
            userName: "me", ppid: 1, status: .running, isProtected: isProtected,
            cpuPercent: 0, residentMemory: 0,
            diskReadRate: 0, diskWriteRate: 0, netDownRate: nil, netUpRate: nil,
            detailLevel: .full)
    }

    private func snapshot() -> ProcessSnapshot {
        let bundle = "/Applications/Safari.app"
        let group = AppGroup(
            bundlePath: bundle,
            displayName: "Safari",
            children: [
                record(pid: 20, name: "Safari", bundlePath: bundle),
                record(pid: 21, name: "SafariWebContent", bundlePath: bundle),
            ])
        let protectedGroup = AppGroup(
            bundlePath: "/System/Applications/Finder.app",
            displayName: "Finder",
            children: [record(pid: 30, name: "Finder",
                              bundlePath: "/System/Applications/Finder.app",
                              isProtected: true)])
        return ProcessSnapshot(
            groups: [group, protectedGroup],
            backgroundProcesses: [
                record(pid: 40, name: "kernel_task", bundlePath: nil, isProtected: true),
                record(pid: 41, name: "helper", bundlePath: nil),
            ],
            timestamp: .now, totalMemoryBytes: 1 << 30, logicalCoreCount: 8)
    }

    @Test func noSelectionDisablesButtons() {
        let vm = ProcessesViewModel()
        #expect(!vm.canEndTask(selection: nil, in: snapshot()))
    }

    @Test func noSnapshotDisablesButtons() {
        let vm = ProcessesViewModel()
        let identity = ProcessIdentity(pid: 41, startUsec: 1)
        #expect(!vm.canEndTask(selection: .process(identity), in: nil))
    }

    @Test func regularProcessEnablesButtons() {
        let vm = ProcessesViewModel()
        let identity = ProcessIdentity(pid: 41, startUsec: 1)
        #expect(vm.canEndTask(selection: .process(identity), in: snapshot()))
    }

    @Test func protectedProcessDisablesButtons() {
        let vm = ProcessesViewModel()
        let identity = ProcessIdentity(pid: 40, startUsec: 1)
        #expect(!vm.canEndTask(selection: .process(identity), in: snapshot()))
    }

    @Test func groupWithUnprotectedChildEnablesButtons() {
        let vm = ProcessesViewModel()
        #expect(vm.canEndTask(
            selection: .group(bundlePath: "/Applications/Safari.app"),
            in: snapshot()))
    }

    @Test func fullyProtectedGroupDisablesButtons() {
        let vm = ProcessesViewModel()
        #expect(!vm.canEndTask(
            selection: .group(bundlePath: "/System/Applications/Finder.app"),
            in: snapshot()))
    }

    @Test func vanishedSelectionDisablesButtons() {
        let vm = ProcessesViewModel()
        let identity = ProcessIdentity(pid: 999, startUsec: 1)
        #expect(!vm.canEndTask(selection: .process(identity), in: snapshot()))
    }
}
