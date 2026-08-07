// App/SettingsStore.swift
// Persisted user options (spec §3.7): exactly three in v1 — Theme,
// Start at login, Show menu-bar monitor. No refresh-rate knob.

import Foundation
import Combine

final class SettingsStore: ObservableObject {
    enum Keys {
        static let theme = "settings.theme"
        static let startAtLogin = "settings.startAtLogin"
        static let showMenuBarMonitor = "settings.showMenuBarMonitor"
    }

    @Published var theme: ThemePreference {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// Default Off (spec §3.7). The SMAppService login item itself is managed
    /// in M4; this store only records the preference.
    @Published var startAtLogin: Bool {
        didSet { UserDefaults.standard.set(startAtLogin, forKey: Keys.startAtLogin) }
    }

    /// Default On (spec §3.7). Off hides the Mini monitor status item + panel;
    /// the main window is unaffected.
    @Published var showMenuBarMonitor: Bool {
        didSet { UserDefaults.standard.set(showMenuBarMonitor, forKey: Keys.showMenuBarMonitor) }
    }

    init(defaults: UserDefaults = .standard) {
        theme = defaults.string(forKey: Keys.theme)
            .flatMap(ThemePreference.init(rawValue:)) ?? .system
        startAtLogin = defaults.bool(forKey: Keys.startAtLogin)
        showMenuBarMonitor = defaults.object(forKey: Keys.showMenuBarMonitor) as? Bool ?? true
    }
}
