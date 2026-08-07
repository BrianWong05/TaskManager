// UI/Settings/SettingsTab.swift
// Settings tab (spec §3.7): background service status row on top, then
// exactly three options — Theme, Start at login, Show menu-bar monitor.
// No refresh-rate knob: cadence is internal behavior (§5.1).

import SwiftUI
import ServiceManagement

struct SettingsTab: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                serviceRow
                optionCard {
                    themeRow
                    Divider().overlay(palette.border)
                    loginRow
                    Divider().overlay(palette.border)
                    menuBarRow
                }
            }
            .padding(16)
        }
        .background(palette.page)
    }

    // MARK: Background service status row (spec §3.7 — stable re-entry point)

    private var serviceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Background service")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(appModel.elevation.statusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(serviceColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(serviceColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            Text(serviceCaption)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 8) {
                Button("Retry setup") {
                    appModel.elevation.retrySetup()
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(palette.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .buttonStyle(.plain)

                Button("Open Login Items") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(palette.subdued)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .winCard()
    }

    private var serviceColor: Color {
        switch appModel.elevation.status {
        case .active: return Color(hex: 0x0F7B0F)
        case .signatureExpired: return Color(hex: 0xC42B1C)
        case .requiresApproval: return Color(hex: 0x9D5D00)
        case .notRegistered: return palette.textSecondary
        }
    }

    private var serviceCaption: String {
        switch appModel.elevation.status {
        case .active:
            return "The privileged helper is registered. Cross-user details, cross-user termination and system Startup toggles are available."
        case .signatureExpired:
            return "The daemon signature expired. Rebuild from Xcode, then Retry setup (see the README runbook)."
        case .requiresApproval:
            return "Approve the background item under System Settings ▸ General ▸ Login Items."
        case .notRegistered:
            return "Everything unprivileged works without it; cross-user features need the helper."
        }
    }

    // MARK: The three options

    private func optionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) { content() }
            .padding(14)
            .winCard()
    }

    private var themeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Theme")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                Text("System tracks the macOS appearance.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Picker("", selection: $settings.theme) {
                ForEach(ThemePreference.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
        }
    }

    private var loginRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start at login")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                Text("Login-item launches stay in the menu bar; manual launches open the window.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { settings.startAtLogin },
                set: { newValue in
                    settings.startAtLogin = newValue
                    applyLoginItem(enabled: newValue)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    private var menuBarRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show menu-bar monitor")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                Text("Live CPU percentage icon with sparklines and top processes.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $settings.showMenuBarMonitor)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    /// SMAppService.mainApp registration mirrors the toggle (spec §3.7).
    /// Independent of the daemon registration.
    private func applyLoginItem(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            // Registration failure (e.g. unsigned build) — revert the UI.
            settings.startAtLogin = !enabled
        }
    }
}
