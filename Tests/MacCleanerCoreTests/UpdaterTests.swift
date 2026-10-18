import Foundation
import Testing
@testable import MacCleanerCore

@Test func versionOrder() {
    #expect(isNewer("1.14.4", than: "1.8.10"))
    #expect(!isNewer("1.8.10", than: "1.14.4"))
    #expect(!isNewer("2.0", than: "2.0.0"))
    #expect(isNewer("2.0.1", than: "2.0"))
    #expect(isNewer("0.2026.10.14.08.27.stable_01", than: "0.2026.09.30.08.29.01"))
    #expect(!isNewer("7.2.2", than: "7.2.2 (88465)"))
    #expect(!isNewer("1.0", than: "1.0"))
    #expect(!isNewer("beta", than: "1.0"))   // nothing to compare: never an update
    #expect(!isNewer("1.0", than: ""))
}

private let appcast = """
<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <title>1.2 beta</title>
      <sparkle:version>120</sparkle:version>
      <sparkle:shortVersionString>1.2</sparkle:shortVersionString>
      <sparkle:channel>beta</sparkle:channel>
      <enclosure url="https://x.test/1.2.dmg" length="1" type="application/octet-stream"/>
    </item>
    <item>
      <title>1.1.5 needs a newer macOS</title>
      <sparkle:version>115</sparkle:version>
      <sparkle:shortVersionString>1.1.5</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>
      <enclosure url="https://x.test/1.1.5.dmg" length="1" type="application/octet-stream"/>
    </item>
    <item>
      <title>1.1</title>
      <sparkle:version>110</sparkle:version>
      <sparkle:shortVersionString>1.1</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://x.test/notes/1.1</sparkle:releaseNotesLink>
      <enclosure url="https://x.test/1.1.dmg" length="1" type="application/octet-stream"/>
      <sparkle:deltas>
        <enclosure url="https://x.test/d.delta" sparkle:deltaFrom="100" sparkle:version="999" length="1"/>
      </sparkle:deltas>
    </item>
    <item>
      <title>1.0.5, old style</title>
      <enclosure url="https://x.test/1.0.5.dmg" sparkle:version="105" sparkle:shortVersionString="1.0.5" length="1"/>
    </item>
  </channel>
</rss>
"""

@Test func appcastPicksNewestEligible() throws {
    let item = try #require(parseAppcast(Data(appcast.utf8), os: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)))
    #expect(item.version == "110")
    #expect(item.shortVersion == "1.1")
    #expect(item.releaseNotes == URL(string: "https://x.test/notes/1.1"))

    // On an older macOS the 14.0 item is out too, and the old-style enclosure attributes count.
    let old = try #require(parseAppcast(Data(appcast.utf8), os: OperatingSystemVersion(majorVersion: 13, minorVersion: 6, patchVersion: 0)))
    #expect(old.version == "105" && old.shortVersion == "1.0.5")

    #expect(parseAppcast(Data("not xml".utf8), os: ProcessInfo.processInfo.operatingSystemVersion) == nil)
}

@Test func parsesAppStoreLookup() throws {
    let json = #"{"resultCount":1,"results":[{"kind":"mac-software","version":"1.4.0","trackViewUrl":"https://apps.apple.com/us/app/x/id1?uo=4"}]}"#
    let found = try #require(parseAppStoreLookup(Data(json.utf8)))
    #expect(found.version == "1.4.0")
    #expect(found.url == URL(string: "https://apps.apple.com/us/app/x/id1?uo=4"))
    #expect(parseAppStoreLookup(Data(#"{"resultCount":0,"results":[]}"#.utf8)) == nil)
}

