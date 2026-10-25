import Foundation

/// A path with symlinks in its parent folders resolved, so a link can't smuggle a protected place past the checks.
/// The last component is kept as is: trashing a symlink moves the link, not what it points to.
private func canonical(_ url: URL) -> String {
    let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
    return url.path == "/" ? "/" : parent.appending(path: url.lastPathComponent).standardizedFileURL.path
}

/// Library folders that hold secrets, synced files or the user's messages. Never cleaned, whatever a rule says.
private let protectedLibraryFolders: Set<String> = ["Keychains", "Mobile Documents", "CloudStorage", "Mail", "Messages", "Accounts"]

/// Why Spruce must never move `url` to the Trash, or nil when it may. The last line of defense: `trash` checks it for every
/// item, whichever rule asked. Allowed: things inside the home folder below its top level (except the protected places),
/// apps in /Applications, and files on external disks.
public func protectedReason(_ url: URL, home: URL) -> String? {
    let path = canonical(url)
    let homePath = home.resolvingSymlinksInPath().standardizedFileURL.path
    let parts = path.split(separator: "/").map(String.init)

    if parts.contains(where: { $0.lowercased().hasSuffix(".photoslibrary") }) { return "a Photos library" }
    if path == homePath || homePath.hasPrefix(path + "/") { return "your home folder" }

    if path.hasPrefix(homePath + "/") {
        let rel = path.dropFirst(homePath.count + 1).split(separator: "/").map(String.init)
        if rel.count == 1 { return "a folder at the top of your home folder" }
        if rel[0] == "Library" {
            if rel.count == 2 { return "a standard Library folder" }
            if protectedLibraryFolders.contains(rel[1]) { return "where macOS keeps passwords, mail, messages or synced files" }
        }
        // Apple's names inside a Caches folder are caches (Xcode's, or the web caches a sandboxed app keeps in its own
        // container). Anywhere else they're Apple's own data.
        for (i, part) in rel.enumerated() where part.lowercased().hasPrefix("com.apple.") {
            if !rel[..<i].contains("Caches") { return "Apple's own data" }
        }
        return nil
    }
    // Apps to uninstall: in /Applications, or in /Users/Shared where some installers (Blizzard's) put them.
    let appRoot = parts.first == "Applications" || (parts.count >= 2 && parts[0] == "Users" && parts[1] == "Shared")
    if appRoot, parts.count >= 2, path.hasSuffix(".app") { return nil }
    if parts.first == "Volumes", parts.count >= 3 { return nil }
    return "outside your home folder"
}

/// Folders My Clutter may look in: the home folder and anything inside it, or a folder on an external disk.
public func isAllowedClutterFolder(_ url: URL, home: URL) -> Bool {
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    let homePath = home.resolvingSymlinksInPath().standardizedFileURL.path
    let parts = path.split(separator: "/")
    return path == homePath || path.hasPrefix(homePath + "/") || (parts.first == "Volumes" && parts.count >= 2)
}

/// A link from an update feed or store that's safe to open: an encrypted web page. Anything else (files, other apps'
/// links, plain http that could be tampered with on the way) is dropped.
public func webLink(_ string: String?) -> URL? {
    guard let string, let url = URL(string: string), url.scheme?.lowercased() == "https", url.host() != nil else { return nil }
    return url
}
