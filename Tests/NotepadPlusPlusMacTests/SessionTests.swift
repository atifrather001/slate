import AppKit
import XCTest
@testable import NotepadPlusPlusMac

@MainActor
final class SessionTests: XCTestCase {
    private var folder: URL!
    private var store: UserDefaults!
    // One fixed name, emptied after each test, so test runs don't pile up settings files.
    private let suite = "SlateTests"

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        store.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, _ text: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testGoToLineClamps() {
        let state = AppState()
        state.updateContent(for: state.activeDocumentID!, newContent: "a\r\nbb\ncc\n")
        // Lines start at 0, 3 (after CRLF), 6 and 9 (the empty last line).
        state.goTo(line: 3)
        XCTAssertEqual(state.activeDocument?.selectionRange.location, 6)
        state.goTo(line: 99)
        XCTAssertEqual(state.activeDocument?.selectionRange.location, 9)
        state.goTo(line: -4)
        XCTAssertEqual(state.activeDocument?.selectionRange.location, 0)
    }

    func testZoomAppliesToEveryTabAndIsRemembered() {
        let state = AppState(store: store)
        state.createNewDocument()
        state.zoom(by: 3)
        XCTAssertEqual(state.fontSize, 16)
        XCTAssertEqual(state.activeSession?.textView.font?.pointSize, 16)
        state.selectPreviousTab()
        XCTAssertEqual(state.activeSession?.textView.font?.pointSize, 16)
        for _ in 0..<100 { state.zoom(by: 1) }
        XCTAssertEqual(state.fontSize, AppState.fontSizes.upperBound)
        XCTAssertEqual(AppState(store: store).fontSize, AppState.fontSizes.upperBound)
        state.resetZoom()
        XCTAssertEqual(AppState(store: store).activeSession?.textView.font?.pointSize, 13)
    }

    func testRecentFilesNewestFirstWithoutDuplicates() throws {
        let state = AppState(store: store)
        let a = try file("a.txt", "a"), b = try file("b.txt", "b")
        try state.open(a)
        try state.open(b)
        try state.open(a)
        XCTAssertEqual(state.recentFiles.map(\.lastPathComponent), ["a.txt", "b.txt"])
        XCTAssertEqual(AppState(store: store).recentFiles.map(\.lastPathComponent), ["a.txt", "b.txt"])
        state.clearRecentFiles()
        XCTAssertTrue(AppState(store: store).recentFiles.isEmpty)
    }

    func testSaveAsAddsToRecentFiles() throws {
        let state = AppState(store: store)
        try state.save(state.activeDocumentID!, to: folder.appendingPathComponent("new.md"))
        XCTAssertEqual(state.recentFiles.first?.lastPathComponent, "new.md")
    }

    func testReopensTabsWithActiveTabAndCursor() throws {
        let first = AppState(store: store)
        let a = try file("a.swift", "let a = 1\nlet b = 2\n"), b = try file("b.py", "pass\n")
        let gone = try file("gone.txt", "x")
        try first.open(a)
        first.activeSession?.select(NSRange(location: 12, length: 0))
        try first.open(gone)
        try first.open(b)
        first.createNewDocument()
        first.setActiveDocument(first.documents.values.first { $0.fileURL == a }!.id)
        first.saveOpenTabs()
        try FileManager.default.removeItem(at: gone)

        let second = AppState(store: store)
        second.reopenTabs()
        XCTAssertEqual(second.documents.values.map(\.displayName), ["a.swift", "b.py"])
        XCTAssertEqual(second.activeDocument?.displayName, "a.swift")
        XCTAssertEqual(second.activeDocument?.selectionRange.location, 12)
    }

    func testNoStoreKeepsNothing() throws {
        let state = AppState()
        try state.open(file("a.txt", "a"))
        state.saveOpenTabs()
        let other = AppState()
        other.reopenTabs()
        XCTAssertEqual(other.documents.count, 1)
        XCTAssertEqual(other.activeDocument?.fileURL, nil)
    }

