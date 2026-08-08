// Data/HeatTiers.swift
// Heat coloring classification (spec §3.3): three tiers of background tint on
// the CPU and Memory columns only. Pure function — unit tested (spec §8).

import Foundation

enum HeatTier: Int, Sendable, Equatable {
    case none = 0
    case tier1 = 1
    case tier2 = 2
    case tier3 = 3
}

enum HeatThresholds {
    /// CPU tiers: >5% / >15% / >40% (spec §3.3).
    static let cpu: [Double] = [5, 15, 40]
    /// Memory tiers by share of total system memory: >5% / >15% / >40%.
    /// (Spec §3.3 prescribes "tiered by share of total system memory"; the
    /// numeric steps mirror the CPU tiers.)
    static let memoryShare: [Double] = [5, 15, 40]
    /// One logical CPU's own utilization, for the Logical processors grid.
    /// Deliberately not `cpu`: those are shares of the whole machine, so a
    /// single core past 40 % of itself would sit in the top tier permanently.
    static let core: [Double] = [25, 50, 75]
}

/// CPU percent on Activity Monitor's scale (100 % = one busy core) → tier.
/// The thresholds stay shares of the *whole machine*, so they scale with core
/// count — otherwise on a 14-core box a process using half of one core (3.5 %
/// of the machine) would light up the hottest tier.
func cpuHeatTier(percent: Double, coreCount: Int) -> HeatTier {
    let cores = Double(max(coreCount, 1))
    return tier(for: percent, thresholds: HeatThresholds.cpu.map { $0 * cores })
}

/// One core's own utilization (0–100 % of that core) → tier.
func coreHeatTier(percent: Double) -> HeatTier {
    tier(for: percent, thresholds: HeatThresholds.core)
}

/// Memory bytes relative to total system memory → tier.
func memoryHeatTier(bytes: UInt64, totalBytes: UInt64) -> HeatTier {
    guard totalBytes > 0 else { return .none }
    let share = Double(bytes) / Double(totalBytes) * 100
    return tier(for: share, thresholds: HeatThresholds.memoryShare)
}

private func tier(for value: Double, thresholds: [Double]) -> HeatTier {
    switch value {
    case ..<thresholds[0]: return .none
    case ..<thresholds[1]: return .tier1
    case ..<thresholds[2]: return .tier2
    default: return .tier3
    }
}
