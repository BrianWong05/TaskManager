// UI/Processes/ProcessInspector.swift
// "Show Details" inspector (spec §3.3, ticket 10): right-side panel sliding
// over the content; the list stays visible and selection stays in sync.
// Single process: nine fields in two capability tiers. App Group: aggregate
// header + clickable child list. Values live-update; an exited process keeps
// its last frame with a "Process exited" notice.

import SwiftUI

struct ProcessInspector: View {
    @Environment(\.palette) private var palette
    let target: ProcessSelection
    let snapshot: ProcessSnapshot?
    @ObservedObject var viewModel: ProcessesViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.border)
            content
                .frame(maxHeight: .infinity)
        }
        .frame(width: 340)
        .background(palette.card)
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.border).frame(width: 1)
        }
    }

    private var header: some View {
        HStack {
            Text("Details")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(palette.subdued)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        switch target {
        case .process(let identity):
            let live = snapshot.flatMap { viewModel.record(for: identity, in: $0) }
            ProcessDetailView(record: live,
                              viewModel: viewModel,
                              elevatedCommandLine: snapshot?.elevatedCommandLines[identity.pid])
        case .group(let bundlePath):
            groupDetail(bundlePath: bundlePath)
        }
    }

    // MARK: App Group — aggregate header + child list

    @ViewBuilder
    private func groupDetail(bundlePath: String) -> some View {
        if let snapshot, let group = snapshot.groups.first(where: { $0.bundlePath == bundlePath }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(nsImage: IconCache.shared.icon(forBundlePath: bundlePath))
                            .resizable()
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                            Text("\(group.children.count) processes")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .padding(.bottom, 12)

                    InspectorField("Total CPU", Format.cpu(group.totalCPUPercent))
                    InspectorField("Total memory", Format.bytes(group.totalMemory))

                    InspectorSectionDivider("Processes")

                    ForEach(group.children) { child in
                        Button {
                            // Clicking a child switches the inspector to it
                            // and keeps list selection in sync (spec §3.3).
                            viewModel.selection = .process(child.identity)
                            viewModel.inspectorTarget = .process(child.identity)
                        } label: {
                            HStack {
                                Text(child.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(child.pid)")
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                                Text(Format.cpu(child.cpuPercent))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                                    .frame(width: 54, alignment: .trailing)
                                Text(Format.bytes(child.residentMemory))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                                    .frame(width: 62, alignment: .trailing)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(palette.subdued.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        } else {
            TabPlaceholder(icon: "questionmark.circle", title: "Group exited",
                           caption: "No processes remain in this App Group.")
        }
    }
}

/// Single-process inspector content. Keeps the last live frame so an exited
/// process still renders with a "Process exited" notice (spec §3.3).
private struct ProcessDetailView: View {
    @Environment(\.palette) private var palette
    let record: ProcessRecord?
    @ObservedObject var viewModel: ProcessesViewModel
    /// Command line the daemon filled for cross-user processes (§4.4).
    var elevatedCommandLine: String?

    @State private var lastRecord: ProcessRecord?
    @State private var commandLine: String?

    var body: some View {
        Group {
            if let record {
                fields(record, exited: false)
            } else if let last = lastRecord {
                fields(last, exited: true)
            } else {
                TabPlaceholder(icon: "questionmark.circle", title: "Process exited",
                               caption: "The inspected process is no longer running.")
            }
        }
        .onAppear { cache(record) }
        .onChange(of: record) { newValue in cache(newValue) }
    }

    private func cache(_ record: ProcessRecord?) {
        guard let record else { return }
        lastRecord = record
        if commandLine == nil, record.detailLevel == .full {
            commandLine = LibProcProcessCollector().commandLine(for: record.pid)
        }
    }

    /// Command line resolution: same-user reads KERN_PROCARGS2 locally;
    /// daemon-filled rows carry it in the snapshot (§4.4).
    private func resolvedCommandLine(_ record: ProcessRecord) -> String? {
        record.detailLevel == .elevated ? elevatedCommandLine : commandLine
    }

    /// Nine fields in two capability tiers (spec §3.3): tier one is free for
    /// all processes; tier two is same-user or daemon-filled.
    private func fields(_ record: ProcessRecord, exited: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if exited {
                    exitedNotice
                }
                InspectorField("Name", record.name)
                InspectorField("PID", "\(record.pid)")
                InspectorField("PPID", "\(record.ppid)")
                InspectorField("User", "\(record.userName) (\(record.uid))")
                InspectorField("Path", record.path)
                InspectorField("Start time", Format.dateTime(
                    Date(timeIntervalSince1970: TimeInterval(record.identity.startUsec) / 1_000_000)))
                InspectorField("CPU", Format.cpu(record.cpuPercent))

                InspectorSectionDivider("Extended")

                if viewModel.requiresElevation(record) {
                    InspectorField("Memory RSS", "Requires elevation")
                    InspectorField("Command line", "Requires elevation")
                    InspectorField("Disk I/O", "Requires elevation")
                } else {
                    InspectorField("Memory RSS", Format.bytes(record.residentMemory))
                    InspectorField("Command line", resolvedCommandLine(record) ?? "—", multiline: true)
                    InspectorField("Disk I/O",
                                   "Read \(Format.rate(record.diskReadRate)) · Write \(Format.rate(record.diskWriteRate))")
                }
            }
            .padding(14)
        }
    }

    private var exitedNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(palette.textSecondary)
            Text("Process exited")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.subdued)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.bottom, 10)
    }
}

// MARK: - Shared field chrome

private struct InspectorField: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    var multiline = false

    init(_ label: String, _ value: String, multiline: Bool = false) {
        self.label = label
        self.value = value
        self.multiline = multiline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(value)
                .font(multiline ? .system(size: 11) : .system(size: 12))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(multiline ? nil : 2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

private struct InspectorSectionDivider: View {
    @Environment(\.palette) private var palette
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Rectangle().fill(palette.border).frame(height: 1)
        }
        .padding(.vertical, 8)
    }
}
