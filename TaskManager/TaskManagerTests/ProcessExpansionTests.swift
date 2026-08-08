// TaskManagerTests/ProcessExpansionTests.swift
// Group expansion/collapse behavior in the Processes tab (spec §3.3):
// search auto-expands matching groups, but the user's explicit chevron
// click must still collapse them.

import Testing
@testable import TaskManager

@MainActor
@Suite struct ProcessExpansionTests {
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
        let group = AppGroup(
            bundlePath: "/Applications/Activity Monitor.app",
            displayName: "Activity Monitor",
            children: [record(pid: 10, name: "Activity Monitor",
                              bundlePath: "/Applications/Activity Monitor.app")])
        return ProcessSnapshot(groups: [group], backgroundProcesses: [],
                               timestamp: .now, totalMemoryBytes: 1 << 30,
                               logicalCoreCount: 8)
    }

    private func isExpanded(_ rows: [ProcessDisplayRow], bundlePath: String) -> Bool? {
        for row in rows {
            if case .group(let group, let expanded) = row, group.bundlePath == bundlePath {
                return expanded
            }
        }
        return nil
    }

    /// Without search, groups start collapsed and toggle on chevron click.
    @Test func normalToggleExpandsAndCollapses() {
        let vm = ProcessesViewModel()
        let snap = snapshot()
        let path = "/Applications/Activity Monitor.app"
        let group = snap.groups[0]

        #expect(isExpanded(vm.displayRows(for: snap), bundlePath: path) == false)
        vm.toggleExpanded(group)
        #expect(isExpanded(vm.displayRows(for: snap), bundlePath: path) == true)
        vm.toggleExpanded(group)
        #expect(isExpanded(vm.displayRows(for: snap), bundlePath: path) == false)
    }

    /// Search auto-expands matching groups (spec §3.3)…
    @Test func searchAutoExpandsMatchingGroups() {
        let vm = ProcessesViewModel()
        let snap = snapshot()
        vm.searchText = "act"
        let rows = vm.displayRows(for: snap)
        #expect(isExpanded(rows, bundlePath: "/Applications/Activity Monitor.app") == true)
    }

    /// …but an explicit chevron click must still collapse the group while
    /// the search is active, and clicking again re-expands it.
    @Test func chevronCollapsesGroupDuringSearch() {
        let vm = ProcessesViewModel()
        let snap = snapshot()
        let path = "/Applications/Activity Monitor.app"
        let group = snap.groups[0]
        vm.searchText = "act"

        vm.toggleExpanded(group)
        #expect(isExpanded(vm.displayRows(for: snap), bundlePath: path) == false,
                "collapsing a search-expanded group must take effect")

        vm.toggleExpanded(group)
        #expect(isExpanded(vm.displayRows(for: snap), bundlePath: path) == true)
    }

    /// Clearing the search restores the regular expansion state — the
    /// search-time collapse override does not leak into it.
    @Test func clearingSearchRestoresRegularExpansionState() {
        let vm = ProcessesViewModel()
        let snap = snapshot()
        let path = "/Applications/Activity Monitor.app"
        let group = snap.groups[0]
        vm.searchText = "act"
        vm.toggleExpanded(group) // collapse during search

        vm.searchText = ""
        // Group was never expanded via the regular state → collapsed again,
        // and the chevron toggles normally.
        #expect(isExpanded(vm.displayRows(for: snap), bundlePath: path) == false)
        vm.toggleExpanded(group)
        #expect(isExpanded(vm.displayRows(for: snap), bundlePath: path) == true)
    }

    /// Changing the query (without clearing it first) restarts the
    /// auto-expand cycle (spec §3.3): a collapse override recorded under
    /// the previous query must not survive into the new one.
    @Test func changingQueryRestartsAutoExpandCycle() {
        let vm = ProcessesViewModel()
        let snap = snapshot()
        let path = "/Applications/Activity Monitor.app"
        let group = snap.groups[0]
        vm.searchText = "act"
        vm.toggleExpanded(group) // collapse during search

        vm.searchText = "activity" // still matches, no empty step in between
        #expect(isExpanded(vm.displayRows(for: snap), bundlePath: path) == true)
    }

    /// Whitespace-only input is not a search: the toggle touches the
    /// regular expansion state, never the search override.
    @Test func whitespaceOnlyQueryTogglesRegularExpansion() {
        let vm = ProcessesViewModel()
        let snap = snapshot()
        let path = "/Applications/Activity Monitor.app"
        let group = snap.groups[0]
        vm.searchText = "   "
        vm.toggleExpanded(group)
        #expect(isExpanded(vm.displayRows(for: snap), bundlePath: path) == true)
        vm.toggleExpanded(group)
        #expect(isExpanded(vm.displayRows(for: snap), bundlePath: path) == false)
    }
}
