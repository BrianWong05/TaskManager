// Daemon/main.swift
// TaskManagerDaemon — root launchd daemon registered via SMAppService.
//
// Exposes exactly three XPC methods (see Shared/XPCProtocol.swift, spec §6.2).
// Connection policy: accept only callers whose binary carries the
// com.brianwong.taskmanager Team-ID signature; audit-log every privileged call.

import Foundation

final class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // TODO(M3): Team-ID validation of newConnection.effectiveUserIdentifier /
        // audit token via SecCodeCopyGuestWithAttributes, plus audit logging.
        newConnection.exportedInterface = NSXPCInterface(with: TaskManagerDaemonProtocol.self)
        newConnection.exportedObject = DaemonOperations()
        newConnection.resume()
        return true
    }
}

/// Implementation of the three-method daemon surface. Bodies land in M3.
final class DaemonOperations: NSObject, TaskManagerDaemonProtocol {
    func processDetails(forPIDs pids: [Int32], reply: @escaping ([TMProcessDetail]) -> Void) {
        reply([])
    }

    func terminate(pid: Int32, mode: TMTerminationMode, reply: @escaping (Bool, String?) -> Void) {
        reply(false, "Daemon not yet implemented")
    }

    func setStartupItem(label: String, enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        reply(false, "Daemon not yet implemented")
    }
}

// Mach-service listener named after the daemon's bundle identifier; launchd
// starts us on demand when the app checks in (plist: Daemon/*.plist).
let listener = NSXPCListener(machServiceName: kTaskManagerDaemonIdentifier)
let delegate = DaemonDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
