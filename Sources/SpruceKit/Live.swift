import AppKit
import MacCleanerCore

/// The engine context for this Mac right now. The installed-app lookup is skipped when nothing needs ownership.
public func liveContext(thresholds: Thresholds, includeInstalled: Bool) -> Context {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let running = runningBundleIDs()
    let installed = includeInstalled ? installedBundleIDs(home: home).union(running) : []
    return Context(home: home, installed: installed, running: running, thresholds: thresholds)
}

/// Scans `categories` on a background task. Cancelling the caller cancels the scan between categories.
public func liveScanner(_ categories: Set<MacCleanerCore.Category>, thresholds: @escaping @Sendable () -> Thresholds) -> Scanner {
    let includeInstalled = !categories.isSubset(of: Set(MacCleanerCore.Category.space))
    return { progress in
        let task = Task.detached(priority: .userInitiated) {
            scan(categories, liveContext(thresholds: thresholds(), includeInstalled: includeInstalled), progress: progress)
        }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}

public func isRunning(_ app: AppInfo) -> Bool {
    runningBundleIDs().contains(app.bundleID.lowercased())
}

func runningBundleIDs() -> Set<String> {
    Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
}
