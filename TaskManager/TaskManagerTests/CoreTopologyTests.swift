// TaskManagerTests/CoreTopologyTests.swift
// Core → performance-level mapping (per-core addendum §2, §4): cluster-relative
// labels, single-level degradation, no two-tier assumption, count-mismatch
// fallback. Pure logic — the machine read is exercised only for sanity.

import Testing
import Foundation
@testable import TaskManager

private let appleSilicon = [(name: "Performance", coreCount: 10),
                            (name: "Efficiency", coreCount: 4)]

@Suite struct CoreTopologyTests {
    /// 4E+10P: efficiency section first, cluster-relative labels, indices
    /// straight from the `cluster-type` letters.
    @Test func labelsFourEfficiencyAndTenPerformanceCores() {
        let types = Array(repeating: "E", count: 4) + Array(repeating: "P", count: 10)
        let topology = CoreTopology.make(coreCount: 14, levels: appleSilicon, clusterTypes: types)

        #expect(topology.clusters.map(\.name) == ["Efficiency", "Performance"])
        #expect(topology.clusters[0].cores.map(\.label) == ["E0", "E1", "E2", "E3"])
        #expect(topology.clusters[0].cores.map(\.index) == [0, 1, 2, 3])
        #expect(topology.clusters[1].cores.map(\.label) == (0..<10).map { "P\($0)" })
        #expect(topology.clusters[1].cores.map(\.index) == Array(4..<14))
        #expect(topology.isSingleLevel == false)
    }

    /// A device tree that lists the P cluster first still labels by letter, not
    /// by position — the read verifies rather than assumes (ticket 01).
    @Test func clusterTypeLettersWinOverIndexOrder() {
        let types = Array(repeating: "P", count: 10) + Array(repeating: "E", count: 4)
        let topology = CoreTopology.make(coreCount: 14, levels: appleSilicon, clusterTypes: types)

        #expect(topology.clusters[0].cores.map(\.index) == Array(10..<14))
        #expect(topology.clusters[1].cores.map(\.index) == Array(0..<10))
    }

    /// Intel: one level → uniform grid, no section name, plain "CPU n".
    @Test func singleLevelMachineDegradesToUniformGrid() {
        let topology = CoreTopology.make(coreCount: 8, levels: [(name: "Performance", coreCount: 8)])

        #expect(topology.isSingleLevel)
        #expect(topology.clusters.count == 1)
        #expect(topology.clusters[0].name.isEmpty)
        #expect(topology.clusters[0].cores.map(\.label) == (0..<8).map { "CPU \($0)" })
    }

    @Test func unreadableTopologyFallsBackToSingleLevel() {
        let topology = CoreTopology.make(coreCount: 4, levels: [])

        #expect(topology.isSingleLevel)
        #expect(topology.clusters[0].cores.map(\.label) == ["CPU 0", "CPU 1", "CPU 2", "CPU 3"])
    }

    /// Three tiers render three sections — nothing assumes exactly two.
    @Test func threeLevelChipGetsThreeSections() {
        let levels = [(name: "Performance", coreCount: 6),
                      (name: "Medium", coreCount: 4),
                      (name: "Efficiency", coreCount: 2)]
        let types = Array(repeating: "E", count: 2)
            + Array(repeating: "M", count: 4)
            + Array(repeating: "P", count: 6)
        let topology = CoreTopology.make(coreCount: 12, levels: levels, clusterTypes: types)

        #expect(topology.clusters.map(\.name) == ["Efficiency", "Medium", "Performance"])
        #expect(topology.clusters.map { $0.cores.count } == [2, 4, 6])
        #expect(topology.clusters[1].cores.map(\.label) == ["M0", "M1", "M2", "M3"])
        #expect(topology.clusters[2].cores.map(\.index) == Array(6..<12))
    }

    /// cluster-type letters that disagree with the perflevel counts → the
    /// documented heuristic: the lowest indices are the efficiency cores.
    @Test func countMismatchFallsBackToEfficiencyFirstHeuristic() {
        let wrong = Array(repeating: "E", count: 6) + Array(repeating: "P", count: 8)
        let topology = CoreTopology.make(coreCount: 14, levels: appleSilicon, clusterTypes: wrong)

        #expect(topology.clusters[0].cores.map(\.index) == [0, 1, 2, 3])
        #expect(topology.clusters[1].cores.map(\.index) == Array(4..<14))
    }

    /// A short cluster-type read (children without the property) is ignored
    /// wholesale rather than shifting every index.
    @Test func partialClusterTypeReadIsIgnored() {
        let topology = CoreTopology.make(coreCount: 14, levels: appleSilicon, clusterTypes: ["E", "E"])

        #expect(topology.clusters[0].cores.map(\.index) == [0, 1, 2, 3])
        #expect(topology.clusters[1].cores.count == 10)
    }

    /// The real IORegistry + sysctl read: whatever this machine is, the
    /// sections must cover every logical CPU exactly once.
    @Test func machineReadCoversEveryLogicalCPUOnce() {
        let topology = CoreTopology.current()
        let indices = topology.clusters.flatMap { $0.cores.map(\.index) }.sorted()

        #expect(topology.coreCount == ProcessInfo.processInfo.processorCount)
        #expect(indices == Array(0..<ProcessInfo.processInfo.processorCount))
    }
}
