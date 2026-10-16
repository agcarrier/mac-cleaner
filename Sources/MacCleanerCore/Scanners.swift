import Foundation

public enum Category: String, Sendable {
    case orphans, caches, agents, xcode, uninstall
    case devcaches, downloads, projects, large

    /// What a plain scan covers.
    public static let scannable: [Category] = [.orphans, .caches, .agents, .xcode]
    /// What `mac-cleaner space` covers.
    public static let space: [Category] = [.devcaches, .downloads, .projects, .large]

    public var title: String {
        switch self {
        case .orphans: "Leftovers from deleted apps"
        case .caches: "App caches"
        case .agents: "Broken launch agents"
        case .xcode: "Xcode junk"
        case .uninstall: "Uninstall"
        case .devcaches: "Package & tool caches"
        case .downloads: "Old installers in Downloads"
        case .projects: "node_modules in idle projects"
        case .large: "Largest files (listed only, never cleaned)"
        }
    }
}

public enum Confidence: Sendable { case high, low }

public enum Action: Sendable {
    case trash([URL])
    case run([String])
    case report  // shown for information, never acted on
}

public struct Finding: Sendable {
    public let category: Category
    public let title: String
    public let detail: String
    public let size: Int64
    public let confidence: Confidence
    public let action: Action
}

public struct Context: Sendable {
    public let home: URL
    public let installed: Set<String>  // lowercased bundle IDs, running apps included
    public let running: Set<String>    // lowercased bundle IDs

    public init(home: URL, installed: Set<String>, running: Set<String>) {
        self.home = home
        self.installed = installed
        self.running = running
    }

    var library: URL { home.appending(path: "Library") }
}

public func scan(_ categories: Set<Category>, _ c: Context) -> [Finding] {
    (Category.scannable + Category.space).filter(categories.contains).flatMap { category -> [Finding] in
        switch category {
        case .orphans: scanOrphans(c)
        case .caches: scanCaches(c)
        case .agents: scanLaunchAgents(c)
        case .xcode: scanXcode(c)
        case .devcaches: scanDevCaches(c)
        case .downloads: scanDownloads(c)
        case .projects: scanNodeModules(c)
        case .large: scanLargeFiles(c)
        case .uninstall: []
        }
    }
}

