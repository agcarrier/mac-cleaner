import Foundation

// MARK: - Launch agents

public struct LaunchAgent: Sendable, Identifiable, Equatable {
    public enum Scope: Sendable { case user, allUsers, daemon }

    public let label: String
    public let url: URL
    public let program: String?
    public let scope: Scope
    /// False for a plist with no Label (some updaters leave an empty one behind); launchd ignores those.
    public let hasLabel: Bool

    public var id: String { url.path }

    /// Only the user's own agents with a real Label, and never Apple's. Everything else needs System Settings or admin.
    public var isSwitchable: Bool { scope == .user && hasLabel && !label.lowercased().hasPrefix("com.apple.") }
}

/// Plists in `~/Library/LaunchAgents`, `/Library/LaunchAgents` and `/Library/LaunchDaemons`, each sorted by label.
public func launchAgents(home: URL, systemRoot: URL = URL(filePath: "/")) -> [LaunchAgent] {
    let roots: [(URL, LaunchAgent.Scope)] = [(home.appending(path: "Library/LaunchAgents"), .user),
                                             (systemRoot.appending(path: "Library/LaunchAgents"), .allUsers),
                                             (systemRoot.appending(path: "Library/LaunchDaemons"), .daemon)]
    return roots.flatMap { root, scope in
        children(root).filter { $0.pathExtension == "plist" }.compactMap { url -> LaunchAgent? in
            guard let plist = NSDictionary(contentsOf: url) else { return nil }
            let label = plist["Label"] as? String
            return LaunchAgent(label: label ?? url.deletingPathExtension().lastPathComponent, url: url,
                               program: launchProgram(plist), scope: scope, hasLabel: label != nil)
        }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}

/// Labels switched off in the `disabled services` block of `launchctl print-disabled`.
/// Older macOS prints `=> disabled`, newer `=> true`. A label that isn't listed is on.
public func parseDisabled(_ output: String) -> Set<String> {
    var inBlock = false
    var out: Set<String> = []
    for line in output.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
        if line.hasSuffix("= {") { inBlock = line.hasPrefix("disabled services"); continue }
        if line == "}" { inBlock = false; continue }
        guard inBlock, line.hasPrefix("\""), let arrow = line.range(of: "\" => ") else { continue }
        let value = line[arrow.upperBound...]
        if value == "disabled" || value == "true" { out.insert(String(line[line.index(after: line.startIndex)..<arrow.lowerBound])) }
    }
    return out
}

/// `launchctl list` (PID, Status, Label): label → running. Loaded but idle agents map to false.
public func parseLoaded(_ output: String) -> [String: Bool] {
    var out: [String: Bool] = [:]
    for line in output.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard cols.count >= 3 else { continue }
        out[String(cols[2])] = Int(cols[0]) != nil
    }
    return out
}

/// Off: disable (persistent, kept by launchd, the plist isn't touched) then bootout (stop it now).
/// On: enable then bootstrap from the same plist. The second command is best effort: it fails when already stopped or loaded.
public func toggleCommands(label: String, plist: URL, uid: uid_t, enable: Bool) -> [[String]] {
    enable ? [["launchctl", "enable", "gui/\(uid)/\(label)"], ["launchctl", "bootstrap", "gui/\(uid)", plist.path]]
           : [["launchctl", "disable", "gui/\(uid)/\(label)"], ["launchctl", "bootout", "gui/\(uid)/\(label)"]]
}

public func setAgent(_ agent: LaunchAgent, enabled: Bool, uid: uid_t = getuid()) throws {
    guard agent.isSwitchable else { throw CocoaError(.featureUnsupported) }
    let commands = toggleCommands(label: agent.label, plist: agent.url, uid: uid, enable: enabled)
    try perform(.run(commands[0]))
    _ = run(commands[1])
}

public func liveLaunchState(uid: uid_t = getuid()) -> (disabled: Set<String>, loaded: [String: Bool]) {
    (parseDisabled(String(decoding: run(["launchctl", "print-disabled", "gui/\(uid)"]).1, as: UTF8.self)),
     parseLoaded(String(decoding: run(["launchctl", "list"]).1, as: UTF8.self)))
}

// MARK: - Background Task Management (System Settings → Login Items)

public struct BackgroundItem: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable { case opensAtLogin, loginItem, agent }

    public let name: String
    public let kind: Kind
    /// The identifier without its numeric type prefix, e.g. `com.openai.chat-helper`.
    public let label: String
    /// The app itself, or the app a helper lives in, when known. For the icon.
    public let appPath: String?
    public let parentName: String?
    /// The user's switch in System Settings → Login Items.
    public let allowed: Bool

    public var id: String { "\(kind)|\(label)" }
}

/// Records from `sfltool dumpbtm` for one user: Key → value per item.
func btmRecords(_ output: String, uid: uid_t) -> [[String: String]] {
    var inUser = false
    var records: [[String: String]] = []
    for raw in output.split(separator: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("Records for UID ") {
            inUser = line.dropFirst("Records for UID ".count).split(separator: " ").first == Substring(String(uid))
            continue
        }
        guard inUser else { continue }
        if line.hasPrefix("#"), line.hasSuffix(":"), Int(line.dropFirst().dropLast()) != nil { records.append([:]); continue }
        guard !records.isEmpty, let colon = line.range(of: ": ") else { continue }
        records[records.count - 1][String(line[..<colon.lowerBound])] = String(line[colon.upperBound...])
    }
    return records
}

