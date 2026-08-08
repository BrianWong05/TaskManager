// UI/Processes/ProcessRowViews.swift
// Group rows, process rows, heat-colored metric cells and the row context
// menu (spec §3.3).

import SwiftUI
import AppKit

/// Heat tier background tints (spec §3.3, prototype palette).
func heatColor(_ tier: HeatTier) -> Color {
    switch tier {
    case .none: return .clear
    case .tier1: return Color(red: 1.0, green: 0.82, blue: 0.47).opacity(0.25)
    case .tier2: return Color(red: 1.0, green: 0.67, blue: 0.35).opacity(0.45)
    case .tier3: return Color(red: 1.0, green: 0.47, blue: 0.31).opacity(0.60)
    }
}

struct ProcessRowView: View {
    @Environment(\.palette) private var palette
    let row: ProcessDisplayRow
    let isSelected: Bool
    @ObservedObject var viewModel: ProcessesViewModel
    let snapshot: ProcessSnapshot?
    let onSelect: () -> Void

    var body: some View {
        switch row {
        case .group(let group, let expanded):
            GroupRow(group: group, expanded: expanded, isSelected: isSelected,
                     viewModel: viewModel, snapshot: snapshot, onSelect: onSelect)
        case .process(let record, let indented):
            ProcessRow(record: record, indented: indented, isSelected: isSelected,
                       viewModel: viewModel, snapshot: snapshot, onSelect: onSelect)
        }
    }
}

// MARK: - Shared row chrome

private struct RowChrome: ViewModifier {
    @Environment(\.palette) private var palette
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(isSelected ? palette.accentSoft : .clear)
            .contentShape(Rectangle())
    }
}

// MARK: - App Group row

