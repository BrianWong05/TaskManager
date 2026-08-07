// App/TaskManagerApp.swift
// Entry point: main window scene. The menu-bar Mini monitor is managed by
// MenuBarController (NSStatusItem-based, see UI/MiniMonitor) rather than a
// MenuBarExtra scene, because the icon is live CPU-percentage text.

import SwiftUI

@main
struct TaskManagerApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        Window("Task Manager", id: "main") {
            ThemedContainer {
                MainShell()
                    .environmentObject(appModel)
                    .environmentObject(settings)
            }
            .preferredColorScheme(settings.theme.colorScheme) // spec §3.7 theme
            .frame(minWidth: 860, minHeight: 520) // spec §3.2 minimum size
        }
        .defaultSize(width: 1000, height: 640) // spec §3.2 default size
    }
}
