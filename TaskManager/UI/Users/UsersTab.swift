// UI/Users/UsersTab.swift
// Users tab (spec §3.6). M0 ships the empty shell; per-user aggregation
// lands with the data layer.

import SwiftUI

struct UsersTab: View {
    var body: some View {
        TabPlaceholder(
            icon: "person.2",
            title: "Users",
            caption: "Per-user process counts and resource use appear here."
        )
    }
}
