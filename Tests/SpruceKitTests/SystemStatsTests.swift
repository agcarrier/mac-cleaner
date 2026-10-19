import Foundation
import Testing
@testable import SpruceKit

@Test func cpuShare() {
    let a = CPUTicks(busy: 100, total: 1_000)
    let b = CPUTicks(busy: 150, total: 1_200)
    #expect(SpruceKit.cpuShare(from: a, to: b) == 0.25)   // 50 busy of 200 ticks
    #expect(SpruceKit.cpuShare(from: a, to: a) == 0)      // no time passed
    #expect(SpruceKit.cpuShare(from: b, to: a) == 0)      // counters went backwards (wrap): no number rather than a wrong one
    #expect(SpruceKit.cpuShare(from: a, to: CPUTicks(busy: 400, total: 1_200)) == 1)  // clamped
}

@Test func memoryUsedAddsTheRightParts() {
    // App memory (internal − purgeable) + wired + compressed, in pages.
    #expect(memoryUsed(internal: 1_000, purgeable: 200, wired: 300, compressed: 100, pageSize: 16_384) == 1_200 * 16_384)
    #expect(memoryUsed(internal: 100, purgeable: 200, wired: 0, compressed: 0, pageSize: 4_096) == 0)  // never negative
}

@Test func liveReadersArePlausible() throws {
    let cpu = try #require(readCPUTicks())
    #expect(cpu.total > 0 && cpu.busy <= cpu.total)
    let memory = try #require(readMemory())
    #expect(memory.used > 0 && memory.used <= memory.total)
    #expect(memory.total == ProcessInfo.processInfo.physicalMemory)
    let disk = try #require(readDisk())
    #expect(disk.free > 0 && disk.free <= disk.total)
}

/// One CPU + memory sample every 3 s must cost next to nothing.
@Test func sampleIsCheap() {
    let start = Date()
    for _ in 0..<1_000 { _ = readCPUTicks(); _ = readMemory() }
    #expect(Date().timeIntervalSince(start) < 0.5)  // under 0.5 ms a sample
}
