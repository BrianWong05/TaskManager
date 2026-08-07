// Daemon/main.swift
// TaskManagerDaemon — root launchd daemon registered via SMAppService.
//
// Exposes exactly three XPC methods (see Shared/XPCProtocol.swift, spec §6.2).
// Connection policy: accept only callers whose binary carries our own Team-ID
// signature (falling back to a bundle-identifier match for ad-hoc builds).
// Every privileged call appends an audit-log line (spec §6.2).

import Foundation
import Security

final class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    private let operations = DaemonOperations()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard CallerValidator.isAuthorized(newConnection) else {
            AuditLog.record(operation: "acceptConnection",
                            target: "pid \(newConnection.processIdentifier)",
                            result: "rejected (signature check failed)")
            return false
        }
        // Audit lines attribute the caller, not the daemon itself (§6.2).
        operations.callerPid = newConnection.processIdentifier
        newConnection.exportedInterface = {
            let interface = NSXPCInterface(with: TaskManagerDaemonProtocol.self)
            // TMProcessDetail arrays need explicit allowed classes on the reply.
            // (Class objects bridge to AnyHashable via NSSet; Swift metatypes
            // are not Hashable directly.)
            let allowedClasses = NSSet(objects: TMProcessDetail.self, NSArray.self) as! Set<AnyHashable>
            interface.setClasses(allowedClasses,
                                 for: #selector(TaskManagerDaemonProtocol.processDetails(forPIDs:reply:)),
                                 argumentIndex: 0, ofReply: true)
            return interface
        }()
        newConnection.exportedObject = operations
        newConnection.resume()
        return true
    }
}

// MARK: - Caller validation (spec §6.2)

enum CallerValidator {
    /// Accept only binaries signed with the same Team ID as this daemon.
    /// The identifier-only fallback applies EXCLUSIVELY when the daemon
    /// itself is ad-hoc signed (development builds): a team-signed daemon
    /// must never accept a caller lacking a TeamIdentifier, otherwise any
    /// locally forged ad-hoc binary with the right identifier could reach
    /// the root surface.
    static func isAuthorized(_ connection: NSXPCConnection) -> Bool {
        guard let callerInfo = signingInfo(pid: connection.processIdentifier) else {
            return false
        }
        let ownTeam = selfSigningInfo()?["TeamIdentifier"] as? String
        let callerTeam = callerInfo["TeamIdentifier"] as? String
        if let ownTeam, !ownTeam.isEmpty {
            return callerTeam == ownTeam
        }
        // Daemon is ad-hoc (pre-team development build): identifier match.
        let identifier = callerInfo[kSecCodeInfoIdentifier as String] as? String
        return identifier == "com.brianwong.taskmanager"
    }

    private static func signingInfo(pid: Int32) -> [String: Any]? {
        let attributes: [CFString: Any] = [kSecGuestAttributePid: Int(pid)]
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &guest) == errSecSuccess,
              let guest else { return nil }
        return signingInfo(code: guest)
    }

    private static func selfSigningInfo() -> [String: Any]? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return nil }
        return signingInfo(code: selfCode)
    }

    private static func signingInfo(code: SecCode) -> [String: Any]? {
        // SecCode and SecStaticCode are the same CF object family; the Swift
        // import treats them as unrelated types.
        let staticCode = unsafeBitCast(code, to: SecStaticCode.self)
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let information else {
            return nil
        }
        return information as? [String: Any]
    }
}

// MARK: - Audit log (spec §6.2)

enum AuditLog {
    private static let path = "/Library/Application Support/TaskManager/audit.log"

    /// Set per accepted connection: audit lines attribute the caller (§6.2).
    nonisolated(unsafe) static var callerPid: Int32 = 0

    static func record(operation: String, target: String, result: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) caller=\(callerPid) op=\(operation) target=\(target) result=\(result)\n"
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory,
                                                 withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                handle.closeFile()
            }
        } else {
            try? Data(line.utf8).write(to: URL(fileURLWithPath: path))
        }
    }
}

// Mach-service listener named after the daemon's bundle identifier; launchd
// starts us on demand when the app checks in (plist: Daemon/*.plist).
let listener = NSXPCListener(machServiceName: kTaskManagerDaemonIdentifier)
let delegate = DaemonDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
