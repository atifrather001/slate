import AppKit
import SwiftTerm

/// The shell in the terminal panel. It starts the first time the panel opens and keeps running
/// while the panel is hidden, like VS Code's terminal; if it exits, the next show starts a new one.
@MainActor
final class TerminalController: NSObject, LocalProcessTerminalViewDelegate {
    private(set) var view: LocalProcessTerminalView?
    private(set) var isRunning = false
    var onTitleChange: ((String) -> Void)?

    /// The user's login shell, so their PATH, aliases and prompt work as in Terminal.
    static var shell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    /// The terminal view, with a shell running in the given folder.
    func start(in folder: URL, fontSize: CGFloat) -> LocalProcessTerminalView {
        let view = self.view ?? makeView()
        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if !isRunning {
            var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
            environment.append("TERM_PROGRAM=Slate")
            let shell = Self.shell
            // A leading dash makes it a login shell, which reads the user's profile.
            view.startProcess(executable: shell, args: [], environment: environment,
                              execName: "-" + (shell as NSString).lastPathComponent,
                              currentDirectory: folder.path)
            isRunning = true
        }
        return view
    }

    /// Changes the shell's folder by typing a cd command, as if the user had.
    func changeDirectory(to folder: URL) {
        guard isRunning, let view else { return }
        let quoted = "'" + folder.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        view.send(txt: " cd \(quoted)\r")
    }

    func setFontSize(_ size: CGFloat) {
        view?.font = .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func stop() {
        guard isRunning else { return }
        view?.terminate()
        isRunning = false
    }

    private func makeView() -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        view.processDelegate = self
        view.configureNativeColors()
        view.caretColor = .controlAccentColor
        self.view = view
        return view
    }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in self.onTitleChange?(title) }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in self.isRunning = false }
    }
}
