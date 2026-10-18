import SwiftUI
import MacCleanerCore

/// One update check per click; the result lasts for the session. Nothing checks on its own.
@MainActor @Observable
final class UpdatesModel {
    enum Phase { case idle, checking(done: Int, total: Int), done(UpdateReport) }
    private(set) var phase = Phase.idle

    func check() {
        if case .checking = phase { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        phase = .checking(done: 0, total: 0)
        Task {
            // Apple's own apps update through Apple, and its store lookup doesn't answer for them.
            let apps = await Task.detached { installedApps(home: home).filter { !$0.isApple } }.value
            phase = .checking(done: 0, total: apps.count)
            let report = await checkUpdates(apps, progress: { done in
                Task { @MainActor in
                    if case .checking = self.phase { self.phase = .checking(done: done, total: apps.count) }
                }
            })
            phase = .done(report)
        }
    }
}

struct UpdatesView: View {
    let model: UpdatesModel

    var body: some View {
        VStack(spacing: 16) {
            ToolHeader(tool: .applications)
            switch model.phase {
            case .idle:
                Spacer()
                Text("Spruce asks the App Store, each app\u{2019}s own update feed, and Homebrew which apps have a newer version. It doesn\u{2019}t download or install anything.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                PillButton("Check for Updates") { model.check() }
                Spacer()
            case .checking(let done, let total):
                Spacer()
                ProgressView()
                Text(total == 0 ? "Finding apps\u{2026}" : "Checked \(done) of \(total)").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
            case .done(let report):
                if report.available.isEmpty {
                    Spacer()
                    Text("Everything Spruce can check is up to date.").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List(report.available) { UpdateRow(update: $0) }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                }
                HStack {
                    Text("\(report.available.count) to update \u{00B7} \(report.upToDate) up to date \u{00B7} \(report.unchecked.count) can\u{2019}t be checked")
                        .foregroundStyle(.secondary)
                        .help(report.unchecked.isEmpty ? "" : "No update source for: " + report.unchecked.map(\.name).joined(separator: ", "))
                    Spacer()
                    Button("Check Again") { model.check() }
                }
                .font(.callout)
            }
        }
        .padding([.horizontal, .bottom], 20)
    }
}

private struct UpdateRow: View {
    let update: AvailableUpdate

    private var source: String {
        switch update.source {
        case .appStore: "App Store"
        case .sparkle: "the app\u{2019}s update feed"
        case .homebrew: "Homebrew"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: update.app.url.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(update.app.name)
                Text("\(update.installed) \u{2192} \(update.latest) \u{00B7} from \(source)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if update.source == .appStore, let page = update.link {
                // macappstore:// opens the page in the App Store app instead of the browser.
                Button("App Store") {
                    var store = URLComponents(url: page, resolvingAgainstBaseURL: false)
                    store?.scheme = "macappstore"
                    NSWorkspace.shared.open(store?.url ?? page)
                }
            } else {
                if let link = update.link {
                    Button(update.source == .sparkle ? "Release Notes" : "Website") { NSWorkspace.shared.open(link) }
                }
                Button("Open App") { NSWorkspace.shared.openApplication(at: update.app.url, configuration: .init()) }
                    .help("Most apps check for updates when they open, or under the app menu \u{2192} Check for Updates.")
            }
        }
    }
}
