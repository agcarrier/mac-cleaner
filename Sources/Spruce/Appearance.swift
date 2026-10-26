import AppKit
import SwiftUI

/// Supporter extras: a seasonal Dock icon and accent themes. Anyone else gets the classic icon and Forest colors.
/// Views read the active theme through `Tool.tint`, and Observation re-renders them when it changes.
@MainActor @Observable
final class Appearance {
    static let shared = Appearance()

    private(set) var theme = AccentTheme.forest
    private(set) var icon = SeasonalIcon.classic

    /// Re-reads Settings. Called at launch and whenever the choices or supporter status change.
    func update(isSupporter: Bool) {
        let defaults = UserDefaults.standard
        let newTheme = isSupporter ? AccentTheme(rawValue: defaults.string(forKey: SettingsKey.accentTheme) ?? "") ?? .forest : .forest
        let newIcon = isSupporter ? SeasonalIcon(rawValue: defaults.string(forKey: SettingsKey.seasonalIcon) ?? "") ?? .classic : .classic
        if newTheme != theme { theme = newTheme }
        if newIcon != icon { icon = newIcon }
        icon.apply()
    }
}

enum AccentTheme: String, CaseIterable, Identifiable {
    case forest, bayou, midnight, pastel
    var id: Self { self }

    var title: String { rawValue.capitalized }

    func tint(for tool: Tool) -> Color {
        switch self {
        case .forest: tool.forestTint
        case .bayou: Self.bayouTints[tool, default: .green]
        case .midnight: Self.midnightTints[tool, default: .indigo]
        case .pastel: Self.pastelTints[tool, default: .mint]
        }
    }

    // Moss, cypress, tea-brown water and a heron's blue.
    private static let bayouTints: [Tool: Color] = [
        .smartCare: Color(red: 0.36, green: 0.55, blue: 0.27), .cleanup: Color(red: 0.71, green: 0.47, blue: 0.20),
        .space: Color(red: 0.25, green: 0.45, blue: 0.47), .applications: Color(red: 0.30, green: 0.47, blue: 0.62),
        .performance: Color(red: 0.66, green: 0.33, blue: 0.29), .myClutter: Color(red: 0.42, green: 0.53, blue: 0.40),
        .screenClean: Color(red: 0.45, green: 0.42, blue: 0.36), .supporter: Color(red: 0.71, green: 0.29, blue: 0.27),
    ]
    // Cool blues and violets that stay readable on a dark window.
    private static let midnightTints: [Tool: Color] = [
        .smartCare: Color(red: 0.36, green: 0.62, blue: 0.95), .cleanup: Color(red: 0.55, green: 0.47, blue: 0.95),
        .space: Color(red: 0.38, green: 0.40, blue: 0.85), .applications: Color(red: 0.30, green: 0.70, blue: 0.85),
        .performance: Color(red: 0.75, green: 0.42, blue: 0.85), .myClutter: Color(red: 0.32, green: 0.62, blue: 0.70),
        .screenClean: Color(red: 0.50, green: 0.52, blue: 0.62), .supporter: Color(red: 0.85, green: 0.40, blue: 0.62),
    ]
    // Soft, but dark enough for white glyphs.
    private static let pastelTints: [Tool: Color] = [
        .smartCare: Color(red: 0.45, green: 0.72, blue: 0.58), .cleanup: Color(red: 0.93, green: 0.62, blue: 0.48),
        .space: Color(red: 0.58, green: 0.56, blue: 0.86), .applications: Color(red: 0.47, green: 0.66, blue: 0.88),
        .performance: Color(red: 0.90, green: 0.55, blue: 0.68), .myClutter: Color(red: 0.43, green: 0.72, blue: 0.74),
        .screenClean: Color(red: 0.62, green: 0.62, blue: 0.68), .supporter: Color(red: 0.92, green: 0.50, blue: 0.55),
    ]
}

enum SeasonalIcon: String, CaseIterable, Identifiable {
    case classic, snowy, autumn, blossom, night
    var id: Self { self }

    var title: String { self == .blossom ? "Cherry blossom" : self == .night ? "Night glow" : rawValue.capitalized }

    /// From the app's Resources. Classic is the bundle icon itself.
    var image: NSImage? {
        guard self != .classic, let url = Bundle.main.url(forResource: rawValue, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Changes the Dock icon while Spruce runs. The Finder icon stays classic: changing a signed bundle's icon would
    /// break its signature.
    @MainActor func apply() {
        NSApp.applicationIconImage = image  // nil restores the bundle's icon
    }
}
