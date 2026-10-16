import Foundation
import Observation
import MacCleanerCore

/// Produces findings, reporting each category as it starts. Runs off the main actor.
public typealias Scanner = @Sendable (_ progress: @escaping @Sendable (MacCleanerCore.Category) -> Void) async -> [Finding]
/// Acts on one finding's action. The live one is `perform`, which only ever moves things to the Trash.
public typealias Performer = @Sendable (Action) throws -> Void

public struct CleanFailure: Equatable, Sendable {
    public let finding: Finding
    public let message: String
}

public struct CleanSummary: Equatable, Sendable {
    public let cleaned: Int
    public let bytes: Int64
    public let failures: [CleanFailure]
}

/// One tool's scan → review → clean cycle. Nothing is acted on unless it was found, shown, and selected.
@MainActor @Observable
public final class ScanModel {
    public enum Phase: Equatable {
        case idle
        case scanning(MacCleanerCore.Category?)
        case review
        case cleaning
        case done(CleanSummary)
    }

    public private(set) var phase: Phase = .idle
    /// Largest first.
    public private(set) var findings: [Finding] = []
    public var selection: Set<Finding.ID> = []
    /// Why the last clean was refused (for example, the app is running). Cleared on the next attempt.
    public private(set) var blockedReason: String?

    private let onlyPreselected: Bool
    private let scanner: Scanner
    private let performer: Performer
    private let preflight: @Sendable () -> String?
    private var scanTask: Task<Void, Never>?
    private var scanID = UUID()

    public init(onlyPreselected: Bool = false, scanner: @escaping Scanner, performer: @escaping Performer = perform,
                preflight: @escaping @Sendable () -> String? = { nil }) {
        self.onlyPreselected = onlyPreselected
        self.scanner = scanner
        self.performer = performer
        self.preflight = preflight
    }

    public var selectedFindings: [Finding] { findings.filter { $0.isActionable && selection.contains($0.id) } }
    public var selectedBytes: Int64 { selectedFindings.reduce(0) { $0 + $1.size } }

    public func scan() {
        switch phase {
        case .scanning, .cleaning: return
        case .idle, .review, .done: break
        }
        let id = UUID()
        scanID = id
        phase = .scanning(nil)
        findings = []
        selection = []
        blockedReason = nil
        let scanner = self.scanner
        // Main-actor isolated, so capturing self across the scan is safe; it's released when the scan ends.
        scanTask = Task {
            let results = await scanner { category in
                Task { @MainActor in self.markProgress(category, id: id) }
            }
            finishScan(id: id, results: results)
        }
    }

    private func markProgress(_ category: MacCleanerCore.Category, id: UUID) {
        guard scanID == id, case .scanning = phase else { return }
        phase = .scanning(category)
    }

    private func finishScan(id: UUID, results: [Finding]) {
        // A cancelled or superseded scan's late results are dropped, so nothing stale can be cleaned.
        guard scanID == id, case .scanning = phase else { return }
        var found = results.sorted { $0.size > $1.size }
        if onlyPreselected { found = found.filter(\.isPreselected) }
        findings = found
        selection = Set(found.filter(\.isPreselected).map(\.id))
        phase = .review
    }

    public func cancel() {
        guard case .scanning = phase else { return }
        scanTask?.cancel()
        scanID = UUID()
        phase = .idle
        findings = []
        selection = []
    }

    public func toggle(_ id: Finding.ID) {
        guard phase == .review, findings.contains(where: { $0.id == id && $0.isActionable }) else { return }
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    public func clean() async {
        let items = selectedFindings
        guard phase == .review, !items.isEmpty else { return }
        if let reason = preflight() {
            blockedReason = reason
            return
        }
        blockedReason = nil
        phase = .cleaning
        let performer = self.performer
        let summary = await Task.detached(priority: .userInitiated) {
            var cleaned = 0, bytes: Int64 = 0, failures: [CleanFailure] = []
            for finding in items {
                do {
                    try performer(finding.action)
                    cleaned += 1
                    bytes += finding.size
                } catch {
                    failures.append(CleanFailure(finding: finding, message: error.localizedDescription))
                }
            }
            return CleanSummary(cleaned: cleaned, bytes: bytes, failures: failures)
        }.value
        phase = .done(summary)
    }
}
