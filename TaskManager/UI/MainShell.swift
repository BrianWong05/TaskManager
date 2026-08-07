// UI/MainShell.swift
// Main window shell (spec §3.2): left vertical nav rail + content area.
// The degradation status bar (§6.4) will occupy the top of the content area
// once Elevation lands in M3.

import SwiftUI

struct MainShell: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            NavigationRail()
            content
        }
        .background(palette.page)
        .navigationTitle("Task Manager")
    }

    @ViewBuilder
    private var content: some View {
        switch appModel.selectedTab {
        case .processes:
            ProcessesTab()
        case .performance:
            PerformanceTab()
        case .startup:
            StartupTab()
        case .users:
            UsersTab()
        case .settings:
            SettingsTab()
        }
    }
}
