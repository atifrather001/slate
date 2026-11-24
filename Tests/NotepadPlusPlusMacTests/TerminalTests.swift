import AppKit
import SwiftUI
import XCTest
@testable import NotepadPlusPlusMac

@MainActor
final class TerminalTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub dir's"),
                                                withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: folder)
    }

    /// The shell reports /private/var where Foundation says /var.
    private func resolved(_ shellPath: String) -> String {
        URL(fileURLWithPath: shellPath.trimmingCharacters(in: .newlines)).resolvingSymlinksInPath().path
    }

    /// Waits for the shell to write a file.
    private func waitForFile(_ url: URL, seconds: Double = 15) async -> String? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let text = try? String(contentsOf: url, encoding: .utf8), text.hasSuffix("\n") { return text }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }

    func testShellStartsInTheFileFolderAndFollowsCd() async throws {
        let controller = TerminalController()
        let view = controller.start(in: folder, fontSize: 13)
        XCTAssertTrue(controller.isRunning)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        view.send(txt: "pwd > where.txt\r")
        let first = await waitForFile(folder.appendingPathComponent("where.txt"))
        XCTAssertEqual(first.map(resolved), folder.path)

        // A folder name with a space and a quote is passed safely.
        let sub = folder.appendingPathComponent("sub dir's")
        controller.changeDirectory(to: sub)
        view.send(txt: "pwd > where.txt\r")
        let second = await waitForFile(sub.appendingPathComponent("where.txt"))
        XCTAssertEqual(second.map(resolved), sub.path)

        controller.stop()
        XCTAssertFalse(controller.isRunning)
    }

    func testPanelToggleAndFolder() throws {
        let state = AppState()
        XCTAssertFalse(state.showsTerminal)
        XCTAssertEqual(state.terminalFolder, FileManager.default.homeDirectoryForCurrentUser)
        let file = folder.appendingPathComponent("a.txt")
        try "a".write(to: file, atomically: true, encoding: .utf8)
        try state.open(file)
        XCTAssertEqual(state.terminalFolder.resolvingSymlinksInPath().path, folder.path)
        state.toggleTerminal()
        XCTAssertTrue(state.showsTerminal)
        state.toggleTerminal()
        XCTAssertFalse(state.showsTerminal)
        XCTAssertFalse(state.terminal.isRunning, "no shell until the panel is shown")
    }

    func testTerminalMenu() throws {
        let delegate = AppDelegate(store: nil)
        let menu = MainMenu.make(target: delegate)
        let view = try XCTUnwrap(menu.items.first { $0.title == "View" }?.submenu)
        let item = try XCTUnwrap(view.items.first { $0.title == "Terminal" })
        XCTAssertEqual(item.keyEquivalent, "`")
        XCTAssertEqual(item.keyEquivalentModifierMask, .control)
    }
}

@MainActor
final class TerminalFocusTests: XCTestCase {
    func testOpeningTheTerminalPutsTheKeyboardThere() async throws {
        let state = AppState()
        // Never ordered in, so nothing appears on screen.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ContentView(state: state, files: FileActions(state: state)))
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(window.firstResponder === state.activeSession?.textView, "the text has the keyboard at first")

        state.toggleTerminal()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertTrue(window.firstResponder === state.terminal.view, "the terminal takes the keyboard when shown")

        // Clicking back into the text keeps the keyboard there.
        window.makeFirstResponder(state.activeSession?.textView)
        state.zoom(by: 1)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(window.firstResponder === state.activeSession?.textView)

        state.toggleTerminal()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(window.firstResponder === state.activeSession?.textView, "hiding returns the keyboard to the text")

        state.toggleTerminal()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertTrue(window.firstResponder === state.terminal.view, "and showing it again moves it back")
        state.terminal.stop()
    }
}
