import SwiftUI
import MacCleanerCore

/// A calm inline note when macOS hides sandboxed apps' data from Spruce. Never a modal, never repeated as an alert.
struct PermissionNote: View {
    @State private var blocked = false

    var body: some View {
        Group {
            if blocked {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    Text("Sandboxed apps were skipped because Spruce doesn't have Full Disk Access.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
                .font(.callout)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .task { blocked = !canReadContainers(home: FileManager.default.homeDirectoryForCurrentUser) }
    }
}
