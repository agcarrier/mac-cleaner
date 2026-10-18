import Foundation
import Observation
import MacCleanerCore

/// Measures a folder in the background. Returns nil when cancelled.
public typealias TreeMeasurer = @Sendable (URL, ItemCounter) async -> DiskNode?

/// The disk map: idle → measuring → map, plus the folder path the user has drilled into.
@MainActor @Observable
public final class DiskMapModel {
    public enum Phase: Equatable { case idle, measuring(URL), map }

    public private(set) var phase: Phase = .idle
    public private(set) var itemsMeasured = 0
    public private(set) var root: DiskNode?
    /// From the root to the folder on screen.
    public private(set) var path: [DiskNode] = []
    public var current: DiskNode? { path.last }

    private let tree: TreeMeasurer
    private var task: Task<Void, Never>?
    private var runID = UUID()

    public init(tree: @escaping TreeMeasurer = { await diskTree($0, counter: $1) }) {
        self.tree = tree
    }

    public func map(_ url: URL) {
        if case .measuring = phase { return }
        let id = UUID()
        runID = id
        reset(keepingRun: true)
        phase = .measuring(url)
        let counter = ItemCounter()
        let tree = self.tree
        task = Task {
            let measuring = Task.detached(priority: .userInitiated) { await tree(url, counter) }
            // Main-actor isolated, so touching self here is safe; polling stops when the run ends or is replaced.
            let poll = Task {
                while !Task.isCancelled, runID == id {
                    itemsMeasured = counter.value
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            let node = await withTaskCancellationHandler { await measuring.value } onCancel: { measuring.cancel() }
            poll.cancel()
            guard runID == id, let node else { return }
            root = node
            path = [node]
            phase = .map
        }
    }

    /// Back to the start with nothing kept, so no half-measured map is ever shown.
    public func cancel() {
        task?.cancel()
        reset()
    }

    public func reset() { reset(keepingRun: false) }

    private func reset(keepingRun: Bool) {
        if !keepingRun { runID = UUID() }
        phase = .idle
        root = nil
        path = []
        itemsMeasured = 0
    }

    /// Only folders with something inside can be opened.
    public func open(_ node: DiskNode) {
        guard phase == .map, node.isDirectory, !node.children.isEmpty, current?.children.contains(node) == true else { return }
        path.append(node)
    }

    public func up(to index: Int) {
        guard path.indices.contains(index) else { return }
        path.removeSubrange((index + 1)...)
    }
}
