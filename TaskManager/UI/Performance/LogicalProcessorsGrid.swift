// UI/Performance/LogicalProcessorsGrid.swift
// The Logical processors CPU graph mode (per-core addendum §1.2): one section
// per performance level, efficiency first, each an adaptive grid of segment
// meters. Cells show the *current* value only — no history — so the tile is a
// stack of lit rungs under a header line carrying the label and the percentage.

import SwiftUI

struct LogicalProcessorsGrid: View {
    @Environment(\.palette) private var palette
    let topology: CoreTopology
    /// Latest per-core percentages: cells, cluster averages and tooltips.
    let current: [Double]

    /// The addendum quotes ≈120 pt, but its reference layout (14 cores:
    /// efficiency 4-across, performance 5 × 2) needs the fifth column to fit
    /// the 516 pt card of a default-size window — the mock's own cells are
    /// ~112 pt in a wider shell. 96 keeps the prototype's cell proportions.
    private let minCellWidth: CGFloat = 96
    private let cellSpacing: CGFloat = 8
    private let sectionSpacing: CGFloat = 14
    private let headerHeight: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let columns = max(1, Int((geo.size.width + cellSpacing) / (minCellWidth + cellSpacing)))
            let rows = topology.clusters.map { rowCount($0, columns: columns) }
            let totalRows = max(1, rows.reduce(0, +))
            let headers = topology.isSingleLevel ? 0 : CGFloat(topology.clusters.count) * (headerHeight + 4)
            let gaps = CGFloat(max(0, topology.clusters.count - 1)) * sectionSpacing
                + CGFloat(totalRows - topology.clusters.count) * cellSpacing
            let cellHeight = max(44, (geo.size.height - headers - gaps) / CGFloat(totalRows))

            VStack(alignment: .leading, spacing: sectionSpacing) {
                ForEach(topology.clusters) { cluster in
                    section(cluster, columns: columns, cellHeight: cellHeight)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    private func section(_ cluster: CoreCluster, columns: Int, cellHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !topology.isSingleLevel {
                Text("\(cluster.name) cores — \(Format.cpu(average(cluster)))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(height: headerHeight, alignment: .leading)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: cellSpacing),
                               count: max(1, min(cluster.cores.count, columns))),
                spacing: cellSpacing
            ) {
                ForEach(cluster.cores) { core in
                    CoreSegmentMeter(label: core.label,
                                     levelName: cluster.name,   // empty on single-level machines
                                     percent: percent(core.index))
                        .frame(height: cellHeight)
                }
            }
        }
    }

    private func rowCount(_ cluster: CoreCluster, columns: Int) -> Int {
        let perRow = max(1, min(cluster.cores.count, columns))
        return max(1, Int(ceil(Double(cluster.cores.count) / Double(perRow))))
    }

    // The topology is read once at startup; a sample that disagrees about the
    // core count must still render, so the lookup is bounds-checked.
    private func percent(_ index: Int) -> Double {
        current.indices.contains(index) ? current[index] : 0
    }

    private func average(_ cluster: CoreCluster) -> Double {
        guard !cluster.cores.isEmpty else { return 0 }
        return cluster.cores.reduce(0) { $0 + percent($1.index) } / Double(cluster.cores.count)
    }
}

/// How many of `SegmentMeter.count` rungs a percentage lights. Any non-zero
/// load lights at least one, so a busy core is never drawn idle.
func litSegments(percent: Double, of count: Int) -> Int {
    guard percent > 0 else { return 0 }
    let scaled = Int((percent / 100 * Double(count)).rounded())
    return min(count, max(1, scaled))
}

/// One core: a stack of rungs lit to the current value, under a header line.
private struct CoreSegmentMeter: View {
    @Environment(\.palette) private var palette
    let label: String
    let levelName: String
    let percent: Double

    static let segmentCount = 10

    var body: some View {
        let tier = coreHeatTier(percent: percent)
        let lit = litSegments(percent: percent, of: Self.segmentCount)

        VStack(spacing: 0) {
            header
            VStack(spacing: 2) {
                // Top rung first: index 0 is the highest, so the stack fills up.
                ForEach(0..<Self.segmentCount, id: \.self) { row in
                    let rung = Self.segmentCount - 1 - row
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        // Unlit rungs stay visible — the empty half of the
                        // stack is what makes it read as a meter.
                        .fill(rung < lit ? litColor(tier, rung: rung) : palette.border.opacity(0.55))
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(EdgeInsets(top: 3, leading: 4, bottom: 4, trailing: 4))
        }
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
        .help(tooltip)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            Text("\(Int(percent.rounded())) %")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 5)
        .padding(.top, 3)
    }

    /// Higher rungs sit at fuller strength, so the stack reads as a climb even
    /// within one tier.
    private func litColor(_ tier: HeatTier, rung: Int) -> Color {
        let ramp = 0.30 + Double(rung) / Double(Self.segmentCount) * 0.62
        return (tier == .none ? palette.accent : heatBaseColor(tier)).opacity(ramp)
    }

    private var tooltip: String {
        levelName.isEmpty
            ? "\(label) — \(Format.cpu(percent))"
            : "\(label) (\(levelName)) — \(Format.cpu(percent))"
    }
}
