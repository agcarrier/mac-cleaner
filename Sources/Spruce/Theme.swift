import SwiftUI
import MacCleanerCore
import SpruceKit

/// A tool's rounded-square glyph, title and subtitle. Big and centered on start screens; compact and leading above lists,
/// so the list gets the room.
struct ToolHeader: View {
    let tool: Tool
    var compact = false
    var title: String?
    var subtitle: String?

    var body: some View {
        if compact {
            HStack(spacing: 12) {
                ToolGlyph(tool: tool, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.title).font(.title2.bold())
                    Text(tool.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 10) {
                ToolGlyph(tool: tool, size: 72)
                Text(title ?? tool.title).font(.title.bold())
                Text(subtitle ?? tool.subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }
}

struct ToolGlyph: View {
    let tool: Tool
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4, style: .continuous)
            .fill(LinearGradient(colors: [tool.tint, tool.tint.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: tool.symbol).font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(.white))
            .shadow(color: tool.tint.opacity(0.35), radius: size / 6, y: size / 12)
    }
}

extension View {
    /// Direction C's content card: a soft panel with a hairline border, for lists and grouped content.
    func card() -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return background(.background.opacity(0.35), in: shape)
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .clipShape(shape)
    }
}

/// The soft color wash behind a tool's view: strongest at the top center, fading to the window background.
struct ToolWash: View {
    let tint: Color

    var body: some View {
        RadialGradient(colors: [tint.opacity(0.28), .clear], center: .top, startRadius: 0, endRadius: 480)
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

/// What a scan looks at, as small tiles on its start screen.
struct CoverageGrid: View {
    let tool: Tool
    let categories: [MacCleanerCore.Category]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(categories, id: \.self) { category in
                HStack(spacing: 8) {
                    Image(systemName: category.symbol).foregroundStyle(tool.tint).frame(width: 18)
                    Text(category.shortTitle).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .card()
            }
        }
        .frame(maxWidth: 440)
    }
}

extension MacCleanerCore.Category {
    var shortTitle: String {
        switch self {
        case .orphans: "Leftovers from deleted apps"
        case .caches: "App caches"
        case .agents: "Broken launch agents"
        case .xcode: "Xcode junk"
        case .uninstall: "Uninstall"
        case .devcaches: "Package & tool caches"
        case .downloads: "Old installers"
        case .projects: "Idle node_modules"
        case .large: "Largest files (listed only)"
        case .duplicates: "Duplicates"
        case .similar: "Similar photos"
        }
    }

    var symbol: String {
        switch self {
        case .orphans: "shippingbox"
        case .caches: "archivebox"
        case .agents: "bolt.horizontal"
        case .xcode: "hammer"
        case .uninstall: "trash"
        case .devcaches: "cube.box"
        case .downloads: "arrow.down.circle"
        case .projects: "folder.badge.gearshape"
        case .large: "doc.text.magnifyingglass"
        case .duplicates: "doc.on.doc"
        case .similar: "photo.on.rectangle"
        }
    }
}

/// The startup disk at the bottom of the sidebar: free space at a glance. Clicking it opens Space.
struct StorageCard: View {
    let open: () -> Void
    @State private var disk: (free: Int64, total: Int64)?
    private let name = (try? URL(filePath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? "Startup Disk"

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                Label(name, systemImage: "internaldrive.fill").font(.callout.weight(.medium))
                ProgressView(value: disk.map { 1 - Double($0.free) / Double(max($0.total, 1)) } ?? 0)
                    .tint(Tool.space.tint)
                Text(disk.map { "\(bytes($0.free)) free of \(bytes($0.total))" } ?? " ")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Space")
        .task {
            // Free space moves slowly; a minute between looks is plenty and costs nothing.
            while !Task.isCancelled {
                disk = readDisk()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
