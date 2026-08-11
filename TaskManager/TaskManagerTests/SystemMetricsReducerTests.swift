// TaskManagerTests/SystemMetricsReducerTests.swift
// System reducer rate math (spec §8): CPU tick deltas → percent, disk/net
// counter deltas → bytes/s, per-core percentages. No kernel calls.

import Testing
import Foundation
@testable import TaskManager

private let memory = MemoryRaw(wired: 100, app: 200, compressed: 100,
                               cached: 300, swapUsed: 0, totalPhysical: 1000)

private func ticks(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64 = 0,
                   perCore: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []) -> CPURawTicks {
    CPURawTicks(user: user, system: system, idle: idle, nice: nice, perCore: perCore)
}

@Suite struct SwapNearlyFullTests {
    private func memory(swapUsed: UInt64, swapTotal: UInt64) -> MemoryRaw {
        MemoryRaw(wired: 0, app: 0, compressed: 0, cached: 0,
                  swapUsed: swapUsed, swapTotal: swapTotal, totalPhysical: 1000)
    }

    /// Notice threshold is 90% of swap; zero total (swap disabled or sysctl
    /// failure) must never trigger it.
    @Test func triggersAtNinetyPercentAndNotOnZeroTotal() {
        #expect(!memory(swapUsed: 89, swapTotal: 100).swapNearlyFull)
        #expect(memory(swapUsed: 90, swapTotal: 100).swapNearlyFull)
        #expect(memory(swapUsed: 100, swapTotal: 100).swapNearlyFull)
        #expect(!memory(swapUsed: 0, swapTotal: 0).swapNearlyFull)
    }
}

@Suite struct SystemMetricsReducerTests {
    @Test func cpuPercentFromTickDeltas() {
        var reducer = SystemMetricsReducer()
        let t0 = Date()
        _ = reducer.update(cpu: ticks(user: 100, system: 100, idle: 800),
                           memory: memory, disk: nil, net: nil, gpu: nil,
                           upTimeSeconds: 0, now: t0)
        // +400 busy ticks over +1000 total ticks = 40 %.
        let sample = reducer.update(cpu: ticks(user: 300, system: 300, idle: 1400),
                                    memory: memory, disk: nil, net: nil, gpu: nil,
                                    upTimeSeconds: 1, now: t0.addingTimeInterval(1))
        #expect(sample != nil)
        #expect(abs(sample!.cpuPercent - 40.0) < 0.001)
    }

    @Test func perCorePercentages() {
        var reducer = SystemMetricsReducer()
        let t0 = Date()
        let core0 = [(user: UInt64(0), system: UInt64(0), idle: UInt64(100), nice: UInt64(0))]
        _ = reducer.update(cpu: ticks(user: 50, system: 50, idle: 100, perCore: core0),
                           memory: memory, disk: nil, net: nil, gpu: nil,
                           upTimeSeconds: 0, now: t0)
        let core1 = [(user: UInt64(100), system: UInt64(0), idle: UInt64(100), nice: UInt64(0))]
        let sample = reducer.update(cpu: ticks(user: 150, system: 50, idle: 100, perCore: core1),
                                    memory: memory, disk: nil, net: nil, gpu: nil,
                                    upTimeSeconds: 1, now: t0.addingTimeInterval(1))
        // Core gained 100 busy ticks with idle unchanged → fully busy.
        #expect(sample?.perCorePercent == [100.0])
    }

    @Test func diskAndNetRatesAreDeltasOverTime() {
        var reducer = SystemMetricsReducer()
        let t0 = Date()
        _ = reducer.update(cpu: nil, memory: memory,
                           disk: DiskRawTotals(bytesRead: 1000, bytesWritten: 0),
                           net: NetRawTotals(bytesIn: 500, bytesOut: 250),
                           gpu: nil, upTimeSeconds: 0, now: t0)
        let sample = reducer.update(cpu: nil, memory: memory,
                                    disk: DiskRawTotals(bytesRead: 3000, bytesWritten: 4000),
                                    net: NetRawTotals(bytesIn: 1500, bytesOut: 1250),
                                    gpu: 12, upTimeSeconds: 2, now: t0.addingTimeInterval(2))
        #expect(abs(sample!.diskReadRate - 1000) < 0.001)  // 2000 B / 2 s
        #expect(abs(sample!.diskWriteRate - 2000) < 0.001) // 4000 B / 2 s
        #expect(abs(sample!.netDownRate - 500) < 0.001)
        #expect(abs(sample!.netUpRate - 500) < 0.001)
        #expect(sample!.gpuUtilization == 12)
    }

    @Test func missingMemoryYieldsNoSample() {
        var reducer = SystemMetricsReducer()
        let sample = reducer.update(cpu: nil, memory: nil, disk: nil, net: nil,
                                    gpu: nil, upTimeSeconds: 0, now: Date())
        #expect(sample == nil)
    }

    /// Both halves of the Activity Monitor model (ADR 0001): In use is exactly
    /// its three displayed parts, and Available is whatever is left of
    /// capacity — so the Performance stat row always adds up.
    @Test func inUseIsItsPartsAndAvailableIsTheRemainder() {
        #expect(memory.inUse == 400)
        #expect(memory.inUse == memory.app &+ memory.wired &+ memory.compressed)
        #expect(memory.inUse &+ memory.available == memory.totalPhysical)
    }
}
