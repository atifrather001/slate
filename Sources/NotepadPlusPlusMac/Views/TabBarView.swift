import SwiftUI

struct TabBarView: View {
    @ObservedObject var state: AppState
    let files: FileActions

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(state.documents.values)) { document in
                        tab(document)
                    }
                }
                .padding(4)
            }
            Button(action: state.createNewDocument) {
                Image(systemName: "plus").frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("New File (⌘N)")
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tab(_ document: Document) -> some View {
        let active = document.id == state.activeDocumentID
        return HStack(spacing: 6) {
            Button {
                state.setActiveDocument(document.id)
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(document.isModified ? Color.orange : Color.clear)
                        .frame(width: 6, height: 6)
                    Text(document.displayName).lineLimit(1)
                }
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            Button {
                files.close(document.id)
            } label: {
                Image(systemName: "xmark").font(.caption).frame(width: 18, height: 26).contentShape(Rectangle())
            }
            .accessibilityLabel("Close \(document.displayName)")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 4).fill(active ? Color.accentColor.opacity(0.22) : Color.clear))
        .help(document.fileURL?.path ?? document.displayName)
        .contextMenu {
            Button("Open in Split View") { state.showInSplit(document.id) }
            Button("Close Tab") { files.close(document.id) }
        }
    }
}
