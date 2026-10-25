import Foundation
import Observation

/// What Spruce has cleared on this Mac, forever: the bytes each clean moved to the Trash, and a tree for every whole
/// gigabyte. Kept in Application Support; nothing leaves the Mac.
public struct ForestLedger: Codable, Equatable, Sendable {
    public private(set) var freedBytes: Int64 = 0
    public private(set) var treesPlanted: [Date] = []

    public static let bytesPerTree: Int64 = 1_000_000_000

    public init() {}

    public mutating func record(_ bytes: Int64, at date: Date) {
        guard bytes > 0 else { return }
        freedBytes = freedBytes.addingReportingOverflow(bytes).overflow ? .max : freedBytes + bytes
        let due = Int(freedBytes / Self.bytesPerTree) - treesPlanted.count
        if due > 0 { treesPlanted += Array(repeating: date, count: due) }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A hand-edited or damaged file never shows a negative total.
        freedBytes = max(0, try c.decode(Int64.self, forKey: .freedBytes))
        treesPlanted = try c.decode([Date].self, forKey: .treesPlanted)
    }
}

@MainActor @Observable
public final class ForestStore {
    public private(set) var ledger: ForestLedger
    private let file: URL

    public static var liveFile: URL {
        URL.applicationSupportDirectory.appending(path: "Spruce/forest.json")
    }

    /// A missing or unreadable file starts from zero.
    public init(file: URL = ForestStore.liveFile) {
        self.file = file
        ledger = (try? JSONDecoder().decode(ForestLedger.self, from: Data(contentsOf: file))) ?? ForestLedger()
    }

    public func record(_ bytes: Int64) {
        ledger.record(bytes, at: .now)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(ledger).write(to: file, options: .atomic)
    }
}
