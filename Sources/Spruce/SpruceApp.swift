import SwiftUI
import MacCleanerCore
import SpruceKit

@main
struct SpruceApp: App {
    @State private var state = AppState()
    @AppStorage(SettingsKey.menuBarMonitor) private var showMonitor = false

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(state: state)
                .environment(state.supporter)
                .environment(state.forest)
                // spruce:// links land in the open window instead of opening another.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView().environment(state.supporter)
        }

        // Off by default; Settings → Menu bar turns it on.
        MenuBarExtra(isInserted: $showMonitor) {
            MonitorPanel(monitor: state.monitor)
        } label: {
            MonitorLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// One model per tool, so results survive switching tools within a session.
@MainActor @Observable
final class AppState {
    let forest = ForestStore()
    let smartCare: ScanModel
    let cleanup: ScanModel
    let space: ScanModel
    let diskMap = DiskMapModel()
    let updates = UpdatesModel()
    let monitor = SystemMonitor()
    let background = BackgroundItemsModel()
    let duplicates: ScanModel
    let similar: ScanModel
    let screenCleaner = ScreenCleaner()
    let supporter = SupporterModel()

    init() {
        // Every clean plants its bytes in the forest.
        let planted: @MainActor (CleanSummary) -> Void = { [forest] in forest.record($0.bytes) }
        smartCare = ScanModel(onlyPreselected: true,
                              scanner: liveScanner(Set(MacCleanerCore.Category.scannable).union([.devcaches, .downloads]), thresholds: { currentThresholds() }),
                              onCleaned: planted)
        cleanup = ScanModel(scanner: liveScanner(Set(MacCleanerCore.Category.scannable), thresholds: { currentThresholds() }), onCleaned: planted)
        space = ScanModel(scanner: liveScanner(Set(MacCleanerCore.Category.space), thresholds: { currentThresholds() }), onCleaned: planted)
        duplicates = ScanModel(scanner: liveClutterScanner(.duplicates, folders: { currentClutterFolders() }), onCleaned: planted)
        similar = ScanModel(scanner: liveClutterScanner(.similar, folders: { currentClutterFolders() }), onCleaned: planted)
    }
}

struct RootView: View {
    let state: AppState
    @State private var tool: Tool? = .smartCare
    @AppStorage(SettingsKey.installerDays) private var installerDays = 30
    @AppStorage(SettingsKey.idleProjectDays) private var idleProjectDays = 60
    @AppStorage(SettingsKey.clutterFolders) private var clutterFolders = ""
    @AppStorage(SettingsKey.accentTheme) private var theme = AccentTheme.forest
    @AppStorage(SettingsKey.seasonalIcon) private var icon = SeasonalIcon.classic

    var body: some View {
        NavigationSplitView {
            List(selection: $tool) {
                ForEach(Tool.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.tools) { SidebarTile(tool: $0).tag($0) }
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) { StorageCard { tool = .space }.padding(10) }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            let current = tool ?? .smartCare
            detail(for: current)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ToolWash(tint: current.tint))
                .tint(current.tint)
                .navigationTitle(current.title)
                // The wash runs up under the toolbar, and the header already names the tool.
                .toolbarBackground(.hidden, for: .windowToolbar)
                .modifier(HiddenToolbarTitle())
        }
        .frame(minWidth: 760, minHeight: 520)
        // Results were judged by the old rules, so drop them rather than leave stale ✓ items selectable.
        .onChange(of: installerDays) { resetResults() }
        .onChange(of: idleProjectDays) { resetResults() }
        .onChange(of: clutterFolders) { [state.duplicates, state.similar].forEach { $0.reset() } }
        .onChange(of: theme, initial: true) { Appearance.shared.update(isSupporter: state.supporter.isSupporter) }
        .onChange(of: icon) { Appearance.shared.update(isSupporter: state.supporter.isSupporter) }
        .onChange(of: state.supporter.isSupporter) { Appearance.shared.update(isSupporter: state.supporter.isSupporter) }
        // The key is untrusted input: unlock() only stores it if the signature checks out.
        .onOpenURL { url in
            guard let key = unlockKey(from: url) else { return }
            state.supporter.unlock(key)
            tool = .supporter
        }
    }

    private func resetResults() {
        [state.smartCare, state.cleanup, state.space].forEach { $0.reset() }
    }

    @ViewBuilder private func detail(for tool: Tool) -> some View {
        switch tool {
        case .smartCare: ScanToolView(tool: tool, model: state.smartCare, showsPermissionNote: true,
                                      covers: MacCleanerCore.Category.scannable + [.devcaches, .downloads])
        case .cleanup: ScanToolView(tool: tool, model: state.cleanup, showsPermissionNote: true, covers: MacCleanerCore.Category.scannable)
        case .space: SpaceView(model: state.space, diskMap: state.diskMap)
        case .applications: ApplicationsTool(updates: state.updates)
        case .performance: PerformanceView(background: state.background)
        case .myClutter: MyClutterView(duplicates: state.duplicates, similar: state.similar)
        case .screenClean: ScreenCleanView(cleaner: state.screenCleaner)
        case .supporter: SupporterView()
        }
    }
}

/// Keeps the window's title (Window menu, Mission Control) but doesn't draw it in the toolbar. macOS 15 and later.
private struct HiddenToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { content.toolbar(removing: .title) } else { content }
    }
}
