import SwiftUI

struct ContentView: View {
    @ObservedObject var state: AppState
    let files: FileActions

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(state: state, files: files)
            Divider()
            if state.findPanelVisible {
                FindReplaceBar(state: state)
                Divider()
            }
            if state.showsTerminal {
                VSplitView {
                    editors
                        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
                    TerminalPanel(state: state)
                        .frame(minHeight: 80, idealHeight: 220)
                }
            } else {
                editors
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            StatusBar(state: state)
        }
        // Files dropped outside the text, such as on the tab bar or status bar, open as tabs.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            openDropped(providers)
            return true
        }
    }

    private func openDropped(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    if let url, url.isFileURL { urls.append(url) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            let files = urls.filter { !(((try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) ?? false) }
            if !files.isEmpty { state.openDroppedFiles?(files) }
        }
    }

    @ViewBuilder private var editors: some View {
        if let id = state.splitDocumentID, let split = state.session(for: id)?.secondary {
            if state.splitVertically {
                VSplitView {
                    mainEditor
                    SplitPaneView(state: state, pane: split)
                }
            } else {
                HSplitView {
                    mainEditor
                    SplitPaneView(state: state, pane: split)
                }
            }
        } else {
            mainEditor
        }
    }

    @ViewBuilder private var mainEditor: some View {
        if let id = state.activeDocumentID, let session = state.session(for: id) {
            EditorView(pane: session.primary, takesFocus: !state.splitFocused)
                .overlay(alignment: .top) { focusMark(!state.splitFocused) }
                .frame(minWidth: 200, minHeight: 120)
        }
    }

    /// A thin accent line on the pane with focus, shown only when split.
    private func focusMark(_ focused: Bool) -> some View {
        Rectangle()
            .fill(state.isSplit && focused ? Color.accentColor : Color.clear)
            .frame(height: 2)
    }
}

/// The second pane, with a header for choosing which tab it shows.
struct SplitPaneView: View {
    @ObservedObject var state: AppState
    let pane: EditorPane

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Menu(state.documents[state.splitDocumentID ?? UUID()]?.displayName ?? "") {
                    ForEach(Array(state.documents.values)) { document in
                        Button(document.displayName) { state.showInSplit(document.id) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Button {
                    state.splitVertically.toggle()
                } label: {
                    Image(systemName: state.splitVertically ? "rectangle.split.2x1" : "rectangle.split.1x2")
                }
                .help(state.splitVertically ? "Split side by side" : "Split top and bottom")
                Button(action: state.closeSplit) {
                    Image(systemName: "xmark")
                }
                .help("Close split (⌘\\)")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .top) {
                Rectangle().fill(state.splitFocused ? Color.accentColor : Color.clear).frame(height: 2)
            }
            Divider()
            EditorView(pane: pane, takesFocus: state.splitFocused)
        }
        .frame(minWidth: 200, minHeight: 120)
    }
}
