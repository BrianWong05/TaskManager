// UI/Performance/PerformanceTab.swift
// Performance tab (spec §3.4): left resource list (name + live value +
// sparkline), right pane with the big ~60 s chart, headline value and stat
// row. Memory card carries the memory-pressure badge.

import SwiftUI
import Charts

enum PerformanceResource: String, CaseIterable, Identifiable {
    case cpu, memory, disk, network, gpu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .gpu: return "GPU"
        }
    }
}

struct PerformanceTab: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var systemStore: SystemMetricsStore
    @EnvironmentObject private var snapshotStore: ProcessSnapshotStore
    @Environment(\.palette) private var palette
    @State private var selected: PerformanceResource = .cpu

    var body: some View {
        HStack(spacing: 0) {
            sideList
            Divider().overlay(palette.border)
            detailPane
        }
        .background(palette.page)
    }

    // MARK: Left resource list

    private var sideList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(PerformanceResource.allCases) { resource in
                    ResourceListEntry(
                        resource: resource,
                        isActive: selected == resource,
                        value: headlineValue(resource),
                        history: history(for: resource),
                        domainMax: isPercentResource(resource) ? 100 : nil,
                        showPressureBadge: resource == .memory && systemStore.pressureLevel != nil
                    ) {
                        selected = resource
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 230)
    }

    // MARK: Right detail pane

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(selected.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if selected == .memory, let level = systemStore.pressureLevel {
                    Text(level.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(level == .critical ? Color(hex: 0xC42B1C) : Color(hex: 0x9D5D00))
                        .clipShape(Capsule())
                }
            }

            Text(headlineValue(selected))
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(palette.accent)

            ResourceChart(
                history: history(for: selected),
                isPercent: isPercentResource(selected),
                rateLabel: isRateResource(selected)
            )
            .frame(maxHeight: .infinity)
            .winCard()

            statGrid
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statGrid: some View {
        let stats = statItems(for: selected)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], spacing: 8) {
            ForEach(stats, id: \.label) { stat in
                VStack(alignment: .leading, spacing: 1) {
                    Text(stat.label)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    Text(stat.value)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    // MARK: Data access

    private func history(for resource: PerformanceResource) -> [Double] {
        switch resource {
        case .cpu: return systemStore.cpuHistory.values
        case .memory: return systemStore.memoryHistory.values
        case .disk: return systemStore.diskHistory.values
        case .network: return systemStore.netHistory.values
        case .gpu: return systemStore.gpuHistory.values
        }
    }

    private func isPercentResource(_ resource: PerformanceResource) -> Bool {
        resource == .cpu || resource == .memory || resource == .gpu
    }

    private func isRateResource(_ resource: PerformanceResource) -> Bool {
        resource == .disk || resource == .network
    }

    private func headlineValue(_ resource: PerformanceResource) -> String {
        guard let sample = systemStore.latest else { return "–" }
        switch resource {
        case .cpu:
            return Format.cpu(sample.cpuPercent)
        case .memory:
            return "\(Format.bytes(memoryInUse(sample.memory))) of \(Format.bytes(sample.memory.totalPhysical))"
        case .disk:
            return Format.rate(sample.diskReadRate + sample.diskWriteRate)
        case .network:
            return Format.rate(sample.netDownRate + sample.netUpRate)
        case .gpu:
            guard let gpu = sample.gpuUtilization else { return "Unavailable" }
            return Format.cpu(gpu)
        }
    }

    /// Stat row (spec §3.4): utilization, process count, cores/capacity,
    /// up time — adapted per resource.
    private func statItems(for resource: PerformanceResource) -> [(label: String, value: String)] {
        guard let sample = systemStore.latest else { return [] }
        let processCount = snapshotStore.snapshot?.processCount ?? 0
        let upTime = Format.upTime(sample.upTimeSeconds)
        switch resource {
        case .cpu:
            return [
                ("Utilization", Format.cpu(sample.cpuPercent)),
                ("Processes", "\(processCount)"),
                ("Logical cores", "\(sample.perCorePercent.isEmpty ? ProcessInfo.processInfo.processorCount : sample.perCorePercent.count)"),
                ("Up time", upTime),
            ]
        case .memory:
            let memory = sample.memory
            return [
                ("In use", Format.bytes(memoryInUse(memory))),
                ("Available", Format.bytes(memory.free &+ memory.inactive)),
                ("Capacity", Format.bytes(memory.totalPhysical)),
                ("Swap used", Format.bytes(memory.swapUsed)),
            ]
        case .disk:
            return [
                ("Read rate", Format.rate(sample.diskReadRate)),
                ("Write rate", Format.rate(sample.diskWriteRate)),
                ("Processes", "\(processCount)"),
                ("Up time", upTime),
            ]
        case .network:
            return [
                ("Receive", Format.rate(sample.netDownRate)),
                ("Send", Format.rate(sample.netUpRate)),
                ("Processes", "\(processCount)"),
                ("Up time", upTime),
            ]
        case .gpu:
            return [
                ("Utilization", sample.gpuUtilization.map(Format.cpu) ?? "Unavailable"),
                ("Processes", "\(processCount)"),
                ("Up time", upTime),
            ]
        }
    }
}

// MARK: - Side list entry

private struct ResourceListEntry: View {
    @Environment(\.palette) private var palette
    let resource: PerformanceResource
    let isActive: Bool
    let value: String
    let history: [Double]
    let domainMax: Double?
    let showPressureBadge: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(resource.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    if showPressureBadge {
                        Circle()
                            .fill(Color(hex: 0x9D5D00))
                            .frame(width: 7, height: 7)
                    }
                }
                Text(value)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Sparkline(values: history, domainMax: domainMax)
                    .frame(height: 26)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? palette.accentSoft : .clear)
            .overlay(alignment: .leading) {
                if isActive {
                    Rectangle()
                        .fill(palette.accent)
                        .frame(width: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Big chart (~60 s window, 1 s ticks, grid background — spec §3.4)

private struct ResourceChart: View {
    @Environment(\.palette) private var palette
    let history: [Double]
    let isPercent: Bool
    let rateLabel: Bool

    private struct Point: Identifiable {
        let index: Int
        let value: Double
        var id: Int { index }
    }

    var body: some View {
        let points = history.enumerated().map { Point(index: $0.offset, value: $0.element) }
        let autoMax = history.max() ?? 1
        let yMax = isPercent ? 100.0 : max(autoMax * 1.2, 1)

        Chart(points) { point in
            AreaMark(x: .value("Seconds", point.index), y: .value("Value", point.value))
                .foregroundStyle(
                    LinearGradient(colors: [palette.accent.opacity(0.25), palette.accent.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Seconds", point.index), y: .value("Value", point.value))
                .foregroundStyle(palette.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: .stride(by: 15)) { _ in
                AxisGridLine().foregroundStyle(palette.border)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(palette.border)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(rateLabel ? Format.bytes(v) : "\(Int(v))%")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        .padding(12)
    }
}