    func testMenusHaveNewCommands() throws {
        let delegate = AppDelegate(store: nil)
        let menu = MainMenu.make(target: delegate)
        func item(_ path: [String]) -> NSMenuItem? {
            var items = menu.items
            var found: NSMenuItem?
            for title in path {
                found = items.first { $0.title == title }
                items = found?.submenu?.items ?? []
            }
            return found
        }
        XCTAssertEqual(item(["Edit", "Go to Line…"])?.keyEquivalent, "l")
        XCTAssertEqual(item(["View", "Zoom In"])?.keyEquivalent, "=")
        XCTAssertEqual(item(["View", "Zoom Out"])?.keyEquivalent, "-")
        XCTAssertEqual(item(["View", "Actual Size"])?.keyEquivalent, "0")
        let recent = try XCTUnwrap(item(["File", "Open Recent"])?.submenu)
        delegate.menuNeedsUpdate(recent)
        XCTAssertEqual(recent.items.map(\.title), ["Clear Menu"])
        XCTAssertFalse(delegate.validateMenuItem(recent.items[0]))
    }
}

@MainActor
final class UntitledNumberTests: XCTestCase {
    private func names(_ state: AppState) -> [String] { state.documents.values.map(\.displayName) }

    func testClosingTheOnlyUntitledTabDoesNotCountUp() {
        let state = AppState()
        for _ in 0..<12 { state.removeDocument(state.activeDocumentID!) }
        XCTAssertEqual(names(state), ["Untitled 1"])
    }

    func testReusesTheLowestFreeNumber() throws {
        let state = AppState()
        state.createNewDocument()
        state.createNewDocument()
        XCTAssertEqual(names(state), ["Untitled 1", "Untitled 2", "Untitled 3"])
        let second = state.documents.values.first { $0.displayName == "Untitled 2" }!.id
        state.removeDocument(second)
        state.createNewDocument()
        XCTAssertEqual(state.activeDocument?.displayName, "Untitled 2")
        state.createNewDocument()
        XCTAssertEqual(state.activeDocument?.displayName, "Untitled 4")
    }

    func testOpeningFilesAndReadOnlyTabsDoNotUseNumbers() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("a.txt")
        try "a".write(to: url, atomically: true, encoding: .utf8)

        let state = AppState()
        try state.open(url)                 // replaces the empty Untitled 1
        state.openReadOnly(title: "changes", text: "", language: .diff)
        state.createNewDocument()
        XCTAssertEqual(state.activeDocument?.displayName, "Untitled 1")
        state.closeAllDocuments()
        state.createNewDocument()
        XCTAssertEqual(names(state), ["Untitled 1", "Untitled 2"])
    }
}

@MainActor
final class DropTests: XCTestCase {
    func testDroppedFinderFilesOpenAsTabs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let csv = folder.appendingPathComponent("data.csv"), txt = folder.appendingPathComponent("notes.txt")
        try "a,b\n1,2\n".write(to: csv, atomically: true, encoding: .utf8)
        try "hello".write(to: txt, atomically: true, encoding: .utf8)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SlateDropTest-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([csv as NSURL, txt as NSURL, folder.appendingPathComponent("sub") as NSURL])
        XCTAssertEqual(EditorTextView.droppedFiles(on: pasteboard).map(\.lastPathComponent), ["data.csv", "notes.txt"])

        let delegate = AppDelegate(store: nil)
        let state = delegate.state
        state.updateContent(for: state.activeDocumentID!, newContent: "keep me")
        let textView = state.activeSession!.textView
        XCTAssertTrue(textView.openDroppedFiles(from: pasteboard))
        XCTAssertEqual(state.documents.values.map(\.displayName), ["Untitled 1", "data.csv", "notes.txt"])
        XCTAssertEqual(state.documents.values.first?.content, "keep me", "no path pasted into the text")
    }

    func testPlainTextDragsStillGoToTheEditor() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SlateDropTest-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("some text", forType: .string)
        let state = AppState()
        XCTAssertFalse(state.activeSession!.textView.openDroppedFiles(from: pasteboard))
    }
}
