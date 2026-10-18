import SwiftUI
import MacCleanerCore
import SpruceKit

/// Review an app and everything it owns, then move the selected items to the Trash.
/// System-wide items need an admin password, so they're listed with their commands and never run.
struct UninstallSheet: View {
    let app: AppInfo
    @State private var model: ScanModel
    @State private var system: [SystemItem] = []
    @State private var confirming = false
    @Environment(\.dismiss) private var dismiss

    init(app: AppInfo) {
        self.app = app
        _model = State(initialValue: ScanModel(
            scanner: { _ in uninstallFindings(for: app, liveContext(thresholds: currentThresholds(), includeInstalled: false)) },
            preflight: { isRunning(app) ? "Quit \(app.name) to uninstall it." : nil }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    Text("Uninstall \(app.name)").font(.title2.bold())
                    Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(20)
        .frame(width: 620, height: 560)
        .sheet(isPresented: $confirming) { ConfirmCleanSheet(model: model) }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in model.refreshBlock() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in model.refreshBlock() }
        .task {
            model.refreshBlock()
            model.scan()
            let app = self.app
            system = await Task.detached { systemItems(for: app) }.value
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .scanning:
            Spacer()
            ProgressView("Finding everything \(app.name) left behind…").frame(maxWidth: .infinity)
            Spacer()
            HStack { Spacer(); Button("Cancel") { model.cancel(); dismiss() } }
        case .review:
            FindingsView(model: model)
            if !system.isEmpty { SystemItemsSection(items: system) }
            PermissionNote()
            HStack {
                Text("\(model.selectedFindings.count) selected · \(bytes(model.selectedBytes))").monospacedDigit().foregroundStyle(.secondary)
                if let reason = model.blockedReason { Text(reason).foregroundStyle(.orange) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                PillButton("Uninstall") { confirming = true }
                    .disabled(model.blockedReason != nil || model.selectedFindings.isEmpty)
            }
        case .cleaning:
            Spacer()
            ProgressView("Moving to the Trash…").frame(maxWidth: .infinity)
            Spacer()
        case .done(let summary):
            Spacer()
            Text("Moved \(bytes(summary.bytes)) to the Trash.").font(.title3)
            if summary.failures.contains(where: { $0.finding.detail == "the app" }) {
                Text("Spruce couldn't move \(app.name).app. It may need an admin password.").foregroundStyle(.orange)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            }
            let others = summary.failures.filter { $0.finding.detail != "the app" }
            if !others.isEmpty { FailureList(failures: others) }
            Spacer()
            HStack { Spacer(); PillButton("Done") { dismiss() } }
        }
    }
}

private struct SystemItemsSection: View {
    let items: [SystemItem]

    var body: some View {
        DisclosureGroup("Needs your admin password (\(items.count))") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Spruce never runs these. Check each one, then run it in Terminal if you want it gone.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(items, id: \.path) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(item.path) · \(item.why)").font(.caption)
                        HStack(alignment: .top) {
                            Text(item.command).font(.caption.monospaced()).textSelection(.enabled)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.command, forType: .string)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}
