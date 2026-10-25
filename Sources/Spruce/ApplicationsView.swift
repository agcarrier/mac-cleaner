import SwiftUI
import SpruceKit
import MacCleanerCore

/// An installed app, identified by where it lives.
struct AppItem: Identifiable, Hashable {
    let app: AppInfo
    var id: String { app.url.path }
    static func == (a: AppItem, b: AppItem) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Applications: the installed list (uninstall), or updates. The switch sits in the toolbar like Space's.
struct ApplicationsTool: View {
    private enum Mode: String, CaseIterable { case installed = "Installed", updates = "Updates" }
    let updates: UpdatesModel
    @State private var mode = Mode.installed

    var body: some View {
        Group {
            switch mode {
            case .installed: ApplicationsView()
            case .updates: UpdatesView(model: updates)
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

struct ApplicationsView: View {
    @State private var apps: [AppItem] = []
    @State private var query = ""
    @State private var selection: AppItem.ID?
    @State private var uninstalling: AppItem?
    @Environment(ForestStore.self) private var forest

    private var filtered: [AppItem] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.app.name.localizedCaseInsensitiveContains(query) || $0.app.bundleID.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 16) {
            ToolHeader(tool: .applications, compact: true)
            List(filtered, selection: $selection) { AppRow(app: $0.app) }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .card()
                .searchable(text: $query, placement: .toolbar, prompt: "Search apps")
            HStack {
                Text("\(apps.count) apps").foregroundStyle(.secondary)
                Spacer()
                PillButton("Uninstall…") { uninstalling = apps.first { $0.id == selection } }
                    .disabled(selection == nil)
            }
        }
        .padding([.horizontal, .bottom], 20)
        .padding(.top, 8)
        .task { await reload() }
        .sheet(item: $uninstalling, onDismiss: { Task { await reload() } }) { UninstallSheet(app: $0.app, forest: forest) }
    }

    private func reload() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Apple's own apps can't be uninstalled, so they aren't listed.
        apps = await Task.detached { installedApps(home: home).filter { !$0.isApple }.map(AppItem.init) }.value
        if let selection, !apps.contains(where: { $0.id == selection }) { self.selection = nil }
    }
}

private struct AppRow: View {
    let app: AppInfo
    @State private var size: Int64?
    @State private var lastUsed: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                Text(lastUsed ?? " ").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(size.map(bytes) ?? "…").monospacedDigit().foregroundStyle(.secondary)
        }
        .task(id: app.url) {
            let url = app.url
            async let measured = Task.detached(priority: .utility) { allocatedSize(url) }.value
            async let used = Task.detached(priority: .utility) { lastUsedDate(url) }.value
            lastUsed = await used.map { "Last used " + RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: .now) } ?? "Never opened"
            size = await measured
        }
    }
}
