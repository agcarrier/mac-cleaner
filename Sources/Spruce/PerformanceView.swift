import SwiftUI
import MacCleanerCore

struct PerformanceView: View {
    private enum Tab: String, CaseIterable { case startup = "Login & Background", maintenance = "Maintenance" }
    @State private var tab = Tab.startup

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                ToolHeader(tool: .performance, compact: true)
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            switch tab {
            case .startup: StartupItemsView()
            case .maintenance: MaintenanceView()
            }
        }
        .padding([.horizontal, .bottom], 20)
        .padding(.top, 8)
    }
}

// MARK: - Login & Background

private struct StartupItemsView: View {
    @State private var agents: [LaunchAgent] = []
    @State private var disabled: Set<String> = []
    @State private var loaded: [String: Bool] = [:]
    @State private var background: [BackgroundItem]?  // nil while sfltool runs
    @State private var legacyOff: Set<String> = []
    @State private var switching: String?
    @State private var problem: String?

    var body: some View {
        List {
            if let background {
                let atLogin = background.filter { $0.kind == .opensAtLogin }
                let helpers = background.filter { $0.kind != .opensAtLogin }
                if !atLogin.isEmpty { Section("Open at login") { ForEach(atLogin) { BackgroundRow(item: $0) } } }
                if !helpers.isEmpty { Section("Apps\u{2019} background helpers") { ForEach(helpers) { BackgroundRow(item: $0) } } }
            } else {
                Section("Open at login") {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading Login Items\u{2026}").foregroundStyle(.secondary) }
                }
            }
            let mine = agents.filter { $0.scope == .user }
            if !mine.isEmpty {
                Section {
                    ForEach(mine) { agentRow($0) }
                } header: {
                    Text("Your launch agents")
                } footer: {
                    Text("Switching one off stops it and keeps it from starting again. Its file stays where it is, so switching it back on restores it.")
                }
            }
            let shared = agents.filter { $0.scope != .user }
            if !shared.isEmpty { Section("For all users") { ForEach(shared) { agentRow($0) } } }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .card()
        HStack {
            if let problem { Text(problem).font(.callout).foregroundStyle(.orange) }
            Spacer()
            Button("Open Login Items Settings\u{2026}") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
            }
        }
        .task {
            await reloadAgents()
            let found = await Task.detached(priority: .utility) { liveBackgroundItems() }.value
            (background, legacyOff) = (found.items, found.legacyDisallowed)
        }
    }

    private func agentRow(_ agent: LaunchAgent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: agent.scope == .daemon ? "gearshape.2" : "gearshape")
                .foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.label).lineLimit(1)
                Text(status(agent)).font(.caption).foregroundStyle(.secondary)
                if let program = agent.program {
                    Text(program).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if switching == agent.id {
                ProgressView().controlSize(.small)
            } else if agent.isSwitchable {
                Toggle("", isOn: Binding(get: { !disabled.contains(agent.label) }, set: { on in Task { await set(agent, on) } }))
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(switching != nil)
            }
        }
    }

    private func status(_ agent: LaunchAgent) -> String {
        if !agent.hasLabel { return "Empty or unlabeled file. macOS ignores it." }
        if agent.scope != .user { return agent.scope == .daemon ? "System daemon \u{00B7} needs an administrator to change" : "All users \u{00B7} needs an administrator to change" }
        if disabled.contains(agent.label) { return "Off" }
        if legacyOff.contains(agent.label) { return "Off in System Settings \u{2192} Login Items" }
        switch loaded[agent.label] {
        case true?: return "Running"
        case false?: return "Loaded, waiting for its next run"
        case nil: return "Not loaded"
        }
    }

    private func set(_ agent: LaunchAgent, _ on: Bool) async {
        switching = agent.id
        problem = nil
        if case .failure(let error) = await Task.detached(operation: { try setAgent(agent, enabled: on) }).result {
            problem = "Couldn\u{2019}t switch \(agent.label) \(on ? "on" : "off"): \(error.localizedDescription)"
        }
        await reloadAgents()
        switching = nil
    }

    private func reloadAgents() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let (found, state) = await Task.detached { (launchAgents(home: home), liveLaunchState()) }.value
        (agents, disabled, loaded) = (found, state.disabled, state.loaded)
    }
}

private struct BackgroundRow: View {
    let item: BackgroundItem

    /// Background Task Management writes the home folder as /Users/<uid>.
    private var path: String? {
        item.appPath?.replacingOccurrences(of: "/Users/\(getuid())/", with: FileManager.default.homeDirectoryForCurrentUser.path + "/")
    }

    private var detail: String {
        var parts = [item.allowed ? "On" : "Off in System Settings"]
        if let parent = item.parentName { parts.append("from \(parent)") }
        if path?.contains("/.Trash/") == true { parts.append("the app is in the Trash") }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let path, FileManager.default.fileExists(atPath: path) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Maintenance

private struct MaintenanceView: View {
    @State private var running: Maintenance?
    @State private var results: [Maintenance: Result<Void, Error>] = [:]
    @State private var confirmSpotlight = false

    var body: some View {
        List(Maintenance.allCases) { task in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(task.title)
                        if task.needsAdmin {
                            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                                .help("Asks for an administrator password when you click Run")
                        }
                    }
                    Text(task.detail).font(.caption).foregroundStyle(.secondary)
                    switch results[task] {
                    case .success?: Label("Done", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    case .failure(let error)?: Text(error.localizedDescription).font(.caption).foregroundStyle(.orange)
                    case nil: EmptyView()
                    }
                }
                Spacer()
                if running == task {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Run") { task == .spotlight ? (confirmSpotlight = true) : start(task) }
                        .disabled(running != nil)
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .card()
        .confirmationDialog("Rebuild the Spotlight index?", isPresented: $confirmSpotlight) {
            Button("Rebuild") { start(.spotlight) }
        } message: {
            Text(Maintenance.spotlight.detail)
        }
    }

    private func start(_ task: Maintenance) {
        running = task
        results[task] = nil
        Task {
            switch await Task.detached(operation: { try runMaintenance(task) }).result {
            case .success(.done): results[task] = .success(())
            case .success(.cancelled): break  // the user closed the password dialog
            case .failure(let error): results[task] = .failure(error)
            }
            running = nil
        }
    }
}
