import AppKit
import MacCleanerCore

let usage = """
usage: mac-cleaner [--clean] [--yes] [--include-low] [--only=orphans,caches,agents,xcode] [--filter=text,…]
       mac-cleaner uninstall <app name | bundle ID | path.app> [--clean] [--yes] [--include-low]

Dry run by default: lists what it would move to the Trash and touches nothing.
  uninstall      the app plus everything in ~/Library that belongs to it
  --clean        move the ✓ items to the Trash (unavailable simulators are deleted with simctl)
  --yes          skip the confirmation prompt
  --include-low  also act on ○ low-confidence items
  --only=…       limit the scan to some categories
  --filter=…     only items whose name contains one of these (case-insensitive), e.g. --filter=spotify

"""

func fail(_ message: String, _ code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
let uninstalling = args.first == "uninstall"
if uninstalling { args.removeFirst() }

var clean = false, yes = false, includeLow = false
var categories = Set(Category.scannable)
var filters: [String] = []
var query: [String] = []
for arg in args {
    switch arg {
    case "--clean": clean = true
    case "--yes", "-y": yes = true
    case "--include-low": includeLow = true
    case "-h", "--help": print(usage, terminator: ""); exit(0)
    case _ where arg.hasPrefix("--only="):
        let names = arg.dropFirst("--only=".count).split(separator: ",").map(String.init)
        let parsed = names.compactMap(Category.init(rawValue:)).filter(Category.scannable.contains)
        guard !parsed.isEmpty, parsed.count == names.count else { fallthrough }
        categories = Set(parsed)
    case _ where arg.hasPrefix("--filter="):
        filters = arg.dropFirst("--filter=".count).split(separator: ",").map { $0.lowercased() }
        guard !filters.isEmpty else { fallthrough }
    case _ where uninstalling && !arg.hasPrefix("-"):
        query.append(arg)
    default:
        fail("unknown option: \(arg)\n\n\(usage)")
    }
}

let home = FileManager.default.homeDirectoryForCurrentUser
let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })

var sections: [(title: String, findings: [Finding])] = []
if uninstalling {
    guard !query.isEmpty else { fail("Which app? e.g. mac-cleaner uninstall Spotify\n\n\(usage)") }
    let name = query.joined(separator: " ")
    let (matches, exact) = findApps(matching: name, home: home)
    func list(_ apps: [AppInfo]) -> String { apps.map { "  \($0.name)  (\($0.bundleID))  \($0.url.path)" }.joined(separator: "\n") }
    guard let app = matches.first else { fail("No installed app matches “\(name)”.", 1) }
    guard exact else { fail("No app is named “\(name)”. Did you mean:\n\(list(matches))\nRe-run with the full name, the bundle ID, or the .app path.", 1) }
    guard matches.count == 1 else { fail("Several apps match “\(name)”:\n\(list(matches))\nUse the bundle ID or the .app path.") }
    if app.isApple { fail("\(app.name) is part of macOS. mac-cleaner won't uninstall Apple apps.", 1) }
    if running.contains(app.bundleID.lowercased()) { fail("\(app.name) is running. Quit it first.", 1) }
    let context = Context(home: home, installed: [], running: running)
    sections = [("Uninstall \(app.name)  (\(app.bundleID))", uninstallFindings(for: app, context))]
} else {
    let context = Context(home: home, installed: installedBundleIDs(home: home).union(running), running: running)
    print("Scanning…")
    let all = scan(categories, context)
    sections = Category.scannable.filter(categories.contains).map { category in (category.title, all.filter { $0.category == category }) }
}
sections = sections.map { section in
    (section.title, section.findings.filter { [filters] f in filters.isEmpty || filters.contains { f.title.lowercased().contains($0) } })
}

func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
let isSelected = { [includeLow] (f: Finding) in f.confidence == .high || includeLow }

for section in sections {
    let group = section.findings.sorted { $0.size > $1.size }
    print("\n\(section.title)  (\(group.count) items, \(bytes(group.reduce(0) { $0 + $1.size })))")
    if group.isEmpty { print("  nothing found") }
    for f in group {
        let size = bytes(f.size)
        print("  \(isSelected(f) ? "✓" : "○") \(String(repeating: " ", count: max(0, 10 - size.count)))\(size)  \(f.title)  ·  \(f.detail)")
    }
}

if (uninstalling || !categories.isDisjoint(with: [.orphans, .caches])), !canReadContainers(home: home) {
    print("\n! Sandboxed apps were skipped: macOS blocked access to ~/Library/Containers.")
    print("  Give your terminal Full Disk Access (System Settings → Privacy & Security) to include them.")
}

let selected = sections.flatMap(\.findings).filter(isSelected)
let selectedSize = selected.reduce(0) { $0 + $1.size }
print("\n✓ selected   ○ low confidence, skipped unless --include-low")

guard clean else {
    print("Dry run: \(selected.count) items (\(bytes(selectedSize))) would go to the Trash. Re-run with --clean to do it.")
    exit(0)
}
guard !selected.isEmpty else { print("Nothing to clean."); exit(0) }
if !yes {
    print("Move \(selected.count) items (\(bytes(selectedSize))) to the Trash? [y/N] ", terminator: "")
    guard readLine()?.lowercased() == "y" else { print("Cancelled."); exit(0) }
}

var moved: Int64 = 0, failed = 0
for f in selected {
    do { try perform(f.action); moved += f.size } catch {
        failed += 1
        print("  ✗ \(f.title): \(error.localizedDescription)")
        if f.detail == "the app" { print("    Drag it to the Trash in Finder instead; it may ask for your password.") }
    }
}
print("Done: \(bytes(moved)) cleared\(failed > 0 ? ", \(failed) failed" : ""). Empty the Trash to get the space back.")
let removedAgent = selected.contains { f in
    if case .trash(let urls) = f.action { urls.contains { $0.path.contains("/LaunchAgents/") } } else { false }
}
if removedAgent { print("Removed launch agents stop running at your next login.") }
