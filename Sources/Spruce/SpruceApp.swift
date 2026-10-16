import SwiftUI

@main
struct SpruceApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
    }
}

struct RootView: View {
    @State private var tool: Tool? = .smartCare

    var body: some View {
        NavigationSplitView {
            List(Tool.allCases, selection: $tool) { tool in
                SidebarTile(tool: tool).tag(tool)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            let current = tool ?? .smartCare
            VStack {
                ToolHeader(tool: current)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ToolWash(tint: current.tint))
            .navigationTitle(current.title)
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
