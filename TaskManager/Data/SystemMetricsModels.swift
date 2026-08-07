// Data/SystemMetricsModels.swift
// System-level metric values published on the 1 s master tick (spec §4.2).

import Foundation

/// Raw cumulative counters straight from the kernel — the reducer turns
/// consecutive ticks into rates and percentages.
struct CPURawTicks: Sendable, Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64
    /// Per-core (user, system, idle, nice) tick tuples.
    var perCore: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)]

    static func == (lhs: CPURawTicks, rhs: CPURawTicks) -> Bool {
        lhs.user == rhs.user && lhs.system == rhs.system
            && lhs.idle == rhs.idle && lhs.nice == rhs.nice
            && lhs.perCore.map(\.user) == rhs.perCore.map(\.user)
    }
}

struct MemoryRaw: Sendable {
    var wired: UInt64
    var active: UInt64
    var inactive: UInt64
    var free: UInt64
    var compressed: UInt64
    var swapUsed: UInt64
    var totalPhysical: UInt64
}

struct DiskRawTotals: Sendable, Equatable {
    var bytesRead: UInt64
    var bytesWritten: UInt64
}

struct NetRawTotals: Sendable, Equatable {
    var bytesIn: UInt64
    var bytesOut: UInt64
}

enum MemoryPressureLevel: String, Sendable {
    case warning = "Memory pressure is high"
    case critical = "Memory pressure is critical"
}

/// One derived system sample per tick.
struct SystemSample: Sendable {
    var cpuPercent: Double            // 0–100 across all cores
    var perCorePercent: [Double]
    var memory: MemoryRaw
    var diskReadRate: Double          // bytes/s
    var diskWriteRate: Double
    var netDownRate: Double           // bytes/s
    var netUpRate: Double
    var gpuUtilization: Double?       // nil = no IOAccelerator exposed it
    var upTimeSeconds: TimeInterval
}
