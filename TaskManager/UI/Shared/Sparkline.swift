// UI/Shared/Sparkline.swift
// Tiny stroke-only history chart used by the Performance side list and the
// Mini monitor panel (spec §3.4, §3.8).

import SwiftUI

struct Sparkline: View {
    let values: [Double]
    /// Fixed upper domain bound; nil = auto-fit to the data.
    var domainMax: Double? = nil
    var lineWidth: CGFloat = 1.5

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let maxDomain = max(domainMax ?? values.max() ?? 1, 0.000001)
            Path { path in
                guard values.count > 1 else { return }
                let stepX = geo.size.width / CGFloat(values.count - 1)
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = geo.size.height * (1 - CGFloat(min(value / maxDomain, 1)))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(palette.accent, lineWidth: lineWidth)
        }
    }
}
