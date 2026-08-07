// UI/NavigationRail.swift
// Left vertical nav rail (spec §3.2): icon + label per tab, non-collapsible
// in v1. Active item shows an accent bar plus a tinted background.

import SwiftUI

struct NavigationRail: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(MainTab.allCases) { tab in
                NavigationRailItem(
                    tab: tab,
                    isActive: appModel.selectedTab == tab
                ) {
                    appModel.select(tab)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 190)
        .background(palette.subdued)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(palette.border)
                .frame(width: 1)
        }
    }
}

private struct NavigationRailItem: View {
    @Environment(\.palette) private var palette
    let tab: MainTab
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(tab.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .font(.system(size: 13, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? palette.textPrimary : palette.textPrimary.opacity(0.85))
            .background(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.accent)
                        .frame(width: 3, height: 14)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? palette.accentSoft : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
