import SwiftUI

/// The sidebar's tools, in order. Later phases add My Clutter and the rest.
enum Tool: String, CaseIterable, Identifiable {
    case smartCare, cleanup, space, applications, performance, screenClean

    var id: Self { self }

    var title: String {
        switch self {
        case .smartCare: "Smart Care"
        case .cleanup: "Cleanup"
        case .space: "Space"
        case .applications: "Applications"
        case .performance: "Performance"
        case .screenClean: "Screen Clean"
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: "sparkles"
        case .cleanup: "bubbles.and.sparkles"
        case .space: "chart.pie.fill"
        case .applications: "square.grid.2x2.fill"
        case .performance: "gauge.with.dots.needle.67percent"
        case .screenClean: "keyboard"
        }
    }

    var tint: Color {
        switch self {
        case .smartCare: .green
        case .cleanup: .orange
        case .space: .indigo
        case .applications: .blue
        case .performance: .pink
        case .screenClean: .gray
        }
    }

    var subtitle: String {
        switch self {
        case .smartCare: "One scan across everything. You review before anything moves."
        case .cleanup: "Leftovers from deleted apps, caches, and broken launch items."
        case .space: "Package caches, old installers, idle projects, and your largest files."
        case .applications: "Remove an app and everything it leaves behind."
        case .performance: "What starts with your Mac, and a few maintenance tasks."
        case .screenClean: "Lock the keyboard and trackpad so you can wipe them and the screen."
        }
    }
}
