import AppKit
import XCTest
@testable import NotepadPlusPlusMac

@MainActor
final class MacroTests: XCTestCase {
    private func type(_ text: String, into textView: NSTextView) {
        for character in text { textView.insertText(String(character), replacementRange: textView.selectedRange()) }
    }

    func testRecordAndPlayBackOnEachLine() {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "alpha\nbeta\ngamma")
        state.updateSelection(for: id, to: NSRange(location: 0, length: 0))
        let textView = state.activeSession!.textView

        state.startRecordingMacro()
        type("- ", into: textView)
        textView.doCommand(by: #selector(NSResponder.moveDown(_:)))
        textView.doCommand(by: #selector(NSResponder.moveToBeginningOfLine(_:)))
        state.stopRecordingMacro()
        XCTAssertEqual(state.recordedMacro, [.insert("- "), .command("moveDown:"), .command("moveToBeginningOfLine:")])

        state.playRecordedMacro(times: 2)
        XCTAssertEqual(state.activeDocument?.content, "- alpha\n- beta\n- gamma")
    }

    func testOneUndoReversesThePlayback() {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "x")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        state.updateSelection(for: id, to: NSRange(location: 1, length: 0))
        let textView = state.activeSession!.textView
        state.startRecordingMacro()
        type("ab", into: textView)
        state.stopRecordingMacro()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        state.playRecordedMacro(times: 3)
        XCTAssertEqual(state.activeDocument?.content, "xabababab")
        textView.undoManager?.undo()
        XCTAssertEqual(state.activeDocument?.content, "xab")
    }

    func testOnlyEditingCommandsAreRecordedAndPlayed() {
        XCTAssertTrue(MacroAction.isRecordable("deleteBackward:"))
        XCTAssertTrue(MacroAction.isRecordable("insertNewline:"))
        XCTAssertFalse(MacroAction.isRecordable("terminate:"))
        XCTAssertFalse(MacroAction.isRecordable("performClose:"))
        XCTAssertFalse(MacroAction.isRecordable("moveDown"))

        let state = AppState()
        let textView = state.activeSession!.textView
        state.startRecordingMacro()
        textView.doCommand(by: Selector(("noSuchCommand:")))
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        state.stopRecordingMacro()
        XCTAssertEqual(state.recordedMacro, [.command("insertNewline:")])
        state.play([.command("terminate:"), .insert("ok")])
        XCTAssertEqual(state.activeDocument?.content, "\nok")
    }

    func testPlaybackIsNotRecordedAndPlayIsOffWhileRecording() {
        let state = AppState()
        let textView = state.activeSession!.textView
        state.startRecordingMacro()
        state.play([.insert("ignored")])
        XCTAssertEqual(state.activeDocument?.content, "")
        type("a", into: textView)
        state.stopRecordingMacro()
        XCTAssertEqual(state.recordedMacro, [.insert("a")])
    }

    func testSavedMacrosPersistAndDelete() throws {
        let suite = "SlateTests"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        let state = AppState(store: store)
        state.startRecordingMacro()
        type("hi", into: state.activeSession!.textView)
        state.stopRecordingMacro()
        state.saveRecordedMacro(named: "  Greet ")
        state.saveRecordedMacro(named: "")
        let reloaded = AppState(store: store)
        XCTAssertEqual(reloaded.savedMacros.map(\.name), ["Greet"])
        reloaded.play(reloaded.savedMacros[0].actions)
        XCTAssertEqual(reloaded.activeDocument?.content, "hi")
        reloaded.deleteMacro(reloaded.savedMacros[0].id)
        XCTAssertTrue(AppState(store: store).savedMacros.isEmpty)
    }

    func testMacroMenu() throws {
        let delegate = AppDelegate(store: nil)
        let menu = MainMenu.make(target: delegate)
        let macro = try XCTUnwrap(menu.items.first { $0.title == "Macro" }?.submenu)
        let record = try XCTUnwrap(macro.items.first)
        XCTAssertEqual(record.keyEquivalent, "r")
        XCTAssertFalse(delegate.validateMenuItem(macro.items[1]), "nothing to play yet")
        _ = delegate.validateMenuItem(record)
        XCTAssertEqual(record.title, "Start Recording")
        NSApplication.shared.sendAction(record.action!, to: record.target, from: record)
        _ = delegate.validateMenuItem(record)
        XCTAssertEqual(record.title, "Stop Recording")
        let saved = try XCTUnwrap(macro.items.first { $0.title == MainMenu.savedMacrosTitle }?.submenu)
        delegate.menuNeedsUpdate(saved)
        XCTAssertEqual(saved.items.map(\.title), ["No Saved Macros"])
    }
}
