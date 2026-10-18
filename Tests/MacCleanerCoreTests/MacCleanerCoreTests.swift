import Foundation
import Testing
@testable import MacCleanerCore

@Test func bundleIDShape() {
    #expect(looksLikeBundleID("com.foo.app"))
    #expect(looksLikeBundleID("org.mozilla.firefox-beta"))
    #expect(!looksLikeBundleID("Google"))
    #expect(!looksLikeBundleID("com.foo"))
    #expect(!looksLikeBundleID("com..foo"))
}

@Test func ownershipRules() {
    let apps: Set = ["com.foo.app", "org.bar.editor"]
    #expect(ownership(of: "com.apple.finder", by: apps) == .system)
    #expect(ownership(of: "com.foo.app", by: apps) == .installed)
    #expect(ownership(of: "COM.FOO.APP", by: apps) == .installed)
    #expect(ownership(of: "com.foo.app.helper", by: apps) == .installed)
    #expect(ownership(of: "com.foo.updater", by: apps) == .sameVendor)
    #expect(ownership(of: "net.gone.app", by: apps) == .orphan)
}

/// Uninstall must take the app's own ID and its children, never a look-alike ID, and keep name-only matches unselected.
@Test func uninstallMatching() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-uninstall-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    func touch(_ path: String, _ contents: Data = Data("x".utf8)) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
    }
    func plist(_ dict: [String: Any]) throws -> Data { try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) }

    try touch("Apps/Fake.app/Contents/Info.plist", plist(["CFBundleIdentifier": "com.fake.app", "CFBundleName": "Fake"]))
    try touch("Library/Preferences/com.fake.app.plist")                 // ✓ own ID
    try touch("Library/Preferences/com.fake.app.helper.plist")          // ✓ child ID
    try touch("Library/Preferences/com.fake.apple.plist")               // ✗ look-alike, not ours
    try touch("Library/Caches/com.fake.app/blob")                       // ✓
    try touch("Library/Application Support/Fake/settings")              // ○ name only
    try touch("Library/Logs/DiagnosticReports/Fake-2026-10-15.ips")     // ✓ crash report
    try touch("Library/LaunchAgents/com.fake.updater.plist",            // ✓ program lives inside the app
              plist(["Label": "com.fake.updater", "Program": root.appending(path: "Apps/Fake.app/Contents/MacOS/updater").path]))
    try touch("Library/LaunchAgents/com.other.agent.plist", plist(["Label": "com.other.agent", "Program": "/usr/bin/true"]))  // ✗

    let app = try #require(AppInfo(url: root.appending(path: "Apps/Fake.app")))
    let found = uninstallFindings(for: app, Context(home: root, installed: [], running: []))
    let confidence = Dictionary(found.map { ($0.title, $0.confidence) }, uniquingKeysWith: { a, _ in a })

    #expect(confidence["Fake.app"] == .high)
    #expect(confidence["com.fake.app.plist"] == .high)
    #expect(confidence["com.fake.app.helper.plist"] == .high)
    #expect(confidence["com.fake.app"] == .high)
    #expect(confidence["Fake"] == .low)
    #expect(confidence["Fake-2026-10-15.ips"] == .high)
    #expect(confidence["com.fake.updater.plist"] == .high)
    #expect(confidence["com.fake.apple.plist"] == nil)
    #expect(confidence["com.other.agent.plist"] == nil)
}