private func btmType(_ r: [String: String]) -> String { r["Type"].map { String($0.prefix { $0 != "(" }).trimmingCharacters(in: .whitespaces) } ?? "" }

private func btmDisposition(_ r: [String: String]) -> Set<String> {
    let inside = (r["Disposition"] ?? "").drop { $0 != "[" }.dropFirst().prefix { $0 != "]" }
    return Set(inside.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
}

private func btmLabel(_ r: [String: String]) -> String {
    let id = r["Identifier"] ?? ""
    return id.split(separator: ".", maxSplits: 1).last.map(String.init) ?? id
}

/// Apps that open at login, and apps' own login items and agents, as System Settings → Login Items shows them.
/// Only registered (`enabled`) items. Legacy agents are left out: they're read from their plists instead.
public func parseBTM(_ output: String, uid: uid_t) -> [BackgroundItem] {
    let records = btmRecords(output, uid: uid)
    let byID = Dictionary(records.compactMap { r in r["Identifier"].map { ($0, r) } }, uniquingKeysWith: { a, _ in a })
    return records.compactMap { r -> BackgroundItem? in
        let kind: BackgroundItem.Kind
        switch btmType(r) {
        case "app": kind = .opensAtLogin
        case "login item": kind = .loginItem
        case "agent": kind = .agent
        default: return nil
        }
        let disposition = btmDisposition(r)
        guard disposition.contains("enabled"), let name = r["Name"] else { return nil }
        let parent = r["Parent Identifier"].flatMap { byID[$0] }
        let path = [r["URL"], parent?["URL"]].compactMap { $0 }.first { $0.hasPrefix("/") }
        return BackgroundItem(name: name, kind: kind, label: btmLabel(r), appPath: path,
                              parentName: parent?["Name"], allowed: disposition.contains("allowed"))
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

/// Labels of the user's legacy launch agents that are switched off in System Settings.
public func legacyDisallowed(_ output: String, uid: uid_t) -> Set<String> {
    Set(btmRecords(output, uid: uid).filter { btmType($0).hasPrefix("legacy") && btmDisposition($0).contains("disallowed") }.map(btmLabel))
}

/// Takes a few seconds. Empty when `sfltool` is missing or refuses.
public func liveBackgroundItems(uid: uid_t = getuid()) -> (items: [BackgroundItem], legacyDisallowed: Set<String>) {
    let output = String(decoding: run(["sfltool", "dumpbtm"]).1, as: UTF8.self)
    return (parseBTM(output, uid: uid), legacyDisallowed(output, uid: uid))
}

// MARK: - Maintenance

public enum Maintenance: String, CaseIterable, Sendable, Identifiable {
    case dns, spotlight, launchServices, quickLook

    public var id: Self { self }

    public var title: String {
        switch self {
        case .dns: "Flush DNS cache"
        case .spotlight: "Rebuild Spotlight index"
        case .launchServices: "Rebuild the \u{201C}Open With\u{201D} menu"
        case .quickLook: "Reset Quick Look thumbnails"
        }
    }

    public var detail: String {
        switch self {
        case .dns: "Helps when a website moved or won\u{2019}t load but works on other devices."
        case .spotlight: "Helps when search misses files. Search is incomplete until macOS finishes, which can take an hour or more."
        case .launchServices: "Helps when \u{201C}Open With\u{201D} shows duplicate or deleted apps."
        case .quickLook: "Helps when Finder shows old or blank previews. They\u{2019}re redrawn as you browse."
        }
    }

    public var needsAdmin: Bool { self == .dns || self == .spotlight }

    public var command: [String] {
        switch self {
        case .dns: adminWrapped("dscacheutil -flushcache; killall -HUP mDNSResponder")
        case .spotlight: adminWrapped("mdutil -E /")
        case .launchServices: ["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                               "-gc", "-r", "-f", "-apps", "local,system,user"]
        case .quickLook: ["qlmanage", "-r", "cache"]
        }
    }
}

/// Runs `shell` as root behind macOS's own password dialog. Cancelling the dialog prints `cancelled` instead of failing.
public func adminWrapped(_ shell: String) -> [String] {
    let quoted = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let lines = ["try",
                 "do shell script \"\(quoted)\" with prompt \"Spruce needs an administrator password for this maintenance task.\" with administrator privileges",
                 "on error number -128",
                 "return \"cancelled\"",
                 "end try"]
    return ["osascript"] + lines.flatMap { ["-e", $0] }
}

public enum MaintenanceResult: Sendable { case done, cancelled }

public func runMaintenance(_ task: Maintenance) throws -> MaintenanceResult {
    let (status, data) = run(task.command)
    guard status == 0 else {
        throw CocoaError(.executableLoad, userInfo: [NSLocalizedDescriptionKey: "\(task.title) didn\u{2019}t finish (exit \(status))."])
    }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "cancelled" ? .cancelled : .done
}
