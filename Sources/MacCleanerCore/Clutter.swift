import CryptoKit
import Foundation
import Vision

// MARK: - Walk

struct ClutterFile: Sendable {
    let url: URL
    let size: Int        // logical bytes, for matching
    let allocated: Int64 // space it takes, for showing
    let created: Date
}

private let clutterKeys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isRegularFileKey,
                                             .fileSizeKey, .totalFileAllocatedSizeKey, .creationDateKey, .fileIdentifierKey]

/// Files worth comparing under `folders`, each once. Skips hidden items, packages (apps, Photos libraries), `Library`,
/// `node_modules`, git repositories (copies there are usually on purpose), iCloud files that aren't downloaded
/// (reading them would download them), symlinks, extra hard links, and files under `minSize`.
func clutterFiles(in folders: [URL], minSize: Int) -> [ClutterFile] {
    var out: [ClutterFile] = []
    var visited: Set<String> = []
    var inodes: Set<UInt64> = []

    func walk(_ dir: URL) {
        guard !Task.isCancelled, visited.insert(dir.standardizedFileURL.path).inserted,
              !FileManager.default.fileExists(atPath: dir.appending(path: ".git").path) else { return }
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: clutterKeys, options: .skipsHiddenFiles)) ?? []
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            guard let v = try? entry.resourceValues(forKeys: Set(clutterKeys)), v.isSymbolicLink != true, v.isPackage != true else { continue }
            if v.isDirectory == true {
                if !["Library", "node_modules"].contains(entry.lastPathComponent) { walk(entry) }
            } else if v.isRegularFile == true, let size = v.fileSize, size >= minSize, !isDataless(entry),
                      v.fileIdentifier.map({ inodes.insert($0).inserted }) ?? true {
                out.append(ClutterFile(url: entry, size: size, allocated: Int64(v.totalFileAllocatedSize ?? size),
                                       created: v.creationDate ?? .distantPast))
            }
        }
    }
    folders.forEach(walk)
    return out
}

/// An iCloud file whose contents live only in the cloud (`SF_DATALESS`).
private func isDataless(_ url: URL) -> Bool {
    var st = stat()
    return lstat(url.path, &st) == 0 && st.st_flags & 0x4000_0000 != 0
}

private func tilde(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }

// MARK: - Duplicates

