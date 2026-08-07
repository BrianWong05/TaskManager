// App/AppModel.swift
// Root app state shared by the main window and the Mini monitor.

import Foundation
import Combine
import AppKit

/// The five navigation destinations of the main window (spec §3.2).
enum MainTab: String, CaseIterable, Identifiable {
    case processes
    case performance
    case startup
    case users
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processes: return "Processes"
        case .performance: return "Performance"
        case .startup: return "Startup apps"
        case .users: return "Users"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .processes: return "list.bullet.rectangle"
        case .performance: return "waveform.path.ecg"
        case .startup: return "speedometer"
        case .users: return "person.2"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: MainTab

    /// Single data source shared by the main window and the Mini monitor
    /// (spec §4.3). Sampling starts once with the app.
    let elevation = ElevationManager()
    let snapshotStore: ProcessSnapshotStore
    let systemStore = SystemMetricsStore()
    let settings = SettingsStore()
    let startupStore: StartupStore

    /// Set by the Mini monitor to select a process once the main window
    /// shows (spec §3.8 panel top-process click).
    @Published var pendingProcessSelection: ProcessSelection?
    /// Drives the §4.2 sampling pause (window hidden + Mini monitor off).
    @Published var mainWindowVisible = true

    private var settingsCancellable: AnyCancellable?

    private(set) var miniMonitor: MiniMonitorController?

    init() {
        let stored = UserDefaults.standard.string(forKey: "selectedTab")
        selectedTab = stored.flatMap(MainTab.init(rawValue:)) ?? .processes
        // The sampler talks to the daemon through the Elevation client for
        // the batched cross-user detail fill (spec §4.4).
        snapshotStore = ProcessSnapshotStore(
            sampler: SamplerActor(elevatedDetailSource: elevation.client))
        startupStore = StartupStore(elevation: elevation)
        snapshotStore.start { [weak systemStore] sample in
            systemStore?.apply(sample)
        }
        elevation.start()
        settingsCancellable = settings.$showMenuBarMonitor
            .sink { [weak self] _ in self?.updateSamplingPause() }
        let monitor = MiniMonitorController()
        monitor.attach(appModel: self)
        miniMonitor = monitor
    }

    /// Window hidden AND menu-bar monitor disabled/hidden → process-level
    /// sampling pauses (spec §4.2).
    func updateSamplingPause() {
        if mainWindowVisible || settings.showMenuBarMonitor {
            snapshotStore.resume()
        } else {
            snapshotStore.pause()
        }
    }

    func select(_ tab: MainTab) {
        selectedTab = tab
        UserDefaults.standard.set(tab.rawValue, forKey: "selectedTab")
    }

    /// Open (or refocus) the main window, optionally selecting a process.
    func openMainWindow(selecting selection: ProcessSelection? = nil) {
        if let selection {
            pendingProcessSelection = selection
            select(.processes)
        }
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
