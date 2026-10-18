import SwiftUI
import MacCleanerCore
import SpruceKit

enum SettingsKey {
    static let installerDays = "installerDays"
    static let idleProjectDays = "idleProjectDays"
    static let unlockCombo = "unlockCombo"
    static let screenCleanSeconds = "screenCleanSeconds"
}

/// The age rules as the user set them in Settings (defaults: 30 and 60 days).
func currentThresholds() -> Thresholds {
    let defaults = UserDefaults.standard
    let installer = defaults.integer(forKey: SettingsKey.installerDays)
    let idle = defaults.integer(forKey: SettingsKey.idleProjectDays)
    return Thresholds(installerDays: installer > 0 ? installer : 30, idleProjectDays: idle > 0 ? idle : 60)
}

struct SettingsView: View {
    @AppStorage(SettingsKey.installerDays) private var installerDays = 30
    @AppStorage(SettingsKey.idleProjectDays) private var idleProjectDays = 60
    @AppStorage(SettingsKey.unlockCombo) private var combo = KeyCombo.standard
    @AppStorage(SettingsKey.screenCleanSeconds) private var seconds = ScreenLock.defaultDuration

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
