// UI/Processes/ProcessesTab.swift
// Processes tab (spec §3.3). M0 ships the empty shell; the grouped list,
// search/sort/heat coloring, termination actions and inspector land in M1.

import SwiftUI

struct ProcessesTab: View {
    @Environment(\.palette) private var palette

    var body: some View {
        TabPlaceholder(
            icon: "list.bullet.rectangle",
            title: "Processes",
            caption: "The app-grouped process list appears here once sampling is wired up."
        )
    }
}
