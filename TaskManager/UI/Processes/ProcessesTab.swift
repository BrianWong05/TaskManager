// UI/Processes/ProcessesTab.swift
// Processes tab (spec §3.3): toolbar (search, live count, End task),
// app-grouped seven-column list, heat coloring, context menus, keyboard
// shortcuts, and the Show Details inspector overlay.

import SwiftUI

/// Fixed column widths shared by the header and every row.
enum ProcessColumns {
    static let statusWidth: CGFloat = 96
    static let cpuWidth: CGFloat = 78
    static let memoryWidth: CGFloat = 96
    static let diskWidth: CGFloat = 96
    static let networkWidth: CGFloat = 96
    static let gpuWidth: CGFloat = 56
}

struct ProcessesTab: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.palette) private var palette
    @StateObject private var viewModel = ProcessesViewModel()
    @FocusState private var searchFocused: Bool

    private var snapshot: ProcessSnapshot? { appModel.snapshotStore.snapshot }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(palette.border)
            columnHeader
            Divider().overlay(palette.border)
            processList
        }
        .background(palette.page)
        .overlay(alignment: .trailing) { inspectorOverlay }
        // ⌘Q performs End task on selection (spec §3.3 — deliberately
        // overrides the platform quit shortcut, Win11 parity).
        .background(
            Button("") {
                viewModel.endTask(viewModel.selection, in: snapshot)
            }
            .keyboardShortcut("q", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        )
        // ⌘F focuses search (spec §3.3).
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        // Esc: close inspector → clear search → deselect (spec §3.3).
        .onExitCommand(perform: handleEscape)
        .alert(item: $viewModel.terminationError) { error in
            Alert(
                title: Text("Cannot end \(error.processName) (\(error.pid))"),
                message: Text(error.reason),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Force Quit", isPresented: forceQuitBinding) {
            Button("Cancel", role: .cancel) { viewModel.forceQuitPending = nil }
            Button("Force Quit", role: .destructive) {
                let target = viewModel.forceQuitPending
                viewModel.forceQuitPending = nil
                viewModel.forceQuit(target, in: snapshot)
            }
        } message: {
            Text(forceQuitMessage)
        }
    }

    private var forceQuitBinding: Binding<Bool> {
        Binding(
            get: { viewModel.forceQuitPending != nil },
            set: { if !$0 { viewModel.forceQuitPending = nil } }
        )
    }

    private var forceQuitMessage: String {
        guard let pending = viewModel.forceQuitPending, let snapshot else {
            return ""
        }
        switch pending {
        case .process(let identity):
            if let record = viewModel.record(for: identity, in: snapshot) {
                return "Are you sure you want to force quit “\(record.name)” (PID \(record.pid))? The process will be killed immediately and unsaved data may be lost."
            }
            return ""
        case .group(let bundlePath):
            if let group = snapshot.groups.first(where: { $0.bundlePath == bundlePath }) {
                return "Force quit all \(group.children.count) processes of “\(group.displayName)”? They will be killed immediately and unsaved data may be lost."
            }
            return ""
        }
    }

    private func handleEscape() {
        if viewModel.inspectorTarget != nil {
            viewModel.inspectorTarget = nil
        } else if !viewModel.searchText.isEmpty {
            viewModel.searchText = ""
        } else {
            viewModel.selection = nil
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                TextField("Search processes", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 240)
            .background(palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(searchFocused ? palette.accent : palette.border, lineWidth: 1)
            )

            Text("\(snapshot?.processCount ?? 0) processes")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)

            Spacer()

            Button {
                viewModel.endTask(viewModel.selection, in: snapshot)
            } label: {
                Text("End task")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(
                        viewModel.canEndTask(selection: viewModel.selection, in: snapshot)
                            ? palette.accent : palette.accent.opacity(0.35)
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canEndTask(selection: viewModel.selection, in: snapshot))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: Column header

    private var columnHeader: some View {
        HStack(spacing: 0) {
            headerCell(.name, title: "Name", width: nil, alignment: .leading)
            headerCell(.status, title: "Status", width: ProcessColumns.statusWidth, alignment: .leading)
            headerCell(.cpu, title: "CPU", width: ProcessColumns.cpuWidth, alignment: .trailing)
            headerCell(.memory, title: "Memory", width: ProcessColumns.memoryWidth, alignment: .trailing)
            headerCell(.disk, title: "Disk", width: ProcessColumns.diskWidth, alignment: .trailing)
            headerCell(.network, title: "Network", width: ProcessColumns.networkWidth, alignment: .trailing)
            headerCell(.gpu, title: "GPU", width: ProcessColumns.gpuWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(palette.card)
    }

    private func headerCell(_ column: ProcessSortColumn, title: String,
                            width: CGFloat?, alignment: HorizontalAlignment) -> some View {
        Button {
            viewModel.toggleSort(column)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(viewModel.sortColumn == column ? palette.accent : palette.textSecondary)
                if viewModel.sortColumn == column {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(palette.accent)
                }
            }
            .frame(maxWidth: width == nil ? .infinity : width,
                   alignment: width == nil ? .leading : (alignment == .trailing ? .trailing : .leading))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    @ViewBuilder
    private var processList: some View {
        let rows = viewModel.displayRows(for: snapshot)
        if rows.isEmpty {
            if snapshot == nil {
                TabPlaceholder(icon: "hourglass", title: "Starting…",
                               caption: "Collecting the process table.")
            } else {
                TabPlaceholder(icon: "magnifyingglass", title: "No results",
                               caption: "No processes match “\(viewModel.searchText)”.")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        ProcessRowView(
                            row: row,
                            isSelected: isSelected(row),
                            viewModel: viewModel,
                            snapshot: snapshot
                        ) {
                            select(row)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
        }
    }

    private func isSelected(_ row: ProcessDisplayRow) -> Bool {
        switch (row, viewModel.selection) {
        case (.group(let group, _), .group(let selected)):
            return group.bundlePath == selected
        case (.process(let record, _), .process(let selected)):
            return record.identity == selected
        default:
            return false
        }
    }

    private func select(_ row: ProcessDisplayRow) {
        switch row {
        case .group(let group, _):
            viewModel.selection = .group(bundlePath: group.bundlePath)
        case .process(let record, _):
            viewModel.selection = .process(record.identity)
        }
    }

    // MARK: Inspector overlay (spec §3.3 — slides over the content,
    // list stays visible, selection kept in sync)

    @ViewBuilder
    private var inspectorOverlay: some View {
        if let target = viewModel.inspectorTarget {
            ProcessInspector(target: target, snapshot: snapshot, viewModel: viewModel) {
                viewModel.inspectorTarget = nil
            }
            .transition(.move(edge: .trailing))
        }
    }
}
