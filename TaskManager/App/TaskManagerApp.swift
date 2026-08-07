// App/TaskManagerApp.swift
// Entry point: main window scene. The menu-bar Mini monitor is managed by
// MenuBarController (NSStatusItem-based, see UI/MiniMonitor) rather than a
// MenuBarExtra scene, because the icon is live CPU-percentage text.

import SwiftUI

@main
struct TaskManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        Window("Task Manager", id: "main") {
            ThemedContainer {
                MainShell()
                    .environmentObject(appModel)
                    .environmentObject(appModel.settings)
            }
            .preferredColorScheme(appModel.settings.theme.colorScheme) // spec §3.7 theme
            .frame(minWidth: 860, minHeight: 520) // spec §3.2 minimum size
            // Window visibility drives the §4.2 sampling pause.
            .onChange(of: scenePhase) { phase in
                appModel.mainWindowVisible = (phase == .active)
                appModel.updateSamplingPause()
            }
        }
        .defaultSize(width: 1000, height: 640) // spec §3.2 default size
    }
}
