// UI/MiniMonitor/MiniMonitorController.swift
// Menu-bar Mini monitor (spec §3.8): the status item icon is live CPU
// percentage text updated on the sampling cadence; clicking opens a panel
// with sparklines, Top 5 processes and an entry back to the main window.
// The Settings toggle hides status item + panel without touching the main
// window (spec §3.7).

import AppKit
import SwiftUI
import Combine

@MainActor
final class MiniMonitorController: NSObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private weak var appModel: AppModel?
    private var cancellables = Set<AnyCancellable>()

    func attach(appModel: AppModel) {
        self.appModel = appModel

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.title = "–"
            button.action = #selector(togglePanel)
            button.target = self
        }
        statusItem = item

        let host = NSHostingController(
            rootView: ThemedContainer { MiniMonitorPanel() }
                .environmentObject(appModel)
                .environmentObject(appModel.snapshotStore)
                .environmentObject(appModel.systemStore)
        )
        popover.contentViewController = host
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 380)

        // Icon text follows the sampling cadence (spec §3.8).
        appModel.systemStore.$latest
            .receive(on: RunLoop.main)
            .sink { [weak self] sample in
                guard let self, let sample else { return }
                self.statusItem?.button?.title = "\(Int(sample.cpuPercent.rounded()))%"
            }
            .store(in: &cancellables)

        // Toggle visibility from Settings (spec §3.7).
        appModel.settings.$showMenuBarMonitor
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.statusItem?.isVisible = visible
                if !visible { self?.popover.performClose(nil) }
            }
            .store(in: &cancellables)
    }

    @objc private func togglePanel() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
