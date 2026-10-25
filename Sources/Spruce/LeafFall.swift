import AppKit
import SwiftUI
import SpruceKit

/// A supporter extra: two seconds of falling leaves over the done screen, and an optional rustle. Plays once per clean;
/// nothing for anyone else, and no leaves with Reduce Motion on.
struct LeafFall: View {
    let tint: Color
    @Environment(SupporterModel.self) private var supporter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.rustleSound) private var rustle = false
    @State private var start = Date.now
    @State private var finished = false

    static let duration = 2.0
    private static let leaves = (0..<24).map { Leaf(seed: $0) }

    var body: some View {
        Group {
            if supporter.isSupporter && !reduceMotion && !finished {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(start) / Self.duration
                    Canvas { context, size in
                        for leaf in Self.leaves { leaf.draw(in: &context, size: size, progress: t, tint: tint) }
                    }
                }
                .task {
                    try? await Task.sleep(for: .seconds(Self.duration))
                    finished = true
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            start = .now
            if supporter.isSupporter && rustle { Self.sound?.play() }
        }
    }

    private static let sound: NSSound? = Bundle.main.url(forResource: "rustle", withExtension: "caf")
        .flatMap { NSSound(contentsOf: $0, byReference: true) }
}

private struct Leaf {
    let x: Double, delay: Double, sway: Double, spin: Double, size: Double, shade: Double

    init(seed: Int) {
        // Fixed per leaf, so it falls the same way each frame.
        var r = UInt64(seed + 1) &* 0x9E37_79B9_7F4A_7C15
        func next() -> Double { r ^= r >> 12; r ^= r << 25; r ^= r >> 27; return Double((r &* 0x2545_F491_4F6C_DD1D) >> 11) / Double(1 << 53) }
        x = next(); delay = next() * 0.35; sway = 20 + next() * 40; spin = (next() - 0.5) * 6; size = 9 + next() * 9; shade = next()
    }

    func draw(in context: inout GraphicsContext, size canvas: CGSize, progress: Double, tint: Color) {
        let p = (progress - delay) / (1 - delay)
        guard p > 0, p < 1 else { return }
        let y = -20 + (canvas.height + 40) * p
        let center = CGPoint(x: canvas.width * x + sway * sin(p * .pi * 3 + x * 6), y: y)
        var leaf = context
        leaf.opacity = p > 0.8 ? (1 - p) / 0.2 : 1
        leaf.translateBy(x: center.x, y: center.y)
        leaf.rotate(by: .radians(spin * p + x * 6))
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -size / 2))
        path.addQuadCurve(to: CGPoint(x: 0, y: size / 2), control: CGPoint(x: size / 2, y: 0))
        path.addQuadCurve(to: CGPoint(x: 0, y: -size / 2), control: CGPoint(x: -size / 2, y: 0))
        leaf.fill(path, with: .color(tint.opacity(0.55 + 0.4 * shade)))
    }
}
