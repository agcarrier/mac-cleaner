import SwiftUI

/// A supporter extra: something calm behind Screen Clean instead of plain black. Every scene stays dim (peak brightness
/// at or under 25%) so smudges still show, and holds still with Reduce Motion on.
enum ScreenScene: String, CaseIterable, Identifiable {
    case black, forest, rain, sunrise
    var id: Self { self }

    var title: String { rawValue.capitalized }
}

struct ScreenSceneView: View {
    let scene: ScreenScene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now

    var body: some View {
        if scene == .black {
            Color.black
        } else {
            // 20 fps is plenty for drifting fog and rain, and keeps Spruce's CPU low while it runs.
            TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 8 : timeline.date.timeIntervalSince(start)
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                    switch scene {
                    case .black: break
                    case .forest: drawForest(&context, size, t)
                    case .rain: drawRain(&context, size, t)
                    case .sunrise: drawSunrise(&context, size, t)
                    }
                }
            }
        }
    }

    /// Three layers of tree silhouettes, nearer ones darker, with a slow fog drifting between them.
    private func drawForest(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let sky = Gradient(colors: [Color(red: 0.03, green: 0.07, blue: 0.08), Color(red: 0.08, green: 0.14, blue: 0.13)])
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let layers: [(height: Double, shade: Double, count: Int, seed: Double)] = [(0.42, 0.13, 26, 1), (0.30, 0.09, 20, 2), (0.20, 0.05, 14, 3)]
        for (i, layer) in layers.enumerated() {
            var trees = Path()
            for n in 0..<layer.count {
                let jitter = sin(Double(n) * 12.9898 * layer.seed) * 0.5 + 0.5
                let x = (Double(n) + jitter * 0.6) / Double(layer.count - 1) * size.width
                let h = size.height * layer.height * (0.7 + 0.4 * jitter)
                let w = h * 0.32
                trees.move(to: CGPoint(x: x, y: size.height - h))
                trees.addLine(to: CGPoint(x: x + w, y: size.height))
                trees.addLine(to: CGPoint(x: x - w, y: size.height))
                trees.closeSubpath()
            }
            context.fill(trees, with: .color(Color(red: layer.shade * 0.6, green: layer.shade, blue: layer.shade * 0.85)))
            // Fog between this layer and the next.
            if i < layers.count - 1 {
                let drift = (t * (8 + Double(i) * 5)).truncatingRemainder(dividingBy: size.width * 2)
                for k in 0..<3 {
                    let x = (Double(k) * size.width * 0.7 + drift).truncatingRemainder(dividingBy: size.width * 2) - size.width * 0.5
                    let band = CGRect(x: x, y: size.height * (0.62 + 0.1 * Double(i)), width: size.width * 0.9, height: size.height * 0.16)
                    var fog = context
                    fog.addFilter(.blur(radius: 60))
                    fog.fill(Path(ellipseIn: band), with: .color(.white.opacity(0.06)))
                }
            }
        }
    }

    /// Drops sliding down dark glass, each on its own slow path.
    private func drawRain(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let glass = Gradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.10), Color(red: 0.02, green: 0.03, blue: 0.05)])
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(glass, startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        for n in 0..<90 {
            let a = Double(n)
            let rand = { (k: Double) in (sin(a * 78.233 + k * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1).magnitude }
            let x = rand(1) * size.width
            let speed = 20 + rand(2) * 70
            let y = (rand(3) * size.height + t * speed).truncatingRemainder(dividingBy: size.height + 40) - 20
            let r = 2 + rand(4) * 4
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * 1.3, width: r * 2, height: r * 2.6)), with: .color(.white.opacity(0.10 + rand(5) * 0.08)))
            // A faint trail above the drop.
            context.fill(Path(CGRect(x: x - r * 0.25, y: y - r * 14, width: r * 0.5, height: r * 13)), with: .color(.white.opacity(0.03)))
        }
    }

    /// A slow gradient from night toward dawn and back, over about two minutes.
    private func drawSunrise(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let phase = (1 - cos(t / 120 * 2 * .pi)) / 2  // 0 → 1 → 0
        let top = Color(red: 0.03 + 0.05 * phase, green: 0.03 + 0.06 * phase, blue: 0.09 + 0.08 * phase)
        let horizon = Color(red: 0.10 + 0.14 * phase, green: 0.05 + 0.08 * phase, blue: 0.08 + 0.04 * phase)
        let sky = Gradient(colors: [top, top, horizon])
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let sun = CGRect(x: size.width / 2 - size.width * 0.3, y: size.height * (1.05 - 0.15 * phase), width: size.width * 0.6, height: size.width * 0.3)
        context.fill(Path(ellipseIn: sun), with: .radialGradient(Gradient(colors: [Color(red: 0.25, green: 0.14, blue: 0.06).opacity(phase), .clear]),
                                                               center: CGPoint(x: sun.midX, y: sun.midY), startRadius: 0, endRadius: sun.width / 2))
    }
}
