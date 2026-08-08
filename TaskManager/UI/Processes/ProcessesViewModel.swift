// UI/Processes/ProcessesViewModel.swift
// Display logic for the Processes tab (spec §3.3): search filtering with
// group auto-expand, single-column sorting with persistence, heat tiers,
// selection, and End task / Force Quit semantics (SIGTERM / SIGKILL).

import Foundation
import Combine
import AppKit

/// What the user has selected in the list.
enum ProcessSelection: Hashable, Sendable {
    case group(bundlePath: String)
    case process(ProcessIdentity)
}

/// Sortable columns — Win11 parity set (spec §3.3).
enum ProcessSortColumn: String, CaseIterable {
    case name, status, cpu, memory, disk, network, gpu

    var title: String {
        switch self {
        case .name: return "Name"
        case .status: return "Status"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .gpu: return "GPU"
        }
    }
}

/// A flattened, display-ready row.
enum ProcessDisplayRow: Identifiable {
    case group(AppGroup, expanded: Bool)
    case process(ProcessRecord, indented: Bool)

    var id: String {
        switch self {
        case .group(let group, _): return "g:\(group.bundlePath)"
        case .process(let record, _): return "p:\(record.identity.pid):\(record.identity.startUsec)"
        }
    }
}

/// Termination failures surfaced as error dialogs with reasons (spec §3.3).
struct TerminationError: Identifiable {
    let id = UUID()
    let processName: String
    let pid: Int32
    let reason: String
}

@MainActor
final class ProcessesViewModel: ObservableObject {
    // MARK: Published state

    @Published var searchText = "" {
        didSet {
            // Every query change restarts the auto-expand cycle (spec §3.3),
            // so per-group collapse overrides never survive a new query.
            if searchText != oldValue { searchCollapsed.removeAll() }
        }
    }
    @Published var selection: ProcessSelection?
    @Published var expandedGroups: Set<String> = []
    /// Groups the user explicitly collapsed while a search is active —
    /// overrides the search auto-expansion (spec §3.3).
    @Published var searchCollapsed: Set<String> = []
    @Published var sortColumn: ProcessSortColumn
    @Published var sortAscending: Bool
    @Published var inspectorTarget: ProcessSelection?
    @Published var terminationError: TerminationError?
    @Published var forceQuitPending: ProcessSelection?

    // MARK: Private

    private enum SortKeys {
        static let column = "processes.sortColumn"
        static let ascending = "processes.sortAscending"
    }

    /// Elevation routing for cross-user termination (spec §4.5 → §6 daemon).
    weak var elevation: ElevationManager?

    private let currentUid = getuid()

    init() {
        let defaults = UserDefaults.standard
        sortColumn = defaults.string(forKey: SortKeys.column)
            .flatMap(ProcessSortColumn.init(rawValue:)) ?? .cpu
        sortAscending = defaults.object(forKey: SortKeys.ascending) as? Bool ?? false
    }

    // MARK: Sorting (spec §3.3 — header click cycles column + direction,
    // choice persists across sessions, default CPU descending)

