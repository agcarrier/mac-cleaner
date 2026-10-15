import AppKit
import MacCleanerCore

let usage = """
usage: mac-cleaner [--clean] [--yes] [--include-low] [--only=orphans,caches,agents,xcode]

Dry run by default: lists what it would move to the Trash and touches nothing.
  --clean        move the ✓ items to the Trash (unavailable simulators are deleted with simctl)
  --yes          skip the confirmation prompt
  --include-low  also act on ○ low-confidence items
  --only=…       limit the scan to some categories

"""

var clean = false, yes = false, includeLow = false
var categories = Set(Category.allCases)
for arg in CommandLine.arguments.dropFirst() {
    switch arg {
    case "--clean": clean = true
    case "--yes", "-y": yes = true
    case "--include-low": includeLow = true
    case "-h", "--help": print(usage, terminator: ""); exit(0)
    case _ where arg.hasPrefix("--only="):
        let names = arg.dropFirst("--only=".count).split(separator: ",").map(String.init)
        let parsed = names.compactMap(Category.init(rawValue:))
        guard !parsed.isEmpty, parsed.count == names.count else { fallthrough }
        categories = Set(parsed)
    default:
        FileHandle.standardError.write(Data("unknown option: \(arg)\n\n\(usage)".utf8))
        exit(2)
    }
}

let home = FileManager.default.homeDirectoryForCurrentUser
let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
let context = Context(home: home, installed: installedBundleIDs(home: home).union(running), running: running)
print("Scanning…")
let findings = scan(categories, context)

func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
let isSelected = { [includeLow] (f: Finding) in f.confidence == .high || includeLow }

for category in Category.allCases where categories.contains(category) {
    let group = findings.filter { $0.category == category }.sorted { $0.size > $1.size }
    print("\n\(category.title)  (\(group.count) items, \(bytes(group.reduce(0) { $0 + $1.size })))")
    if group.isEmpty { print("  nothing found") }
    for f in group {
        let size = bytes(f.size)
        print("  \(isSelected(f) ? "✓" : "○") \(String(repeating: " ", count: max(0, 10 - size.count)))\(size)  \(f.title)  ·  \(f.detail)")
    }
}

if !categories.isDisjoint(with: [.orphans, .caches]), !canReadContainers(home: home) {
    print("\n! Sandboxed apps were skipped: macOS blocked access to ~/Library/Containers.")
    print("  Give your terminal Full Disk Access (System Settings → Privacy & Security) to include them.")
}

let selected = findings.filter(isSelected)
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
    do { try perform(f.action); moved += f.size } catch { failed += 1; print("  ✗ \(f.title): \(error.localizedDescription)") }
}
print("Done: \(bytes(moved)) cleared\(failed > 0 ? ", \(failed) failed" : ""). Empty the Trash to get the space back.")
if selected.contains(where: { $0.category == .agents }) { print("Removed launch agents stop running at your next login.") }