private let casks = """
[
  {"token": "foo", "version": "1.2.3,abc123", "homepage": "https://foo.test", "artifacts": [{"app": ["Foo.app"]}, {"zap": {"trash": []}}]},
  {"token": "foo@beta", "version": "1.3.0", "homepage": "https://foo.test", "artifacts": [{"app": ["Foo.app"]}]},
  {"token": "bar-one", "version": "0.5", "homepage": "https://a.test", "artifacts": [{"app": ["Bar.app"]}]},
  {"token": "bar-two", "version": "1.4", "homepage": "https://b.test", "artifacts": [{"app": ["Bar.app"]}]},
  {"token": "baz", "version": "latest", "homepage": "https://baz.test", "artifacts": [{"app": ["Baz.app"]}]},
  {"token": "qux", "version": "2.0", "deprecated": true, "homepage": "https://qux.test", "artifacts": [{"app": ["Qux.app"]}]},
  {"token": "renamed", "version": "3.1", "homepage": "https://r.test", "artifacts": [{"app": ["Source Name.app", {"target": "Target.app"}]}]}
]
"""

@Test func caskIndexSkipsAmbiguous() {
    let index = caskIndex(Data(casks.utf8))
    #expect(index["Foo.app"]?.version == "1.2.3")
    #expect(index["Foo.app"]?.token == "foo")
    #expect(index["Bar.app"] == nil)     // two different products
    #expect(index["Baz.app"] == nil)     // "latest" can't be compared
    #expect(index["Qux.app"] == nil)     // deprecated
    #expect(index["Target.app"]?.version == "3.1")
    #expect(index["Source Name.app"] == nil)
}

private struct Offline: Error {}

@Test func checkUpdatesUsesRightSource() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-updates-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    func app(_ name: String, id: String, short: String, build: String = "1", feed: String? = nil, store: Bool = false) throws -> AppInfo {
        let contents = root.appending(path: "\(name).app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleShortVersionString": short, "CFBundleVersion": build]
        if let feed { info["SUFeedURL"] = feed }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appending(path: "Info.plist"))
        if store {
            try FileManager.default.createDirectory(at: contents.appending(path: "_MASReceipt"), withIntermediateDirectories: true)
            try Data("r".utf8).write(to: contents.appending(path: "_MASReceipt/receipt"))
        }
        return try #require(AppInfo(url: root.appending(path: "\(name).app")))
    }
    let apps = [
        try app("Store", id: "com.store.app", short: "1.0", store: true),
        try app("Gone", id: "com.gone.app", short: "1.0", store: true),
        try app("Sparkly", id: "com.sparkly.app", short: "1.0", build: "100", feed: "https://feed.test/appcast.xml"),
        try app("Current", id: "com.current.app", short: "1.1", build: "110", feed: "https://feed.test/appcast.xml"),
        try app("Offline", id: "com.offline.app", short: "1.0", feed: "https://down.test/appcast.xml"),
        try app("Foo", id: "com.foo.app", short: "1.2.0"),
        try app("Unknown", id: "com.unknown.app", short: "1.0"),
    ]
    let fetch: @Sendable (URL) async throws -> Data = { url in
        switch url.host() {
        case "itunes.apple.com":
            return url.query()?.contains("com.store.app") == true
                ? Data(#"{"resultCount":1,"results":[{"version":"1.1","trackViewUrl":"https://apps.apple.com/app/id9"}]}"#.utf8)
                : Data(#"{"resultCount":0,"results":[]}"#.utf8)
        case "feed.test": return Data(appcast.utf8)
        case "formulae.brew.sh": return Data(casks.utf8)
        default: throw Offline()
        }
    }
    let report = await checkUpdates(apps, os: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0), fetch: fetch)

    let byName = Dictionary(report.available.map { ($0.app.name, $0) }, uniquingKeysWith: { a, _ in a })
    #expect(Set(byName.keys) == ["Store", "Sparkly", "Foo"])
    #expect(byName["Store"]?.source == .appStore)
    #expect(byName["Store"]?.link == URL(string: "https://apps.apple.com/app/id9"))
    #expect(byName["Sparkly"]?.source == .sparkle)
    #expect(byName["Sparkly"]?.installed == "1.0" && byName["Sparkly"]?.latest == "1.1")
    #expect(byName["Sparkly"]?.link == URL(string: "https://x.test/notes/1.1"))
    #expect(byName["Foo"]?.source == .homebrew && byName["Foo"]?.latest == "1.2.3")
    #expect(report.upToDate == 1)  // Current
    #expect(Set(report.unchecked.map(\.name)) == ["Gone", "Offline", "Unknown"])
}
