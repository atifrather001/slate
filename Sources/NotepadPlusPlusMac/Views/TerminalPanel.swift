import SwiftTerm
import SwiftUI

/// The terminal at the bottom of the window.
struct TerminalPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                Text(state.terminalTitle.isEmpty ? "Terminal" : state.terminalTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    state.openTerminalInFileFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Go to the current file's folder (⌃⇧`)")
                Button(action: state.toggleTerminal) {
                    Image(systemName: "xmark")
                }
                .help("Hide the terminal (⌃`); it keeps running")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            TerminalHost(state: state)
        }
    }
}

private struct TerminalHost: NSViewRepresentable {
    let state: AppState

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.clipsToBounds = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let terminal = state.terminal.start(in: state.terminalFolder, fontSize: state.fontSize)
        guard terminal.superview !== container else { return }
        terminal.removeFromSuperview()
        terminal.frame = container.bounds
        terminal.autoresizingMask = [.width, .height]
        container.addSubview(terminal)
        DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
    }
}