/// SHA-256 of the first `limit` bytes (or the whole file). Nil when it can't be read.
private func digest(_ url: URL, limit: Int? = nil) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    var remaining = limit ?? .max
    while remaining > 0 {
        let chunk: Data?
        do { chunk = try handle.read(upToCount: min(1 << 20, remaining)) } catch { return nil }
        guard let chunk, !chunk.isEmpty else { break }  // nil or empty: end of file
        hasher.update(data: chunk)
        remaining -= chunk.count
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

/// The copy that stays: not in Downloads, then the oldest, then the shortest path.
private func keepFirst(_ a: ClutterFile, _ b: ClutterFile) -> Bool {
    let downloads = (a.url.pathComponents.contains("Downloads"), b.url.pathComponents.contains("Downloads"))
    if downloads.0 != downloads.1 { return !downloads.0 }
    if a.created != b.created { return a.created < b.created }
    if a.url.path.count != b.url.path.count { return a.url.path.count < b.url.path.count }
    return a.url.path < b.url.path
}

/// Byte-for-byte identical files: same size, then same first 64 KB, then same full SHA-256. In each group the kept copy is
/// report-only, so it can never be selected. Loose copies (in Downloads, or beside the kept file) are ✓; copies in other
/// folders are ○, because a project or an app's data often keeps the same file in several places on purpose.
public func findDuplicates(in folders: [URL], minSize: Int = 100_000) -> [Finding] {
    var out: [Finding] = []
    for sameSize in Dictionary(grouping: clutterFiles(in: folders, minSize: minSize), by: \.size).values where sameSize.count > 1 {
        if Task.isCancelled { break }
        for (partial, sameStart) in Dictionary(grouping: sameSize, by: { digest($0.url, limit: 65_536) }) where partial != nil && sameStart.count > 1 {
            for (full, copies) in Dictionary(grouping: sameStart, by: { digest($0.url) }) where full != nil && copies.count > 1 {
                let ranked = copies.sorted(by: keepFirst)
                let kept = ranked[0], group = kept.url.path
                out.append(Finding(category: .duplicates, title: kept.url.lastPathComponent,
                                   detail: "Kept \u{00B7} \(tilde(kept.url.deletingLastPathComponent()))",
                                   size: kept.allocated, confidence: .high, action: .report, group: group))
                for copy in ranked.dropFirst() {
                    let folder = copy.url.deletingLastPathComponent()
                    let loose = copy.url.pathComponents.contains("Downloads") || folder == kept.url.deletingLastPathComponent()
                    out.append(Finding(category: .duplicates, title: copy.url.lastPathComponent, detail: "Copy in \(tilde(folder))",
                                       size: copy.allocated, confidence: loose ? .high : .low, action: .trash([copy.url]), group: group))
                }
            }
        }
    }
    return out
}

// MARK: - Similar photos

private let photoExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp"]

/// Feature-print distance under which two photos count as similar. Calibrated 2026-10-18 on real photos: shots of the same
/// animal scored 0.22–0.45, a 600 px quality-50 copy of a photo 0.43, a PNG re-save 0.02, different animals mostly above 0.45.
let similarThreshold: Float = 0.45

/// Visually alike photos, compared within each folder. A photo joins a group when it's close to the group's first photo
/// (oldest first), so loose chains don't merge everything. Always ○: the user picks.
public func findSimilarPhotos(in folders: [URL], minSize: Int = 20_000) -> [Finding] {
    let photos = clutterFiles(in: folders, minSize: minSize).filter { photoExtensions.contains($0.url.pathExtension.lowercased()) }
    var out: [Finding] = []
    for folder in Dictionary(grouping: photos, by: { $0.url.deletingLastPathComponent() }).values where folder.count > 1 {
        if Task.isCancelled { break }
        let sorted = folder.sorted { $0.created < $1.created }
        let prints = featurePrints(sorted.map(\.url))
        var groups: [[Int]] = []
        // ponytail: compares each photo with every group seed in its folder, O(photos × groups); fine for a folder of thousands.
        for i in sorted.indices {
            guard let print = prints[i] else { continue }
            if let g = groups.firstIndex(where: { distance(prints[$0[0]]!, print) < similarThreshold }) {
                groups[g].append(i)
            } else {
                groups.append([i])
            }
        }
        for members in groups where members.count > 1 {
            let group = sorted[members[0]].url.path
            for i in members {
                out.append(Finding(category: .similar, title: sorted[i].url.lastPathComponent,
                                   detail: "Similar photos in \(tilde(sorted[i].url.deletingLastPathComponent()))",
                                   size: sorted[i].allocated, confidence: .low, action: .trash([sorted[i].url]), group: group))
            }
        }
    }
    return out
}

func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float {
    var d: Float = .infinity
    try? a.computeDistance(&d, to: b)
    return d
}

/// One feature print per image, computed in parallel. Nil for images Vision can't read.
func featurePrints(_ urls: [URL]) -> [VNFeaturePrintObservation?] {
    final class Results: @unchecked Sendable {  // each slot is written once, under the lock
        let lock = NSLock()
        var prints: [VNFeaturePrintObservation?]
        init(_ n: Int) { prints = Array(repeating: nil, count: n) }
    }
    let results = Results(urls.count)
    DispatchQueue.concurrentPerform(iterations: urls.count) { i in
        let request = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(url: urls[i]).perform([request])
        let print = request.results?.first as? VNFeaturePrintObservation
        results.lock.withLock { results.prints[i] = print }
    }
    return results.prints
}
