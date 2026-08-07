// Data/ProcessSnapshotStore.swift
// @MainActor sink for SamplerActor publications (spec §4.3). Main window and
// Mini monitor render the same snapshot.

import Foundation
import Combine

@MainActor
final class ProcessSnapshotStore: ObservableObject {
    @Published private(set) var snapshot: ProcessSnapshot?
    @Published private(set) var perProcessNetworkDegraded = false

    private let sampler: SamplerActor
    private var onSystemSample: (@MainActor (SystemSample) -> Void)?
    /// Window hidden AND Mini monitor off → process-level sampling pauses
    /// while system-level sampling continues (spec §4.2).
    private var paused = false

    init(sampler: SamplerActor = SamplerActor()) {
        self.sampler = sampler
    }

    func start(onSystemSample: @escaping @MainActor (SystemSample) -> Void = { _ in }) {
        self.onSystemSample = onSystemSample
        Task {
            await sampler.start { [weak self] snapshot, systemSample in
                // nil = process sampling paused (§4.2): keep the last frame.
                if let snapshot {
                    self?.apply(snapshot)
                }
                if let systemSample {
                    self?.onSystemSample?(systemSample)
                }
            }
        }
    }

    func stop() {
        Task { await sampler.stop() }
    }

    /// Pause only the process table; system sampling keeps running (§4.2).
    func pause() {
        guard !paused else { return }
        paused = true
        Task { await sampler.setProcessSamplingPaused(true) }
    }

    func resume() {
        guard paused else { return }
        paused = false
        Task { await sampler.setProcessSamplingPaused(false) }
    }

    private func apply(_ newSnapshot: ProcessSnapshot) {
        snapshot = newSnapshot
    }

    /// Inspector support: command line fetch is same-user only unprivileged.
    func commandLine(for pid: Int32) -> String? {
        LibProcProcessCollector().commandLine(for: pid)
    }
}
