// UI/Startup/StartupTab.swift
// Startup apps tab (spec §3.5). M0 ships the empty shell; launchd
// enumeration, BTM parsing and toggles land in M4.

import SwiftUI

struct StartupTab: View {
    var body: some View {
        TabPlaceholder(
            icon: "speedometer",
            title: "Startup apps",
            caption: "Launch agents, launch daemons and login items appear here."
        )
    }
}
