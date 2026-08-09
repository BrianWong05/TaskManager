// Data/Collectors/ProcessCollector.swift
// Unprivileged process-table collection (spec §5). Protocol-backed so unit
// tests inject mocks (spec §8) — no test touches real system calls.

import Foundation

/// Raw per-process sample straight from the kernel, before any rate math.
/// Fields an unprivileged caller cannot read (cross-user) arrive as nil.
struct RawProcessSample: Sendable {
    let pid: Int32
    let startUsec: UInt64
    let name: String
    let path: String
    let uid: UInt32
    let ppid: Int32
    let rawStatus: Int32
    /// Cumulative CPU time, user + system, nanoseconds (proc_taskallinfo).
    let cpuNanoseconds: UInt64
    /// ri_phys_footprint (dirty + compressed + swapped — matches Activity
    /// Monitor's Memory column and the system OOM dialog); falls back to
    /// resident_size when proc_pid_rusage is unreadable.
    let residentMemory: UInt64
    /// Cumulative disk I/O (proc_pid_rusage); nil when EPERM (cross-user).
    let diskBytesRead: UInt64?
    let diskBytesWritten: UInt64?
    /// Responsible process (responsibility SPI); nil when self-responsible
    /// or unavailable. Drives App Grouping of bundle-less helpers.
    var responsiblePid: Int32? = nil
}

/// Mock seam for the process table (spec §8).
protocol ProcessTableCollecting: Sendable {
    /// One enumeration of every visible process (~1.6 ms for 950 pids, §5).
    func sampleAll() -> [RawProcessSample]
    /// Full argv via sysctl(KERN_PROCARGS2); same-user only, nil otherwise.
    func commandLine(for pid: Int32) -> String?
    func totalMemoryBytes() -> UInt64
    func logicalCoreCount() -> Int
}

/// 4 * MAXPATHLEN — the buffer size proc_pidpath expects.
private let kProcPathBufferSize = 4096

