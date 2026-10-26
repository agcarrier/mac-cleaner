import Foundation
import Testing
@testable import SpruceKit

@Test func namesAreCleaned() {
    let raw = ["  Ana  ", "ana", "", String(repeating: "x", count: 60), "Bo   B", "\n\t"]
    #expect(cleanThanksNames(raw) == ["Ana", "Bo B", String(repeating: "x", count: 40)])
}

@Test func thanksFileDecodes() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "thanks-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(#"["Zoë", " zoë ", "Al"]"#.utf8).write(to: file)
    #expect(thanks(from: file) == ["Al", "Zoë"])
    #expect(thanks(from: file.appending(path: "missing")) == [])
}
