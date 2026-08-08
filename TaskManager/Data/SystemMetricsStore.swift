// Data/SystemMetricsStore.swift
// @MainActor sink for system samples: ring-buffer history per resource
// (spec §4.2 — 60 samples × 1 s, ephemeral) plus the memory-pressure event
// source (spec §5, DISPATCH_SOURCE_TYPE_MEMORYPRESSURE).

import Foundation
import Combine
import Dispatch

@MainActor
final class SystemMetricsStore: ObservableObject {
    static let historyCapacity = 60

    @Published var cpuHistory = RingBuffer<Double>(capacity: SystemMetricsStore.historyCapacity)
    @Published var memoryHistory = RingBuffer<Double>(capacity: SystemMetricsStore.historyCapacity) // % of total
    @Published var diskHistory = RingBuffer<Double>(capacity: SystemMetricsStore.historyCapacity)   // bytes/s
    @Published var netHistory = RingBuffer<Double>(capacity: SystemMetricsStore.historyCapacity)    // bytes/s
    @Published var gpuHistory = RingBuffer<Double>(capacity: SystemMetricsStore.historyCapacity)    // %
    @Published private(set) var latest: SystemSample?

    /// Static core → performance-level map for the grid (addendum §2).
    let topology: CoreTopology

    /// Memory-pressure event badge on the Performance memory card (§3.4).
    /// Cleared automatically after 60 s without a new event.
    @Published private(set) var pressureLevel: MemoryPressureLevel?
    @Published private(set) var pressureDate: Date?

    private let pressureSource: DispatchSourceMemoryPressure

    init(topology: CoreTopology = .current()) {
        self.topology = topology
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .main)
        pressureSource = source
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            Task { @MainActor in
                self.pressureLevel = event.contains(.critical) ? .critical : .warning
                self.pressureDate = Date()
            }
        }
        source.activate()
    }

    deinit {
        pressureSource.cancel()
    }

    func apply(_ sample: SystemSample) {
        latest = sample
        cpuHistory.append(sample.cpuPercent)
        let total = sample.memory.totalPhysical
        let inUseShare = total > 0 ? Double(memoryInUse(sample.memory)) / Double(total) * 100 : 0
        memoryHistory.append(inUseShare)
        diskHistory.append(sample.diskReadRate + sample.diskWriteRate)
        netHistory.append(sample.netDownRate + sample.netUpRate)
        gpuHistory.append(sample.gpuUtilization ?? 0)

        // Pressure badge expires after a minute of quiet (spec §3.4 badge).
        if let date = pressureDate, Date().timeIntervalSince(date) > 60 {
            pressureLevel = nil
            pressureDate = nil
        }
    }
}