/// Real implementation on top of libproc (see bridging header).
struct LibProcProcessCollector: ProcessTableCollecting {
    func sampleAll() -> [RawProcessSample] {
        // First call with a nil buffer returns the byte size needed.
        let noBuffer: UnsafeMutableRawPointer? = nil
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, noBuffer, 0)
        guard bufferSize > 0 else { return [] }
        let capacity = Int(bufferSize) / MemoryLayout<pid_t>.stride + 32
        var pids = [pid_t](repeating: 0, count: capacity)
        let pidBytes = Int32(capacity * MemoryLayout<pid_t>.stride)
        let returned = pids.withUnsafeMutableBytes { raw in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, raw.baseAddress, pidBytes)
        }
        guard returned > 0 else { return [] }
        let count = Int(returned) / MemoryLayout<pid_t>.stride

        var samples: [RawProcessSample] = []
        samples.reserveCapacity(count)
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            if let sample = fullSample(pid: pid) ?? baseOnlySample(pid: pid) {
                samples.append(sample)
            }
        }
        return samples
    }

    /// Same-user detail: bsd + task info in one call (PROC_PIDTASKALLINFO).
    private func fullSample(pid: Int32) -> RawProcessSample? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        let got = withUnsafeMutablePointer(to: &info) { ptr in
            proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, ptr, size)
        }
        guard got == size else { return nil } // EPERM cross-user, ESRCH race

        let bsd = info.pbsd
        let path = processPath(pid: pid)
        // proc_pid_rusage: 0 on success, -1 on failure (EPERM cross-user).
        // NOTE: the C signature `rusage_info_t *buffer` is misleading — the
        // kernel treats the pointer VALUE itself as the output buffer. Swift
        // imports it as a pointer-to-pointer, so passing `&ptr` lets the
        // kernel write 464 bytes onto the stack slot (stack-smash). Reborrow
        // the struct pointer with a matching pointee type instead.
        var rusage = rusage_info_current()
        let r = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
            let buffer = UnsafeMutableRawPointer(ptr)
                .assumingMemoryBound(to: Optional<UnsafeMutableRawPointer>.self)
            return proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, buffer)
        }
        return RawProcessSample(
            pid: pid,
            startUsec: UInt64(bsd.pbi_start_tvsec) * 1_000_000 + UInt64(bsd.pbi_start_tvusec),
            name: displayName(bsd.pbi_name, path: path, pid: pid),
            path: path,
            uid: bsd.pbi_uid,
            ppid: Int32(bsd.pbi_ppid),
            rawStatus: Int32(bsd.pbi_status),
            cpuNanoseconds: machTimeToNanoseconds(info.ptinfo.pti_total_user &+ info.ptinfo.pti_total_system),
            residentMemory: r == 0 ? rusage.ri_phys_footprint : info.ptinfo.pti_resident_size,
            diskBytesRead: r == 0 ? rusage.ri_diskio_bytesread : nil,
            diskBytesWritten: r == 0 ? rusage.ri_diskio_byteswritten : nil,
            responsiblePid: responsiblePid(of: pid)
        )
    }

    /// Name/path/owner for a process whose task info we cannot read
    /// (cross-user). PROC_PIDTBSDINFO also fails cross-user (EPERM), which used
    /// to drop every root/other-user process from the table entirely — the
    /// base-first design of §4.4/§4.5 needs them visible with base fields.
    /// sysctl(KERN_PROC) reads uid/ppid/start/name for ANY pid unprivileged
    /// (it is how `ps` lists every process), and proc_pidpath supplies the
    /// full path. Together they are the honest base row; the daemon fills the
    /// elevation-gated fields later (§4.4).
    private func baseOnlySample(pid: Int32) -> RawProcessSample? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var kp = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let ok = sysctl(&mib, 4, &kp, &size, nil, 0) == 0 && size > 0
        guard ok else { return nil } // process exited between listpids and now
        let path = processPath(pid: pid)
        return RawProcessSample(
            pid: pid,
            startUsec: UInt64(bitPattern: Int64(kp.kp_proc.p_starttime.tv_sec)) * 1_000_000
                + UInt64(bitPattern: Int64(kp.kp_proc.p_starttime.tv_usec)),
            name: displayName(kp.kp_proc.p_comm, path: path, pid: pid),
            path: path,
            uid: kp.kp_eproc.e_pcred.p_ruid,
            ppid: kp.kp_eproc.e_ppid,
            rawStatus: Int32(kp.kp_proc.p_stat),
            cpuNanoseconds: 0,
            residentMemory: 0,
            diskBytesRead: nil,
            diskBytesWritten: nil,
            responsiblePid: responsiblePid(of: pid)
        )
    }

    /// nil when self-responsible or the SPI fails, so grouping falls back to
    /// the process's own bundle. ponytail: one syscall per pid per tick, no
    /// cache — cache by identity if profiling ever flags it.
    private func responsiblePid(of pid: Int32) -> Int32? {
        let responsible = responsibility_get_pid_responsible_for_pid(pid)
        return responsible > 0 && responsible != pid ? responsible : nil
    }

    private func processPath(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: kProcPathBufferSize)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return "" }
        return String(cString: buffer)
    }

    private func displayName<T>(_ nameField: T, path: String, pid: Int32) -> String {
        let name = cStringToString(nameField)
        if !name.isEmpty { return name }
        return path.split(separator: "/").last.map(String.init) ?? "pid \(pid)"
    }

    func commandLine(for pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        // Layout: argc (int32) | exec path \0 | argv strings \0 ...
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

    func totalMemoryBytes() -> UInt64 {
        UInt64(ProcessInfo.processInfo.physicalMemory)
    }

    func logicalCoreCount() -> Int {
        ProcessInfo.processInfo.processorCount
    }
}

/// Fixed-size C char tuple → Swift String (any arity).
func cStringToString<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { raw in
        guard let base = raw.baseAddress else { return "" }
        return String(cString: base.assumingMemoryBound(to: CChar.self))
    }
}
