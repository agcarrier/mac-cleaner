import Darwin
import Foundation

/// CPU time since boot, all cores together, in scheduler ticks.
public struct CPUTicks: Equatable, Sendable {
    public let busy: UInt64
    public let total: UInt64
    public init(busy: UInt64, total: UInt64) {
        self.busy = busy
        self.total = total
    }
}

/// The share of CPU time spent busy between two samples, 0...1. Zero when no time passed or the counters wrapped.
public func cpuShare(from a: CPUTicks, to b: CPUTicks) -> Double {
    guard b.total > a.total, b.busy >= a.busy else { return 0 }
    return min(1, Double(b.busy - a.busy) / Double(b.total - a.total))
}

/// Bytes in use the way Activity Monitor adds them up: app memory (internal − purgeable) + wired + compressed.
public func memoryUsed(internal: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64 {
    ((`internal` > purgeable ? `internal` - purgeable : 0) + wired + compressed) * pageSize
}

private let host = mach_host_self()

public func readCPUTicks() -> CPUTicks? {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
    }
    guard status == KERN_SUCCESS else { return nil }
    let ticks = info.cpu_ticks  // user, system, idle, nice
    let busy = UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.3)
    return CPUTicks(busy: busy, total: busy + UInt64(ticks.2))
}

public func readMemory() -> (used: UInt64, total: UInt64)? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
    let status = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
    }
    guard status == KERN_SUCCESS else { return nil }
    let used = memoryUsed(internal: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
                          wired: UInt64(stats.wire_count), compressed: UInt64(stats.compressor_page_count),
                          pageSize: UInt64(sysconf(_SC_PAGESIZE)))
    let total = ProcessInfo.processInfo.physicalMemory
    return (min(used, total), total)
}

/// The startup volume, as Finder counts free space (purgeable space included).
public func readDisk() -> (free: Int64, total: Int64)? {
    let values = try? URL(filePath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
    guard let free = values?.volumeAvailableCapacityForImportantUsage, let total = values?.volumeTotalCapacity else { return nil }
    return (free, Int64(total))
}
