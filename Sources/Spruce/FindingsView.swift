import SwiftUI
import MacCleanerCore
import SpruceKit

func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

/// Findings grouped by category. ✓ rows start checked, ○ rows start unchecked, report-only rows have no checkbox.
struct FindingsView: View {
    @Bindable var model: ScanModel

    private var groups: [(category: MacCleanerCore.Category, findings: [Finding])] {
        var order: [MacCleanerCore.Category] = []
        var byCategory: [MacCleanerCore.Category: [Finding]] = [:]
        for finding in model.findings {
            if byCategory[finding.category] == nil { order.append(finding.category) }
            byCategory[finding.category, default: []].append(finding)
        }
        return order.map { ($0, byCategory[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.category) { group in
                Section {
                    ForEach(group.findings) { FindingRow(finding: $0, model: model) }
                } header: {
                    HStack {
                        Text(group.category.title)
                        Spacer()
                        Text(bytes(group.findings.reduce(0) { $0 + $1.size })).monospacedDigit()
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
