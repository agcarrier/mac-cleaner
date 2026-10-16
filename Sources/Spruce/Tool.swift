import SwiftUI

/// The sidebar's tools, in order. Later phases add Performance, My Clutter, Screen Clean and the rest.
enum Tool: String, CaseIterable, Identifiable {
    case smartCare, cleanup, space, applications

    var id: Self { self }

    var title: String {
        switch self {
        case .smartCare: "Smart Care"
        case .cleanup: "Cleanup"
        case .space: "Space"
        case .applications: "Applications"
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: "sparkles"
        case .cleanup: "bubbles.and.sparkles"
        case .space: "chart.pie.fill"
        case .applications: "square.grid.2x2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .smartCare: .green
        case .cleanup: .orange
        case .space: .indigo
        case .applications: .blue
        }
    }

    var subtitle: String {
        switch self {
        case .smartCare: "One scan across everything. You review before anything moves."
        case .cleanup: "Leftovers from deleted apps, caches, and broken launch items."
        case .space: "Package caches, old installers, idle projects, and your largest files."
        case .applications: "Remove an app and everything it leaves behind."
        }
    }
}
