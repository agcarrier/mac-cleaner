import Foundation
import Testing
@testable import MacCleanerCore
@testable import SpruceKit

private func file(_ path: String, _ size: Int64) -> DiskNode {
    DiskNode(url: URL(filePath: path), size: size, isDirectory: false, children: [])
}

private let deep = DiskNode(url: URL(filePath: "/r/a/b"), size: 10, isDirectory: true, children: [file("/r/a/b/x", 10)])
private let a = DiskNode(url: URL(filePath: "/r/a"), size: 30, isDirectory: true, children: [file("/r/a/y", 20), deep])
private let lump = DiskNode(url: URL(filePath: "/r"), name: "3 smaller items", size: 5, isDirectory: false, children: [], lumped: 3)
private let root = DiskNode(url: URL(filePath: "/r"), size: 35, isDirectory: true, children: [a, lump])

@MainActor
private func waitWhileMeasuring(_ m: DiskMapModel) async {
    for _ in 0..<200 {
        if case .measuring = m.phase { try? await Task.sleep(for: .milliseconds(10)) } else { return }
    }
}

@Test @MainActor func mapThenDrill() async {
    let m = DiskMapModel(tree: { _, _ in root })
    m.map(URL(filePath: "/r"))
    await waitWhileMeasuring(m)
    #expect(m.phase == .map)
    #expect(m.current == root)

    m.open(a)
    m.open(deep)
    #expect(m.path.map(\.name) == ["r", "a", "b"])
    m.up(to: 0)
    #expect(m.current == root)
    m.reset()
    #expect(m.phase == .idle && m.root == nil && m.path.isEmpty)
}

@Test @MainActor func openIgnoresFilesAndLumps() async {
    let m = DiskMapModel(tree: { _, _ in root })
    m.map(URL(filePath: "/r"))
    await waitWhileMeasuring(m)
    m.open(lump)
    m.open(file("/r/a/y", 20))
    #expect(m.path.count == 1)
}

@Test @MainActor func cancelDiscardsMap() async {
    let m = DiskMapModel(tree: { _, _ in
        try? await Task.sleep(for: .seconds(5))
        return Task.isCancelled ? nil : root
    })
    m.map(URL(filePath: "/r"))
    #expect(m.phase == .measuring(URL(filePath: "/r")))
    m.map(URL(filePath: "/other"))  // ignored while measuring
    #expect(m.phase == .measuring(URL(filePath: "/r")))
    m.cancel()
    #expect(m.phase == .idle)
    try? await Task.sleep(for: .milliseconds(50))
    #expect(m.phase == .idle && m.root == nil)
}
