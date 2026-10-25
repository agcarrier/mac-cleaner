import Foundation
import Testing
@testable import MacCleanerCore

private let home = URL(filePath: "/Users/someone")

/// The last line of defense: whatever rule asked, these are never moved to the Trash.
@Test func protectedPathsAreRefused() {
    let refused = [
        "/Users/someone",                                          // the home folder itself
        "/Users/someone/Documents",                                // any folder directly in home
        "/Users/someone/.ssh",
        "/Users/someone/Library",
        "/Users/someone/Library/Application Support",              // the standard Library folders themselves
        "/Users/someone/Library/Caches",
        "/Users/someone/Library/Keychains/login.keychain-db",      // secrets
        "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs/report.pdf",  // iCloud Drive
        "/Users/someone/Library/CloudStorage/Dropbox/a.txt",
        "/Users/someone/Library/Mail/V10/x",
        "/Users/someone/Library/Messages/chat.db",
        "/Users/someone/Library/Containers/com.apple.Notes",       // Apple's own data
        "/Users/someone/Library/Preferences/com.apple.dock.plist",
        "/Users/Shared/Documents/notes.txt",                        // only apps are uninstalled from /Users/Shared
        "/Users/someone/Pictures/Photos Library.photoslibrary",
        "/Users/someone/Pictures/Photos Library.photoslibrary/originals/a.heic",
        "/System/Library/CoreServices/Finder.app",                 // outside home
        "/Library/LaunchDaemons/com.docker.vmnetd.plist",
        "/usr/local/bin/brew",
        "/Applications",
        "/Applications/Utilities",
        "/Volumes/Backup",                                         // a whole disk
        "/",
    ]
    for path in refused {
        #expect(protectedReason(URL(filePath: path), home: home) != nil, "\(path) should be protected")
    }

    let allowed = [
        "/Users/someone/Library/Caches/com.foo.app",
        "/Users/someone/Library/Caches/com.apple.dt.Xcode/SomeCache",   // Xcode junk is the one Apple cache we clean
        "/Users/someone/Library/Containers/com.foo.app",
        "/Users/someone/Library/Developer/Xcode/DerivedData/Proj-abc",
        "/Users/someone/.npm/_cacache",
        "/Users/someone/Downloads/Installer.dmg",
        "/Users/someone/Documents/copy of photo.jpg",
        "/Users/someone/Applications/Thing.app",
        "/Applications/Thing.app",                                  // uninstall
        "/Applications/Vendor/Thing.app",
        "/Volumes/Backup/photos/a.jpg",                             // files on an external disk
        // Seen live: a sandboxed app's own web caches carry Apple's names, but they're that app's caches.
        "/Users/someone/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches/com.apple.WebKit.Networking",
        "/Users/Shared/Battle.net/Agent/Agent.app",                 // seen live: Blizzard installs apps here
    ]
    for path in allowed {
        #expect(protectedReason(URL(filePath: path), home: home) == nil, "\(path) should be allowed")
    }
}

/// The guard sits inside the Trash step itself, so nothing reaches the Trash around it.
@Test func trashRefusesProtectedPaths() throws {
    let fake = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-guard-\(UUID())")
    defer { try? FileManager.default.removeItem(at: fake) }
    let documents = fake.appending(path: "Documents")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    var called = false
    #expect(throws: (any Error).self) { try trash(documents, home: fake, trashItem: { _ in called = true }) }
    #expect(!called)
    #expect(FileManager.default.fileExists(atPath: documents.path))
}

