import Foundation

// MARK: - Versions

private func numbers(_ version: String) -> [Int] {
    version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
}

/// True only when `candidate` is strictly newer, comparing numeric parts (`1.14.4` > `1.8.10`, `2.0` == `2.0.0`).
/// Anything without numbers on either side is never newer, so bad data can't claim an update.
public func isNewer(_ candidate: String, than installed: String) -> Bool {
    let a = numbers(candidate), b = numbers(installed)
    guard !a.isEmpty, !b.isEmpty else { return false }
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return false
}

// MARK: - Sparkle

public struct AppcastItem: Sendable, Equatable {
    /// `sparkle:version`, compared with the app's CFBundleVersion.
    public let version: String
    /// What to show, e.g. "1.1".
    public let shortVersion: String
    public let releaseNotes: URL?
}

private final class AppcastParser: NSObject, XMLParserDelegate {
    struct Raw { var version, short, minOS, channel, notes, link: String? }
    var items: [Raw] = []
    private var current: Raw?
    private var text = ""
    private var inDeltas = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "item": current = Raw()
        case "sparkle:deltas": inDeltas = true
        case "enclosure" where !inDeltas:
            // Older feeds put the versions on the enclosure instead of their own elements.
            if current?.version == nil { current?.version = attributes["sparkle:version"] }
            if current?.short == nil { current?.short = attributes["sparkle:shortVersionString"] }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "item": if let item = current { items.append(item) }; current = nil
        case "sparkle:deltas": inDeltas = false
        case "sparkle:version": current?.version = value
        case "sparkle:shortVersionString": current?.short = value
        case "sparkle:minimumSystemVersion": current?.minOS = value
        case "sparkle:channel": current?.channel = value
        case "sparkle:releaseNotesLink": current?.notes = value
        case "link": current?.link = value
        default: break
        }
    }
}

/// The newest release this Mac can install: no channel (betas), and a minimum macOS this Mac meets.
public func parseAppcast(_ data: Data, os: OperatingSystemVersion) -> AppcastItem? {
    let delegate = AppcastParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    guard parser.parse() else { return nil }
    let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    let eligible = delegate.items.compactMap { raw -> AppcastItem? in
        guard raw.channel == nil, let version = raw.version ?? raw.short, !version.isEmpty else { return nil }
        if let min = raw.minOS, isNewer(min, than: osVersion) { return nil }
        return AppcastItem(version: version, shortVersion: raw.short ?? version,
                           releaseNotes: (raw.notes ?? raw.link).flatMap(URL.init(string:)))
    }
    return eligible.reduce(nil) { best, item in best.map { isNewer(item.version, than: $0.version) ? item : $0 } ?? item }
}

// MARK: - App Store

/// The version and store page from `itunes.apple.com/lookup`. Nil when the store has no result (Apple's own apps).
public func parseAppStoreLookup(_ data: Data) -> (version: String, url: URL?)? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let first = (json["results"] as? [[String: Any]])?.first, let version = first["version"] as? String else { return nil }
    return (version, (first["trackViewUrl"] as? String).flatMap(URL.init(string:)))
}

// MARK: - Homebrew

public struct Cask: Sendable {
    public let token: String
    /// Without the build after a comma.
    public let version: String
    public let homepage: URL?
}

public let caskAPI = URL(string: "https://formulae.brew.sh/api/cask.json")!

/// Casks by the app file name they install. Leaves out names more than one product installs, `@` variants (betas, LTS),
/// deprecated or disabled casks, and `latest` versions.
public func caskIndex(_ data: Data) -> [String: Cask] {
    guard let all = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
    var counts: [String: Int] = [:]
    var candidates: [String: Cask] = [:]
    for cask in all {
        guard let token = cask["token"] as? String, !token.contains("@") else { continue }
        var names: [String] = []
        for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
            for entry in artifact["app"] as? [Any] ?? [] {
                if let name = entry as? String { names.append(name) }
                // ["Source.app", {"target": "Installed.app"}]: the app lands under its target name.
                else if let target = (entry as? [String: Any])?["target"] as? String, !names.isEmpty { names[names.count - 1] = target }
            }
        }
        names.forEach { counts[$0, default: 0] += 1 }
        let version = (cask["version"] as? String ?? "").split(separator: ",").first.map(String.init) ?? ""
        guard version != "latest", !version.isEmpty, cask["deprecated"] as? Bool != true, cask["disabled"] as? Bool != true else { continue }
        for name in names {
            candidates[name] = Cask(token: token, version: version, homepage: (cask["homepage"] as? String).flatMap(URL.init(string:)))
        }
    }
    return candidates.filter { counts[$0.key] == 1 }
}

