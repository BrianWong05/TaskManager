// UI/Processes/IconCache.swift
// App icon resolution, cached per bundle path (spec §4.1): refreshed only on
// process-table structure changes, never per tick. App icons do not change
// while the app runs, so an unbounded cache keyed by bundle path is correct.

import AppKit
import UniformTypeIdentifiers

@MainActor
final class IconCache {
    static let shared = IconCache()

    private var cache: [String: NSImage] = [:]
    private let genericIcon: NSImage

    private init() {
        genericIcon = NSWorkspace.shared.icon(for: UTType.application)
    }

    func icon(forBundlePath bundlePath: String?) -> NSImage {
        guard let bundlePath else { return genericIcon }
        if let cached = cache[bundlePath] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        icon.size = NSSize(width: 18, height: 18)
        cache[bundlePath] = icon
        return icon
    }
}
