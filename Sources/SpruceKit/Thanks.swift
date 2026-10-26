import Foundation

/// Supporters who asked to be thanked by name, as typed in the Payment Link's optional field. `tools/pull-thanks.sh`
/// writes art/Thanks.json before a release, after Andrew reads the list; the build bundles it.
public func cleanThanksNames(_ raw: [String]) -> [String] {
    var seen = Set<String>()
    return raw
        .map { String($0.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(40)) }
        .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

/// A missing or unreadable file means no names.
public func thanks(from file: URL) -> [String] {
    (try? JSONDecoder().decode([String].self, from: Data(contentsOf: file))).map(cleanThanksNames) ?? []
}

public func bundledThanks() -> [String] {
    Bundle.main.url(forResource: "Thanks", withExtension: "json").map(thanks(from:)) ?? []
}
