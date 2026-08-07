// Elevation/ElevationManager.swift
// SMAppService registration lifecycle + degradation state (spec §6.3, §6.4).
// Statuses feed the Settings service row (§3.7), the dismissable status bar
// (§6.4) and the first-launch guided setup (§6.3).

import Foundation
import Combine
import ServiceManagement

enum ElevationStatus: Equatable {
    /// Daemon registered and answering XPC.
    case active
    /// Registered in SMAppService but the daemon does not answer — typical
    /// signature-expiry symptom (spec §1 runbook).
    case signatureExpired
    /// Registered but awaiting user approval in System Settings.
    case requiresApproval
    /// Never registered, or removed by the user.
    case notRegistered
}

@MainActor
final class ElevationManager: ObservableObject {
    static let daemonPlistName = "com.brianwong.taskmanager.daemon.plist"

    @Published private(set) var status: ElevationStatus = .notRegistered
    /// Set once the user declines/dismisses setup so the guided sheet does
    /// not nag on every launch; "Retry setup" remains in Settings (§3.7).
    var setupDeclined: Bool {
        get { UserDefaults.standard.bool(forKey: "elevation.setupDeclined") }
        set { UserDefaults.standard.set(newValue, forKey: "elevation.setupDeclined") }
    }

    let client = DaemonClient()

    private var refreshTimer: Timer?
    private var probing = false

    private var daemonService: SMAppService {
        SMAppService.daemon(plistName: Self.daemonPlistName)
    }

    func start() {
        refresh()
        // Poll at a lazy cadence: catches Login-Items disablement and
        // signature expiry while running (spec §6.4 transition #6).
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Guided-setup entry point (spec §6.3). Throws on SMAppService failure;
    /// the system then shows the "Background Items Added" approval prompt.
    func register() throws {
        try daemonService.register()
        refresh()
    }

    /// Stable re-entry point after signature expiry / decline (spec §3.7).
    func retrySetup() {
        setupDeclined = false
        do {
            // Re-registering refreshes the stored signature requirement so a
            // freshly re-signed daemon passes launchd's check again.
            if daemonService.status == .enabled {
                try daemonService.unregister()
            }
            try daemonService.register()
        } catch {
            // Unregister can fail when nothing is registered; registration
            // errors surface through the next refresh anyway.
        }
        refresh()
    }

    var isActive: Bool { status == .active }

    func refresh() {
        guard !probing else { return }
        probing = true
        let serviceStatus = daemonService.status
        Task { [weak self, client] in
            let reachable: Bool
            switch serviceStatus {
            case .enabled:
                reachable = await client.isAvailable()
            default:
                reachable = false
            }
            await MainActor.run {
                guard let self else { return }
                switch serviceStatus {
                case .enabled:
                    self.status = reachable ? .active : .signatureExpired
                case .requiresApproval:
                    self.status = .requiresApproval
                default:
                    self.status = .notRegistered
                }
                self.probing = false
            }
        }
    }

    /// Human-readable state for the Settings service row (spec §3.7).
    var statusLabel: String {
        switch status {
        case .active: return "Registered"
        case .signatureExpired: return "Signature expired"
        case .requiresApproval: return "Awaiting approval"
        case .notRegistered: return "Not registered"
        }
    }
}
