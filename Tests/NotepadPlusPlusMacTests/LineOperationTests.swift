import AppKit
import XCTest
@testable import NotepadPlusPlusMac

@MainActor
final class LineOperationTests: XCTestCase {
    /// Applies an operation to text with the selection marked by [ and ] (or | for a cursor).
    private func run(_ operation: LineOperation, _ marked: String) -> String {
        var text = marked
        var selection = NSRange(location: 0, length: 0)
        if let bar = text.range(of: "|") {
            selection.location = text.utf16.distance(from: text.startIndex, to: bar.lowerBound)
            text.removeSubrange(bar)
        } else if let open = text.range(of: "["), let close = text.range(of: "]") {
            let start = text.utf16.distance(from: text.startIndex, to: open.lowerBound)
            let end = text.utf16.distance(from: text.startIndex, to: close.lowerBound) - 1
            text.removeSubrange(close)
            text.removeSubrange(text.range(of: "[")!)
            selection = NSRange(location: start, length: end - start)
        }
        guard let edit = operation.edit(in: text, selection: selection) else { return "unchanged" }
        let result = NSMutableString(string: text)
        result.replaceCharacters(in: edit.range, with: edit.text)
        let after = edit.selection
        if after.length == 0 {
            result.insert("|", at: after.location)
        } else {
            result.insert("]", at: NSMaxRange(after))
            result.insert("[", at: after.location)
        }
        return result as String
    }

    func testDuplicateDeleteAndMove() {
        XCTAssertEqual(run(.duplicate, "a\nb|c\nd"), "a\nbc\nb|c\nd")
        XCTAssertEqual(run(.duplicate, "[a\nb]\nc"), "a\nb\n[a\nb]\nc")
        XCTAssertEqual(run(.duplicate, "only|"), "only\nonly|")
        XCTAssertEqual(run(.delete, "a\nb|\nc"), "a\n|c")
        XCTAssertEqual(run(.delete, "a\nb\nc|"), "a\nb|")
        XCTAssertEqual(run(.delete, "solo|"), "|")
        XCTAssertEqual(run(.delete, "a\n|\n"), "a\n|")
        XCTAssertEqual(run(.moveUp, "a\nb|\nc"), "b|\na\nc")
        XCTAssertEqual(run(.moveUp, "a|\nb"), "unchanged")
        XCTAssertEqual(run(.moveDown, "a|\nb\nc"), "b\na|\nc")
        XCTAssertEqual(run(.moveDown, "a\nb\nc|"), "unchanged")
        XCTAssertEqual(run(.moveDown, "[a\nb]\nc\n"), "c\n[a\nb]\n")
        XCTAssertEqual(run(.insertAbove, "a\nb|c"), "a\n|\nbc")
        XCTAssertEqual(run(.insertBelow, "a|b\nc"), "ab\n|\nc")
    }

    func testSelectionEndingAtLineStartLeavesThatLine() {
        XCTAssertEqual(run(.delete, "[a\n]b\nc"), "|b\nc")
    }

    func testJoin() {
        XCTAssertEqual(run(.join, "one|\n   two\nthree"), "one two|\nthree")
        XCTAssertEqual(run(.join, "[a\n\tb\nc]"), "a b c|")
        XCTAssertEqual(run(.join, "last|"), "unchanged")
    }

    func testSortingAndCleanupUseWholeFileWithoutSelection() {
        XCTAssertEqual(run(.sortAscending, "c\na\nB\nb|\n"), "[B\na\nb\nc]\n")
        XCTAssertEqual(run(.sortIgnoringCase, "c\nb\nA|"), "[A\nb\nc]")
        XCTAssertEqual(run(.sortDescending, "a\nc\nb|"), "[c\nb\na]")
        XCTAssertEqual(run(.reverse, "1\n2\n3|"), "[3\n2\n1]")
        XCTAssertEqual(run(.removeDuplicates, "a\nb\na\nb\nc|"), "[a\nb\nc]")
        XCTAssertEqual(run(.removeConsecutiveDuplicates, "a\na\nb\na|"), "[a\nb\na]")
        XCTAssertEqual(run(.removeEmpty, "a\n\n  \nb|"), "[a\n  \nb]")
        XCTAssertEqual(run(.removeBlank, "a\n\n \t\nb|"), "[a\nb]")
        XCTAssertEqual(run(.sortAscending, "a\nb|"), "unchanged")
    }

    func testSortOnlySelectedLines() {
        XCTAssertEqual(run(.sortAscending, "z\n[c\nb]\na"), "z\n[b\nc]\na")
    }

    func testTrimKeepsCarriageReturnsAndCursor() {
        XCTAssertEqual(run(.trimTrailing, "a  \nb\t|"), "a\nb|")
        XCTAssertEqual(run(.trimLeading, "  a\n\tb|"), "a\nb|")
        XCTAssertEqual(run(.trimBoth, " a \r\n|"), "a\r\n|")
    }

