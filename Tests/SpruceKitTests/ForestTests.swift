import Foundation
import Testing
@testable import SpruceKit

private let gb: Int64 = 1_000_000_000
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "forest-\(UUID()).json")
}

@Test func treesPerGigabyte() {
    var ledger = ForestLedger()
    ledger.record(gb * 6 / 10, at: now)
    #expect(ledger.treesPlanted.isEmpty)
    ledger.record(gb * 6 / 10, at: now)
    #expect(ledger.treesPlanted.count == 1)
    #expect(ledger.freedBytes == gb * 12 / 10)
    ledger.record(gb * 13 / 10, at: now)  // 2.5 GB total
    #expect(ledger.treesPlanted.count == 2)
    ledger.record(gb / 2, at: now)  // 3.0 GB
    #expect(ledger.treesPlanted.count == 3)
}

@Test func ignoresNonPositive() {
    var ledger = ForestLedger()
    ledger.record(0, at: now)
    ledger.record(-5 * gb, at: now)
    #expect(ledger == ForestLedger())
}

@MainActor @Test func persists() {
    let file = tempFile()
    defer { try? FileManager.default.removeItem(at: file) }
    let store = ForestStore(file: file)
    store.record(3 * gb)
    #expect(ForestStore(file: file).ledger == store.ledger)
    #expect(store.ledger.treesPlanted.count == 3)
}

@MainActor @Test func corruptLedgerStartsEmpty() throws {
    let file = tempFile()
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(ForestStore(file: file).ledger == ForestLedger())  // missing
    try Data("{not json".utf8).write(to: file)
    #expect(ForestStore(file: file).ledger == ForestLedger())
    try Data(#"{"freedBytes":-9,"treesPlanted":[]}"#.utf8).write(to: file)
    #expect(ForestStore(file: file).ledger.freedBytes == 0)
    // A missing folder is created on the first save.
    let nested = FileManager.default.temporaryDirectory.appending(path: "forest-\(UUID())/forest.json")
    ForestStore(file: nested).record(gb)
    #expect(ForestStore(file: nested).ledger.treesPlanted.count == 1)
    try? FileManager.default.removeItem(at: nested.deletingLastPathComponent())
}
