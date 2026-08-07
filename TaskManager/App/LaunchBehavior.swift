// App/LaunchBehavior.swift
// Launch behavior (spec §3.7, no setting): login-item launches stay
// background-only (menu-bar presence, no window); manual launches open the
// main window. Login-item launches are detected heuristically — the app
// starting within seconds of the user session beginning while the login
// item is registered — since macOS exposes no direct "launched as login
// item" API.

import AppKit
import ServiceManagement
import Foundation

enum LaunchBehavior {
    static func isLoginItemLaunch() -> Bool {
        guard SMAppService.mainApp.status == .enabled else { return false }
        guard let loginDate = currentSessionLoginDate() else { return false }
        return Date().timeIntervalSince(loginDate) < 30
    }

    /// Latest USER_PROCESS utmpx entry for the current user → session start.
    private static func currentSessionLoginDate() -> Date? {
        let currentUser = NSUserName()
        var latest: Date?
        setutxent()
        defer { endutxent() }
        while let entry = getutxent() {
            let record = entry.pointee
            guard record.ut_type == USER_PROCESS else { continue }
            let user = withUnsafeBytes(of: record.ut_user) { raw -> String in
                guard let base = raw.baseAddress else { return "" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
            guard user == currentUser else { continue }
            let stamp = Date(timeIntervalSince1970: TimeInterval(record.ut_tv.tv_sec))
            if stamp > (latest ?? .distantPast) {
                latest = stamp
            }
        }
        return latest
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard LaunchBehavior.isLoginItemLaunch() else { return }
        // Let SwiftUI finish presenting, then drop the window: the Mini
        // monitor remains as the sole presence (spec §3.7).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                window.close()
            }
        }
    }

    /// Reopening a background-only instance (Dock click) restores the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
