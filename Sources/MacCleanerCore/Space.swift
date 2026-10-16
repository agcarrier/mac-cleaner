import Foundation

// `mac-cleaner space`: where the big, re-creatable stuff lives.

/// Package-manager and tool caches, by known location. Pure caches refill on their own (✓);
/// downloaded browsers and npx tools cost a long re-download, so they stay ○.
let devCacheLocations: [(path: String, name: String, note: String, confidence: Confidence)] = [
    (".npm/_cacache", "npm cache", "refills as you install packages", .high),
    (".cache/uv", "uv cache", "refills as you install Python packages", .high),
    (".bun/install/cache", "bun cache", "refills as you install packages", .high),
    ("Library/Caches/Yarn", "Yarn cache", "refills as you install packages", .high),
    ("Library/pnpm/store", "pnpm store", "refills on the next pnpm install", .high),
    ("Library/Caches/pip", "pip cache", "refills as you install Python packages", .high),
    (".cache/pip", "pip cache", "refills as you install Python packages", .high),
    ("Library/Caches/Homebrew", "Homebrew downloads", "same as `brew cleanup`", .high),
    (".gradle/caches", "Gradle cache", "refills on the next build", .high),
    (".cargo/registry/cache", "Cargo downloads", "refills on the next build", .high),
    ("Library/Developer/Xcode/UserData/Previews", "SwiftUI preview data", "Xcode rebuilds it", .high),
    (".npm/_npx", "npx tool installs", "each tool re-downloads the next time you run it with npx", .low),
    ("Library/Caches/ms-playwright", "Playwright browsers", "restore with `npx playwright install`", .low),
    (".cache/puppeteer", "Puppeteer browsers", "re-downloaded on the next Puppeteer install", .low),
]

func scanDevCaches(_ c: Context) -> [Finding] {
    devCacheLocations.compactMap { location in
        let url = c.home.appending(path: location.path)
        let size = allocatedSize(url)
        guard size > 0 else { return nil }
        return Finding(category: .devcaches, title: location.name, detail: "~/\(location.path), \(location.note)",
                       size: size, confidence: location.confidence, action: .trash([url]))
    }
}

/// Disk images and installer packages in ~/Downloads. Installers can be downloaded again, so old ones are ✓.
func scanDownloads(_ c: Context, now: Date = .now) -> [Finding] {
    children(c.home.appending(path: "Downloads"))
        .filter { ["dmg", "pkg", "mpkg", "iso"].contains($0.pathExtension.lowercased()) }
        .map { url in
            let days = daysSince(modified(url), now)
            return Finding(category: .downloads, title: url.lastPathComponent, detail: "installer, \(days) days old",
                           size: allocatedSize(url), confidence: days >= 30 ? .high : .low, action: .trash([url]))
        }
}

/// Top-level node_modules in projects nobody has touched for 60+ days. `npm install` brings them back,
/// but that's the user's call, so they're always ○.
func scanNodeModules(_ c: Context, now: Date = .now, found: [URL]? = nil) -> [Finding] {
    let dirs = found ?? spotlight(["-onlyin", c.home.path, "kMDItemFSName == 'node_modules' && kMDItemContentType == 'public.folder'"])
    return dirs
        .filter { !$0.path.contains("/Library/") && !$0.path.contains("/.Trash/") && $0.path.components(separatedBy: "/node_modules").count == 2 }
        .compactMap { modules in
            let project = modules.deletingLastPathComponent()
            // Latest sign of life: the folder itself, package.json, or a git commit/checkout.
            let touched = [project, project.appending(path: "package.json"), project.appending(path: ".git/index")].compactMap(modified).max()
            let days = daysSince(touched, now)
            let size = allocatedSize(modules)
            guard days >= 60, size > 0 else { return nil }
            let shown = project.path.replacingOccurrences(of: c.home.path, with: "~")
            return Finding(category: .projects, title: project.lastPathComponent, detail: "\(shown), untouched \(days) days, `npm install` restores it",
                           size: size, confidence: .low, action: .trash([modules]))
        }
}

/// Files over 1 GB outside Library folders. Could be anything you care about, so these are only listed.
func scanLargeFiles(_ c: Context) -> [Finding] {
    spotlight(["-onlyin", c.home.path, "kMDItemFSSize > 1000000000"])
        .filter { !$0.path.contains("/Library/") && !$0.path.contains("/.Trash/") && !$0.path.contains(".app/") }
        .map { url in
            Finding(category: .large, title: url.lastPathComponent, detail: url.deletingLastPathComponent().path.replacingOccurrences(of: c.home.path, with: "~"),
                    size: allocatedSize(url), confidence: .low, action: .report)
        }
        .sorted { $0.size > $1.size }
        .prefix(15).map { $0 }
}

func spotlight(_ args: [String]) -> [URL] {
    String(decoding: run(["mdfind"] + args).1, as: UTF8.self).split(separator: "\n").map { URL(filePath: String($0)) }
}

func modified(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
}

func daysSince(_ date: Date?, _ now: Date) -> Int {
    guard let date else { return 0 }
    return max(0, Int(now.timeIntervalSince(date) / 86_400))
}
