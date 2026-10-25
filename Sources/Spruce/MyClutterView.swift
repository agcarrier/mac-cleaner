import SwiftUI
import SpruceKit
import MacCleanerCore

/// Duplicates or similar photos, each its own scan; the switch sits in the toolbar like Space's.
struct MyClutterView: View {
    private enum Mode: String, CaseIterable { case duplicates = "Duplicates", similar = "Similar Photos" }
    let duplicates: ScanModel
    let similar: ScanModel
    @State private var mode = Mode.duplicates

    var body: some View {
        Group {
            switch mode {
            case .duplicates: ScanToolView(tool: .myClutter, model: duplicates, accessory: AnyView(FolderList()))
            case .similar: ScanToolView(tool: .myClutter, model: similar, accessory: AnyView(FolderList()))
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

/// The folders My Clutter looks in. Changing them drops old results (RootView watches the key).
private struct FolderList: View {
    @AppStorage(SettingsKey.clutterFolders) private var stored = ""
    @State private var refused: String?

    private var folders: [URL] { stored.isEmpty ? defaultClutterFolders : stored.split(separator: "\n").map { URL(filePath: String($0)) } }

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(folders, id: \.path) { folder in
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill").foregroundStyle(Tool.myClutter.tint)
                            Text(folder.lastPathComponent).lineLimit(1)
                            Button { save(folders.filter { $0 != folder }) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("Stop looking in \(folder.path)")
                                .disabled(folders.count == 1)
                        }
                        .font(.callout)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                        .help(folder.path)
                    }
                }
            }
            Button("Add Folder\u{2026}") { add() }
            if !stored.isEmpty { Button("Reset") { stored = "" } }
        }
        .frame(maxWidth: 640)
        .overlay(alignment: .bottom) {
            if let refused { Text(refused).font(.caption).foregroundStyle(.orange).offset(y: 18) }
        }
    }

    private func save(_ urls: [URL]) {
        stored = urls == defaultClutterFolders ? "" : urls.map(\.path).joined(separator: "\n")
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let (ok, no) = (panel.urls.filter { isAllowedClutterFolder($0, home: home) }, panel.urls.filter { !isAllowedClutterFolder($0, home: home) })
        refused = no.isEmpty ? nil : "Spruce only looks in your home folder or on external disks, so it skipped \(no.map(\.lastPathComponent).joined(separator: ", "))."
        save(folders + ok.filter { new in !folders.contains { $0.path == new.path } })
    }
}
