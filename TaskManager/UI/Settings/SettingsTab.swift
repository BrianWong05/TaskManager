// UI/Settings/SettingsTab.swift
// Settings tab (spec §3.7). M0 ships the empty shell; the background service
// status row and the three options land in M4.

import SwiftUI

struct SettingsTab: View {
    var body: some View {
        TabPlaceholder(
            icon: "gearshape",
            title: "Settings",
            caption: "Background service status, theme, start-at-login and the menu-bar monitor toggle appear here."
        )
    }
}
