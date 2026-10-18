import SwiftUI
import MacCleanerCore
import SpruceKit

/// A tool screen driven by its model: start, scanning, review, cleaning, done.
struct ScanToolView: View {
    let tool: Tool
    @Bindable var model: ScanModel
    var showsPermissionNote = false
    /// Shown under the header, e.g. My Clutter's folder list.
    var accessory: AnyView? = nil
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 16) {
            ToolHeader(tool: tool)
            accessory
            content
            if showsPermissionNote { PermissionNote() }
        }
        .padding([.horizontal, .bottom], 20)
        .sheet(isPresented: $confirming) { ConfirmCleanSheet(model: model) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            Spacer()
            PillButton("Scan") { model.scan() }
            Spacer()
        case .scanning(let category):
            Spacer()
            ProgressView()
            Text(category.map { "Scanning \($0.title)…" } ?? "Starting…").foregroundStyle(.secondary)
            Button("Cancel") { model.cancel() }
            Spacer()
        case .review where model.findings.isEmpty:
            Spacer()
            Text("Nothing to clean.").font(.title3).foregroundStyle(.secondary)
            Button("Scan Again") { model.scan() }
            Spacer()
        case .review:
            FindingsView(model: model)
            HStack {
                Text("\(model.selectedFindings.count) selected · \(bytes(model.selectedBytes))")
                    .monospacedDigit().foregroundStyle(.secondary)
                if let reason = model.blockedReason { Text(reason).foregroundStyle(.orange) }
                Spacer()
                Button("Scan Again") { model.scan() }
                PillButton("Clean") { confirming = true }
                    .disabled(model.selectedFindings.isEmpty)
            }
        case .cleaning:
            Spacer()
            ProgressView("Checking nothing changed, then moving to the Trash…")
            Spacer()
        case .done(let summary):
            Spacer()
            Text("Moved \(bytes(summary.bytes)) to the Trash.").font(.title3)
            Text("Empty the Trash to get the space back.").foregroundStyle(.secondary)
            if !summary.failures.isEmpty { FailureList(failures: summary.failures) }
            PillButton("Scan Again") { model.scan() }
            Spacer()
        }
    }
}

struct FailureList: View {
    let failures: [CleanFailure]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Couldn't move \(failures.count) item\(failures.count == 1 ? "" : "s"):").font(.callout.bold())
            ForEach(failures, id: \.finding.id) { failure in
                Text("\(failure.finding.title): \(failure.message)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

/// The last look before anything moves: exactly the selected items, their total, and an explicit confirm.
struct ConfirmCleanSheet: View {
    let model: ScanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = model.selectedFindings
        VStack(alignment: .leading, spacing: 12) {
            Text("Move \(items.count) item\(items.count == 1 ? "" : "s") to the Trash?").font(.headline)
            List(items) { finding in
                HStack {
                    Text(finding.title).lineLimit(1)
                    Spacer()
                    Text(bytes(finding.size)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 160, maxHeight: 320)
            let permanent = items.filter(\.isPermanent).count
            Text(permanent == 0
                 ? "Total: \(bytes(model.selectedBytes)). Nothing is deleted until you empty the Trash."
                 : "Total: \(bytes(model.selectedBytes)). \(permanent) item\(permanent == 1 ? " is" : "s are") deleted permanently and can't be recovered. Everything else goes to the Trash.")
                .font(.callout).foregroundStyle(permanent == 0 ? Color.secondary : Color.red)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    dismiss()
                    Task { await model.clean() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
