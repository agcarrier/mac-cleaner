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