private struct GroupRow: View {
    @Environment(\.palette) private var palette
    let group: AppGroup
    let expanded: Bool
    let isSelected: Bool
    @ObservedObject var viewModel: ProcessesViewModel
    let snapshot: ProcessSnapshot?
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    viewModel.toggleExpanded(group)
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                Image(nsImage: IconCache.shared.icon(forBundlePath: group.bundlePath))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(group.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("(\(group.children.count))")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(group.aggregateStatus.rawValue)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .frame(width: ProcessColumns.statusWidth, alignment: .leading)

            metricCell(Format.cpu(group.totalCPUPercent),
                       tier: cpuHeatTier(percent: group.totalCPUPercent,
                                         coreCount: snapshot?.logicalCoreCount ?? 1))
                .frame(width: ProcessColumns.cpuWidth, alignment: .trailing)

            metricCell(Format.bytes(group.totalMemory),
                       tier: memoryHeatTier(bytes: group.totalMemory,
                                            totalBytes: snapshot?.totalMemoryBytes ?? 0))
                .frame(width: ProcessColumns.memoryWidth, alignment: .trailing)

            metricCell(Format.rate(group.totalDiskRate), tier: .none)
                .frame(width: ProcessColumns.diskWidth, alignment: .trailing)

            metricCell(group.totalNetRate.map(Format.rate) ?? "–", tier: .none)
                .frame(width: ProcessColumns.networkWidth, alignment: .trailing)

            Text("–") // per-process GPU unavailable on macOS (spec §4.5)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .frame(width: ProcessColumns.gpuWidth, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .modifier(RowChrome(isSelected: isSelected))
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("End all in group") {
                if let snapshot {
                    viewModel.endAll(in: group.bundlePath, snapshot: snapshot)
                }
            }
            .disabled(!group.children.contains { !$0.isProtected })
            Button("Force Quit all in group…") {
                // Confirmation flows through the same pending alert as single
                // rows; forceQuit(.group) then SIGKILLs every unprotected child.
                viewModel.forceQuitPending = .group(bundlePath: group.bundlePath)
            }
            .disabled(!group.children.contains { !$0.isProtected })
            Divider()
            Button("Show Details") {
                onSelect()
                viewModel.inspectorTarget = .group(bundlePath: group.bundlePath)
            }
        }
    }

    private func metricCell(_ text: String, tier: HeatTier) -> some View {
        Text(text)
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(palette.textPrimary)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(heatColor(tier))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Process row

private struct ProcessRow: View {
    @Environment(\.palette) private var palette
    let record: ProcessRecord
    let indented: Bool
    let isSelected: Bool
    @ObservedObject var viewModel: ProcessesViewModel
    let snapshot: ProcessSnapshot?
    let onSelect: () -> Void

    private var elevated: Bool { !viewModel.requiresElevation(record) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if indented {
                    Image(nsImage: IconCache.shared.icon(forBundlePath: record.bundlePath))
                        .resizable()
                        .frame(width: 16, height: 16)
                        .padding(.leading, 22)
                } else {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 16)
                }
                Text(record.name)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                if record.isProtected {
                    Text("Protected")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(palette.subdued)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(record.status.rawValue)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .frame(width: ProcessColumns.statusWidth, alignment: .leading)

            cpuCell
                .frame(width: ProcessColumns.cpuWidth, alignment: .trailing)

            memoryCell
                .frame(width: ProcessColumns.memoryWidth, alignment: .trailing)

            diskCell
                .frame(width: ProcessColumns.diskWidth, alignment: .trailing)

            netCell
                .frame(width: ProcessColumns.networkWidth, alignment: .trailing)

            Text("–") // per-process GPU unavailable on macOS (spec §4.5)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .frame(width: ProcessColumns.gpuWidth, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .modifier(RowChrome(isSelected: isSelected))
        .onTapGesture(perform: onSelect)
        .contextMenu { contextMenu }
    }

    // Extended metric cells show "Requires elevation" for cross-user rows
    // while the daemon is unavailable (spec §4.5 fallback table).

    @ViewBuilder private var cpuCell: some View {
        if elevated {
            metricText(Format.cpu(record.cpuPercent),
                       tier: cpuHeatTier(percent: record.cpuPercent,
                                         coreCount: snapshot?.logicalCoreCount ?? 1))
        } else {
            gatedText
        }
    }

    @ViewBuilder private var memoryCell: some View {
        if elevated {
            metricText(Format.bytes(record.residentMemory),
                       tier: memoryHeatTier(bytes: record.residentMemory,
                                            totalBytes: snapshot?.totalMemoryBytes ?? 0))
        } else {
            gatedText
        }
    }

    @ViewBuilder private var diskCell: some View {
        if elevated {
            metricText(Format.rate(record.totalDiskRate), tier: .none)
        } else {
            gatedText
        }
    }

    @ViewBuilder private var netCell: some View {
        if let down = record.netDownRate, let up = record.netUpRate {
            metricText(Format.rate(down + up), tier: .none)
        } else {
            Text("–") // nettop degraded or no data for this pid (spec §4.5)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var gatedText: some View {
        Text("Requires elevation")
            .font(.system(size: 10))
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
    }

    private func metricText(_ text: String, tier: HeatTier) -> some View {
        Text(text)
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(palette.textPrimary)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(heatColor(tier))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: Context menu (spec §3.3)

    @ViewBuilder private var contextMenu: some View {
        Button("End task") {
            viewModel.endTask(.process(record.identity), in: snapshot)
        }
        .disabled(record.isProtected)

        Button("Force Quit…") {
            viewModel.forceQuitPending = .process(record.identity)
        }
        .disabled(record.isProtected)

        Divider()

        Button("Show in Finder") {
            viewModel.showInFinder(record)
        }
        .disabled(record.bundlePath == nil && record.path.isEmpty)

        Button("Show Details") {
            onSelect()
            viewModel.inspectorTarget = .process(record.identity)
        }

        Button("Copy") {
            viewModel.copy(record)
        }
    }
}
