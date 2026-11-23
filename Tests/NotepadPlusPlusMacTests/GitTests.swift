import XCTest
@testable import NotepadPlusPlusMac

@MainActor
final class GitTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: folder)
    }

    @discardableResult
    private func git(_ arguments: String...) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path, "-c", "user.name=Test", "-c", "user.email=test@example.com",
                             "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main"] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func testLineDiffMarksAddedChangedAndDeleted() throws {
        let diff = try XCTUnwrap(LineDiff(old: "a\nb\nc\nd\ne", new: "a\nB\nc\nnew\ne\nf"))
        XCTAssertEqual(diff.changes, [1: .modified, 3: .modified, 5: .added])
        XCTAssertEqual(diff.added, 1)
        XCTAssertEqual(diff.modified, 2)

        let deletion = try XCTUnwrap(LineDiff(old: "a\nb\nc\nd", new: "a\nd"))
        XCTAssertEqual(deletion.changes, [:])
        XCTAssertEqual(deletion.deletionsAbove, [1])
        XCTAssertEqual(deletion.deleted, 2)
        XCTAssertTrue(try XCTUnwrap(LineDiff(old: "same\n", new: "same\n")).isEmpty)
    }

    func testUnifiedDiffMatchesGit() throws {
        let old = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"
        var lines = old.components(separatedBy: "\n")
        lines[2] = "changed 3"
        lines.insert("inserted", at: 20)
        lines.remove(at: 27)
        let new = lines.joined(separator: "\n")
        try git("init", "-q")
        try old.write(to: folder.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        try git("add", "f.txt")
        try git("commit", "-q", "-m", "one")
        try new.write(to: folder.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path, "diff", "--no-color", "--no-ext-diff", "--diff-algorithm=myers", "f.txt"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let expected = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        // Git adds the nearest "function" line after a hunk header; Slate doesn't.
        let gitHunks = expected.components(separatedBy: "\n").drop { !$0.hasPrefix("@@") }
            .map { $0.hasPrefix("@@") ? String($0[..<$0.range(of: "@@", options: .backwards)!.upperBound]) : $0 }
            .joined(separator: "\n")
        let ours = try XCTUnwrap(LineDiff(old: old, new: new)).unified(oldName: "a", newName: "b")
        let ourHunks = ours.components(separatedBy: "\n").drop { !$0.hasPrefix("@@") }.joined(separator: "\n")
        XCTAssertEqual(ourHunks, gitHunks)
    }

    func testOpenFileInRepositoryShowsBranchAndChanges() async throws {
        try git("init", "-q")
        let file = folder.appendingPathComponent("app.swift")
        try "let a = 1\nlet b = 2\n".write(to: file, atomically: true, encoding: .utf8)
        try git("add", "app.swift")
        try git("commit", "-q", "-m", "first")
        try git("checkout", "-q", "-b", "feature")

        let state = AppState()
        try state.open(file)
        let id = state.activeDocumentID!
        await state.refreshGit(id)?.value
        XCTAssertEqual(state.git[id]?.branch, "feature")
        XCTAssertEqual(state.session(for: id)?.gitDiff?.isEmpty, true)

        state.updateContent(for: id, newContent: "let a = 10\nlet b = 2\nlet c = 3\n")
        state.updateDiff(id)
        XCTAssertEqual(state.session(for: id)?.gitDiff?.changes, [0: .modified, 2: .added])

        state.showChanges()
        XCTAssertEqual(state.activeDocument?.displayName, "app.swift changes")
        XCTAssertTrue(state.activeDocument!.isReadOnly)
        XCTAssertFalse(state.activeDocument!.isModified)
        XCTAssertTrue(state.activeDocument!.content.contains("-let a = 1\n+let a = 10\n"))
        XCTAssertFalse(state.activeSession!.textView.isEditable)
    }

    func testRepositoryIsNotChangedByReading() async throws {
        try git("init", "-q")
        let file = folder.appendingPathComponent("a.txt")
        try "a\n".write(to: file, atomically: true, encoding: .utf8)
        try git("add", "a.txt")
        try git("commit", "-q", "-m", "first")
        let index = folder.appendingPathComponent(".git/index")
        let before = try Data(contentsOf: index)
        let modified = try FileManager.default.attributesOfItem(atPath: index.path)[.modificationDate] as? Date
        try "b\n".write(to: file, atomically: true, encoding: .utf8)
        _ = await GitTracker.snapshot(for: file)
        XCTAssertEqual(try Data(contentsOf: index), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: index.path)[.modificationDate] as? Date, modified)
    }

    func testNewAndOutsideFiles() async throws {
        let outside = folder.appendingPathComponent("loose.txt")
        try "x".write(to: outside, atomically: true, encoding: .utf8)
        let none = await GitTracker.snapshot(for: outside)
        XCTAssertNil(none)

        try git("init", "-q")
        let snapshot = await GitTracker.snapshot(for: outside)
        XCTAssertEqual(snapshot?.branch, "main")
        XCTAssertNil(snapshot?.committedText)
    }
}
