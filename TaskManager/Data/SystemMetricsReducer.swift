// Data/SystemMetricsReducer.swift
// Pure reduction of raw system counters into a SystemSample: tick deltas →
// percentages and rates. Unit-testable without the kernel (spec §8).

import Foundation

struct SystemMetricsReducer {
    private var previousCPU: CPURawTicks?
    private var previousDisk: DiskRawTotals?
    private var previousNet: NetRawTotals?
    private var previousTime: Date?

    mutating func update(cpu: CPURawTicks?,
                         memory: MemoryRaw?,
                         disk: DiskRawTotals?,
                         net: NetRawTotals?,
                         gpu: Double?,
                         upTimeSeconds: TimeInterval,
                         now: Date) -> SystemSample? {
        guard let memory else { return nil }
        let dt = previousTime.map { max(now.timeIntervalSince($0), 0.001) }

        var cpuPercent = 0.0
        var perCore: [Double] = []
        if let cpu, let previous = previousCPU, let dt {
            let busy = Double((cpu.user &+ cpu.system &+ cpu.nice)
                              &- (previous.user &+ previous.system &+ previous.nice))
            let total = Double((cpu.user &+ cpu.system &+ cpu.idle &+ cpu.nice)
                               &- (previous.user &+ previous.system &+ previous.idle &+ previous.nice))
            if total > 0 { cpuPercent = busy / total * 100 }
            perCore = zip(cpu.perCore, previous.perCore).map { current, prev in
                let busyTicks = Double((current.user &+ current.system &+ current.nice)
                                       &- (prev.user &+ prev.system &+ prev.nice))
                let allTicks = Double((current.user &+ current.system &+ current.idle &+ current.nice)
                                      &- (prev.user &+ prev.system &+ prev.idle &+ prev.nice))
                return allTicks > 0 ? busyTicks / allTicks * 100 : 0
            }
        }

        let diskReadRate = rate(now: disk?.bytesRead, before: previousDisk?.bytesRead, dt: dt)
        let diskWriteRate = rate(now: disk?.bytesWritten, before: previousDisk?.bytesWritten, dt: dt)
        let netDownRate = rate(now: net?.bytesIn, before: previousNet?.bytesIn, dt: dt)
        let netUpRate = rate(now: net?.bytesOut, before: previousNet?.bytesOut, dt: dt)

        previousCPU = cpu
        previousDisk = disk
        previousNet = net
        previousTime = now

        return SystemSample(
            cpuPercent: cpuPercent,
            perCorePercent: perCore,
            memory: memory,
            diskReadRate: diskReadRate,
            diskWriteRate: diskWriteRate,
            netDownRate: netDownRate,
            netUpRate: netUpRate,
            gpuUtilization: gpu,
            upTimeSeconds: upTimeSeconds
        )
    }

    private func rate(now: UInt64?, before: UInt64?, dt: Double?) -> Double {
        guard let now, let before, let dt, now >= before else { return 0 }
        return Double(now - before) / dt
    }
}
