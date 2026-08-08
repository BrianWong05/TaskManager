// TaskManagerTests/ConfirmationMessageTests.swift
// Copy for the Force Quit confirmation alert (spec §3.3): the dialog
// must state name and PID — groups with a single killable child read
// like a plain process, multi-child groups list every target PID.

import Testing
@testable import TaskManager

@MainActor
@Suite struct ConfirmationMessageTests {
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
        let textBundle = "/Applications/TextEdit.app"
        let safariBundle = "/Applications/Safari.app"
        return ProcessSnapshot(
            groups: [
                AppGroup(bundlePath: textBundle, displayName: "TextEdit",
                         children: [record(pid: 50, name: "TextEdit", bundlePath: textBundle)]),
                AppGroup(bundlePath: safariBundle, displayName: "Safari",
                         children: [
                            record(pid: 60, name: "Safari", bundlePath: safariBundle),
                            record(pid: 61, name: "SafariWebContent", bundlePath: safariBundle),
                            record(pid: 62, name: "SafariNetworking", bundlePath: safariBundle,
                                   isProtected: true),
                         ]),
            ],
            backgroundProcesses: [record(pid: 70, name: "helper", bundlePath: nil)],
            timestamp: .now, totalMemoryBytes: 1 << 30, logicalCoreCount: 8)
    }

    @Test func processMessageNamesProcessAndPid() {
        let vm = ProcessesViewModel()
        let message = vm.forceQuitMessage(
            for: .process(ProcessIdentity(pid: 70, startUsec: 1)), in: snapshot())
        #expect(message.contains("helper"))
        #expect(message.contains("PID 70"))
    }

    @Test func singleChildGroupReadsLikeAProcess() {
        let vm = ProcessesViewModel()
        let message = vm.forceQuitMessage(
            for: .group(bundlePath: "/Applications/TextEdit.app"), in: snapshot())
        #expect(message.contains("TextEdit"))
        #expect(message.contains("PID 50"))
        // Singular grammar — never "all 1 processes" (spec §3.3 copy).
        #expect(!message.contains("processes"))
        #expect(!message.contains("all 1"))
    }

    @Test func multiChildGroupListsCountAndEveryTargetPid() {
        let vm = ProcessesViewModel()
        let message = vm.forceQuitMessage(
            for: .group(bundlePath: "/Applications/Safari.app"), in: snapshot())
        #expect(message.contains("Safari"))
        #expect(message.contains("2 processes"))
        #expect(message.contains("60"))
        #expect(message.contains("61"))
        // Protected children are never killed, so they must not be listed.
        #expect(!message.contains("62"))
    }

    @Test func missingOrEmptyTargetsYieldNoMessage() {
        let vm = ProcessesViewModel()
        #expect(vm.forceQuitMessage(for: nil, in: snapshot()) == "")
        #expect(vm.forceQuitMessage(
            for: .process(ProcessIdentity(pid: 999, startUsec: 1)), in: snapshot()) == "")
    }
}