    func toggleSort(_ column: ProcessSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            // Numeric columns default descending; Name/Status ascending.
            sortAscending = (column == .name || column == .status)
        }
        let defaults = UserDefaults.standard
        defaults.set(sortColumn.rawValue, forKey: SortKeys.column)
        defaults.set(sortAscending, forKey: SortKeys.ascending)
    }

    // MARK: Row construction

    /// Flattened visible rows after search filter + sort (spec §3.3).
    /// If any child of a group matches the search, the whole group stays
    /// visible and is auto-expanded.
    func displayRows(for snapshot: ProcessSnapshot?) -> [ProcessDisplayRow] {
        guard let snapshot else { return [] }
        let query = activeQuery

        var groups = snapshot.groups
        var background = snapshot.backgroundProcesses

        if !query.isEmpty {
            groups = groups.filter { group in
                group.displayName.lowercased().contains(query)
                    || group.children.contains { $0.name.lowercased().contains(query) }
            }
            background = background.filter { $0.name.lowercased().contains(query) }
        }

        groups.sort { compareGroups($0, $1) }
        background.sort { compareProcesses($0, $1) }

        var rows: [ProcessDisplayRow] = []
        for group in groups {
            // Search hit inside the group forces expansion (spec §3.3),
            // unless the user explicitly collapsed it during the search.
            let expanded = query.isEmpty
                ? expandedGroups.contains(group.bundlePath)
                : !searchCollapsed.contains(group.bundlePath)
            rows.append(.group(group, expanded: expanded))
            if expanded {
                var children = group.children
                children.sort { compareProcesses($0, $1) }
                rows.append(contentsOf: children.map { .process($0, indented: true) })
            }
        }
        rows.append(contentsOf: background.map { .process($0, indented: false) })
        return rows
    }

    func toggleExpanded(_ group: AppGroup) {
        if activeQuery.isEmpty {
            if expandedGroups.contains(group.bundlePath) {
                expandedGroups.remove(group.bundlePath)
            } else {
                expandedGroups.insert(group.bundlePath)
            }
        } else {
            // During search groups are auto-expanded; the chevron records
            // an explicit override instead of touching the regular state.
            if searchCollapsed.contains(group.bundlePath) {
                searchCollapsed.remove(group.bundlePath)
            } else {
                searchCollapsed.insert(group.bundlePath)
            }
        }
    }

    /// Trimmed, lowercased search text; empty means no active search.
    /// Single source of truth for "is a search active" across the view
    /// model — rows, toggles and the override lifecycle all read this.
    private var activeQuery: String {
        searchText.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func groupMetric(_ group: AppGroup) -> Double {
        switch sortColumn {
        case .name: return 0 // handled by name compare below
        case .status: return Double(group.children.count)
        case .cpu: return group.totalCPUPercent
        case .memory: return Double(group.totalMemory)
        case .disk: return group.totalDiskRate
        case .network: return group.totalNetRate ?? 0 // unavailable sorts last
        case .gpu: return 0
        }
    }

    private func processMetric(_ record: ProcessRecord) -> Double {
        switch sortColumn {
        case .name, .status, .gpu: return 0
        case .cpu: return record.cpuPercent
        case .memory: return Double(record.residentMemory)
        case .disk: return record.totalDiskRate
        case .network: return record.totalNetRate ?? 0 // unavailable sorts last
        }
    }

    private func compareProcesses(_ lhs: ProcessRecord, _ rhs: ProcessRecord) -> Bool {
        switch sortColumn {
        case .name:
            return sortAscending
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
        case .status:
            let l = lhs.status.rawValue, r = rhs.status.rawValue
            return sortAscending ? l < r : l > r
        default:
            let l = processMetric(lhs), r = processMetric(rhs)
            if l == r { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
            return sortAscending ? l < r : l > r
        }
    }

    private func compareGroups(_ lhs: AppGroup, _ rhs: AppGroup) -> Bool {
        if sortColumn == .name {
            return sortAscending
                ? lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                : lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedDescending
        }
        let l = groupMetric(lhs), r = groupMetric(rhs)
        if l == r { return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending }
        return sortAscending ? l < r : l > r
    }

    // MARK: Termination (spec §3.3 — End task = SIGTERM without confirmation,
    // Force Quit = SIGKILL always confirmed; protected rows disabled)

    func endTask(_ selection: ProcessSelection?, in snapshot: ProcessSnapshot?) {
        guard let snapshot else { return }
        guard let selection else { return }
        switch selection {
        case .process(let identity):
            if let record = record(for: identity, in: snapshot) {
                terminate(record, mode: .graceful)
            }
        case .group(let bundlePath):
            endAll(in: bundlePath, snapshot: snapshot)
        }
    }

    func forceQuit(_ selection: ProcessSelection?, in snapshot: ProcessSnapshot?) {
        guard let selection else { return }
        guard let snapshot else { return }
        switch selection {
        case .process(let identity):
            if let record = record(for: identity, in: snapshot),
               !record.isProtected {
                terminate(record, mode: .force)
            }
        case .group(let bundlePath):
            if let group = snapshot.groups.first(where: { $0.bundlePath == bundlePath }) {
                for child in group.children where !child.isProtected {
                    terminate(child, mode: .force)
                }
            }
        }
    }

    func endAll(in bundlePath: String, snapshot: ProcessSnapshot) {
        guard let group = snapshot.groups.first(where: { $0.bundlePath == bundlePath }) else { return }
        for child in group.children where !child.isProtected {
            terminate(child, mode: .graceful)
        }
    }

    /// Selection eligibility for the toolbar End task button.
    func canEndTask(selection: ProcessSelection?, in snapshot: ProcessSnapshot?) -> Bool {
        guard let selection, let snapshot else { return false }
        switch selection {
        case .process(let identity):
            guard let record = record(for: identity, in: snapshot) else { return false }
            return !record.isProtected
        case .group(let bundlePath):
            guard let group = snapshot.groups.first(where: { $0.bundlePath == bundlePath }) else { return false }
            return group.children.contains { !$0.isProtected }
        }
    }

    func record(for identity: ProcessIdentity, in snapshot: ProcessSnapshot) -> ProcessRecord? {
        if let hit = snapshot.backgroundProcesses.first(where: { $0.identity == identity }) {
            return hit
        }
        for group in snapshot.groups {
            if let hit = group.children.first(where: { $0.identity == identity }) {
                return hit
            }
        }
        return nil
    }

    /// Copy for the pending Force Quit confirmation (spec §3.3 — the
    /// dialog must state name and PID). A group with a single killable
    /// child reads like a plain process; multi-child groups list every
    /// target PID. Empty when there is nothing to confirm.
    func forceQuitMessage(for pending: ProcessSelection?, in snapshot: ProcessSnapshot?) -> String {
        guard let pending, let snapshot else { return "" }
        switch pending {
        case .process(let identity):
            guard let record = record(for: identity, in: snapshot) else { return "" }
            return singleProcessMessage(record)
        case .group(let bundlePath):
            guard let group = snapshot.groups.first(where: { $0.bundlePath == bundlePath }) else {
                return ""
            }
            let targets = group.children.filter { !$0.isProtected }
            if let only = targets.first, targets.count == 1 {
                return singleProcessMessage(only)
            }
            guard !targets.isEmpty else { return "" }
            let pids = targets.map { String($0.pid) }.joined(separator: ", ")
            return "Force quit all \(targets.count) processes of “\(group.displayName)” (PIDs \(pids))? They will be killed immediately and unsaved data may be lost."
        }
    }

    private func singleProcessMessage(_ record: ProcessRecord) -> String {
        "Are you sure you want to force quit “\(record.name)” (PID \(record.pid))? The process will be killed immediately and unsaved data may be lost."
    }

    /// Termination routing (spec §3.3, §4.5): own-user processes get a local
    /// signal; cross-user processes go through the daemon when Elevation is
    /// active, otherwise the failure dialog explains why.
    private func terminate(_ record: ProcessRecord, mode: TMTerminationMode) {
        guard !record.isProtected else { return }
        // kill(0/…) signals process groups: never leave the UI layer able
        // to pass anything but a plain positive pid.
        guard record.pid > 1 else { return }
        if record.detailLevel == .requiresElevation || record.uid != currentUid {
            guard let elevation, elevation.isActive else {
                terminationError = TerminationError(
                    processName: record.name, pid: record.pid,
                    reason: "Requires elevation — set up the background service in Settings, then retry.")
                return
            }
            let client = elevation.client
            Task {
                let result = await client.terminate(pid: record.pid, mode: mode)
                if !result.success {
                    terminationError = TerminationError(
                        processName: record.name, pid: record.pid,
                        reason: result.reason ?? "Termination failed")
                }
            }
            return
        }
        let signal = mode == .force ? SIGKILL : SIGTERM
        let result = kill(record.pid, signal)
        if result != 0 {
            let code = errno
            let reason: String
            switch code {
            case EPERM:
                // Cross-user process: needs the daemon (M3).
                reason = "Requires elevation — the process belongs to another user."
            case ESRCH:
                reason = "The process has already exited."
            default:
                reason = "Signal failed (errno \(code))."
            }
            terminationError = TerminationError(processName: record.name, pid: record.pid, reason: reason)
        }
    }

    // MARK: Detail gating

    /// Cross-user rows gate extended fields until Elevation fills them
    /// (spec §4.5).
    func requiresElevation(_ record: ProcessRecord) -> Bool {
        record.detailLevel == .requiresElevation
    }

    // MARK: Clipboard (spec §3.3 — Copy: name + PID + path)

    func copy(_ record: ProcessRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(record.name) (\(record.pid))\n\(record.path)", forType: .string)
    }

    func showInFinder(_ record: ProcessRecord) {
        let url = URL(fileURLWithPath: record.bundlePath ?? record.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
