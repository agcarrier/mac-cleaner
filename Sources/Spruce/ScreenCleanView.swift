import AppKit
import ApplicationServices
import SwiftUI
import SpruceKit

struct ScreenCleanView: View {
    let cleaner: ScreenCleaner
    @AppStorage(SettingsKey.unlockCombo) private var combo = KeyCombo.standard
    @AppStorage(SettingsKey.screenCleanSeconds) private var seconds = ScreenLock.defaultDuration
    @State private var trusted = AXIsProcessTrusted()
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 16) {
            ToolHeader(tool: .screenClean)
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label("Every keyboard and trackpad stops working, and the screen goes dark.", systemImage: "keyboard")
                Label("Press \(combo.display) to unlock.", systemImage: "command")
                Label("It unlocks by itself after \(duration), in case the combo doesn't.", systemImage: "timer")
            }
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if trusted {
                PillButton("Start Screen Clean") { problem = cleaner.start(combo: combo, duration: seconds) }
            } else {
                Text("To block the keyboard and trackpad, macOS needs you to give Spruce Accessibility access. Spruce uses it only while Screen Clean is running.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                PillButton("Allow Accessibility…") { requestAccess() }
            }
            if let problem { Text(problem).font(.callout).foregroundStyle(.orange) }
            Spacer()
        }
        .padding([.horizontal, .bottom], 20)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = AXIsProcessTrusted()
            if trusted { problem = nil }
        }
    }

    private var duration: String {
        let s = Int(seconds)
        return s < 60 ? "\(s) seconds" : "\(s / 60) minute\(s == 60 ? "" : "s")"
    }

    /// Only ever from the button: shows macOS's own prompt once, and opens the Accessibility list.
    private func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
