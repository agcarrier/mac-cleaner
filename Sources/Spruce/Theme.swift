import SwiftUI

/// A tool's big rounded-square glyph, title and subtitle.
struct ToolHeader: View {
    let tool: Tool

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [tool.tint, tool.tint.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: tool.symbol).font(.system(size: 32, weight: .semibold)).foregroundStyle(.white))
                .shadow(color: tool.tint.opacity(0.35), radius: 12, y: 6)
            Text(tool.title).font(.title.bold())
            Text(tool.subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 28)
    }
}

/// The soft color wash behind a tool's view: strongest at the top center, fading to the window background.
struct ToolWash: View {
    let tint: Color

    var body: some View {
        RadialGradient(colors: [tint.opacity(0.25), .clear], center: .top, startRadius: 0, endRadius: 420)
            .ignoresSafeArea()
    }
}

/// The one primary action on a screen.
struct PillButton: View {
    let title: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Text(title).font(.headline).padding(.horizontal, 22).padding(.vertical, 3)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

/// A sidebar row: the tool's symbol in a small colored tile, like System Settings.
struct SidebarTile: View {
    let tool: Tool

    var body: some View {
        Label {
            Text(tool.title)
        } icon: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tool.tint.gradient)
                .frame(width: 20, height: 20)
                .overlay(Image(systemName: tool.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
        }
    }
}
