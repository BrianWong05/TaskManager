// UI/Shared/Sparkline.swift
// Tiny history chart used by the Performance side list, the Mini monitor panel
// (spec §3.4, §3.8) and the Logical processors cells (per-core addendum §1.2).
// Plain paths, no Swift Charts — the per-core grid draws one per logical CPU
// every second and has to stay inside the app's CPU budget.

import SwiftUI

struct Sparkline: View {
    let values: [Double]
    /// Fixed upper domain bound; nil = auto-fit to the data.
    var domainMax: Double? = nil
    var lineWidth: CGFloat = 1.5
    /// Adds the big chart's top-down gradient under the line.
    var fill = false

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let maxDomain = max(domainMax ?? values.max() ?? 1, 0.000001)
            let stepX = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : 0
            let points = values.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) * stepX,
                        y: geo.size.height * (1 - CGFloat(min(value / maxDomain, 1))))
            }
            ZStack {
                if fill, points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        path.addLines(points)
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [palette.accent.opacity(0.25), palette.accent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                }
                Path { path in
                    guard points.count > 1 else { return }
                    path.addLines(points)
                }
                .stroke(palette.accent, lineWidth: lineWidth)
            }
        }
    }
}