/// Leftover user data from an app Spruce can't see (on an external disk, say) must never start checked.
@Test func orphanedUserDataStartsUnchecked() throws {
    let fake = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-orphan-data-\(UUID())")
    defer { try? FileManager.default.removeItem(at: fake) }
    let lib = fake.appending(path: "Library")
    func touch(_ path: String, _ data: Data = Data("x".utf8)) throws {
        let url = lib.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    let metadata = try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": "net.gone.app"], format: .xml, options: 0)
    try touch("Containers/net.gone.app/.com.apple.containermanagerd.metadata.plist", metadata)
    try touch("Containers/net.gone.app/Data/Documents/novel.txt")
    try touch("Application Support/net.gone.app/library.db")
    try touch("Caches/net.gone.app/blob")
    try touch("Saved Application State/net.gone.app.savedState/data")

    let found = scanOrphans(Context(home: fake, installed: [], running: []))
    let byDir = Dictionary(found.map { (String($0.detail.prefix { $0 != "," }), $0.confidence) }, uniquingKeysWith: { a, _ in a })
    #expect(byDir["Containers"] == .low)
    #expect(byDir["Application Support"] == .low)
    #expect(byDir["Caches"] == .high)
    #expect(byDir["Saved Application State"] == .high)
}

/// An app with a two-part ID like com.google would otherwise claim every com.google.* folder, Chrome's included.
@Test func shortBundleIDsOwnOnlyThemselves() throws {
    let fake = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-short-id-\(UUID())")
    defer { try? FileManager.default.removeItem(at: fake) }
    let contents = fake.appending(path: "Short.app/Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.google"], format: .xml, options: 0)
        .write(to: contents.appending(path: "Info.plist"))
    let short = try #require(AppInfo(url: fake.appending(path: "Short.app")))
    #expect(short.owns("com.google"))
    #expect(!short.owns("com.google.Chrome"))

    let normal = try #require(AppInfo(url: try {
        let c = fake.appending(path: "Normal.app/Contents")
        try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.foo.app"], format: .xml, options: 0)
            .write(to: c.appending(path: "Info.plist"))
        return fake.appending(path: "Normal.app")
    }()))
    #expect(normal.owns("com.foo.app.helper"))
}

/// An agent whose program lives on a disk that isn't plugged in isn't broken.
@Test func agentsOnUnpluggedDisksAreNotBroken() throws {
    let fake = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-agents-\(UUID())")
    defer { try? FileManager.default.removeItem(at: fake) }
    let agents = fake.appending(path: "Library/LaunchAgents")
    try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    func agent(_ label: String, _ program: String) throws {
        try PropertyListSerialization.data(fromPropertyList: ["Label": label, "Program": program], format: .xml, options: 0)
            .write(to: agents.appending(path: "\(label).plist"))
    }
    try agent("com.ext.agent", "/Volumes/NotPluggedIn/tool")
    try agent("com.gone.agent", "/opt/gone/tool")
    let found = scanLaunchAgents(Context(home: fake, installed: [], running: []))
    #expect(found.map(\.title) == ["com.gone.agent"])
}

/// My Clutter only looks inside the home folder or on external disks.
@Test func clutterFoldersAreLimited() {
    #expect(isAllowedClutterFolder(URL(filePath: "/Users/someone/Pictures"), home: home))
    #expect(isAllowedClutterFolder(URL(filePath: "/Users/someone"), home: home))
    #expect(isAllowedClutterFolder(URL(filePath: "/Volumes/Backup/Photos"), home: home))
    #expect(!isAllowedClutterFolder(URL(filePath: "/"), home: home))
    #expect(!isAllowedClutterFolder(URL(filePath: "/usr/local"), home: home))
    #expect(!isAllowedClutterFolder(URL(filePath: "/Applications"), home: home))
    #expect(!isAllowedClutterFolder(URL(filePath: "/Users/other/Documents"), home: home))
}

/// Links from update feeds open only if they're web pages or App Store pages.
@Test func onlySafeLinksOpen() {
    #expect(webLink("https://example.com/notes") != nil)
    #expect(webLink("https://apps.apple.com/us/app/x/id1") != nil)
    #expect(webLink("http://example.com") == nil)          // unencrypted: could be tampered with on the way
    #expect(webLink("file:///etc/passwd") == nil)
    #expect(webLink("x-apple.systempreferences:com.apple.preference.security") == nil)
    #expect(webLink("smb://evil.example/share") == nil)
    #expect(webLink("javascript:alert(1)") == nil)
    #expect(webLink(nil) == nil)
}

/// Every command runs by its full path, never looked up by name.
@Test func commandsUseFullPaths() {
    for task in Maintenance.allCases { #expect(task.command.first?.hasPrefix("/") == true, "\(task)") }
    #expect(toggleCommands(label: "a.b.c", plist: URL(filePath: "/x.plist"), uid: 501, enable: true).allSatisfy { $0.first?.hasPrefix("/") == true })
    #expect(adminWrapped("x").first == "/usr/bin/osascript")
    for shell in [Maintenance.dns, .spotlight] {
        let script = shell.command.joined(separator: " ")
        #expect(!script.contains("\"dscacheutil") && !script.contains("; killall") && !script.contains("\"mdutil"))
    }
}
