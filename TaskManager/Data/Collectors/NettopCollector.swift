// Data/Collectors/NettopCollector.swift
// Per-process network via shell-out to nettop (spec §5) — the one fragile
// dependency, isolated here in a single swappable collector. The Network
// column shows `–` while this fails (spec §4.5).

import Foundation

/// Cumulative per-process network counters keyed by pid.
struct NetCounters: Sendable {
    var bytesIn: UInt64
    var bytesOut: UInt64
}

/// Mock seam for nettop (spec §8 — recorded fixtures in tests).
protocol NettopCollecting: Sendable {
    /// nil = nettop failed this tick.
    func sample() -> [Int32: NetCounters]?
}

struct NettopCollector: NettopCollecting {
    func sample() -> [Int32: NetCounters]? {
        NettopCollector.parse(runNettopOutput())
    }

    private func runNettopOutput() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        // Drain the pipe continuously: on large process tables nettop's
        // output exceeds the pipe buffer and the child would block on write
        // until we killed it, faking a nettop failure (spec §4.5).
        let box = OutputBox()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                box.append(chunk)
            }
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        // nettop -L 1 can stall briefly; bound the wait without busy-polling.
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        box.append(pipe.fileHandleForReading.readDataToEndOfFile())
        return box.string()
    }

    /// Thread-safe accumulator for the drained pipe data.
    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }
        func string() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return String(data: data, encoding: .utf8)
        }
    }

    /// Parses `nettop -P -x` CSV: header `,bytes_in,bytes_out,` then rows of
    /// `name.pid,bytes_in,bytes_out,`. Exposed for unit testing (spec §8).
    static func parse(_ output: String?) -> [Int32: NetCounters]? {
        guard let output, !output.isEmpty else { return nil }
        var result: [Int32: NetCounters] = [:]
        var sawDataRow = false
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let key = fields[0]
            guard let dot = key.lastIndex(of: ".") else { continue } // header row has no pid
            let pidPart = key[key.index(after: dot)...]
            guard let pid = Int32(pidPart),
                  let bytesIn = UInt64(fields[1]),
                  let bytesOut = UInt64(fields[2]) else { continue }
            result[pid] = NetCounters(bytesIn: bytesIn, bytesOut: bytesOut)
            sawDataRow = true
        }
        return sawDataRow ? result : nil
    }
}
