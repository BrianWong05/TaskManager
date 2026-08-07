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
}

/// CPU percent (normalized to all cores) → tier.
func cpuHeatTier(percent: Double) -> HeatTier {
    tier(for: percent, thresholds: HeatThresholds.cpu)
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
