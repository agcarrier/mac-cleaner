import SwiftUI
import MacCleanerCore
import SpruceKit

@main
struct SpruceApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(state: state)
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
    }
}

/// One model per tool, so results survive switching tools within a session.
@MainActor @Observable
final class AppState {
    let smartCare = ScanModel(onlyPreselected: true,
                              scanner: liveScanner(Set(MacCleanerCore.Category.scannable).union([.devcaches, .downloads]), thresholds: { currentThresholds() }))
    let cleanup = ScanModel(scanner: liveScanner(Set(MacCleanerCore.Category.scannable), thresholds: { currentThresholds() }))
    let space = ScanModel(scanner: liveScanner(Set(MacCleanerCore.Category.space), thresholds: { currentThresholds() }))
}

struct RootView: View {
    let state: AppState
    @State private var tool: Tool? = .smartCare
    @AppStorage(SettingsKey.installerDays) private var installerDays = 30
    @AppStorage(SettingsKey.idleProjectDays) private var idleProjectDays = 60

    var body: some View {
        NavigationSplitView {
            List(Tool.allCases, selection: $tool) { tool in
                SidebarTile(tool: tool).tag(tool)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            let current = tool ?? .smartCare
            detail(for: current)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ToolWash(tint: current.tint))
                .navigationTitle(current.title)
        }
        .frame(minWidth: 760, minHeight: 520)
        // Results were judged by the old rules, so drop them rather than leave stale ✓ items selectable.
        .onChange(of: installerDays) { resetResults() }
        .onChange(of: idleProjectDays) { resetResults() }
    }

    private func resetResults() {
        [state.smartCare, state.cleanup, state.space].forEach { $0.reset() }
    }

    @ViewBuilder private func detail(for tool: Tool) -> some View {
        switch tool {
        case .smartCare: ScanToolView(tool: tool, model: state.smartCare, showsPermissionNote: true)
        case .cleanup: ScanToolView(tool: tool, model: state.cleanup, showsPermissionNote: true)
        case .space: ScanToolView(tool: tool, model: state.space)
        case .applications: ApplicationsView()
        }
    }
}
