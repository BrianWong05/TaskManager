// UI/Performance/LogicalProcessorsGrid.swift
// The Logical processors CPU graph mode (per-core addendum §1.2): one section
// per performance level, efficiency first, each an adaptive grid of 0–100 %
// mini charts with a hover tooltip. Sections share the card's height in
// proportion to their row counts, as prototyped.

import SwiftUI

struct LogicalProcessorsGrid: View {
    @Environment(\.palette) private var palette
    let topology: CoreTopology
    let histories: [RingBuffer<Double>]
    /// Latest per-core percentages — cluster averages and tooltips.
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
                    CoreChartCell(label: core.label,
                                  levelName: cluster.name,   // empty on single-level machines
                                  history: history(core.index),
                                  current: percent(core.index))
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
    // core count must still render, so every lookup is bounds-checked.
    private func history(_ index: Int) -> [Double] {
        histories.indices.contains(index) ? histories[index].values : []
    }

    private func percent(_ index: Int) -> Double {
        current.indices.contains(index) ? current[index] : 0
    }

    private func average(_ cluster: CoreCluster) -> Double {
        guard !cluster.cores.isEmpty else { return 0 }
        return cluster.cores.reduce(0) { $0 + percent($1.index) } / Double(cluster.cores.count)
    }
}

/// One core's mini chart: fixed 0–100 % scale, corner label, hover tooltip.
private struct CoreChartCell: View {
    @Environment(\.palette) private var palette
    let label: String
    let levelName: String
    let history: [Double]
    let current: Double

    var body: some View {
        Sparkline(values: history, domainMax: 100, lineWidth: 1, fill: true)
            .padding(3)
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textSecondary)
                    .padding(3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
            .help(tooltip)
    }

    private var tooltip: String {
        levelName.isEmpty
            ? "\(label) — \(Format.cpu(current))"
            : "\(label) (\(levelName)) — \(Format.cpu(current))"
    }
}
