import SwiftUI
import MacCleanerCore

/// An installed app, identified by where it lives.
struct AppItem: Identifiable, Hashable {
    let app: AppInfo
    var id: String { app.url.path }
    static func == (a: AppItem, b: AppItem) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ApplicationsView: View {
    @State private var apps: [AppItem] = []
    @State private var query = ""
    @State private var selection: AppItem.ID?
    @State private var uninstalling: AppItem?

    private var filtered: [AppItem] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.app.name.localizedCaseInsensitiveContains(query) || $0.app.bundleID.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 16) {
            ToolHeader(tool: .applications)
            List(filtered, selection: $selection) { AppRow(app: $0.app) }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .searchable(text: $query, placement: .toolbar, prompt: "Search apps")
            HStack {
                Text("\(apps.count) apps").foregroundStyle(.secondary)
                Spacer()
                PillButton("Uninstall…") { uninstalling = apps.first { $0.id == selection } }
                    .disabled(selection == nil)
            }
        }
        .padding([.horizontal, .bottom], 20)
        .task { await reload() }
        .sheet(item: $uninstalling, onDismiss: { Task { await reload() } }) { UninstallSheet(app: $0.app) }
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
