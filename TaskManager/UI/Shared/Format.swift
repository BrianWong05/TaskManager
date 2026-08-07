// UI/Shared/Format.swift
// Shared display formatting for the tabular columns.

import Foundation

enum Format {
    /// CPU percent with one decimal, Win11-style ("12.3 %").
    static func cpu(_ percent: Double) -> String {
        percent < 0.05 ? "0 %" : String(format: "%.1f %%", percent)
    }

    /// 1024-based byte count ("412 KB", "1.2 GB").
    static func bytes(_ value: UInt64) -> String {
        bytes(Double(value))
    }

    static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = value
        var unit = 0
        while v >= 1024, unit < units.count - 1 {
            v /= 1024
            unit += 1
        }
        if unit == 0 { return "\(Int(v)) B" }
        return String(format: "%.1f %@", v, units[unit])
    }

    /// Transfer rate ("3.4 MB/s").
    static func rate(_ bytesPerSecond: Double) -> String {
        bytesPerSecond < 1 ? "0 B/s" : "\(bytes(bytesPerSecond))/s"
    }

    /// Start time for the inspector.
    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
