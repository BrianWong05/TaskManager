// UI/Performance/PerformanceTab.swift
// Performance tab (spec §3.4). M0 ships the empty shell; system collectors,
// ring buffers and charts land in M2.

import SwiftUI

struct PerformanceTab: View {
    var body: some View {
        TabPlaceholder(
            icon: "waveform.path.ecg",
            title: "Performance",
            caption: "CPU, Memory, Disk, Network and GPU charts appear here."
        )
    }
}
