import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MacCleanerCore

private func tempDir() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-clutter-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@discardableResult
private func write(_ root: URL, _ path: String, _ data: Data, created: Date? = nil) throws -> URL {
    let url = root.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    if let created { try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path) }
    return url
}

private let blob = Data((0..<150_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })

/// Only ordinary, local files of a useful size, outside places where a copy is usually on purpose.
@Test func walkSkips() throws {
    let root = try tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(root, "keep/file.bin", blob)
    try write(root, ".hidden/file.bin", blob)
    try write(root, "Thing.app/Contents/file.bin", blob)
    try write(root, "Library/file.bin", blob)
    try write(root, "proj/node_modules/pkg/file.bin", blob)
    try write(root, "repo/.git/HEAD", Data("ref".utf8))
    try write(root, "repo/src/file.bin", blob)
    try write(root, "keep/small.txt", Data("tiny".utf8))
    try FileManager.default.createSymbolicLink(at: root.appending(path: "keep/link.bin"), withDestinationURL: root.appending(path: "keep/file.bin"))
    try FileManager.default.linkItem(at: root.appending(path: "keep/file.bin"), to: root.appending(path: "keep/hardlink.bin"))

    // The same folder listed twice (or a parent and its child) is walked once.
    let files = clutterFiles(in: [root, root.appending(path: "keep")], minSize: 100_000)
    #expect(files.map(\.url.lastPathComponent) == ["file.bin"])
}

@Test func duplicatesKeepOne() throws {
    let root = try tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(root, "a/one.bin", blob, created: Date(timeIntervalSince1970: 1_000))
    try write(root, "b/two.bin", blob, created: Date(timeIntervalSince1970: 2_000))
    try write(root, "c/three.bin", blob, created: Date(timeIntervalSince1970: 3_000))
    try write(root, "d/unique.bin", Data(blob.reversed()))

    let found = findDuplicates(in: [root])
    #expect(found.count == 3)
    #expect(Set(found.map(\.group)).count == 1)
    let kept = found.filter { !$0.isActionable }
    #expect(kept.map(\.title) == ["one.bin"])
    let copies = found.filter(\.isActionable)
    #expect(copies.count == 2)
    #expect(Set(found.map(\.category)) == [.duplicates])
}

/// ✓ only for loose copies: in Downloads, or beside the kept file. Copies spread across other folders are often part of a
/// project or an app's data (Andrew's Divinity campaigns, site kits), so they start unchecked.
@Test func onlyLooseCopiesPreselected() throws {
    let root = try tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(root, "Documents/photo.jpg", blob, created: Date(timeIntervalSince1970: 1_000))
    try write(root, "Documents/photo 2.jpg", blob, created: Date(timeIntervalSince1970: 2_000))
    try write(root, "Downloads/photo.jpg", blob, created: Date(timeIntervalSince1970: 3_000))
    try write(root, "Projects/site/assets/photo.jpg", blob, created: Date(timeIntervalSince1970: 4_000))

    let found = findDuplicates(in: [root])
    let checked = Dictionary(found.filter(\.isActionable).map { ($0.detail + "/" + $0.title, $0.isPreselected) }, uniquingKeysWith: { a, _ in a })
    #expect(checked.count == 3)
    #expect(checked.first { $0.key.hasSuffix("photo 2.jpg") }?.value == true)
    #expect(checked.first { $0.key.contains("Downloads") }?.value == true)
    #expect(checked.first { $0.key.contains("assets") }?.value == false)
}

private func keptTitle(_ found: [Finding]) -> String? { found.first(where: { !$0.isActionable })?.title }

/// Downloads copies go first; then the oldest stays; then the shortest path.
@Test func keptCopyRules() throws {
    let root = try tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(root, "Downloads/oldest.bin", blob, created: Date(timeIntervalSince1970: 1_000))
    try write(root, "Documents/newer.bin", blob, created: Date(timeIntervalSince1970: 3_000))
    try write(root, "Documents/deep/older.bin", blob, created: Date(timeIntervalSince1970: 2_000))
    #expect(keptTitle(findDuplicates(in: [root])) == "older.bin")

    let same = Date(timeIntervalSince1970: 5_000)
    let other = try tempDir()
    defer { try? FileManager.default.removeItem(at: other) }
    try write(other, "x/longer-name.bin", blob, created: same)
    try write(other, "x/s.bin", blob, created: same)
    #expect(keptTitle(findDuplicates(in: [other])) == "s.bin")
}

@Test func fullHashDecides() throws {
    let root = try tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    var tail = blob
    tail[tail.count - 1] ^= 0xFF  // same size, same first 64 KB, different last byte
    try write(root, "a.bin", blob)
    try write(root, "b.bin", tail)
    #expect(findDuplicates(in: [root]).isEmpty)
}

// MARK: - Similar photos

/// Draws a picture: a few shapes on a gradient, varied by `seed`.
private func drawPicture(seed: Int, size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size)
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: (seed == 0 ? [CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1), CGColor(red: 0.9, green: 0.9, blue: 0.6, alpha: 1)]
                                                 : [CGColor(red: 0.2, green: 0.6, blue: 0.1, alpha: 1), CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)]) as CFArray,
                              locations: nil)!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: s), options: [])
    if seed == 0 {
        ctx.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: s * 0.3, y: s * 0.5, width: s * 0.35, height: s * 0.35))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s * 0.25))
    } else {
        ctx.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.4, alpha: 1))
        for i in 0..<8 { ctx.fill(CGRect(x: CGFloat(i) * s / 8, y: 0, width: s / 16, height: s)) }
    }
    return ctx.makeImage()!
}

private func save(_ image: CGImage, _ url: URL, _ type: UTType, quality: Double = 1) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    #expect(CGImageDestinationFinalize(dest))
}

@Test func similarPhotosGroup() throws {
    let root = try tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try save(drawPicture(seed: 0, size: 1024), root.appending(path: "pics/original.png"), .png)
    try save(drawPicture(seed: 0, size: 800), root.appending(path: "pics/smaller.jpg"), .jpeg, quality: 0.8)
    try save(drawPicture(seed: 1, size: 1024), root.appending(path: "pics/different.png"), .png)

    let found = findSimilarPhotos(in: [root], minSize: 0)
    #expect(Set(found.map(\.title)) == ["original.png", "smaller.jpg"])
    #expect(Set(found.map(\.group)).count == 1)
    let allOptional = found.allSatisfy { $0.confidence == .low && $0.isActionable && !$0.isPreselected && $0.category == .similar }
    #expect(allOptional)
}
