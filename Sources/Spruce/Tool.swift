import SwiftUI

/// The sidebar's tools, in order. Later phases add the menu bar monitor and Cloud & Mail.
enum Tool: String, CaseIterable, Identifiable {
    case smartCare, cleanup, space, applications, performance, myClutter, screenClean, supporter

    var id: Self { self }

    /// Sidebar groups, in order.
    static let sections: [(title: String, tools: [Tool])] = [
        ("Clean", [.smartCare, .cleanup, .space]),
        ("Manage", [.applications, .performance, .myClutter]),
        ("Tools", [.screenClean, .supporter]),
    ]

    var title: String {
        switch self {
        case .smartCare: "Smart Care"
        case .cleanup: "Cleanup"
        case .space: "Space"
        case .applications: "Applications"
        case .performance: "Performance"
        case .myClutter: "My Clutter"
        case .screenClean: "Screen Clean"
        case .supporter: "Supporter"
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: "sparkles"
        case .cleanup: "bubbles.and.sparkles"
        case .space: "chart.pie.fill"
        case .applications: "square.grid.2x2.fill"
        case .performance: "gauge.with.dots.needle.67percent"
        case .myClutter: "doc.on.doc.fill"
        case .screenClean: "keyboard"
        case .supporter: "heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .smartCare: .green
        case .cleanup: .orange
        case .space: .indigo
        case .applications: .blue
        case .performance: .pink
        case .myClutter: .teal
        case .screenClean: .gray
        case .supporter: .red
        }
    }

    var subtitle: String {
        switch self {
        case .smartCare: "One scan across everything. You review before anything moves."
        case .cleanup: "Leftovers from deleted apps, caches, and broken launch items."
        case .space: "Package caches, old installers, idle projects, and your largest files."
        case .applications: "Remove an app and everything it leaves behind."
        case .performance: "What starts with your Mac, and a few maintenance tasks."
        case .myClutter: "Duplicate files and similar photos in the folders you choose."
        case .screenClean: "Lock the keyboard and trackpad so you can wipe them and the screen."
        case .supporter: "Spruce is free. If it helps you, you can say thanks."
        }
    }
}
