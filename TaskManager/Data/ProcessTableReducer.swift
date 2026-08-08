// Data/ProcessTableReducer.swift
// Pure reduction of raw kernel samples into a ProcessSnapshot: rate deltas,
// PID+start-time identity, App Grouping (spec §4). No system calls here —
// unit tests feed synthetic samples through this seam (spec §8).

import Foundation

struct ProcessTableReducer {
    /// Prior tick's cumulative counters, keyed by full identity so a reused
    /// PID is never compared against its previous occupant (spec §4.1).
    private struct Prior {
        var cpuNanoseconds: UInt64
        var diskBytesRead: UInt64?
        var diskBytesWritten: UInt64?
        var netBytesIn: UInt64?
        var netBytesOut: UInt64?
        var timestampUsec: UInt64
    }

    private var prior: [ProcessIdentity: Prior] = [:]
    private let currentUid: UInt32

    init(currentUid: UInt32 = getuid()) {
        self.currentUid = currentUid
    }

    mutating func update(
        samples: [RawProcessSample],
        net: [Int32: NetCounters]?,
        nowUsec: UInt64,
        coreCount: Int,
        totalMemoryBytes: UInt64
    ) -> ProcessSnapshot {
        var records: [ProcessRecord] = []
        records.reserveCapacity(samples.count)
        var seen = Set<ProcessIdentity>()
        seen.reserveCapacity(samples.count)

        for sample in samples {
            let identity = ProcessIdentity(pid: sample.pid, startUsec: sample.startUsec)
            seen.insert(identity)
            let previous = prior[identity]

            let dtSeconds = previous.map { max(Double(nowUsec - $0.timestampUsec) / 1_000_000, 0.001) }

            // CPU% = Δcpu_ns / Δwall_ns, on Activity Monitor's scale where
            // 100 % is one fully-busy core and the value can exceed 100 % for a
            // multi-threaded process. Spec §4.1 normalized this across all
            // cores (the Windows convention); matching Activity Monitor is a
            // deliberate deviation. New rows: 0.
            var cpuPercent = 0.0
            if let previous, let dtSeconds, sample.cpuNanoseconds >= previous.cpuNanoseconds {
                let delta = Double(sample.cpuNanoseconds - previous.cpuNanoseconds)
                cpuPercent = delta / (dtSeconds * 1_000_000_000) * 100
            }

            let diskReadRate = rate(now: sample.diskBytesRead, before: previous?.diskBytesRead, dt: dtSeconds)
            let diskWriteRate = rate(now: sample.diskBytesWritten, before: previous?.diskBytesWritten, dt: dtSeconds)

            let netCounters = net?[sample.pid]
            let netDown = rate(now: netCounters?.bytesIn, before: previous?.netBytesIn, dt: dtSeconds)
            let netUp = rate(now: netCounters?.bytesOut, before: previous?.netBytesOut, dt: dtSeconds)
            // No nettop sample at all this tick → column shows `–` (spec §4.5).
            let netAvailable = net != nil && netCounters != nil

            // Same-user rows have full detail; cross-user rows gate the
            // extended fields until the daemon fills them (spec §4.4/§4.5).
            let detailLevel: ProcessDetailLevel = sample.uid == currentUid
                ? .full : .requiresElevation

            prior[identity] = Prior(
                cpuNanoseconds: sample.cpuNanoseconds,
                diskBytesRead: sample.diskBytesRead,
                diskBytesWritten: sample.diskBytesWritten,
                netBytesIn: netCounters?.bytesIn,
                netBytesOut: netCounters?.bytesOut,
                timestampUsec: nowUsec
            )

            records.append(ProcessRecord(
                identity: identity,
                name: sample.name,
                path: sample.path,
                bundlePath: appBundlePath(forExecutablePath: sample.path),
                uid: sample.uid,
                userName: userName(for: sample.uid),
                ppid: sample.ppid,
                status: status(fromRaw: sample.rawStatus),
                isProtected: isSystemProtected(pid: sample.pid, name: sample.name, path: sample.path),
                cpuPercent: cpuPercent,
                residentMemory: sample.residentMemory,
                diskReadRate: diskReadRate,
                diskWriteRate: diskWriteRate,
                netDownRate: netAvailable ? netDown : nil,
                netUpRate: netAvailable ? netUp : nil,
                detailLevel: detailLevel
            ))
        }

        // Vanished processes are dropped immediately (spec §4.1).
        for key in prior.keys where !seen.contains(key) {
            prior.removeValue(forKey: key)
        }

        return Self.snapshot(from: records, totalMemoryBytes: totalMemoryBytes, coreCount: coreCount)
    }

    /// Groups records into App Groups + flat background section (spec §3.3).
    static func snapshot(from records: [ProcessRecord], totalMemoryBytes: UInt64, coreCount: Int) -> ProcessSnapshot {
        var byBundle: [String: [ProcessRecord]] = [:]
        var background: [ProcessRecord] = []
        for record in records {
            if let bundle = record.bundlePath {
                byBundle[bundle, default: []].append(record)
            } else {
                background.append(record)
            }
        }
        let groups = byBundle.map { bundlePath, children in
            AppGroup(
                bundlePath: bundlePath,
                displayName: displayName(forBundlePath: bundlePath),
                children: children.sorted { $0.cpuPercent > $1.cpuPercent }
            )
        }
        return ProcessSnapshot(
            groups: groups,
            backgroundProcesses: background,
            timestamp: Date(),
            totalMemoryBytes: totalMemoryBytes,
            logicalCoreCount: coreCount
        )
    }

    /// "Safari.app" → "Safari"; falls back to the last path component.
    static func displayName(forBundlePath bundlePath: String) -> String {
        let last = bundlePath.split(separator: "/").last.map(String.init) ?? bundlePath
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }

    private func rate(now: UInt64?, before: UInt64?, dt: Double?) -> Double {
        guard let now, let before, let dt, now >= before else { return 0 }
        return Double(now - before) / dt
    }

    private func status(fromRaw raw: Int32) -> ProcessStatus {
        // sys/proc.h: SIDL 1, SRUN 2, SSLEEP 3, SSTOP 4, SZOMB 5.
        switch raw {
        case 1: return .starting
        case 2, 3: return .running
        case 4: return .stopped
        case 5: return .exiting
        default: return .running
        }
    }

    private func userName(for uid: UInt32) -> String {
        if let entry = getpwuid(uid) {
            return String(cString: entry.pointee.pw_name)
        }
        return "uid \(uid)"
    }
}
