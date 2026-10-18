import SwiftUI
import MacCleanerCore
import SpruceKit

func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

/// Findings grouped by category. ✓ rows start checked, ○ rows start unchecked, report-only rows have no checkbox.
struct FindingsView: View {
    @Bindable var model: ScanModel

    /// One section per category, except that grouped findings (copies of one file, similar photos) get a section per group.
    private var sections: [(id: String, title: String, findings: [Finding])] {
        var order: [String] = []
        var byKey: [String: [Finding]] = [:]
        for finding in model.findings {
            let key = finding.group ?? finding.category.rawValue
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(finding)
        }
        return order.map { key in
            let items = byKey[key] ?? []
            guard let first = items.first, first.group != nil else { return (key, items.first?.category.title ?? "", items) }
            let title = first.category == .duplicates ? "\(first.title) \u{00B7} \(items.count) copies" : "\(items.count) similar photos"
            return (key, title, items)
        }
    }

    var body: some View {
        List {
            ForEach(sections, id: \.id) { section in
                Section {
                    ForEach(section.findings) { FindingRow(finding: $0, model: model) }
                } header: {
                    HStack {
                        Text(section.title).lineLimit(1)
                        Spacer()
                        // A group's kept copy isn't space you can get back, so only the others count.
                        let counted = section.findings.first?.group == nil ? section.findings : section.findings.filter(\.isActionable)
                        Text(bytes(counted.reduce(0) { $0 + $1.size })).monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

private struct FindingRow: View {
    let finding: Finding
    let model: ScanModel

    var body: some View {
        HStack(spacing: 10) {
            if finding.isActionable {
                Toggle("", isOn: Binding(get: { model.selection.contains(finding.id) }, set: { _ in model.toggle(finding.id) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            } else if finding.group != nil {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green).frame(width: 14)
                    .help("Kept. Spruce never selects this copy, so one always stays.")
            } else {
                Image(systemName: "eye").foregroundStyle(.tertiary).frame(width: 14).help("Listed only. Spruce never cleans this.")
            }
            // Clicking the text toggles too. The gesture sits beside the checkbox, never around it,
            // so one click can't reach both and cancel itself out.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(finding.title).lineLimit(1)
                        if finding.isPermanent {
                            Text("Permanent").font(.caption2.bold()).foregroundStyle(.red)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.red.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(finding.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(bytes(finding.size)).monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.toggle(finding.id) }
        }
    }
}
