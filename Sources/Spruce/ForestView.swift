import SwiftUI
import SpruceKit

/// The running total for everyone; for supporters, a tree for every gigabyte Spruce has cleared on this Mac.
struct ForestView: View {
    @Environment(ForestStore.self) private var forest
    let isSupporter: Bool

    static let maxDrawn = 300

    var body: some View {
        let ledger = forest.ledger
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your forest").font(.headline)
                Spacer()
                Text("\(bytes(ledger.freedBytes)) cleared on this Mac").font(.callout).foregroundStyle(.secondary)
            }
            if isSupporter {
                if ledger.treesPlanted.isEmpty {
                    Text("Your first tree grows when Spruce has cleared 1 GB.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Grove(trees: Array(ledger.treesPlanted.prefix(Self.maxDrawn)))
                        .frame(height: Grove.height(for: min(ledger.treesPlanted.count, Self.maxDrawn)))
                    if ledger.treesPlanted.count > Self.maxDrawn {
                        Text("+ \(ledger.treesPlanted.count - Self.maxDrawn) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Supporters see their forest grow here.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .card()
    }
}

/// Rows of trees on soft ground lines, oldest first and largest.
private struct Grove: View {
    let trees: [Date]

    static let perRow = 20
    static let rowHeight: CGFloat = 46

    static func height(for count: Int) -> CGFloat { CGFloat((count + perRow - 1) / perRow) * rowHeight + 6 }

    var body: some View {
        Canvas { context, size in
            let slot = size.width / CGFloat(Self.perRow)
            let ground = Color.green.opacity(0.18)
            let rows = (trees.count + Self.perRow - 1) / Self.perRow
            for row in 0..<rows {
                let baseline = CGFloat(row + 1) * Self.rowHeight
                context.fill(Path(roundedRect: CGRect(x: 0, y: baseline - 2, width: size.width, height: 4), cornerRadius: 2), with: .color(ground))
            }
            for (i, date) in trees.enumerated() {
                let seed = UInt64(bitPattern: Int64(date.timeIntervalSince1970 * 1000)) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(i)
                // Older trees (earlier in the list) have had longer to grow.
                let age = trees.count > 1 ? 1 - Double(i) / Double(trees.count - 1) : 1
                let height = Self.rowHeight * (0.55 + 0.4 * age)
                let x = (CGFloat(i % Self.perRow) + 0.5) * slot + CGFloat(Int(seed >> 8 & 7) - 3)
                let baseline = CGFloat(i / Self.perRow + 1) * Self.rowHeight
                let shade = Color(hue: 0.33 + Double(seed >> 16 & 0xFF) / 255 * 0.07,
                                  saturation: 0.55 + Double(seed >> 24 & 0xFF) / 255 * 0.3,
                                  brightness: 0.45 + Double(seed >> 32 & 0xFF) / 255 * 0.25)
                context.fill(tree(centerX: x, baseline: baseline, height: height), with: .color(shade))
            }
        }
        .accessibilityLabel("\(trees.count) trees")
    }

    /// The menu bar tree's four tiers and trunk, drawn in an 18-point box and scaled to `height`.
    private func tree(centerX: CGFloat, baseline: CGFloat, height: CGFloat) -> Path {
        let s = height / 18
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: centerX + (x - 9) * s, y: baseline - height + y * s) }
        var path = Path(roundedRect: CGRect(origin: p(7.9, 14.0), size: CGSize(width: 2.2 * s, height: 3.6 * s)), cornerRadius: 0.7 * s)
        let tiers: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(8.6, 15.0, 1.6, 8.1), (5.8, 12.0, 1.1, 6.5), (3.0, 8.9, 0.6, 5.0), (0.6, 5.8, 0, 3.5)]
        for (top, bottom, topHalf, bottomHalf) in tiers {
            path.move(to: p(9 - topHalf, top))
            if topHalf > 0 { path.addLine(to: p(9 + topHalf, top)) }
            path.addLine(to: p(9 + bottomHalf, bottom - 0.9))
            path.addCurve(to: p(9 - bottomHalf, bottom - 0.9),
                          control1: p(9 + bottomHalf * 0.55, bottom + 0.35), control2: p(9 - bottomHalf * 0.55, bottom + 0.35))
            path.closeSubpath()
        }
        return path
    }
}
