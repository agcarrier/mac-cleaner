import Foundation
import Testing
@testable import MacCleanerCore

private func tempTree() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-map-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func write(_ root: URL, _ path: String, bytes: Int) throws {
    let url = root.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 7, count: bytes).write(to: url)
}

/// Every folder's size is the sum of everything under it, lumped items included, and matches a plain walk.
@Test func treeSizesAddUp() async throws {
    let root = try tempTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(root, "big.bin", bytes: 3_000_000)
    try write(root, "a/one.bin", bytes: 2_000_000)
    try write(root, "a/b/two.bin", bytes: 1_500_000)
    for i in 0..<5 { try write(root, "a/small\(i).txt", bytes: 100) }

    let counter = ItemCounter()
    let tree = try #require(await diskTree(root, counter: counter))
    #expect(tree.size == allocatedSize(root))
    #expect(tree.isDirectory)
    #expect(tree.children.map(\.name) == ["a", "big.bin"])  // largest first: a holds 3.5 MB

    func check(_ node: DiskNode) {
        if node.isDirectory { #expect(node.size == node.children.reduce(0) { $0 + $1.size }) }
        node.children.forEach(check)
    }
    check(tree)
    #expect(counter.value == 10)  // big.bin, a, one.bin, b, two.bin, 5 small files
}

@Test func smallItemsAreLumped() async throws {
    let root = try tempTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(root, "big.bin", bytes: 2_000_000)
    for i in 0..<4 { try write(root, "small\(i).txt", bytes: 100) }

    let tree = try #require(await diskTree(root))
    #expect(tree.children.count == 2)
    let lump = try #require(tree.children.last)
    #expect(lump.lumped == 4)
    #expect(lump.name == "4 smaller items")
    #expect(!lump.isDirectory && lump.children.isEmpty)
    #expect(lump.id != tree.id)
}

@Test func symlinksNotFollowed() async throws {
    let root = try tempTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(root, "real/big.bin", bytes: 2_000_000)
    try FileManager.default.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: root.appending(path: "real"))

    let tree = try #require(await diskTree(root))
    let real = try #require(tree.children.first { $0.name == "real" })
    #expect(tree.size < real.size * 2)
    #expect(tree.children.first { $0.name == "link" }?.isDirectory != true)
}

@Test func cancelledWalkReturnsNil() async throws {
    let root = try tempTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(root, "a/b.bin", bytes: 10)
    let task = Task { await diskTree(root) }
    task.cancel()
    #expect(await task.value == nil)
}

@Test func treemapTilesTheRect() {
    let sizes: [Double] = [500, 300, 120, 50, 20, 6, 3, 1]
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
    let rects = treemap(sizes, in: bounds)
    #expect(rects.count == sizes.count)

    let total = sizes.reduce(0, +)
    for (rect, size) in zip(rects, sizes) {
        // Area is proportional to size, and every tile is inside the bounds.
        #expect(abs(rect.width * rect.height - size / total * bounds.width * bounds.height) < 1)
        #expect(bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect))
    }
    for i in rects.indices {
        for j in rects.indices where j > i {
            let overlap = rects[i].intersection(rects[j])
            #expect(overlap.isNull || overlap.width * overlap.height < 0.5)
        }
    }
    // Squarified: equal sizes in a square come out as squares.
    for rect in treemap([1, 1, 1, 1], in: CGRect(x: 0, y: 0, width: 100, height: 100)) {
        #expect(abs(rect.width - 50) < 0.01 && abs(rect.height - 50) < 0.01)
    }
}

@Test func treemapEdgeCases() {
    #expect(treemap([], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
    #expect(treemap([5, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)) == [CGRect(x: 0, y: 0, width: 10, height: 10), .zero])
    #expect(treemap([0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)) == [.zero, .zero])
    #expect(treemap([1], in: .zero) == [.zero])
}

/// A file with several hard links takes its space once, like `du`. Spotlight's index on Andrew's Mac has 84,000 of them.
@Test func hardLinksCountedOnce() async throws {
    let root = try tempTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(root, "a/big.bin", bytes: 2_000_000)
    try FileManager.default.createDirectory(at: root.appending(path: "b"), withIntermediateDirectories: true)
    try FileManager.default.linkItem(at: root.appending(path: "a/big.bin"), to: root.appending(path: "b/same.bin"))

    let tree = try #require(await diskTree(root))
    let single = allocatedSize(root.appending(path: "a/big.bin"))
    #expect(tree.size == single)
}
