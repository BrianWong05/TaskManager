// Data/Collectors/SystemCollectors.swift
// System-level collectors (spec §5, verified on macOS 26). Protocol-backed so
// the reducer's rate math is unit-testable without the kernel (spec §8).

import Foundation
import IOKit

/// Mock seam for every system metric source (spec §8).
protocol SystemMetricsCollecting: Sendable {
    func cpuTicks() -> CPURawTicks?
    func memory() -> MemoryRaw?
    func diskTotals() -> DiskRawTotals?
    func netTotals() -> NetRawTotals?
    /// "Device Utilization %" from IOAccelerator PerformanceStatistics.
    func gpuUtilization() -> Double?
    func upTimeSeconds() -> TimeInterval
}

struct SystemMetricsCollector: SystemMetricsCollecting {
    /// hw.pagesize, cached once (avoids the non-concurrency-safe global var).
    private static let pageSize: UInt64 = {
        var size: Int64 = 0
        var length = MemoryLayout<Int64>.size
        sysctlbyname("hw.pagesize", &size, &length, nil, 0)
        return size > 0 ? UInt64(size) : 16_384
    }()

    // MARK: CPU — host_statistics(HOST_CPU_LOAD_INFO) + per-core (spec §5)

    func cpuTicks() -> CPURawTicks? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let total = CPURawTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3),
            perCore: perCoreTicks()
        )
        return total
    }

    private func perCoreTicks() -> [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] {
        var infoCount = mach_msg_type_number_t(0)
        var infoPointer: processor_info_array_t?
        var cpuCount = natural_t(0)
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &infoPointer, &infoCount)
        guard result == KERN_SUCCESS, let pointer = infoPointer else { return [] }
        defer {
            let byteSize = vm_size_t(MemoryLayout<integer_t>.stride) * vm_size_t(infoCount)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: pointer), byteSize)
        }
        var cores: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []
        let states = UnsafeBufferPointer(start: pointer, count: Int(infoCount))
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            guard base + 3 < states.count else { break }
            cores.append((user: UInt64(states[base + Int(CPU_STATE_USER)]),
                          system: UInt64(states[base + Int(CPU_STATE_SYSTEM)]),
                          idle: UInt64(states[base + Int(CPU_STATE_IDLE)]),
                          nice: UInt64(states[base + Int(CPU_STATE_NICE)])))
        }
        return cores
    }

    // MARK: Memory — HOST_VM_INFO64 + vm.swapusage (spec §5)

    func memory() -> MemoryRaw? {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = Self.pageSize
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        let swapOK = sysctl(&mib, 2, &swap, &size, nil, 0) == 0

        return MemoryRaw(
            wired: UInt64(stats.wire_count) * pageSize,
            active: UInt64(stats.active_count) * pageSize,
            inactive: UInt64(stats.inactive_count) * pageSize,
            free: UInt64(stats.free_count) * pageSize,
            compressed: UInt64(stats.compressor_page_count) * pageSize,
            swapUsed: swapOK ? swap.xsu_used : 0,
            totalPhysical: UInt64(ProcessInfo.processInfo.physicalMemory)
        )
    }

    // MARK: Disk — IOKit IOBlockStorageDriver "Statistics" (spec §5)

    func diskTotals() -> DiskRawTotals? {
        var totals = DiskRawTotals(bytesRead: 0, bytesWritten: 0)
        var found = false
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let statistics = registryDictionary(service, key: "Statistics") {
                if let read = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value {
                    totals.bytesRead += read
                }
                if let written = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value {
                    totals.bytesWritten += written
                }
                found = true
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return found ? totals : nil
    }

    // MARK: Network — getifaddrs byte counters (spec §5)

    func netTotals() -> NetRawTotals? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var totals = NetRawTotals(bytesIn: 0, bytesOut: 0)
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let info = entry.pointee
            if let addr = info.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let name = info.ifa_name, String(cString: name) != "lo0",
               let dataPtr = info.ifa_data {
                let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                totals.bytesIn += UInt64(data.ifi_ibytes)
                totals.bytesOut += UInt64(data.ifi_obytes)
            }
            cursor = info.ifa_next
        }
        return totals
    }

    // MARK: GPU — IOAccelerator "PerformanceStatistics" (spec §5)

    func gpuUtilization() -> Double? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = registryDictionary(service, key: "PerformanceStatistics") {
                // Apple Silicon exposes "Device Utilization %"; some drivers
                // report "GPU Core Utilization %" instead.
                for key in ["Device Utilization %", "GPU Core Utilization %"] {
                    if let value = (stats[key] as? NSNumber)?.doubleValue {
                        best = max(best ?? 0, value)
                    }
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return best
    }

    // MARK: Up time — kern.boottime

    func upTimeSeconds() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return 0 }
        return Date().timeIntervalSince1970 - TimeInterval(boot.tv_sec)
    }

    private func registryDictionary(_ service: io_registry_entry_t, key: String) -> [String: Any]? {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return property.takeRetainedValue() as? [String: Any]
    }
}
