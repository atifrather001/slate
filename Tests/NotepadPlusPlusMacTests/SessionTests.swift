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
