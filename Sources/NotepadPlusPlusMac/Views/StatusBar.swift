import SwiftUI

struct StatusBar: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 16) {
            if let activity = state.gitActivity {
                ProgressView().controlSize(.mini)
                Text(activity)
            }
            if state.isRecordingMacro {
                Label("Recording macro", systemImage: "record.circle")
                    .foregroundStyle(.red)
            }
            if let document = state.focusedDocument, let session = state.activeSession {
                let cursor = session.cursorPosition(at: document.selectionRange.location)
                Text("Ln \(cursor.line), Col \(cursor.column)")
                Text("\(session.lineStarts.count) lines")
                if let git = state.git[document.id] {
                    Label(git.branch, systemImage: "arrow.triangle.branch")
                        .help("Git branch")
                    if git.committedText == nil {
                        Text("Not committed").foregroundStyle(.secondary)
                    } else if let diff = session.gitDiff, !diff.isEmpty {
                        HStack(spacing: 6) {
                            if diff.added > 0 { Text("+\(diff.added)").foregroundStyle(.green) }
                            if diff.modified > 0 { Text("~\(diff.modified)").foregroundStyle(.blue) }
                            if diff.deleted > 0 { Text("−\(diff.deleted)").foregroundStyle(.red) }
                        }
                        .help("Lines added, changed and deleted since the last commit")
                    }
                }
                Spacer()
                Text(document.lineEnding.rawValue)
                Text(document.encoding.rawValue)
                Picker("Language", selection: Binding(
                    get: { document.language },
                    set: { state.setLanguage($0, for: document.id) }
                )) {
                    ForEach(Language.menuOrder) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
