import SwiftUI
import SpruceKit

/// CPU, memory and free disk for the menu bar panel. Samples only while `run()` is running, which is tied to the panel:
/// when the panel closes, SwiftUI cancels the task and sampling stops.
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
            // The first CPU figure needs two samples, so it comes after a second; then every 3 s.
            try? await Task.sleep(for: .seconds(ticks == 0 && cpu == nil ? 1 : 3))
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

/// The app icon's spruce as a menu bar template image (black, so macOS tints it for light and dark menu bars): four tiers,
/// each flaring past the one above with a thin gap between, and a trunk. Drawn bottom tier first; each higher tier clears a
/// gap into the one below, then fills.
/// Supporters' seasonal icons add a mark: snow, a falling leaf, blossoms cut into the tiers, or a star.
@MainActor private func spruceIcon(_ variant: SeasonalIcon) -> NSImage {
    if let cached = spruceIcons[variant] { return cached }
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        // (top y, bottom y, half width at top, half width at bottom)
        let tiers: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(8.6, 15.0, 1.6, 8.1), (5.8, 12.0, 1.1, 6.5), (3.0, 8.9, 0.6, 5.0), (0.6, 5.8, 0, 3.5)]
        NSColor.black.setFill()
        NSColor.black.setStroke()
        NSBezierPath(roundedRect: NSRect(x: 7.9, y: 14.0, width: 2.2, height: 3.6), xRadius: 0.7, yRadius: 0.7).fill()
        for (top, bottom, topHalf, bottomHalf) in tiers {
            let tier = NSBezierPath()
            tier.lineJoinStyle = .round
            tier.move(to: NSPoint(x: 9 - topHalf, y: top))
            if topHalf > 0 { tier.line(to: NSPoint(x: 9 + topHalf, y: top)) }
            tier.line(to: NSPoint(x: 9 + bottomHalf, y: bottom - 0.9))
            tier.curve(to: NSPoint(x: 9 - bottomHalf, y: bottom - 0.9),
                       controlPoint1: NSPoint(x: 9 + bottomHalf * 0.55, y: bottom + 0.35),
                       controlPoint2: NSPoint(x: 9 - bottomHalf * 0.55, y: bottom + 0.35))
            tier.close()
            NSGraphicsContext.current?.compositingOperation = .clear
            tier.lineWidth = 1.3
            tier.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            tier.fill()
            tier.lineWidth = 0.6  // rounds the tips
            tier.stroke()
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> NSBezierPath { NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
        switch variant {
        case .classic: break
        case .snowy:
            [dot(2.2, 2.4, 0.8), dot(15.6, 1.6, 0.7), dot(16.4, 6.2, 0.8), dot(1.4, 8.6, 0.7)].forEach { $0.fill() }
        case .autumn:
            let leaf = NSBezierPath()
            leaf.move(to: NSPoint(x: 14.2, y: 1.0))
            leaf.curve(to: NSPoint(x: 17.4, y: 4.4), controlPoint1: NSPoint(x: 17.0, y: 0.8), controlPoint2: NSPoint(x: 17.6, y: 2.4))
            leaf.curve(to: NSPoint(x: 14.2, y: 1.0), controlPoint1: NSPoint(x: 15.0, y: 4.6), controlPoint2: NSPoint(x: 14.0, y: 3.0))
            leaf.fill()
        case .blossom:
            NSGraphicsContext.current?.compositingOperation = .clear
            [dot(7.4, 7.8, 0.75), dot(11.0, 10.6, 0.75), dot(6.6, 12.8, 0.75), dot(10.0, 4.6, 0.6)].forEach { $0.fill() }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        case .night:
            let star = NSBezierPath()
            let (cx, cy) = (15.2, 2.8)
            for i in 0..<8 {
                let r: CGFloat = i % 2 == 0 ? 2.4 : 0.7
                let a = CGFloat(i) * .pi / 4 - .pi / 2
                let p = NSPoint(x: cx + r * cos(a), y: cy + r * sin(a))
                i == 0 ? star.move(to: p) : star.line(to: p)
            }
            star.close()
            star.fill()
        }
        return true
    }
    image.isTemplate = true
    spruceIcons[variant] = image
    return image
}

@MainActor private var spruceIcons: [SeasonalIcon: NSImage] = [:]

/// Just the tree. A template NSImage given straight to Image is what the menu bar draws reliably.
struct MonitorLabel: View {
    var body: some View { Image(nsImage: spruceIcon(Appearance.shared.icon)) }
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
        .task { await monitor.run() }
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