/// App groups named after the app are its own; developer-wide groups may be shared.
/// System-wide items are matched by link or by developer, and never by look-alike IDs.
@Test func groupsAndSystemItems() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-system-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    func touch(_ path: String, _ contents: Data = Data("x".utf8)) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
    }
    func plist(_ dict: [String: Any]) throws -> Data { try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) }

    try touch("Apps/Fake.app/Contents/Info.plist", plist(["CFBundleIdentifier": "com.fake.app", "CFBundleName": "Fake"]))
    try touch("Library/Group Containers/TEAM.com.fake.app/data")   // ✓ named after the app
    try touch("Library/Group Containers/TEAM.com.fake/data")       // ○ developer-wide
    try touch("Library/LaunchDaemons/com.fake.helper.plist", plist(["Label": "com.fake.helper"]))           // same developer
    try touch("Library/LaunchDaemons/com.fakeother.plist", plist(["Label": "com.fakeother"]))               // ✗ look-alike
    try touch("Library/LaunchDaemons/net.x.plist", plist(["Label": "net.x", "AssociatedBundleIdentifiers": "com.fake.app"]))  // linked
    try touch("Library/PrivilegedHelperTools/com.fake.app.daemon")                                          // linked

    let app = try #require(AppInfo(url: root.appending(path: "Apps/Fake.app")))
    let found = uninstallFindings(for: app, Context(home: root, installed: [], running: []), groups: ["TEAM.com.fake.app", "TEAM.com.fake", "TEAM.com.fake.missing"])
    let confidence = Dictionary(found.map { ($0.title, $0.confidence) }, uniquingKeysWith: { a, _ in a })
    #expect(confidence["TEAM.com.fake.app"] == .high)
    #expect(confidence["TEAM.com.fake"] == .low)
    #expect(confidence["TEAM.com.fake.missing"] == nil)

    let system = systemItems(for: app, root: root, receipts: ["com.fake.app", "com.fake.pkg", "com.fakeother", "org.other"])
    let why = Dictionary(system.map { (($0.path as NSString).lastPathComponent, $0.why) }, uniquingKeysWith: { a, _ in a })
    #expect(why["com.fake.helper.plist"] == "same developer")
    #expect(why["net.x.plist"] == "linked to the app")
    #expect(why["com.fake.app.daemon"] == "linked to the app")
    #expect(why["installer receipt com.fake.app"] == "linked to the app")
    #expect(why["installer receipt com.fake.pkg"] == "same developer")
    #expect(why["com.fakeother.plist"] == nil)
    #expect(why["installer receipt com.fakeother"] == nil)
    #expect(why["installer receipt org.other"] == nil)
}

/// Space rules: installers ✓ only after 30 days, node_modules listed (○) only after 60 idle days and only at
/// the top level, and Apple's plain-named caches never shown.
@Test func spaceRules() throws {
    let home = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-space-\(UUID())")
    defer { try? FileManager.default.removeItem(at: home) }
    let now = Date()
    func touch(_ path: String, daysAgo: Double = 0) throws {
        let url = home.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        for target in [url, url.deletingLastPathComponent()] {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: target.path)
        }
    }
    try touch("Downloads/Old.dmg", daysAgo: 45)
    try touch("Downloads/New.pkg", daysAgo: 3)
    try touch("Downloads/notes.pdf", daysAgo: 400)                 // not an installer
    try touch("code/idle/node_modules/pkg/index.js", daysAgo: 90)
    try touch("code/idle/package.json", daysAgo: 90)
    try touch("code/busy/node_modules/pkg/index.js", daysAgo: 90)
    try touch("code/busy/package.json", daysAgo: 2)                 // recent work
    try touch("Library/Caches/GeoServices/blob")                     // Apple, hidden
    try touch("Library/Caches/Homebrew/blob")                        // not Apple, shown

    let c = Context(home: home, installed: [], running: [])
    let downloads = Dictionary(scanDownloads(c, now: now).map { ($0.title, $0.confidence) }, uniquingKeysWith: { a, _ in a })
    #expect(downloads == ["Old.dmg": .high, "New.pkg": .low])

    let found = ["code/idle/node_modules", "code/busy/node_modules", "code/idle/node_modules/pkg/node_modules"].map { home.appending(path: $0) }
    let projects = scanNodeModules(c, now: now, found: found)
    #expect(projects.map(\.title) == ["idle"])
    #expect(projects.first?.confidence == .low)

    let caches = scanCaches(c).map(\.title)
    #expect(!caches.contains("GeoServices"))
    #expect(caches.contains("Homebrew"))
}

/// The safety rule: a lone orphaned pref might belong to a CLI tool, so it stays low confidence
/// unless a container or saved window state proves a GUI app owned it.
@Test func orphanConfidence() throws {
    let home = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: home) }
    let lib = home.appending(path: "Library")
    func touch(_ path: String) throws {
        let url = lib.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }
    try touch("Preferences/net.lonely.tool.plist")         // orphan, pref only → low
    try touch("Preferences/net.gone.app.plist")            // orphan, has saved state → high
    try touch("Saved Application State/net.gone.app.savedState/data")
    try touch("Preferences/com.foo.updater.plist")          // same vendor → low
    try touch("Preferences/com.foo.app.plist")              // installed → not listed

    let found = scanOrphans(Context(home: home, installed: ["com.foo.app"], running: []))
    let confidence = Dictionary(found.map { ("\($0.title) \($0.detail.prefix(while: { $0 != "," }))", $0.confidence) }, uniquingKeysWith: { a, _ in a })

    #expect(confidence["net.lonely.tool Preferences"] == .low)
    #expect(confidence["net.gone.app Preferences"] == .high)
    #expect(confidence["net.gone.app Saved Application State"] == .high)
    #expect(confidence["com.foo.updater Preferences"] == .low)
    #expect(!found.contains { $0.title == "com.foo.app" })
}

