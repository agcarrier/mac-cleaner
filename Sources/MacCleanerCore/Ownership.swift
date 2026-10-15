/// Who owns a bundle-ID-named item, judged against the installed (or running) apps.
public enum Ownership: Equatable {
    case system      // com.apple.*, never touched
    case installed   // exact match, or a parent/child ID of an installed app
    case sameVendor  // same reverse-DNS vendor as an installed app, e.g. com.foo.updater next to com.foo.app
    case orphan      // nothing installed claims it
}

/// Reverse-DNS with at least three non-empty ASCII parts: `com.foo.app`. Two-part names are too ambiguous to judge.
public func looksLikeBundleID(_ s: String) -> Bool {
    let parts = s.split(separator: ".", omittingEmptySubsequences: false)
    return parts.count >= 3 && parts.allSatisfy { part in
        !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

/// `apps` must hold lowercased bundle IDs.
public func ownership(of id: String, by apps: Set<String>) -> Ownership {
    let id = id.lowercased()
    if id.hasPrefix("com.apple.") { return .system }
    if apps.contains(where: { id == $0 || id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") }) { return .installed }
    let vendor = id.split(separator: ".").prefix(2).joined(separator: ".") + "."
    if apps.contains(where: { $0.hasPrefix(vendor) }) { return .sameVendor }
    return .orphan
}
