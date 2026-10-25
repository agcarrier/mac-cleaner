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

    /// The app's own ID or a child of it (helpers, extensions): com.foo.app, com.foo.app.helper. Never com.foo.apple.
    /// Children only count for IDs with three or more parts: an app called com.google mustn't claim com.google.Chrome.
    func owns(_ name: String) -> Bool {
        let n = name.lowercased(), id = bundleID.lowercased()
        return n == id || (id.split(separator: ".").count >= 3 && n.hasPrefix(id + "."))
    }

    /// Same developer by reverse-DNS prefix: com.docker.vmnetd for com.docker.docker.
    func sameVendor(_ name: String) -> Bool {
        let vendor = bundleID.lowercased().split(separator: ".").prefix(2).joined(separator: ".") + "."
        return name.lowercased().hasPrefix(vendor)
    }

    /// App groups the app declares in its code signature; their folders live in ~/Library/Group Containers.
    var appGroups: [String] {
        let (status, data) = run(["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", url.path])
        guard status == 0, let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        return plist["com.apple.security.application-groups"] as? [String] ?? []
    }
}

/// Something outside ~/Library that belongs to the app. Needs admin rights, so we only report it.
public struct SystemItem: Sendable {
    public let path: String
    public let why: String
    public let command: String
}

/// Apps people installed, sorted by name: skips the Trash, mounted disk images, helper apps nested in other bundles,
/// and private copies tucked inside Library folders (Claude Code keeps several in Application Support).
public func installedApps(home: URL) -> [AppInfo] {
    installedAppPaths(home: home)
        .filter { !$0.contains("/.Trash/") && !$0.hasPrefix("/Volumes/") && !$0.contains("/Library/")
            && !($0 as NSString).deletingLastPathComponent.contains(".app") }
        .compactMap { AppInfo(url: URL(filePath: $0)) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

/// When the app was last opened, per Spotlight.
public func lastUsedDate(_ url: URL) -> Date? {
    guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
    return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
}

/// Resolves a .app path, a bundle ID, or an app name. `exact` is false when nothing matched exactly and these
/// are only "name contains" suggestions, which the caller must not act on.
public func findApps(matching query: String, home: URL) -> (apps: [AppInfo], exact: Bool) {
    let path = (query as NSString).expandingTildeInPath
    if path.hasSuffix(".app"), let app = AppInfo(url: URL(filePath: path)) { return ([app], true) }
    let q = query.lowercased()
    let apps = installedApps(home: home)
    func names(_ app: AppInfo) -> [String] {
        [app.bundleID, app.name, app.url.deletingPathExtension().lastPathComponent].map { $0.lowercased() }
    }
    let exact = apps.filter { names($0).contains(q) }
    return exact.isEmpty ? (apps.filter { names($0).contains { $0.contains(q) } }, false) : (exact, true)
}

/// The app bundle plus everything in ~/Library that belongs to it. `groups` defaults to the app's signed app groups.
public func uninstallFindings(for app: AppInfo, _ c: Context, groups: [String]? = nil) -> [Finding] {
    let groups = groups ?? app.appGroups
    let owned = app.owns
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
    // Group folder names are exactly the group IDs. A group named after the app (TEAM.ru.keepcoder.Telegram) is its own;
    // a developer-wide one (TEAM.dev.warp) may be shared with the developer's other apps.
    for group in groups {
        let dir = c.library.appending(path: "Group Containers/\(group)")
        guard FileManager.default.fileExists(atPath: dir.path) else { continue }
        let own = group.lowercased().contains(app.bundleID.lowercased())
        add(dir, own ? "Group Containers" : "Group Containers, may be shared with this developer's other apps", own ? .high : .low)
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

/// System-wide launch items, privileged helpers and installer receipts. `root` and `receipts` are injectable for tests;
/// by default they're `/` and the output of `pkgutil --pkgs`.
public func systemItems(for app: AppInfo, root: URL = URL(filePath: "/"), receipts: [String]? = nil) -> [SystemItem] {
    let library = root.appending(path: "Library")
    let helpers = library.appending(path: "PrivilegedHelperTools")
    var out: [SystemItem] = []
    func link(_ name: String) -> String? { app.owns(name) ? "linked to the app" : app.sameVendor(name) ? "same developer" : nil }

    for sub in ["LaunchDaemons", "LaunchAgents"] {
        for url in children(library.appending(path: sub)) where url.pathExtension == "plist" {
            guard let plist = NSDictionary(contentsOf: url) else { continue }
            let program = launchProgram(plist) ?? ""
            let why = associatedApps(plist).contains(where: app.owns) || program.hasPrefix(app.url.path + "/")
                ? "linked to the app" : link(plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent)
            guard let why else { continue }
            // A loaded daemon keeps running until it's booted out or the Mac restarts.
            let domain = sub == "LaunchDaemons" ? "system" : "gui/$(id -u)"
            out.append(SystemItem(path: url.path, why: why, command: "sudo launchctl bootout \(domain) '\(url.path)'; sudo mv '\(url.path)' ~/.Trash/"))
        }
    }
    for url in children(helpers) {
        guard let why = link(url.lastPathComponent) else { continue }
        out.append(SystemItem(path: url.path, why: why, command: "sudo mv '\(url.path)' ~/.Trash/"))
    }
    let pkgs = receipts ?? String(decoding: run(["/usr/sbin/pkgutil", "--pkgs"]).1, as: UTF8.self).split(separator: "\n").map(String.init)
    for pkg in pkgs {
        guard let why = link(pkg) else { continue }
        out.append(SystemItem(path: "installer receipt \(pkg)", why: why, command: "sudo pkgutil --forget \(pkg)"))
    }
    return out
}
