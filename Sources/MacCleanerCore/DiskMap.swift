import CoreGraphics
import Foundation

/// One item in the disk map. A folder's size is the sum of its children's, so lumped detail still counts.
public struct DiskNode: Sendable, Identifiable, Equatable {
    public let url: URL
    public let name: String
    public let size: Int64
    public let isDirectory: Bool
    /// Largest first.
    public let children: [DiskNode]
    /// Above zero for the tile that stands in for that many small items.
    public let lumped: Int

    public init(url: URL, name: String? = nil, size: Int64, isDirectory: Bool, children: [DiskNode], lumped: Int = 0) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
        self.lumped = lumped
    }

    public var id: String { lumped > 0 ? url.path + "/\u{2026}smaller" : url.path }

    /// By identity and size, not the whole subtree: the view compares nodes on every hover.
    public static func == (a: DiskNode, b: DiskNode) -> Bool { a.id == b.id && a.size == b.size }

    /// Keeps at most `maxChildren` children of `minSize` or more; the rest become one lump tile.
    static let maxChildren = 60
    static let minSize: Int64 = 1_000_000

    static func folder(_ url: URL, _ items: [DiskNode]) -> DiskNode {
        let sorted = items.sorted { $0.size > $1.size }
        var kept = Array(sorted.prefix(maxChildren).prefix { $0.size >= minSize })
        let rest = sorted.dropFirst(kept.count)
        if !rest.isEmpty {
            kept.append(DiskNode(url: url, name: "\(rest.count) smaller item\(rest.count == 1 ? "" : "s")",
                                 size: rest.reduce(0) { $0 + $1.size }, isDirectory: false, children: [], lumped: rest.count))
        }
        return DiskNode(url: url, size: items.reduce(0) { $0 + $1.size }, isDirectory: true, children: kept)
    }
}

/// The walk's shared state: how many items it has looked at (for a progress line, safe to read from any thread),
/// and which hard-linked files it has already counted.
public final class ItemCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var linked: Set<UInt64> = []
    public init() {}
    public var value: Int { lock.withLock { count } }
    func add(_ n: Int) { lock.withLock { count += n } }
    /// True the first time a hard-linked file is seen. The walk stays on one volume, so the file ID alone is unique.
    func firstSighting(_ file: UInt64) -> Bool { lock.withLock { linked.insert(file).inserted } }
}

private let walkKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .volumeURLKey,
                                          .linkCountKey, .fileIdentifierKey]

/// Measures everything under `url`. Never follows symlinks or crosses into another volume, and counts a hard-linked
/// file once (at whichever path the walk reaches first), like `du`.
/// Returns nil when the surrounding task is cancelled.
public func diskTree(_ url: URL, counter: ItemCounter = ItemCounter()) async -> DiskNode? {
    let volume = try? url.resourceValues(forKeys: [.volumeURLKey]).volume
    let node = await measure(url, volume: volume, depth: 0, counter: counter)
    return Task.isCancelled ? nil : node
}

private func measure(_ dir: URL, volume: URL?, depth: Int, counter: ItemCounter) async -> DiskNode {
    // Unreadable folders count as empty; macOS hides some even with Full Disk Access.
    let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: walkKeys)) ?? []
    counter.add(entries.count)
    var items: [DiskNode] = []
    var folders: [URL] = []
    for entry in entries {
        if Task.isCancelled { break }
        let values = try? entry.resourceValues(forKeys: Set(walkKeys))
        if values?.isDirectory == true, values?.isSymbolicLink != true {
            if volume == nil || values?.volume == volume { folders.append(entry) }  // a mount point is another disk
        } else {
            var size = Int64(values?.totalFileAllocatedSize ?? 0)
            if (values?.linkCount ?? 1) > 1, let file = values?.fileIdentifier, !counter.firstSighting(file) { size = 0 }
            items.append(DiskNode(url: entry, size: size, isDirectory: false, children: []))
        }
    }
    // ponytail: parallel only in the top three levels; deeper folders are small and many, so tasks would cost more than they save.
    if depth < 3 {
        items += await withTaskGroup(of: DiskNode.self) { group in
            for folder in folders { group.addTask { await measure(folder, volume: volume, depth: depth + 1, counter: counter) } }
            return await group.reduce(into: []) { $0.append($1) }
        }
    } else {
        for folder in folders where !Task.isCancelled { items.append(await measure(folder, volume: volume, depth: depth + 1, counter: counter)) }
    }
    return DiskNode.folder(dir, items)
}

/// Squarified treemap (Bruls, Huizing, van Wijk): one rect per size, areas proportional, tiles kept close to square.
/// `sizes` should be largest first. Sizes of zero or less get `.zero`.
public func treemap(_ sizes: [Double], in bounds: CGRect) -> [CGRect] {
    var result = [CGRect](repeating: .zero, count: sizes.count)
    let total = sizes.filter { $0 > 0 }.reduce(0, +)
    guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }
    let areas = sizes.map { max(0, $0) / total * bounds.width * bounds.height }
    var free = bounds
    var row: [Int] = []

    func worst(_ row: [Int], _ side: Double) -> Double {
        let sum = row.reduce(0) { $0 + areas[$1] }
        let big = row.map { areas[$0] }.max() ?? 0, small = row.map { areas[$0] }.min() ?? 0
        return max(side * side * big / (sum * sum), sum * sum / (side * side * small))
    }

    func place(_ row: [Int]) {
        let sum = row.reduce(0) { $0 + areas[$1] }
        if free.width >= free.height {
            let width = sum / free.height
            var y = free.minY
            for i in row {
                result[i] = CGRect(x: free.minX, y: y, width: width, height: areas[i] / width)
                y += areas[i] / width
            }
            free = CGRect(x: free.minX + width, y: free.minY, width: max(0, free.width - width), height: free.height)
        } else {
            let height = sum / free.width
            var x = free.minX
            for i in row {
                result[i] = CGRect(x: x, y: free.minY, width: areas[i] / height, height: height)
                x += areas[i] / height
            }
            free = CGRect(x: free.minX, y: free.minY + height, width: free.width, height: max(0, free.height - height))
        }
    }

    for i in areas.indices where areas[i] > 0 {
        let side = min(free.width, free.height)
        if !row.isEmpty, worst(row + [i], side) > worst(row, side) {
            place(row)
            row = []
        }
        row.append(i)
    }
    if !row.isEmpty { place(row) }
    return result
}
