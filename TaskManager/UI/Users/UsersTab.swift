// UI/Users/UsersTab.swift
// Users tab (spec §3.6): one row per user with process count and aggregate
// CPU/memory; current user highlighted; rows whose detail still requires
// elevation show a "requires elevation" chip.

import SwiftUI

private struct UserRowData: Identifiable {
    let uid: UInt32
    let name: String
    let processCount: Int
    let totalCPU: Double
    let totalMemory: UInt64
    let needsElevation: Bool

    var id: UInt32 { uid }
}

struct UsersTab: View {
    @EnvironmentObject private var appModel: AppModel
    /// Observed directly — see ProcessesTab (§4.2).
    @EnvironmentObject private var snapshotStore: ProcessSnapshotStore
    @Environment(\.palette) private var palette

    private let currentUid = getuid()

    var body: some View {
        VStack(spacing: 0) {
            columnHeader
            Divider().overlay(palette.border)
            if rows.isEmpty {
                TabPlaceholder(icon: "person.2", title: "Waiting for data",
                               caption: "Per-user aggregates appear after the first sample.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            userRow(row)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
            }
        }
        .background(palette.page)
    }

    private var rows: [UserRowData] {
        guard let snapshot = snapshotStore.snapshot else { return [] }
        var byUid: [UInt32: (name: String, count: Int, cpu: Double, memory: UInt64, gated: Bool)] = [:]
        var all = snapshot.backgroundProcesses
        for group in snapshot.groups { all.append(contentsOf: group.children) }
        for record in all {
            var entry = byUid[record.uid] ?? (record.userName, 0, 0, 0, false)
            entry.count += 1
            entry.cpu += record.cpuPercent
            entry.memory += record.residentMemory
            entry.gated = entry.gated || record.detailLevel == .requiresElevation
            byUid[record.uid] = entry
        }
        return byUid
            .map { uid, entry in
                UserRowData(uid: uid, name: entry.name, processCount: entry.count,
                            totalCPU: entry.cpu, totalMemory: entry.memory,
                            needsElevation: entry.gated)
            }
            .sorted { $0.totalMemory > $1.totalMemory }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("User")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Processes")
                .frame(width: 100, alignment: .trailing)
            Text("CPU")
                .frame(width: 100, alignment: .trailing)
            Text("Memory")
                .frame(width: 120, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(palette.card)
    }

    private func userRow(_ row: UserRowData) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(palette.textSecondary)
                Text(row.name)
                    .font(.system(size: 12, weight: row.uid == currentUid ? .semibold : .regular))
                    .foregroundStyle(palette.textPrimary)
                if row.uid == currentUid {
                    Text("Current user")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(palette.accentSoft)
                        .clipShape(Capsule())
                }
                if row.needsElevation {
                    Text("requires elevation")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(palette.subdued)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(row.processCount)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .frame(width: 100, alignment: .trailing)

            Text(Format.cpu(row.totalCPU))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .frame(width: 100, alignment: .trailing)

            Text(Format.bytes(row.totalMemory))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, row.uid == currentUid ? 8 : 0)
        .background(row.uid == currentUid ? palette.accentSoft.opacity(0.5) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
