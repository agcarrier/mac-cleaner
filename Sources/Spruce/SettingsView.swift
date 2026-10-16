import SwiftUI
import MacCleanerCore

enum SettingsKey {
    static let installerDays = "installerDays"
    static let idleProjectDays = "idleProjectDays"
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
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
