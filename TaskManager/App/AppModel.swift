// App/AppModel.swift
// Root app state shared by the main window and the Mini monitor.

import Foundation
import Combine

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
    let snapshotStore = ProcessSnapshotStore()

    init() {
        let stored = UserDefaults.standard.string(forKey: "selectedTab")
        selectedTab = stored.flatMap(MainTab.init(rawValue:)) ?? .processes
        snapshotStore.start()
    }

    func select(_ tab: MainTab) {
        selectedTab = tab
        UserDefaults.standard.set(tab.rawValue, forKey: "selectedTab")
    }
}
