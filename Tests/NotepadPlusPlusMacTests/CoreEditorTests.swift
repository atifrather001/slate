import AppKit
import Highlightr
import XCTest
@testable import NotepadPlusPlusMac

@MainActor
final class CoreEditorTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, _ data: Data) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testSavingUneditedFilesPreservesEveryByte() throws {
        let samples: [Data] = [
            Data(), Data("a\nb\n".utf8), Data("a\r\nb\r\n".utf8), Data("a\rb\r".utf8),
            Data("a\r\nb\nc\rd".utf8), Data("\r\r\n".utf8), Data("e\u{301} café 😀".utf8),
            Data([0xEF, 0xBB, 0xBF]) + Data("bom\r\n".utf8),
            Data([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, 0x61]),
            Data([0xFF, 0xFE]) + "hi\r\n".data(using: .utf16LittleEndian)!,
            Data([0xFE, 0xFF]) + "hi\n".data(using: .utf16BigEndian)!,
            Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x80]), Data([0x81, 0x8D, 0xE9]),
        ] + (1...255).map { Data([0x61, UInt8($0), 0x62]) }

        for (index, bytes) in samples.enumerated() {
            let state = AppState()
            let url = try file("sample\(index)", bytes)
            try state.open(url)
            XCTAssertFalse(state.activeDocument!.isModified)
            try state.save(state.activeDocumentID!, to: url)
            XCTAssertEqual(try Data(contentsOf: url), bytes, "sample \(index)")
        }
    }

    func testEditedCRLFFileStaysCRLF() throws {
        let state = AppState()
        let url = try file("windows.txt", Data("a\r\nb".utf8))
        try state.open(url)
        state.activeSession!.replace(NSRange(location: 3, length: 0), with: "\nc\r\nd")
        try state.save(state.activeDocumentID!, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a\r\nb\r\nc\r\nd")
    }

    func testBinaryFileIsRefused() throws {
        let state = AppState()
        XCTAssertThrowsError(try state.open(file("binary", Data([1, 0, 2]))))
        XCTAssertEqual(state.documents.count, 1)
    }

    func testUnencodableSaveLeavesFileUntouched() throws {
        let original = Data([0x63, 0x61, 0x66, 0xE9])
        let state = AppState()
        let url = try file("old.txt", original)
        try state.open(url)
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "日本")
        XCTAssertThrowsError(try state.save(id, to: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
        state.setEncoding(.utf8, for: id)
        try state.save(id, to: url)
        XCTAssertEqual(try Data(contentsOf: url), Data("日本".utf8))
        XCTAssertFalse(state.activeDocument!.isModified)
    }

    func testSaveKeepsSymlinkAndPermissions() throws {
        let target = try file("target.sh", Data("echo a\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        let link = folder.appendingPathComponent("link.sh")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let state = AppState()
        try state.open(link)
        state.updateContent(for: state.activeDocumentID!, newContent: "echo b\n")
        try state.save(state.activeDocumentID!, to: link)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "echo b\n")
        XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: link.path))
        let mode = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o755)
    }

    func testChangeByAnotherAppIsDetected() throws {
        let state = AppState()
        let url = try file("shared.txt", Data("mine".utf8))
        try state.open(url)
        XCTAssertFalse(state.hasChangedOnDisk(state.activeDocumentID!))
        try Data("theirs".utf8).write(to: url)
        XCTAssertTrue(state.hasChangedOnDisk(state.activeDocumentID!))
    }

    func testSaveAsSetsNameAndLanguage() throws {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "let a = 1")
        try state.save(id, to: folder.appendingPathComponent("new.swift"))
        XCTAssertEqual(state.activeDocument?.displayName, "new.swift")
        XCTAssertEqual(state.activeDocument?.language, .swift)
        XCTAssertFalse(state.activeDocument!.isModified)
    }

    func testOpeningReusesEmptyTabAndDoesNotDuplicate() throws {
        let state = AppState()
        let first = try file("a.py", Data("pass".utf8))
        try state.open(first)
        try state.open(first)
        XCTAssertEqual(state.documents.count, 1)
        try state.open(file("b.txt", Data("b".utf8)))
        XCTAssertEqual(state.documents.count, 2)
    }

    func testClosingTabs() {
        let state = AppState()
        let first = state.activeDocumentID!
        state.createNewDocument()
        let second = state.activeDocumentID!
        state.removeDocument(second)
        XCTAssertEqual(state.activeDocumentID, first)
        state.removeDocument(first)
        XCTAssertEqual(state.documents.count, 1)
        XCTAssertNotEqual(state.activeDocumentID, first)
    }

    func testUnicodeNormalizationCountsAsEdit() {
        let state = AppState()
        state.updateContent(for: state.activeDocumentID!, newContent: "é")
        var document = state.activeDocument!
        document.savedContent = "e\u{301}"
        XCTAssertTrue(document.isModified)
    }

    func testEachTabHasItsOwnUndo() {
        let state = AppState()
        let first = state.activeDocumentID!
        state.updateContent(for: first, newContent: "one")
        let firstView = state.activeSession!.textView
        state.createNewDocument()
        state.updateContent(for: state.activeDocumentID!, newContent: "two")
        firstView.undoManager?.undo()
        XCTAssertEqual(state.documents[first]?.content, "")
        XCTAssertEqual(state.activeDocument?.content, "two")
        firstView.undoManager?.redo()
        XCTAssertEqual(state.documents[first]?.content, "one")
    }

    func testSearchOptions() {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "Cat cat category")
        state.findText = "cat"
        state.replaceText = "$1"
        state.findOptions.caseSensitive = true
        state.findOptions.wholeWord = true
        state.replaceAll()
        XCTAssertEqual(state.activeDocument?.content, "Cat $1 category")
    }

    func testRegexReplacement() {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "a=1\nb=2")
        state.findOptions.regex = true
        state.findText = #"^(\w)=(\d)"#
        state.replaceText = #"$2\n$1"#
        state.replaceAll()
        XCTAssertEqual(state.activeDocument?.content, "1\na\n2\nb")
    }

    func testTrailingBackslashReplacement() {
        let search = TextSearch(query: "x", replacement: "y\\", options: FindOptions(regex: true))!
        XCTAssertEqual(search.replacingAll(in: "x").text, "y\\")
    }

    func testPreviousAndWrap() {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "x x x")
        state.updateSelection(for: id, to: NSRange(location: 0, length: 0))
        state.findText = "x"
        state.findPrevious()
        XCTAssertEqual(state.activeDocument?.selectionRange.location, 4)
        state.findNext()
        XCTAssertEqual(state.activeDocument?.selectionRange.location, 0)
        state.findOptions.wrapAround = false
        state.findPrevious()
        XCTAssertEqual(state.findMessage, "Not found")
    }

    func testEmptyMatchesAdvance() {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "a\nb\nc")
        state.updateSelection(for: id, to: NSRange(location: 0, length: 0))
        state.findOptions.regex = true
        state.findText = "^"
        state.findNext()
        XCTAssertEqual(state.activeDocument?.selectionRange.location, 2)
        state.findNext()
        XCTAssertEqual(state.activeDocument?.selectionRange.location, 4)
    }

    func testReplaceCurrentUsesSurroundingText() {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "ab ac")
        state.updateSelection(for: id, to: NSRange(location: 0, length: 0))
        state.findOptions.regex = true
        state.findText = "a(?=c)"
        state.replaceText = "Z"
        state.findNext()
        state.replaceCurrent()
        XCTAssertEqual(state.activeDocument?.content, "ab Zc")
    }

    func testInvalidRegexIsReported() {
        let state = AppState()
        state.findOptions.regex = true
        state.findText = "("
        state.findNext()
        XCTAssertEqual(state.findMessage, "Invalid pattern")
    }

    func testLineAndColumn() {
        let session = EditorSession()
        session.load("ab\r\ncd\ne\n")
        XCTAssertEqual(session.lineStarts, [0, 4, 7, 9])
        XCTAssertEqual(session.cursorPosition(at: 5).line, 2)
        XCTAssertEqual(session.cursorPosition(at: 5).column, 2)
        XCTAssertEqual(session.cursorPosition(at: 9).line, 4)
    }

    func testEveryLanguageExistsInHighlighter() throws {
        let highlightr = try XCTUnwrap(Highlightr())
        let supported = Set(highlightr.supportedLanguages())
        for name in Language.allCases.compactMap(\.highlighterName) {
            XCTAssertNotNil(highlightr.highlight("x", as: name), name)
            let aliases = ["xml", "objectivec"]
            XCTAssertTrue(supported.contains(name) || aliases.contains(name), name)
        }
    }

    func testCodeGetsColored() async {
        let text = "// note\nlet greeting = \"hello 😀\"\n"
        for dark in [false, true] {
            let spans: [SyntaxHighlighter.Span] = await withCheckedContinuation { continuation in
                SyntaxHighlighter.shared.highlight(text, language: "swift", dark: dark) {
                    continuation.resume(returning: $0)
                }
            }
            XCTAssertGreaterThan(Set(spans.map { $0.color.description }).count, 2)
        }
    }
}