    func testUnicodeLines() {
        XCTAssertEqual(run(.moveDown, "😀 one|\ntwo"), "two\n😀 one|")
        XCTAssertEqual(run(.sortAscending, "é\ne\u{301}\na|"), "[a\né\ne\u{301}]")
    }

    func testEditorOperationIsOneUndo() {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "b\na\nc")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        state.updateSelection(for: id, to: NSRange(location: 0, length: 0))
        state.perform(.sortAscending)
        XCTAssertEqual(state.activeDocument?.content, "a\nb\nc")
        state.activeSession!.textView.undoManager?.undo()
        XCTAssertEqual(state.activeDocument?.content, "b\na\nc")
    }

    func testReadOnlyTabsAreLeftAlone() {
        let state = AppState()
        state.openReadOnly(title: "changes", text: "b\na", language: .diff)
        state.perform(.sortAscending)
        XCTAssertEqual(state.activeDocument?.content, "b\na")
    }

    func testMenuHasEveryOperation() throws {
        let delegate = AppDelegate(store: nil)
        let menu = MainMenu.make(target: delegate)
        let edit = try XCTUnwrap(menu.items.first { $0.title == "Edit" }?.submenu)
        let lines = try XCTUnwrap(edit.items.first { $0.title == "Line Operations" }?.submenu)
        let titles = lines.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(Set(titles), Set(LineOperation.allCases.map(\.rawValue)))
        XCTAssertEqual(lines.items.first { $0.title == "Duplicate Line" }?.keyEquivalent, "d")
    }
}

@MainActor
final class ChangeHistoryTests: XCTestCase {
    func testUnsavedThenSavedColors() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("notes.txt")
        try "one\ntwo\nthree\n".write(to: url, atomically: true, encoding: .utf8)

        let state = AppState()
        try state.open(url)
        let id = state.activeDocumentID!
        XCTAssertEqual(state.session(for: id)?.changeHistory, ChangeHistory())

        state.updateContent(for: id, newContent: "one\nTWO\nthree\nfour\n")
        state.updateDiff(id)
        XCTAssertEqual(state.session(for: id)?.changeHistory.unsaved, [1, 3])
        XCTAssertEqual(state.session(for: id)?.changeHistory.saved, [])

        try state.save(id, to: url)
        XCTAssertEqual(state.session(for: id)?.changeHistory.unsaved, [])
        XCTAssertEqual(state.session(for: id)?.changeHistory.saved, [1, 3])

        state.updateContent(for: id, newContent: "zero\none\nTWO\nthree\nfour\n")
        state.updateDiff(id)
        XCTAssertEqual(state.session(for: id)?.changeHistory.unsaved, [0])
        XCTAssertEqual(state.session(for: id)?.changeHistory.saved, [2, 4])

        state.toggleChangeHistory()
        XCTAssertEqual(state.session(for: id)?.changeHistory, ChangeHistory())
    }

    func testNewTabMarksTypedLines() {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "hello\nworld")
        state.updateDiff(id)
        XCTAssertEqual(state.session(for: id)?.changeHistory.unsaved, [0, 1])
    }
}

@MainActor
final class WindowBehaviorTests: XCTestCase {
    func testClosingTheWindowClosesFilesAndKeepsSlateRunning() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("a.txt")
        try "a".write(to: url, atomically: true, encoding: .utf8)

        let delegate = AppDelegate(store: nil)
        let state = delegate.state
        try state.open(url)
        state.createNewDocument()
        state.showInSplit(state.activeDocumentID!)
        // Nothing is unsaved, so no question is asked.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled, .closable],
                              backing: .buffered, defer: true)
        XCTAssertFalse(delegate.windowShouldClose(window))
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        XCTAssertTrue(state.isPristine)
        XCTAssertFalse(state.isSplit)
        XCTAssertEqual(state.activeDocument?.displayName, "Untitled 1")
    }

    func testDockClickDoesNotReopenAndNewUsesTheEmptyTab() {
        let delegate = AppDelegate(store: nil)
        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        XCTAssertFalse(delegate.isWindowVisible)
        delegate.state.closeAllDocuments()
        delegate.newFile()
        XCTAssertEqual(delegate.state.documents.count, 1)
        delegate.state.updateContent(for: delegate.state.activeDocumentID!, newContent: "x")
        delegate.newFile()
        XCTAssertEqual(delegate.state.documents.count, 2)
    }

    func testDockMenu() throws {
        let delegate = AppDelegate(store: nil)
        let menu = try XCTUnwrap(delegate.applicationDockMenu(NSApplication.shared))
        XCTAssertEqual(menu.items.map(\.title), ["New", "Open…", "Open Recent"])
        XCTAssertEqual(menu.items[2].submenu?.items.map(\.title), ["Clear Menu"])
        XCTAssertTrue(menu.items.prefix(2).allSatisfy { $0.target === delegate && $0.action != nil })
    }
}
