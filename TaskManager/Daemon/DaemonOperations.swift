// Daemon/DaemonOperations.swift
// The three privileged operations (spec §6.2). Runs as root — every
// libproc/sysctl call succeeds across users. Each call is audit-logged.

import Foundation

final class DaemonOperations: NSObject, TaskManagerDaemonProtocol {
    /// Set on connection acceptance; forwarded to the audit log so lines
    /// attribute the caller rather than the daemon itself (spec §6.2).
    var callerPid: Int32 = 0 {
        didSet { AuditLog.callerPid = callerPid }
    }

    // MARK: 1. Batched cross-user detail fill (spec §4.4)

    func processDetails(forPIDs pids: [Int32], reply: @escaping ([TMProcessDetail]) -> Void) {
        var details: [TMProcessDetail] = []
        for pid in pids {
            if let detail = detail(for: pid) {
                details.append(detail)
            }
        }
        AuditLog.record(operation: "processDetails",
                        target: "\(pids.count) pids",
                        result: "filled \(details.count)")
        reply(details)
    }

    private func detail(for pid: Int32) -> TMProcessDetail? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        let got = withUnsafeMutablePointer(to: &info) { ptr in
            proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, ptr, size)
        }
        guard got == size else { return nil }

        var rusage = rusage_info_current()
        let r = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
            let buffer = UnsafeMutableRawPointer(ptr)
                .assumingMemoryBound(to: Optional<UnsafeMutableRawPointer>.self)
            return proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, buffer)
        }

        return TMProcessDetail(
            pid: pid,
            residentMemory: info.ptinfo.pti_resident_size,
            cpuNanoseconds: info.ptinfo.pti_total_user &+ info.ptinfo.pti_total_system,
            commandLine: commandLine(for: pid) ?? "",
            diskBytesRead: r > 0 ? rusage.ri_diskio_bytesread : 0,
            diskBytesWritten: r > 0 ? rusage.ri_diskio_byteswritten : 0,
            uid: info.pbsd.pbi_uid
        )
    }

    private func commandLine(for pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        guard size >= MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBufferPointer { raw in
            raw.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        }
        guard argc > 0 else { return nil }
        var args: [String] = []
        var i = MemoryLayout<Int32>.size
        while i < size, buffer[i] != 0 { i += 1 } // skip the exec path
        while args.count < Int(argc), i < size {
            while i < size, buffer[i] == 0 { i += 1 }
            let start = i
            while i < size, buffer[i] != 0 { i += 1 }
            if i > start {
                let bytes = buffer[start..<i].map { UInt8(bitPattern: $0) }
                args.append(String(decoding: bytes, as: UTF8.self))
            }
        }
        return args.isEmpty ? nil : args.joined(separator: " ")
    }

    // MARK: 2. Termination (SIGTERM / SIGKILL — spec §3.3 semantics)

    func terminate(pid: Int32, mode: TMTerminationMode, reply: @escaping (Bool, String?) -> Void) {
        // Root kill(0/…) signals whole process groups: reject anything that
        // is not a plain positive pid above launchd.
        guard pid > 1 else {
            AuditLog.record(operation: "terminate", target: "pid \(pid)", result: "rejected: invalid pid")
            reply(false, "Invalid pid")
            return
        }
        let signal = mode == .force ? SIGKILL : SIGTERM
        let result = kill(pid, signal)
        if result == 0 {
            AuditLog.record(operation: "terminate",
                            target: "pid \(pid) mode \(mode == .force ? "force" : "graceful")",
                            result: "ok")
            reply(true, nil)
            return
        }
        let reason: String
        switch errno {
        case EPERM:
            // Root receiving EPERM ⇒ SIP / platform protection.
            reason = "Protected by the system"
        case ESRCH:
            reason = "The process has already exited"
        default:
            reason = "Signal failed (errno \(errno))"
        }
        AuditLog.record(operation: "terminate",
                        target: "pid \(pid) mode \(mode == .force ? "force" : "graceful")",
                        result: "failed: \(reason)")
        reply(false, reason)
    }

    // MARK: 3. System-scope Startup item toggle (spec §3.5)

    func setStartupItem(label: String, enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        // Whitelist characters: launchd labels are reverse-DNS style.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        guard label.unicodeScalars.allSatisfy({ allowed.contains($0) }), !label.isEmpty else {
            reply(false, "Invalid label")
            return
        }
        let verb = enabled ? "enable" : "disable"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [verb, "system/\(label)"]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AuditLog.record(operation: "setStartupItem",
                            target: "\(verb) \(label)", result: "failed: \(error)")
            reply(false, "launchctl could not be launched")
            return
        }
        if process.terminationStatus == 0 {
            AuditLog.record(operation: "setStartupItem",
                            target: "\(verb) \(label)", result: "ok")
            reply(true, nil)
        } else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            AuditLog.record(operation: "setStartupItem",
                            target: "\(verb) \(label)",
                            result: "failed: \(message)")
            reply(false, message.isEmpty ? "launchctl exited \(process.terminationStatus)" : message)
        }
    }
}