// MARK: - Checking

public enum UpdateSource: Sendable, Equatable { case appStore, sparkle, homebrew }

public struct AvailableUpdate: Sendable, Identifiable {
    public let app: AppInfo
    public let installed: String
    public let latest: String
    public let source: UpdateSource
    /// The App Store page, the release notes, or the app's website.
    public let link: URL?
    public var id: String { app.url.path }
}

public struct UpdateReport: Sendable {
    public let available: [AvailableUpdate]
    public let upToDate: Int
    /// No source, or the source didn't answer usefully.
    public let unchecked: [AppInfo]
}

public typealias Fetcher = @Sendable (URL) async throws -> Data

public let liveFetch: Fetcher = { url in
    let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
    if let status = (response as? HTTPURLResponse)?.statusCode, status >= 400 { throw URLError(.badServerResponse) }
    return data
}

private enum Outcome: Sendable { case update(AvailableUpdate), current, unknown(AppInfo) }

private func info(_ app: AppInfo) -> NSDictionary? { NSDictionary(contentsOf: app.url.appending(path: "Contents/Info.plist")) }
private func isFromAppStore(_ app: AppInfo) -> Bool { FileManager.default.fileExists(atPath: app.url.appending(path: "Contents/_MASReceipt/receipt").path) }
private func feed(_ app: AppInfo) -> URL? { (info(app)?["SUFeedURL"] as? String).flatMap(URL.init(string:)) }

/// Checks each app against its source: the App Store when it came from there, else its Sparkle feed, else Homebrew by file name.
/// Eight requests at a time; `progress` gets the number of apps done.
public func checkUpdates(_ apps: [AppInfo], os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
                         region: String = Locale.current.region?.identifier.lowercased() ?? "us",
                         fetch: @escaping Fetcher = liveFetch, progress: @escaping @Sendable (Int) -> Void = { _ in }) async -> UpdateReport {
    let needsCasks = apps.contains { !isFromAppStore($0) && feed($0) == nil }
    let casks = needsCasks ? ((try? await fetch(caskAPI)).map(caskIndex) ?? [:]) : [:]

    var outcomes: [Outcome] = []
    await withTaskGroup(of: Outcome.self) { group in
        var next = 0
        func addNext() {
            guard next < apps.count else { return }
            let app = apps[next]
            next += 1
            group.addTask { await check(app, casks: casks, os: os, region: region, fetch: fetch) }
        }
        for _ in 0..<8 { addNext() }
        for await outcome in group {
            outcomes.append(outcome)
            progress(outcomes.count)
            addNext()
        }
    }
    var available: [AvailableUpdate] = [], unchecked: [AppInfo] = [], current = 0
    for outcome in outcomes {
        switch outcome {
        case .update(let update): available.append(update)
        case .current: current += 1
        case .unknown(let app): unchecked.append(app)
        }
    }
    return UpdateReport(available: available.sorted { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending },
                        upToDate: current,
                        unchecked: unchecked.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
}

private func check(_ app: AppInfo, casks: [String: Cask], os: OperatingSystemVersion, region: String, fetch: Fetcher) async -> Outcome {
    let plist = info(app)
    let short = plist?["CFBundleShortVersionString"] as? String ?? ""
    let build = plist?["CFBundleVersion"] as? String ?? short
    func result(_ newer: Bool, _ latest: String, _ source: UpdateSource, _ link: URL?) -> Outcome {
        newer && latest != short ? .update(AvailableUpdate(app: app, installed: short, latest: latest, source: source, link: link)) : .current
    }
    if isFromAppStore(app) {
        var lookup = URLComponents(string: "https://itunes.apple.com/lookup")!
        lookup.queryItems = [URLQueryItem(name: "bundleId", value: app.bundleID), URLQueryItem(name: "country", value: region)]
        guard let data = try? await fetch(lookup.url!), let found = parseAppStoreLookup(data) else { return .unknown(app) }
        return result(isNewer(found.version, than: short), found.version, .appStore, found.url)
    }
    if let feed = feed(app) {
        guard let data = try? await fetch(feed), let item = parseAppcast(data, os: os) else { return .unknown(app) }
        return result(isNewer(item.version, than: build), item.shortVersion, .sparkle, item.releaseNotes)
    }
    if let cask = casks[app.url.lastPathComponent] {
        return result(isNewer(cask.version, than: short), cask.version, .homebrew, cask.homepage)
    }
    return .unknown(app)
}
