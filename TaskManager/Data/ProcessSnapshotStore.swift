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

    init(sampler: SamplerActor = SamplerActor()) {
        self.sampler = sampler
    }

    func start() {
        Task {
            await sampler.start { [weak self] snapshot in
                self?.apply(snapshot)
            }
        }
    }

    func stop() {
        Task { await sampler.stop() }
    }

    private func apply(_ newSnapshot: ProcessSnapshot) {
        snapshot = newSnapshot
    }

    /// Inspector support: command line fetch is same-user only unprivileged.
    func commandLine(for pid: Int32) -> String? {
        LibProcProcessCollector().commandLine(for: pid)
    }
}
