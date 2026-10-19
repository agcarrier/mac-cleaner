import SwiftUI
import SpruceKit

/// CPU, memory and free disk for the menu bar item. Samples only while `run()` is running, which is tied to the item's
/// label: when the item leaves the menu bar, SwiftUI cancels the task and sampling stops.
@MainActor @Observable
final class SystemMonitor {
    private(set) var cpu: Double?
    private(set) var memory: (used: UInt64, total: UInt64)?
    private(set) var disk: (free: Int64, total: Int64)?

    func run() async {
        var last = readCPUTicks()
        memory = readMemory()
        disk = readDisk()
        var ticks = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            let now = readCPUTicks()
            if let last, let now { cpu = cpuShare(from: last, to: now) }
            last = now
            memory = readMemory()
            ticks += 1
            if ticks % 10 == 0 { disk = readDisk() }  // every 30 s; free space moves slowly
        }
    }
}

private func percent(_ share: Double) -> String { share.formatted(.percent.precision(.fractionLength(0))) }

struct MonitorLabel: View {
    let monitor: SystemMonitor

    var body: some View {
        Text("\(Image(systemName: "gauge.with.dots.needle.33percent")) \(monitor.cpu.map(percent) ?? "\u{2013}")")
            .monospacedDigit()
            .task { await monitor.run() }
    }
}

struct MonitorPanel: View {
    let monitor: SystemMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("CPU", symbol: "cpu", share: monitor.cpu, detail: monitor.cpu.map(percent))
            row("Memory", symbol: "memorychip", share: monitor.memory.map { Double($0.used) / Double($0.total) },
                detail: monitor.memory.map { "\(memoryBytes($0.used)) of \(memoryBytes($0.total))" })
            row("Disk", symbol: "internaldrive", share: monitor.disk.map { 1 - Double($0.free) / Double($0.total) },
                detail: monitor.disk.map { "\(bytes($0.free)) free" })
            Divider()
            Button("Open Spruce") { openSpruce() }
                .buttonStyle(.plain)
                .foregroundStyle(Tool.smartCare.tint)
        }
        .padding(14)
        .frame(width: 250)
    }

    private func row(_ title: String, symbol: String, share: Double?, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(detail ?? "\u{2013}").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            ProgressView(value: min(max(share ?? 0, 0), 1)).progressViewStyle(.linear).tint(.secondary)
        }
    }

    private func memoryBytes(_ n: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .memory) }

    /// Brings the existing window forward, or opens one if it was closed.
    private func openSpruce() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { openWindow(id: "main") }
    }
}
