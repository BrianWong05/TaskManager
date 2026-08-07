// Shared/XPCProtocol.swift
// Compiled into both the app and the daemon targets.
//
// The privileged daemon surface is exactly three methods (spec §6.2). Do NOT
// widen this interface (e.g. no open-files inspector, no arbitrary exec).

import Foundation

/// Mach service / bundle identifier of the daemon.
public let kTaskManagerDaemonIdentifier = "com.brianwong.taskmanager.daemon"

/// Termination mode for `terminate(pid:mode:)` — mirrors the app's semantics:
/// End task = SIGTERM (graceful, no confirmation), Force Quit = SIGKILL.
@objc public enum TMTerminationMode: Int32 {
    case graceful = 0 // SIGTERM
    case force = 1    // SIGKILL
}

/// Cross-user per-process detail filled by the daemon in one batched round-trip
/// (spec §4.4). Only fields an unprivileged caller cannot read itself.
@objc(TMProcessDetail)
// Immutable value container crossing actor boundaries in the sampling flow.
public final class TMProcessDetail: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    @objc public let pid: Int32
    /// Resident memory in bytes (resident_size; phys_footprint needs task ports, spec §4.5).
    @objc public let residentMemory: UInt64
    /// Cumulative CPU time in nanoseconds (for rate computation by the app).
    @objc public let cpuNanoseconds: UInt64
    /// Full argv, space-joined (KERN_PROCARGS2 is same-user only unprivileged).
    @objc public let commandLine: String
    /// Cumulative disk I/O counters from proc_pid_rusage.
    @objc public let diskBytesRead: UInt64
    @objc public let diskBytesWritten: UInt64
    /// Owning user id (for the "requires elevation" gating decisions).
    @objc public let uid: UInt32

    @objc public init(pid: Int32,
                      residentMemory: UInt64,
                      cpuNanoseconds: UInt64,
                      commandLine: String,
                      diskBytesRead: UInt64,
                      diskBytesWritten: UInt64,
                      uid: UInt32) {
        self.pid = pid
        self.residentMemory = residentMemory
        self.cpuNanoseconds = cpuNanoseconds
        self.commandLine = commandLine
        self.diskBytesRead = diskBytesRead
        self.diskBytesWritten = diskBytesWritten
        self.uid = uid
    }

    public func encode(with coder: NSCoder) {
        coder.encode(pid, forKey: "pid")
        coder.encode(residentMemory, forKey: "residentMemory")
        coder.encode(cpuNanoseconds, forKey: "cpuNanoseconds")
        coder.encode(commandLine, forKey: "commandLine")
        coder.encode(diskBytesRead, forKey: "diskBytesRead")
        coder.encode(diskBytesWritten, forKey: "diskBytesWritten")
        coder.encode(uid, forKey: "uid")
    }

    public init?(coder: NSCoder) {
        pid = coder.decodeInt32(forKey: "pid")
        residentMemory = UInt64(coder.decodeInt64(forKey: "residentMemory"))
        cpuNanoseconds = UInt64(coder.decodeInt64(forKey: "cpuNanoseconds"))
        commandLine = coder.decodeObject(of: NSString.self, forKey: "commandLine") as String? ?? ""
        diskBytesRead = UInt64(coder.decodeInt64(forKey: "diskBytesRead"))
        diskBytesWritten = UInt64(coder.decodeInt64(forKey: "diskBytesWritten"))
        uid = UInt32(coder.decodeInt32(forKey: "uid"))
    }
}

/// The daemon's exported interface — exactly three methods (spec §6.2).
@objc public protocol TaskManagerDaemonProtocol {
    /// Batched cross-user detail fill: one round-trip per sampling tick (spec §4.4).
    func processDetails(forPIDs pids: [Int32], reply: @escaping ([TMProcessDetail]) -> Void)
    /// SIGTERM / SIGKILL a process. Fails with a reason string for SIP-protected processes.
    func terminate(pid: Int32, mode: TMTerminationMode, reply: @escaping (Bool, String?) -> Void)
    /// System-scope `launchctl enable/disable` for a Startup item (spec §3.5).
    func setStartupItem(label: String, enabled: Bool, reply: @escaping (Bool, String?) -> Void)
}

/// Interface the app implements so the daemon can gate connections: the daemon
/// only accepts callers that pass its Team-ID signature check.
@objc public protocol TaskManagerDaemonListenerProtocol {
    func acceptConnection(completion: @escaping (Bool) -> Void)
}
