import Foundation

public struct AppInfo: Sendable {
    public let url: URL
    public let bundleID: String
    public let name: String

    public init?(url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        self.url = url
        bundleID = id
        name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    public var isApple: Bool { bundleID.lowercased().hasPrefix("com.apple.") || url.path.hasPrefix("/System/") }
}

/// Resolves a .app path, a bundle ID, or an app name. Exact matches win; otherwise falls back to "name contains".
/// More than one result means the query is ambiguous.
public func findApps(matching query: String, home: URL) -> [AppInfo] {
    let path = (query as NSString).expandingTildeInPath
    if path.hasSuffix(".app"), let app = AppInfo(url: URL(filePath: path)) { return [app] }
    let q = query.lowercased()
    // Apps people installed: skip the Trash, mounted disk images, helper apps nested in other bundles,
    // and private copies tucked inside Library folders (Claude Code keeps several in Application Support).
    let apps = installedAppPaths(home: home)
        .filter { !$0.contains("/.Trash/") && !$0.hasPrefix("/Volumes/") && !$0.contains("/Library/")
            && !($0 as NSString).deletingLastPathComponent.contains(".app") }
        .sorted()
        .compactMap { AppInfo(url: URL(filePath: $0)) }
    func names(_ app: AppInfo) -> [String] {
        [app.bundleID, app.name, app.url.deletingPathExtension().lastPathComponent].map { $0.lowercased() }
    }
    let exact = apps.filter { names($0).contains(q) }
    return exact.isEmpty ? apps.filter { names($0).contains { $0.contains(q) } } : exact
}

/// The app bundle plus everything in ~/Library that belongs to it.
public func uninstallFindings(for app: AppInfo, _ c: Context) -> [Finding] {
    let id = app.bundleID.lowercased()
    // The app's own ID or a child of it (helpers, extensions): com.foo.app, com.foo.app.helper. Never com.foo.apple.
    func owned(_ name: String) -> Bool {
        let n = name.lowercased()
        return n == id || n.hasPrefix(id + ".")
    }
    var out: [Finding] = []
    var seen = Set<String>()
    func add(_ url: URL, _ detail: String, _ confidence: Confidence) {
        guard seen.insert(url.standardizedFileURL.path).inserted else { return }
        out.append(Finding(category: .uninstall, title: url.lastPathComponent, detail: detail,
                           size: allocatedSize(url), confidence: confidence, action: .trash([url])))
    }

    add(app.url, "the app", .high)

    for sub in ["Preferences", "Preferences/ByHost", "Application Support", "Caches", "Saved Application State",
                "HTTPStorages", "WebKit", "Cookies", "Logs", "Application Scripts"] {
        for url in children(c.library.appending(path: sub)) {
            let name = ["plist", "savedState", "binarycookies"].contains(url.pathExtension)
                ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
            if owned(name) { add(url, sub, .high) }
        }
    }
    for dir in children(c.library.appending(path: "Containers")) where containerOwner(dir).map(owned) == true {
        add(dir, "Containers", .high)
    }
    for url in children(c.library.appending(path: "LaunchAgents")) where url.pathExtension == "plist" {
        guard let plist = NSDictionary(contentsOf: url) else { continue }
        let label = plist["Label"] as? String ?? ""
        let insideApp = launchProgram(plist)?.hasPrefix(app.url.path + "/") == true
        if associatedApps(plist).contains(where: owned) || owned(label) || insideApp { add(url, "LaunchAgents", .high) }
    }
    let appNames = Set([app.name, app.url.deletingPathExtension().lastPathComponent])
    for url in children(c.library.appending(path: "Logs/DiagnosticReports"))
    where appNames.contains(where: { url.lastPathComponent.hasPrefix($0 + "-") || url.lastPathComponent.hasPrefix($0 + "_") }) {
        add(url, "crash report", .high)
    }
    // Folders named after the app instead of its bundle ID: usually right, but can be a vendor folder other apps share.
    for sub in ["Application Support", "Caches", "Logs"] {
        for name in appNames {
            let url = c.library.appending(path: "\(sub)/\(name)")
            if FileManager.default.fileExists(atPath: url.path) { add(url, "\(sub), matched by name only", .low) }
        }
    }
    return out
}
