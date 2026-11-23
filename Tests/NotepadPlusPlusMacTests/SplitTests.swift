import AppKit
import XCTest
@testable import NotepadPlusPlusMac

@MainActor
final class SplitTests: XCTestCase {
    func testSameTabInBothPanesSharesTextAndUndo() throws {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "hello")
        state.showInSplit(id)
        let session = try XCTUnwrap(state.session(for: id))
        let second = try XCTUnwrap(session.secondary)
        XCTAssertEqual(second.textView.string, "hello")

        // Undo groups close when the run loop turns, as they do between key presses.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        second.textView.setSelectedRange(NSRange(location: 5, length: 0))
        second.textView.insertText(" world", replacementRange: NSRange(location: 5, length: 0))
        XCTAssertEqual(session.primary.textView.string, "hello world")
        XCTAssertEqual(state.documents[id]?.content, "hello world")
        XCTAssertTrue(state.documents[id]!.isModified)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        session.primary.textView.undoManager?.undo()
        XCTAssertEqual(second.textView.string, "hello")
        XCTAssertEqual(state.documents[id]?.content, "hello")
    }

    func testCommandsFollowTheFocusedPane() throws {
        let state = AppState()
        let left = state.activeDocumentID!
        state.updateContent(for: left, newContent: "left")
        state.createNewDocument()
        let right = state.activeDocumentID!
        state.updateContent(for: right, newContent: "right x")
        state.setActiveDocument(left)
        state.showInSplit(right)

        XCTAssertTrue(state.splitFocused)
        XCTAssertEqual(state.focusedDocumentID, right)
        XCTAssertEqual(state.activeDocumentID, left)
        state.findText = "x"
        state.findNext()
        XCTAssertEqual(state.documents[right]?.selectionRange, NSRange(location: 6, length: 1))
        state.setLanguage(.python)
        XCTAssertEqual(state.documents[right]?.language, .python)
        XCTAssertEqual(state.documents[left]?.language, .plainText)

        state.focusMainPane()
        XCTAssertEqual(state.focusedDocumentID, left)
        state.goTo(line: 1)
        XCTAssertEqual(state.activeSession?.textView, state.session(for: left)?.primary.textView)
    }

    func testFocusingAPaneUpdatesFocus() throws {
        let state = AppState()
        let id = state.activeDocumentID!
        state.showInSplit(id)
        let session = try XCTUnwrap(state.session(for: id))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: true)
        let host = NSView(frame: window.contentView!.bounds)
        window.contentView = host
        host.addSubview(session.primary.scrollView)
        host.addSubview(session.secondary!.scrollView)
        XCTAssertTrue(window.makeFirstResponder(session.primary.textView))
        XCTAssertFalse(state.splitFocused)
        XCTAssertTrue(window.makeFirstResponder(session.secondary!.textView))
        XCTAssertTrue(state.splitFocused)
    }

    func testSwitchingAndClosingSplit() throws {
        let state = AppState()
        let first = state.activeDocumentID!
        state.createNewDocument()
        let second = state.activeDocumentID!
        state.showInSplit(first)
        XCTAssertNotNil(state.session(for: first)?.secondary)
        state.showInSplit(second)
        XCTAssertNil(state.session(for: first)?.secondary)
        XCTAssertNotNil(state.session(for: second)?.secondary)

        state.removeDocument(second)
        XCTAssertFalse(state.isSplit)
        XCTAssertFalse(state.splitFocused)

        state.toggleSplit()
        XCTAssertEqual(state.splitDocumentID, state.activeDocumentID)
        state.toggleSplit()
        XCTAssertFalse(state.isSplit)
        XCTAssertNil(state.activeSession?.secondary)
    }

    func testSecondPaneGetsColorsAndZoom() async throws {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "// note\nlet a = \"x\"\n")
        state.setLanguage(.swift, for: id)
        state.zoom(by: 2)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        state.showInSplit(id)
        let pane = try XCTUnwrap(state.session(for: id)?.secondary)
        XCTAssertEqual(pane.textView.font?.pointSize, 15)
        let colored = (0..<pane.textView.string.utf16.count).contains {
            pane.textView.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: $0, effectiveRange: nil) != nil
        }
        XCTAssertTrue(colored)
    }
}
