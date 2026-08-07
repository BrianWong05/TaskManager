// Elevation/DaemonClient.swift
// XPC client for the privileged daemon (spec §6). Lazily connects to the
// mach service; every call degrades to a failure result when the daemon is
// unavailable (degraded mode, spec §6.4) — never throws into UI paths.

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

    /// True when a connection can be established right now. Used as the
    /// availability probe for degraded-mode detection.
    func isAvailable() async -> Bool {
        await proxy() != nil
    }

    /// Batched cross-user detail fill — one round-trip per tick (spec §4.4).
    func processDetails(forPIDs pids: [Int32]) async -> [TMProcessDetail] {
        guard let proxy = await proxy() else { return [] }
        return await withCheckedContinuation { continuation in
            let reply: @Sendable ([TMProcessDetail]) -> Void = { details in
                continuation.resume(returning: details)
            }
            proxy.processDetails(forPIDs: pids, reply: unsafe reply)
        }
    }

    func terminate(pid: Int32, mode: TMTerminationMode) async -> (success: Bool, reason: String?) {
        guard let proxy = await proxy() else {
            return (false, "Background service unavailable")
        }
        return await withCheckedContinuation { continuation in
            let reply: @Sendable (Bool, String?) -> Void = { success, reason in
                continuation.resume(returning: (success, reason))
            }
            proxy.terminate(pid: pid, mode: mode, reply: unsafe reply)
        }
    }

    func setStartupItem(label: String, enabled: Bool) async -> (success: Bool, reason: String?) {
        guard let proxy = await proxy() else {
            return (false, "Background service unavailable")
        }
        return await withCheckedContinuation { continuation in
            let reply: @Sendable (Bool, String?) -> Void = { success, reason in
                continuation.resume(returning: (success, reason))
            }
            proxy.setStartupItem(label: label, enabled: enabled, reply: unsafe reply)
        }
    }

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
