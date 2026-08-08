// Data/CoreTopology.swift
// Static CPU core topology behind the Logical processors view (per-core
// addendum §2): host_processor_info index → performance level, taken from the
// IORegistry `cpus` children's `cluster-type` and cross-checked against
// hw.perflevelN. Read once — topology never changes, so per-tick cost is zero.

import Foundation
import IOKit

/// One logical CPU as the grid draws it.
struct CoreCell: Equatable, Identifiable {
    /// Index into `SystemSample.perCorePercent` / `host_processor_info`.
    let index: Int
    /// Cluster-relative label — "E0", "P5", or "CPU 3" on single-level machines.
    let label: String

    var id: Int { index }
}

/// One performance level and the cores it owns — one section of the grid.
struct CoreCluster: Equatable, Identifiable {
    /// hw.perflevelN.name ("Efficiency", "Performance"); empty on a machine
    /// that reports no performance levels.
    let name: String
    let cores: [CoreCell]

    var id: Int { cores.first?.index ?? -1 }
}

struct CoreTopology: Equatable {
    /// Efficiency-first, one per performance level. A single cluster renders as
    /// a uniform header-less grid (Intel).
    let clusters: [CoreCluster]

    var isSingleLevel: Bool { clusters.count <= 1 }
    var coreCount: Int { clusters.reduce(0) { $0 + $1.cores.count } }
}

// MARK: - Pure builder (unit-tested seam)

extension CoreTopology {
    /// `levels` arrives in sysctl order — descending performance, so perflevel0
    /// is the fastest and the sections come out reversed. `clusterTypes` is the
    /// IORegistry `cluster-type` letter per logical index, empty when unreadable.
    static func make(coreCount: Int,
                     levels: [(name: String, coreCount: Int)],
                     clusterTypes: [String] = []) -> CoreTopology {
        guard coreCount > 0 else { return CoreTopology(clusters: []) }
        let ordered = Array(levels.reversed())
        // No usable perflevel data → one uniform "CPU n" grid.
        guard ordered.count > 1, ordered.reduce(0, { $0 + $1.coreCount }) == coreCount else {
            let cores = (0..<coreCount).map { CoreCell(index: $0, label: "CPU \($0)") }
            return CoreTopology(clusters: [CoreCluster(name: "", cores: cores)])
        }
        let groups = indexGroups(coreCount: coreCount, levels: ordered, clusterTypes: clusterTypes)
        return CoreTopology(clusters: zip(ordered, groups).map { level, indices in
            let letter = level.name.first.map { String($0).uppercased() } ?? "C"
            return CoreCluster(
                name: level.name,
                cores: indices.enumerated().map { CoreCell(index: $1, label: "\(letter)\($0)") })
        })
    }

    /// Index set per level: the IORegistry `cluster-type` letters when they
    /// agree with the perflevel counts, else the documented fallback — indices
    /// handed out in order, efficiency cores first.
    private static func indexGroups(coreCount: Int,
                                    levels: [(name: String, coreCount: Int)],
                                    clusterTypes: [String]) -> [[Int]] {
        if clusterTypes.count == coreCount,
           let matched = groupsByClusterType(levels: levels, clusterTypes: clusterTypes) {
            return matched
        }
        var next = 0
        return levels.map { level in
            defer { next += level.coreCount }
            return Array(next..<(next + level.coreCount))
        }
    }

    /// nil when the letters don't partition the cores exactly the way the
    /// perflevel names and counts say they should.
    private static func groupsByClusterType(levels: [(name: String, coreCount: Int)],
                                            clusterTypes: [String]) -> [[Int]]? {
        var byLetter: [String: [Int]] = [:]
        for (index, type) in clusterTypes.enumerated() {
            byLetter[type.uppercased(), default: []].append(index)
        }
        var groups: [[Int]] = []
        for level in levels {
            guard let letter = level.name.first.map({ String($0).uppercased() }),
                  let indices = byLetter.removeValue(forKey: letter),
                  indices.count == level.coreCount else { return nil }
            groups.append(indices)
        }
        return byLetter.isEmpty ? groups : nil
    }
}

// MARK: - Machine read (startup, once)

extension CoreTopology {
    static func current() -> CoreTopology {
        let count = sysctlInt("hw.logicalcpu") ?? ProcessInfo.processInfo.processorCount
        return make(coreCount: count, levels: perfLevels(), clusterTypes: clusterTypes())
    }

    private static func perfLevels() -> [(name: String, coreCount: Int)] {
        guard let count = sysctlInt("hw.nperflevels"), count > 0 else { return [] }
        return (0..<count).compactMap { level -> (name: String, coreCount: Int)? in
            guard let cores = sysctlInt("hw.perflevel\(level).logicalcpu") else { return nil }
            return (name: sysctlString("hw.perflevel\(level).name") ?? "", coreCount: cores)
        }
    }

    /// The `cpus` node's children in **iteration order** — never the `cpuN` node
    /// names, whose digits skip values on some machines (addendum §2).
    private static func clusterTypes() -> [String] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return [] }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var types: [String] = []
        var child = IOIteratorNext(iterator)
        while child != 0 {
            if let type = clusterType(child) { types.append(type) }
            IOObjectRelease(child)
            child = IOIteratorNext(iterator)
        }
        return types
    }

    private static func clusterType(_ entry: io_registry_entry_t) -> String? {
        guard let property = IORegistryEntryCreateCFProperty(
            entry, "cluster-type" as CFString, kCFAllocatorDefault, 0) else { return nil }
        let value = property.takeRetainedValue()
        // Device-tree strings arrive as NUL-terminated data.
        if let data = value as? Data {
            return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        }
        return value as? String
    }
}

private func sysctlInt(_ name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return Int(value)
}

private func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}
