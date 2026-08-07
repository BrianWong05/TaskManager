// TaskManagerTests/SystemMetricsReducerTests.swift
// System reducer rate math (spec §8): CPU tick deltas → percent, disk/net
// counter deltas → bytes/s, per-core percentages. No kernel calls.

import Testing
import Foundation
@testable import TaskManager

private let memory = MemoryRaw(wired: 100, active: 200, inactive: 50, free: 300,
                               compressed: 100, swapUsed: 0, totalPhysical: 1000)

private func ticks(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64 = 0,
                   perCore: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []) -> CPURawTicks {
    CPURawTicks(user: user, system: system, idle: idle, nice: nice, perCore: perCore)
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

    @Test func memoryInUseIsWiredActiveCompressed() {
        #expect(memoryInUse(memory) == 400)
    }
}