@Test func thresholdsAreParameters() throws {
    let home = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-thresholds-\(UUID())")
    defer { try? FileManager.default.removeItem(at: home) }
    let now = Date()
    let url = home.appending(path: "Downloads/New.pkg")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3 * 86_400)], ofItemAtPath: url.path)

    let c = Context(home: home, installed: [], running: [], thresholds: Thresholds(installerDays: 2, idleProjectDays: 60))
    #expect(scanDownloads(c, now: now).first { $0.title == "New.pkg" }?.confidence == .high)
    #expect(scanDownloads(Context(home: home, installed: [], running: []), now: now).first?.confidence == .low)
}

@Test func preselectionAndIDs() {
    let trash = Finding(category: .caches, title: "a", detail: "", size: 1, confidence: .high, action: .trash([URL(filePath: "/tmp/a")]))
    let low = Finding(category: .caches, title: "b", detail: "", size: 1, confidence: .low, action: .trash([URL(filePath: "/tmp/b")]))
    let report = Finding(category: .large, title: "c", detail: "d", size: 1, confidence: .high, action: .report)
    #expect(trash.isPreselected && !low.isPreselected && !report.isPreselected)
    #expect(!report.isActionable && trash.isActionable)
    #expect(trash.id == "caches|/tmp/a" && report.id == "large|c|d")
    #expect(Set([trash.id, low.id, report.id]).count == 3)
}

@Test func scanReportsProgressInOrder() {
    let home = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-progress-\(UUID())")
    final class Box: @unchecked Sendable { var seen: [MacCleanerCore.Category] = [] }
    let box = Box()
    _ = scan([.downloads, .devcaches], Context(home: home, installed: [], running: [])) { box.seen.append($0) }
    #expect(box.seen == [.devcaches, .downloads])
}

@Test func installedAppsAreTopLevelAndSorted() {
    let apps = installedApps(home: FileManager.default.homeDirectoryForCurrentUser)
    #expect(!apps.isEmpty)
    #expect(!apps.contains { $0.url.path.contains("/Library/") || $0.url.deletingLastPathComponent().path.contains(".app") })
    // Finder-style order: locale-aware and case-insensitive.
    #expect(zip(apps, apps.dropFirst()).allSatisfy { $0.name.localizedCaseInsensitiveCompare($1.name) != .orderedDescending })
}

/// Review finding 2: actions that can't go to the Trash (simctl deletes) are never preselected, and say so.
@Test func permanentActionsAreNeverPreselected() {
    let sims = Finding(category: .xcode, title: "2 unavailable simulators", detail: "", size: 1, confidence: .high,
                       action: .run(["xcrun", "simctl", "delete", "unavailable"]))
    #expect(sims.isActionable)
    #expect(sims.isPermanent)
    #expect(!sims.isPreselected)
    let trash = Finding(category: .caches, title: "a", detail: "", size: 1, confidence: .high, action: .trash([URL(filePath: "/tmp/a")]))
    #expect(!trash.isPermanent && trash.isPreselected)
}

/// trashItem refuses some files with "no permission" (files another app created carry com.apple.provenance; seen
/// 2026-10-18 on files made in Claude's terminal) even though moving them works. Then they're moved into ~/.Trash directly.
@Test func trashFallsBackToMovingIntoTrash() throws {
    let home = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-trash-\(UUID())")
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appending(path: ".Trash"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: home.appending(path: "Desktop"), withIntermediateDirectories: true)
    let refuse: (URL) throws -> Void = { _ in throw CocoaError(.fileWriteNoPermission) }

    for _ in 0..<2 {
        let file = home.appending(path: "Desktop/b.bin")
        try Data("x".utf8).write(to: file)
        try trash(file, home: home, trashItem: refuse)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
    let inTrash = try FileManager.default.contentsOfDirectory(atPath: home.appending(path: ".Trash").path).sorted()
    #expect(inTrash == ["b 2.bin", "b.bin"])

    // Any other failure is reported, and the file stays where it was.
    let kept = home.appending(path: "Desktop/c.bin")
    try Data("x".utf8).write(to: kept)
    #expect(throws: CocoaError.self) { try trash(kept, home: home, trashItem: { _ in throw CocoaError(.fileReadUnknown) }) }
    #expect(FileManager.default.fileExists(atPath: kept.path))
}
