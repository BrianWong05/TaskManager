// UI/MainShell.swift
// Main window shell (spec §3.2): left vertical nav rail + content area, with
// the degradation status bar (§6.4) on top and the first-launch guided
// Elevation setup (§6.3) attached.

import SwiftUI

struct MainShell: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.palette) private var palette
    @State private var statusBarDismissed = false
    @State private var showSetup = false

    private var elevationStatus: ElevationStatus { appModel.elevation.status }

    var body: some View {
        VStack(spacing: 0) {
            if elevationStatus != .active && !statusBarDismissed {
                ElevationStatusBar { statusBarDismissed = true }
            }
            HStack(spacing: 0) {
                NavigationRail()
                content
            }
        }
        .background(palette.page)
        .navigationTitle("Task Manager")
        // Re-show the bar whenever the degradation reason changes (§6.4).
        .onChange(of: elevationStatus) { _ in
            statusBarDismissed = false
        }
        // Guided setup on first launch (spec §6.3).
        .onAppear {
            if elevationStatus == .notRegistered && !appModel.elevation.setupDeclined {
                showSetup = true
            }
        }
        .onChange(of: elevationStatus) { newStatus in
            if newStatus == .notRegistered && !appModel.elevation.setupDeclined && !showSetup {
                showSetup = true
            }
        }
        .sheet(isPresented: $showSetup) {
            ElevationSetupSheet()
                .environmentObject(appModel)
        }
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
