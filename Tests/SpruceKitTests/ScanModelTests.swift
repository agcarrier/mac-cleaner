import Foundation
import Testing
@testable import MacCleanerCore
@testable import SpruceKit

private let high = Finding(category: .caches, title: "high", detail: "", size: 300, confidence: .high, action: .trash([URL(filePath: "/tmp/high")]))
private let low = Finding(category: .caches, title: "low", detail: "", size: 200, confidence: .low, action: .trash([URL(filePath: "/tmp/low")]))
private let report = Finding(category: .large, title: "report", detail: "big", size: 100, confidence: .high, action: .report)

/// Collects the paths of every action the model performs.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    var performed: [String] { lock.withLock { paths } }
    func record(_ action: Action) {
        if case .trash(let urls) = action { lock.withLock { paths += urls.map(\.path) } }
    }
}

private struct Boom: LocalizedError { var errorDescription: String? { "permission denied" } }

@MainActor
private func model(_ findings: [Finding], onlyPreselected: Bool = false, recorder: Recorder = Recorder(),
                   failing: Set<String> = [], preflight: @escaping @Sendable () -> String? = { nil }) -> ScanModel {
    ScanModel(onlyPreselected: onlyPreselected, scanner: { _ in findings }, performer: { action in
        if case .trash(let urls) = action, urls.contains(where: { failing.contains($0.path) }) { throw Boom() }
        recorder.record(action)
    }, preflight: preflight)
}

@MainActor
private func waitWhileScanning(_ m: ScanModel) async {
    for _ in 0..<200 {
        if case .scanning = m.phase { try? await Task.sleep(for: .milliseconds(10)) } else { return }
    }
}

@Test @MainActor func preselectsOnlyHighActionable() async {
    let m = model([high, low, report])
    m.scan(); await waitWhileScanning(m)
    #expect(m.phase == .review)
    #expect(m.selection == [high.id])
    #expect(m.findings.map(\.id) == [high.id, low.id, report.id])  // largest first
}

@Test @MainActor func onlyPreselectedFilters() async {
    let m = model([high, low, report], onlyPreselected: true)
    m.scan(); await waitWhileScanning(m)
    #expect(m.findings == [high])
}

@Test @MainActor func toggleIgnoresReports() async {
    let m = model([high, low, report])
    m.scan(); await waitWhileScanning(m)
    m.toggle(report.id)
    m.toggle(low.id)
    #expect(m.selection == [high.id, low.id])
    #expect(m.selectedBytes == 500)
}

@Test @MainActor func emptySelectionDoesNothing() async {
    let recorder = Recorder()
    let m = model([high, low], recorder: recorder)
    m.scan(); await waitWhileScanning(m)
    m.toggle(high.id)
    await m.clean()
    #expect(m.phase == .review)
    #expect(recorder.performed.isEmpty)
}

@Test @MainActor func partialFailureIsReported() async {
    let recorder = Recorder()
    let m = model([high, low], recorder: recorder, failing: ["/tmp/high"])
    m.scan(); await waitWhileScanning(m)
    m.toggle(low.id)
    await m.clean()
    guard case .done(let summary) = m.phase else { Issue.record("expected done, got \(m.phase)"); return }
    #expect(summary.cleaned == 1)
    #expect(summary.bytes == 200)
    #expect(summary.failures.map(\.finding.id) == [high.id])
    #expect(summary.failures.first?.message.isEmpty == false)
    #expect(recorder.performed == ["/tmp/low"])
}

@Test @MainActor func cleanOnlyFromReview() async {
    let recorder = Recorder()
    let m = model([high, low], recorder: recorder)
    await m.clean()                               // idle
    #expect(recorder.performed.isEmpty)
    m.scan(); await waitWhileScanning(m)
    m.toggle(low.id)
    async let first: Void = m.clean()
    async let second: Void = m.clean()
    _ = await (first, second)
    #expect(recorder.performed.sorted() == ["/tmp/high", "/tmp/low"])
}

@Test @MainActor func cancelDiscardsResults() async {
    let recorder = Recorder()
    let m = ScanModel(scanner: { _ in
        try? await Task.sleep(for: .milliseconds(300))
        return [high]
    }, performer: { recorder.record($0) })
    m.scan()
    await m.clean()                               // while scanning: ignored
    m.cancel()
    #expect(m.phase == .idle)
    try? await Task.sleep(for: .milliseconds(500))
    #expect(m.phase == .idle)
    #expect(m.findings.isEmpty)
    #expect(recorder.performed.isEmpty)
}

@Test @MainActor func preflightBlocksClean() async {
    let recorder = Recorder()
    let m = model([high], recorder: recorder, preflight: { "Quit Foo first." })
    m.scan(); await waitWhileScanning(m)
    await m.clean()
    #expect(m.phase == .review)
    #expect(m.blockedReason == "Quit Foo first.")
    #expect(recorder.performed.isEmpty)
}

@Test @MainActor func cleanActsOnlyOnSelection() async {
    let recorder = Recorder()
    let m = model([high, low], recorder: recorder)
    m.scan(); await waitWhileScanning(m)
    m.toggle(high.id)
    m.toggle(low.id)
    #expect(m.selectedFindings == [low])
    await m.clean()
    #expect(recorder.performed == ["/tmp/low"])
}
