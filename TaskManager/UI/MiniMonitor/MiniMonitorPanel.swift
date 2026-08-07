// UI/MiniMonitor/MiniMonitorPanel.swift
// Popover panel of the Mini monitor (spec §3.8): CPU/Memory sparklines with
// current values, Top 5 processes by CPU (click selects in the main window),
// and an "Open Task Manager" button.

import SwiftUI

struct MiniMonitorPanel: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var snapshotStore: ProcessSnapshotStore
    @EnvironmentObject private var systemStore: SystemMetricsStore
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            metricsCard(title: "CPU",
                        value: systemStore.latest.map { Format.cpu($0.cpuPercent) } ?? "–",
                        history: systemStore.cpuHistory.values,
                        domainMax: 100)
            metricsCard(title: "Memory",
                        value: memoryValue,
                        history: systemStore.memoryHistory.values,
                        domainMax: 100)

            Text("Top processes by CPU")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)

            topProcesses

            Spacer(minLength: 0)

            Button {
                appModel.openMainWindow()
            } label: {
                Text("Open Task Manager")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(palette.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 320, height: 380)
        .background(palette.page)
    }

    private var memoryValue: String {
        guard let memory = systemStore.latest?.memory else { return "–" }
        return "\(Format.bytes(memoryInUse(memory))) / \(Format.bytes(memory.totalPhysical))"
    }

    private func metricsCard(title: String, value: String, history: [Double], domainMax: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
            Sparkline(values: history, domainMax: domainMax)
                .frame(height: 34)
        }
        .padding(10)
        .winCard()
    }

    /// Top 5 processes by CPU across the whole table (spec §3.8).
    private var topProcesses: some View {
        let top = flattenedProcesses
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(5)
        return VStack(spacing: 2) {
            if top.isEmpty {
                Text("No process data yet")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            ForEach(Array(top)) { record in
                Button {
                    appModel.openMainWindow(selecting: .process(record.identity))
                } label: {
                    HStack(spacing: 8) {
                        Text(record.name)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(Format.cpu(record.cpuPercent))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(palette.card)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private var flattenedProcesses: [ProcessRecord] {
        guard let snapshot = snapshotStore.snapshot else { return [] }
        var records = snapshot.backgroundProcesses
        for group in snapshot.groups {
            records.append(contentsOf: group.children)
        }
        return records
    }
}
