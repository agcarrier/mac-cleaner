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
