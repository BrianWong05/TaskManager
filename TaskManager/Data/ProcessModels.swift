// Data/ProcessModels.swift
// Immutable value types published by the SamplerActor every tick (spec §4).

import Foundation

/// Process identity = PID + start timestamp composite key (spec §4.1).
/// Protects against PID reuse: same PID with a different start time is a
/// different process.
struct ProcessIdentity: Hashable, Sendable {
    let pid: Int32
    /// Start time in microseconds since the epoch (kinfo_proc.kp_proc.p_starttime).
    let startUsec: UInt64
}

/// Coarse process state rendered in the Status column.
enum ProcessStatus: String, Sendable {
    case running = "Running"
    case stopped = "Stopped"
    case starting = "Starting"
    case exiting = "Exiting"
}

/// Detail availability for cross-user rows (spec §4.5, §6.4).
enum ProcessDetailLevel: Sendable, Equatable {
    /// Same-user process: all base + extended fields readable unprivileged.
    case full
    /// Cross-user process, daemon unavailable: extended fields gated.
    case requiresElevation
    /// Daemon filled the extended fields this tick.
    case elevated
}

/// One row of the Processes tab. Immutable per snapshot.
struct ProcessRecord: Identifiable, Sendable, Equatable {
    let identity: ProcessIdentity
    var name: String
    var path: String
    /// Containing .app bundle path if the executable resolves into one.
    var bundlePath: String?
    var uid: UInt32
    var userName: String
    var ppid: Int32
    var status: ProcessStatus
    /// SIP/platform-protected: termination controls disabled (spec §3.3, §6.5).
    var isProtected: Bool

    /// Normalized to all cores: one fully busy core == 1.0 (spec §4.1).
    var cpuPercent: Double
    var residentMemory: UInt64
    var diskReadRate: Double    // bytes/s
    var diskWriteRate: Double   // bytes/s
    /// nil = per-process network unavailable this tick (column shows `–`).
    var netDownRate: Double?    // bytes/s
    var netUpRate: Double?      // bytes/s

    var detailLevel: ProcessDetailLevel

    var id: ProcessIdentity { identity }
    var pid: Int32 { identity.pid }

    var totalDiskRate: Double { diskReadRate + diskWriteRate }
    var totalNetRate: Double { (netDownRate ?? 0) + (netUpRate ?? 0) }
}

/// App Group: all processes whose executable resolves into the same .app
/// bundle (spec §3.3, §4.1). Group metrics are sums of children.
struct AppGroup: Identifiable, Sendable {
    let bundlePath: String
    var displayName: String
    var children: [ProcessRecord]

    var id: String { bundlePath }
    var totalCPUPercent: Double { children.reduce(0) { $0 + $1.cpuPercent } }
    var totalMemory: UInt64 { children.reduce(0) { $0 + $1.residentMemory } }
    var totalDiskRate: Double { children.reduce(0) { $0 + $1.totalDiskRate } }
    var totalNetRate: Double { children.reduce(0) { $0 + $1.totalNetRate } }
    var containsProtected: Bool { children.contains(where: \.isProtected) }
}

/// The flat "Background processes" section + grouped apps, one frame.
struct ProcessSnapshot: Sendable {
    var groups: [AppGroup]
    var backgroundProcesses: [ProcessRecord]
    var timestamp: Date
    var totalMemoryBytes: UInt64
    var logicalCoreCount: Int
    /// Command lines filled by the daemon for cross-user processes (§4.4).
    var elevatedCommandLines: [Int32: String] = [:]

    var processCount: Int {
        backgroundProcesses.count + groups.reduce(0) { $0 + $1.children.count }
    }
}

/// Extract the containing .app bundle path from an executable path, e.g.
/// `/Applications/Safari.app/Contents/MacOS/Safari` → `/Applications/Safari.app`.
/// Returns nil for processes without a bundle (flat "Background processes").
func appBundlePath(forExecutablePath path: String) -> String? {
    guard let range = path.range(of: ".app/", options: .caseInsensitive) else {
        return path.hasSuffix(".app") ? path : nil
    }
    let end = path.index(range.lowerBound, offsetBy: 4) // include ".app"
    return String(path[..<end])
}

/// Conservative set of SIP / platform-protected processes (spec §6.5).
/// Termination controls are disabled for these with "Protected by the system".
func isSystemProtected(pid: Int32, name: String, path: String) -> Bool {
    if pid <= 1 { return true } // kernel_task (0) and launchd (1)
    switch name {
    case "kernel_task", "launchd", "WindowServer", "UserEventAgent",
         "distnoted", "opendirectoryd":
        return true
    default:
        return false
    }
}
