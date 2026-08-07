// Elevation/DaemonClient.swift
// XPC client for the privileged daemon (spec §6). Lazily connects to the
// mach service; every call degrades to a failure result when the daemon is
// unavailable (degraded mode, spec §6.4) — never throws into UI paths.
//
// IMPORTANT: NSXPCConnection does NOT invoke pending reply blocks when the
// connection is interrupted/invalidated/unreachable. Every call therefore
// races its reply against a deadline so the sampler and user actions can
// never wedge (degraded mode must keep working, spec §6.4).

import Foundation

/// Mock seam for the batched cross-user detail fill (spec §4.4, §8).
protocol ElevatedDetailSource: Sendable {
    func details(for pids: [Int32]) async -> [TMProcessDetail]
}

extension DaemonClient: ElevatedDetailSource {
    func details(for pids: [Int32]) async -> [TMProcessDetail] {
        await processDetails(forPIDs: pids)
    }
}

actor DaemonClient {
    private var connection: NSXPCConnection?

    /// Sendable weak-reference box so XPC handler closures do not capture
    /// the actor directly (region-isolation friendly).
    private final class WeakBox: @unchecked Sendable {
        weak var client: DaemonClient?
        init(_ client: DaemonClient) { self.client = client }
    }

    /// One-shot guard: exactly one resume per continuation even when both a
    /// late reply block and the deadline fire.
    private final class ReplyGate: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        func fire() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if fired { return false }
            fired = true
            return true
        }
    }

    // MARK: Availability probe

    /// True only when a genuine round-trip answers in time. A registered-but-
    /// unlaunchable daemon (signature expiry) fails this probe, which is how
    /// ElevationManager distinguishes `.signatureExpired` (spec §1 runbook).
    func isAvailable() async -> Bool {
        guard let proxy = await proxy() else { return false }
        return await withTimeout(2.5, fallback: false) { resume in
            let reply: @Sendable ([TMProcessDetail]) -> Void = { _ in resume(true) }
            // Empty batch: the cheapest genuine round-trip on the surface.
            proxy.processDetails(forPIDs: [], reply: unsafe reply)
        }
    }

    // MARK: The three calls

    /// Batched cross-user detail fill — one round-trip per tick (spec §4.4).
    func processDetails(forPIDs pids: [Int32]) async -> [TMProcessDetail] {
        guard let proxy = await proxy() else { return [] }
        return await withTimeout(3, fallback: []) { resume in
            let reply: @Sendable ([TMProcessDetail]) -> Void = { details in resume(details) }
            proxy.processDetails(forPIDs: pids, reply: unsafe reply)
        }
    }

    func terminate(pid: Int32, mode: TMTerminationMode) async -> (success: Bool, reason: String?) {
        guard let proxy = await proxy() else {
            return (false, "Background service unavailable")
        }
        return await withTimeout(5, fallback: (false, "Background service unavailable")) { resume in
            let reply: @Sendable (Bool, String?) -> Void = { success, reason in resume((success, reason)) }
            proxy.terminate(pid: pid, mode: mode, reply: unsafe reply)
        }
    }

    func setStartupItem(label: String, enabled: Bool) async -> (success: Bool, reason: String?) {
        guard let proxy = await proxy() else {
            return (false, "Background service unavailable")
        }
        return await withTimeout(5, fallback: (false, "Background service unavailable")) { resume in
            let reply: @Sendable (Bool, String?) -> Void = { success, reason in resume((success, reason)) }
            proxy.setStartupItem(label: label, enabled: enabled, reply: unsafe reply)
        }
    }

    /// Races the XPC reply against a wall-clock deadline. The single gate
    /// guarantees exactly one resume: reply wins when it arrives in time,
    /// otherwise the deadline resumes with `fallback` and resets the stale
    /// connection; a reply arriving later is swallowed by the gate.
    private func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        fallback: T,
        operation: (@escaping @Sendable (T) -> Void) -> Void
    ) async -> T {
        let gate = ReplyGate()
        return await withCheckedContinuation { continuation in
            let resumeOnce: @Sendable (T) -> Void = { value in
                if gate.fire() { continuation.resume(returning: value) }
            }
            operation(resumeOnce)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                if gate.fire() {
                    continuation.resume(returning: fallback)
                    await self?.reset()
                }
            }
        }
    }

    // MARK: Connection management

    private func proxy() async -> TaskManagerDaemonProtocol? {
        if connection == nil {
            let new = NSXPCConnection(machServiceName: kTaskManagerDaemonIdentifier,
                                      options: .privileged)
            let interface = NSXPCInterface(with: TaskManagerDaemonProtocol.self)
            let allowedClasses = NSSet(objects: TMProcessDetail.self, NSArray.self) as! Set<AnyHashable>
            interface.setClasses(allowedClasses,
                                 for: #selector(TaskManagerDaemonProtocol.processDetails(forPIDs:reply:)),
                                 argumentIndex: 0, ofReply: true)
            new.remoteObjectInterface = interface
            let box = WeakBox(self)
            new.interruptionHandler = {
                Task { await box.client?.reset() }
            }
            new.invalidationHandler = {
                Task { await box.client?.reset() }
            }
            new.resume()
            connection = new
        }
        guard let connection else { return nil }
        // The proxy is returned synchronously; the error handler only fires
        // later, on a failed call, and simply drops the stale connection.
        let box = WeakBox(self)
        return connection.remoteObjectProxyWithErrorHandler { _ in
            Task { await box.client?.reset() }
        } as? TaskManagerDaemonProtocol
    }

    private func reset() {
        connection?.invalidate()
        connection = nil
    }
}
