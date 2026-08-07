// UI/TabPlaceholder.swift
// Shared empty-state shown by tabs before their milestone lands. Every tab
// defines an empty state and an error state (spec §3.1).

import SwiftUI

struct TabPlaceholder: View {
    @Environment(\.palette) private var palette
    let icon: String
    let title: String
    let caption: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(palette.textSecondary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.page)
    }
}
