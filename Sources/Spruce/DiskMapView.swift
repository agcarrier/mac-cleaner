import SwiftUI
import MacCleanerCore
import SpruceKit

/// Space: the findings list, or the disk map. The switch sits in the toolbar so the map keeps the whole window.
struct SpaceView: View {
    private enum Mode: String, CaseIterable { case findings = "Findings", map = "Disk Map" }
    let model: ScanModel
    let diskMap: DiskMapModel
    @State private var mode = Mode.findings

    var body: some View {
        Group {
            switch mode {
            case .findings: ScanToolView(tool: .space, model: model, covers: MacCleanerCore.Category.space)
            case .map: DiskMapView(model: diskMap)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

struct DiskMapView: View {
    let model: DiskMapModel
    @State private var hovered: DiskNode?

    var body: some View {
        VStack(spacing: 12) {
            switch model.phase {
            case .idle:
                Spacer()
                ToolHeader(tool: .space)
                Text("See what\u{2019}s taking up space, folder by folder. Nothing is changed.").foregroundStyle(.secondary)
                PillButton("Map Home Folder") { model.map(FileManager.default.homeDirectoryForCurrentUser) }
                Button("Choose Folder\u{2026}") { chooseFolder() }
                Spacer()
            case .measuring(let url):
                Spacer()
                ToolHeader(tool: .space)
                ProgressView().padding(.top, 8)
                Text("Measuring \(url.lastPathComponent)\u{2026} \(model.itemsMeasured.formatted()) items")
                    .monospacedDigit().foregroundStyle(.secondary)
                Button("Cancel") { model.cancel() }
                Spacer()
            case .map:
                if let current = model.current {
                    breadcrumb(current)
                    TreemapView(node: current, hovered: $hovered) { model.open($0) }
                    footer(current)
                }
            }
        }
        .padding(20)
    }

    private func breadcrumb(_ current: DiskNode) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(model.path.enumerated()), id: \.element.id) { index, node in
                if index > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                Button(node.name) { model.up(to: index) }
                    .buttonStyle(.plain)
                    .fontWeight(node == current ? .semibold : .regular)
                    .foregroundStyle(node == current ? .primary : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(bytes(current.size)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func footer(_ current: DiskNode) -> some View {
        HStack {
            if let hovered, current.children.contains(hovered) {
                Text(hovered.name).lineLimit(1).truncationMode(.middle)
                Text("\(bytes(hovered.size)) \u{00B7} \(share(hovered, of: current))")
                    .monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text("Click a folder to open it. Right-click to reveal in Finder.").foregroundStyle(.secondary)
            }
            Spacer()
            Button("New Map") { model.reset() }
        }
        .font(.callout)
    }

    private func share(_ node: DiskNode, of parent: DiskNode) -> String {
        guard parent.size > 0 else { return "0%" }
        return (Double(node.size) / Double(parent.size)).formatted(.percent.precision(.fractionLength(0...1)))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Map"
        if panel.runModal() == .OK, let url = panel.url { model.map(url) }
    }
}

/// The current folder's children as squarified tiles, largest at the top left.
private struct TreemapView: View {
    let node: DiskNode
    @Binding var hovered: DiskNode?
    let open: (DiskNode) -> Void

    var body: some View {
        GeometryReader { geo in
            let rects = treemap(node.children.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(node.children, rects).enumerated()), id: \.element.0.id) { index, pair in
                    let (child, rect) = pair
                    if rect.width >= 2, rect.height >= 2 {
                        Tile(node: child, rank: index, size: rect.size, isHovered: hovered == child)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .onHover { inside in
                                if inside { hovered = child } else if hovered == child { hovered = nil }
                            }
                            .onTapGesture { open(child) }
                            .contextMenu {
                                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([child.url]) }
                            }
                            .help("\(child.name), \(bytes(child.size))")
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct Tile: View {
    let node: DiskNode
    let rank: Int
    let size: CGSize
    let isHovered: Bool

    private var fill: Color {
        if node.lumped > 0 { return .secondary.opacity(0.18) }
        if node.isDirectory { return Tool.space.tint.opacity(max(0.45, 0.9 - Double(rank) * 0.03)) }
        return .gray.opacity(0.55)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .brightness(isHovered ? 0.12 : 0)
            .padding(1)
            .overlay(alignment: .topLeading) {
                if size.width > 70, size.height > 34 {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            if node.isDirectory { Image(systemName: "folder.fill").font(.caption2) }
                            Text(node.name).font(.caption.weight(.semibold)).lineLimit(1)
                        }
                        Text(bytes(node.size)).font(.caption2).monospacedDigit().opacity(0.85)
                    }
                    .foregroundStyle(node.lumped > 0 ? Color.secondary : Color.white)
                    .padding(6)
                }
            }
            .contentShape(Rectangle())
    }
}
