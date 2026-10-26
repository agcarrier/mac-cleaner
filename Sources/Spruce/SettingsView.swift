import SwiftUI
import MacCleanerCore
import SpruceKit

enum SettingsKey {
    static let installerDays = "installerDays"
    static let idleProjectDays = "idleProjectDays"
    static let unlockCombo = "unlockCombo"
    static let screenCleanSeconds = "screenCleanSeconds"
    static let clutterFolders = "clutterFolders"
    static let menuBarMonitor = "menuBarMonitor"
    static let rustleSound = "rustleSound"
    static let accentTheme = "accentTheme"
    static let seasonalIcon = "seasonalIcon"
}

/// My Clutter's folders, one path per line in UserDefaults. Default: Desktop, Documents, Downloads, Pictures.
func currentClutterFolders() -> [URL] {
    let stored = UserDefaults.standard.string(forKey: SettingsKey.clutterFolders) ?? ""
    return stored.isEmpty ? defaultClutterFolders : stored.split(separator: "\n").map { URL(filePath: String($0)) }
}

let defaultClutterFolders = ["Desktop", "Documents", "Downloads", "Pictures"].map {
    FileManager.default.homeDirectoryForCurrentUser.appending(path: $0)
}

/// The age rules as the user set them in Settings (defaults: 30 and 60 days).
func currentThresholds() -> Thresholds {
    let defaults = UserDefaults.standard
    let installer = defaults.integer(forKey: SettingsKey.installerDays)
    let idle = defaults.integer(forKey: SettingsKey.idleProjectDays)
    return Thresholds(installerDays: installer > 0 ? installer : 30, idleProjectDays: idle > 0 ? idle : 60)
}

struct SettingsView: View {
    @Environment(SupporterModel.self) private var supporter
    @AppStorage(SettingsKey.rustleSound) private var rustle = false
    @AppStorage(SettingsKey.accentTheme) private var theme = AccentTheme.forest
    @AppStorage(SettingsKey.seasonalIcon) private var icon = SeasonalIcon.classic
    @AppStorage(SettingsKey.installerDays) private var installerDays = 30
    @AppStorage(SettingsKey.idleProjectDays) private var idleProjectDays = 60
    @AppStorage(SettingsKey.unlockCombo) private var combo = KeyCombo.standard
    @AppStorage(SettingsKey.screenCleanSeconds) private var seconds = ScreenLock.defaultDuration
    @AppStorage(SettingsKey.menuBarMonitor) private var showMonitor = false

    var body: some View {
        Form {
            Section("Cleaning") {
                Stepper(value: $installerDays, in: 1...365) {
                    VStack(alignment: .leading) {
                        Text("Old installers: \(installerDays) days")
                        Text("Disk images and installer packages in Downloads are selected once they're this old.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $idleProjectDays, in: 1...365) {
                    VStack(alignment: .leading) {
                        Text("Idle projects: \(idleProjectDays) days")
                        Text("node_modules folders are listed once a project has had no changes for this long.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Menu bar") {
                Toggle(isOn: $showMonitor) {
                    VStack(alignment: .leading) {
                        Text("Show CPU, memory and free disk in the menu bar")
                        Text("A tree appears in the menu bar; click it for the numbers. Spruce only measures while that panel is open.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Appearance") {
                Picker(selection: $icon) {
                    ForEach(SeasonalIcon.allCases) { Text($0.title).tag($0) }
                } label: {
                    SupporterLabel("Icon", detail: "Shown in the Dock and menu bar while Spruce runs.")
                }
                Picker(selection: $theme) {
                    ForEach(AccentTheme.allCases) { Text($0.title).tag($0) }
                } label: {
                    SupporterLabel("Accent colors", detail: "Each tool's color across Spruce.")
                }
            }
            .disabled(!supporter.isSupporter)
            Section("Sounds") {
                Toggle(isOn: $rustle) {
                    SupporterLabel("Rustle when a clean finishes", detail: "A soft rustle of leaves. Off by default.")
                }
                .disabled(!supporter.isSupporter)
            }
            Section("Screen Clean") {
                ComboRecorder(combo: $combo)
                Picker(selection: $seconds) {
                    Text("30 seconds").tag(30.0)
                    ForEach([1, 2, 3, 5, 10], id: \.self) { Text("\($0) minute\($0 == 1 ? "" : "s")").tag(Double($0 * 60)) }
                } label: {
                    VStack(alignment: .leading) {
                        Text("Unlock by itself after")
                        Text("A failsafe, in case the combo doesn't work.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

/// Shows the unlock combo; "Change…" records the next key press. Combos with fewer than two modifiers are refused.
struct ComboRecorder: View {
    @Binding var combo: KeyCombo
    @State private var monitor: Any?
    @State private var refusal: String?

    var body: some View {
        LabeledContent {
            HStack {
                if monitor != nil {
                    Text("Press the new combo…").foregroundStyle(.secondary)
                    Button("Cancel") { stopRecording() }
                } else {
                    Text(combo.display).font(.body.monospaced())
                    Button("Change…") { startRecording() }
                    if combo != .standard { Button("Reset") { combo = .standard } }
                }
            }
        } label: {
            VStack(alignment: .leading) {
                Text("Unlock combo")
                Text(refusal ?? "Use at least two of ⌃ ⌥ ⇧ ⌘, so wiping the keys can't unlock it.")
                    .font(.caption).foregroundStyle(refusal == nil ? Color.secondary : Color.orange)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        refusal = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil } // Escape
            let new = KeyCombo(keyCode: Int64(event.keyCode), modifiers: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)),
                               key: keyName(event))
            if new.isValid { combo = new } else { refusal = "\(new.display) has too few modifiers. Try again with two or more." }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// The key's printed letter, or its code for keys without one (function keys, arrows).
    private func keyName(_ event: NSEvent) -> String {
        let chars = event.charactersIgnoringModifiers?.uppercased() ?? ""
        let printable = !chars.isEmpty && chars.unicodeScalars.allSatisfy { $0.value > 0x20 && !(0xF700...0xF8FF).contains($0.value) }
        return printable ? chars : "Key \(event.keyCode)"
    }
}

/// A setting's title and caption; supporter-only settings say so until Spruce is unlocked.
struct SupporterLabel: View {
    @Environment(SupporterModel.self) private var supporter
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 6) {
                Text(title)
                if !supporter.isSupporter {
                    Text("Supporter").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(.red.opacity(0.15))).foregroundStyle(.red)
                }
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