public func perform(_ action: Action) throws {
    switch action {
    case .trash(let urls):
        for url in urls { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    case .run(let args):
        let (status, _) = run(args)
        if status != 0 { throw CocoaError(.executableLoad, userInfo: [NSLocalizedDescriptionKey: "\(args.joined(separator: " ")) exited \(status)"]) }
    case .report:
        break
    }
}

// MARK: - Installed apps

/// Every app bundle Spotlight knows about, including nested helper apps, plus a folder walk.
public func installedAppPaths(home: URL) -> Set<String> {
    var paths = Set(String(decoding: run(["mdfind", "kMDItemContentType == 'com.apple.application-bundle'"]).1, as: UTF8.self)
        .split(separator: "\n").map(String.init))
    // Fallback for when Spotlight is off or still indexing: app folders plus one level of subfolders (Utilities, vendor folders).
    for root in [URL(filePath: "/Applications"), URL(filePath: "/System/Applications"), home.appending(path: "Applications")] {
        for url in children(root) {
            if url.pathExtension == "app" { paths.insert(url.path) } else { children(url).filter { $0.pathExtension == "app" }.forEach { paths.insert($0.path) } }
        }
    }
    return paths
}

public func installedBundleIDs(home: URL) -> Set<String> {
    Set(installedAppPaths(home: home).compactMap { Bundle(path: $0)?.bundleIdentifier?.lowercased() })
}

// MARK: - Orphans

func scanOrphans(_ c: Context) -> [Finding] {
    var items: [(id: String, url: URL, dir: String)] = []
    for dir in children(c.library.appending(path: "Containers")) {
        if let id = containerOwner(dir) { items.append((id, dir, "Containers")) }
    }
    for sub in ["Preferences", "Application Support", "Caches", "Saved Application State", "HTTPStorages", "WebKit", "Cookies"] {
        for url in children(c.library.appending(path: sub)) {
            let name = ["plist", "savedState", "binarycookies"].contains(url.pathExtension)
                ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
            if looksLikeBundleID(name) { items.append((name, url, sub)) }
        }
    }
    // Containers and saved window state only exist for real GUI apps. Prefs and Application Support can belong to
    // CLI tools and helpers we can't see, so on their own they stay low confidence.
    let guiApps = Set(items.filter { $0.dir == "Containers" || $0.dir == "Saved Application State" }.map { $0.id.lowercased() })
    return items.compactMap { item in
        let owner = ownership(of: item.id, by: c.installed)
        guard owner == .orphan || owner == .sameVendor else { return nil }
        let risky = item.dir == "Preferences" || item.dir == "Application Support"
        let high = owner == .orphan && (!risky || guiApps.contains(item.id.lowercased()))
        let why = owner == .orphan ? "no installed app" : "vendor still has an installed app"
        return Finding(category: .orphans, title: item.id, detail: "\(item.dir), \(why)",
                       size: allocatedSize(item.url), confidence: high ? .high : .low, action: .trash([item.url]))
    }
}

/// False when containers exist but macOS blocks reading their metadata (no Full Disk Access).
public func canReadContainers(home: URL) -> Bool {
    let dirs = children(home.appending(path: "Library/Containers"))
    return dirs.isEmpty || dirs.prefix(20).contains { containerOwner($0) != nil }
}

/// A container's real owner comes from its metadata plist, not its folder name.
func containerOwner(_ dir: URL) -> String? {
    NSDictionary(contentsOf: dir.appending(path: ".com.apple.containermanagerd.metadata.plist"))?["MCMMetadataIdentifier"] as? String
}

// MARK: - Caches

/// Apple frameworks that cache under plain names instead of com.apple.* IDs. Only names known to be Apple's;
/// anything unsure stays visible as ○.
let appleCacheNames: Set<String> = ["ARFileCache", "CloudKit", "EnergyKit", "FamilyCircle", "familycircled", "GameKit",
                                    "GeoServices", "JetPackResourceBundles", "LSMImageCache", "PassKit", "ProfileAvatars", "TrickPlay"]

func scanCaches(_ c: Context) -> [Finding] {
    var out: [Finding] = []
    for url in children(c.library.appending(path: "Caches")) {
        let name = url.lastPathComponent
        if appleCacheNames.contains(name) { continue }
        // Named caches (Homebrew, ms-playwright, pip, ...) have no bundle ID, so we can't tell if their owner is running.
        var confidence = Confidence.low
        if looksLikeBundleID(name) {
            let owner = ownership(of: name, by: c.installed)
            if owner == .system || owner == .orphan { continue }  // orphans are listed under their own category
            if ownership(of: name, by: c.running) == .installed { continue }
            confidence = .high
        }
        let size = allocatedSize(url)
        if size > 0 { out.append(Finding(category: .caches, title: name, detail: "~/Library/Caches", size: size, confidence: confidence, action: .trash([url]))) }
    }
    for dir in children(c.library.appending(path: "Containers")) {
        guard let id = containerOwner(dir), ownership(of: id, by: c.installed) == .installed,
              ownership(of: id, by: c.running) != .installed else { continue }
        // Empty the container's Caches folder, never the folder itself: it's part of the container's structure.
        let kids = children(dir.appending(path: "Data/Library/Caches"))
        let size = kids.reduce(0) { $0 + allocatedSize($1) }
        if size > 0 { out.append(Finding(category: .caches, title: id, detail: "sandboxed app caches", size: size, confidence: .high, action: .trash(kids))) }
    }
    return out
}

// MARK: - Launch agents

func scanLaunchAgents(_ c: Context) -> [Finding] {
    children(c.library.appending(path: "LaunchAgents")).filter { $0.pathExtension == "plist" }.compactMap { url in
        guard let plist = NSDictionary(contentsOf: url) else { return nil }
        let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
        if label.lowercased().hasPrefix("com.apple.") { return nil }
        let apps = associatedApps(plist)
        let program = launchProgram(plist)
        let why: String
        if let program, program.hasPrefix("/"), !FileManager.default.fileExists(atPath: program) {
            why = "program is gone: \(program)"
        } else if !apps.isEmpty, apps.allSatisfy({ ownership(of: $0, by: c.installed) == .orphan }) {
            why = "its app \(apps[0]) is not installed"
        } else {
            return nil
        }
        return Finding(category: .agents, title: label, detail: why, size: allocatedSize(url), confidence: .high, action: .trash([url]))
    }
}

/// AssociatedBundleIdentifiers is Apple's own link from a launch item to its app; it can be a string or an array.
func associatedApps(_ plist: NSDictionary) -> [String] {
    plist["AssociatedBundleIdentifiers"] as? [String] ?? (plist["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []
}

func launchProgram(_ plist: NSDictionary) -> String? {
    plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
}

// MARK: - Xcode

func scanXcode(_ c: Context) -> [Finding] {
    let dev = c.library.appending(path: "Developer")
    let xcodeOpen = c.running.contains("com.apple.dt.xcode")
    var out: [Finding] = []
    func add(_ title: String, _ dir: URL, _ confidence: Confidence, _ note: String) {
        let kids = children(dir)
        let size = kids.reduce(0) { $0 + allocatedSize($1) }
        guard size > 0 else { return }
        out.append(Finding(category: .xcode, title: title, detail: xcodeOpen ? "\(note) (Xcode is open)" : note, size: size,
                           confidence: xcodeOpen ? .low : confidence, action: .trash(kids)))
    }
    add("DerivedData", dev.appending(path: "Xcode/DerivedData"), .high, "rebuilt on next build")
    add("Xcode caches", c.library.appending(path: "Caches/com.apple.dt.Xcode"), .high, "regenerated")
    add("Simulator caches", dev.appending(path: "CoreSimulator/Caches"), .high, "regenerated")
    add("iOS Device Logs", dev.appending(path: "Xcode/iOS Device Logs"), .high, "old device crash logs")
    for dir in children(dev.appending(path: "Xcode")) where dir.lastPathComponent.hasSuffix("DeviceSupport") {
        add(dir.lastPathComponent, dir, .low, "re-downloaded when a device connects")
    }
    add("Archives", dev.appending(path: "Xcode/Archives"), .low, "needed to symbolicate builds you shipped")

    let sims = unavailableSimulators()
    if !sims.isEmpty {
        let size = sims.reduce(0) { $0 + allocatedSize(dev.appending(path: "CoreSimulator/Devices/\($1)")) }
        out.append(Finding(category: .xcode, title: "\(sims.count) unavailable simulators", detail: "their runtime is no longer installed",
                           size: size, confidence: xcodeOpen ? .low : .high, action: .run(["xcrun", "simctl", "delete", "unavailable"])))
    }
    return out
}

func unavailableSimulators() -> [String] {
    let (status, data) = run(["xcrun", "simctl", "list", "devices", "unavailable", "--json"])
    guard status == 0, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let devices = json["devices"] as? [String: [[String: Any]]] else { return [] }
    return devices.values.flatMap { $0.compactMap { $0["udid"] as? String } }
}

// MARK: - Helpers

func children(_ url: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
}

public func allocatedSize(_ url: URL) -> Int64 {
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
    guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
    guard values.isDirectory == true else { return Int64(values.totalFileAllocatedSize ?? 0) }
    guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), errorHandler: { _, _ in true }) else { return 0 }
    var total: Int64 = 0
    for case let file as URL in walker {
        total += Int64((try? file.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
    }
    return total
}

func run(_ args: [String]) -> (Int32, Data) {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return (-1, Data()) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, data)
}
