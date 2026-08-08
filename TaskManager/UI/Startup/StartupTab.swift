// UI/Startup/StartupTab.swift
// Startup apps tab (spec §3.5): launchd agents/daemons from the three
// directories plus read-only BTM login items. Columns: Name / Location /
// Status / toggle action. Header shows item count + enabled count.

import SwiftUI

struct StartupTab: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.palette) private var palette

    private var store: StartupStore { appModel.startupStore }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.border)
            columnHeader
            Divider().overlay(palette.border)
            itemList
        }
        .background(palette.page)
        .task { await store.reload() }
        .alert("Cannot toggle item",
               isPresented: Binding(get: { store.toggleErrorMessage != nil },
                                    set: { if !$0 { store.toggleErrorMessage = nil } })) {
            Button("OK", role: .cancel) { store.toggleErrorMessage = nil }
        } message: {
            Text(store.toggleErrorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            let enabledCount = store.items.filter(\.enabled).count
            Text("\(store.items.count) items · \(enabledCount) enabled")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Button {
                // User-initiated: re-read Login Items too, accepting the
                // authorization prompt sfltool triggers.
                Task { await store.reload(refreshLoginItems: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Location")
                .frame(width: 260, alignment: .leading)
            Text("Status")
                .frame(width: 90, alignment: .leading)
            Text("")
                .frame(width: 150, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(palette.card)
    }

    @ViewBuilder
    private var itemList: some View {
        if store.items.isEmpty {
            TabPlaceholder(icon: "speedometer",
                           title: store.isLoading ? "Loading…" : "No Startup items",
                           caption: store.isLoading
                               ? "Enumerating launch agents, daemons and login items."
                               : "No launchd entries or login items were found.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.items) { item in
                        StartupRow(item: item) {
                            Task { await store.toggle(item) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
        }
    }
}

private struct StartupRow: View {
    @Environment(\.palette) private var palette
    let item: StartupItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(item.name)
                .font(.system(size: 12))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.location)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 260, alignment: .leading)

            Text(item.enabled ? "Enabled" : "Disabled")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(item.enabled ? Color(hex: 0x0F7B0F) : palette.textSecondary)
                .frame(width: 90, alignment: .leading)

            action
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var action: some View {
        switch item.toggleAbility {
        case .readOnly:
            // BTM items: real state + System Settings hand-off (spec §3.5).
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)
        default:
            Button(item.enabled ? "Disable" : "Enable", action: onToggle)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(palette.subdued)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .buttonStyle(.plain)
        }
    }
}
