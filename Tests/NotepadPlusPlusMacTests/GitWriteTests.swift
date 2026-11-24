import XCTest
@testable import NotepadPlusPlusMac

@MainActor
final class GitWriteTests: XCTestCase {
    private var folder: URL!
    private var remote: URL { folder.appendingPathComponent("remote.git") }
    private var work: URL { folder.appendingPathComponent("work") }
    private var other: URL { folder.appendingPathComponent("other") }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Identity and no signing for these test repositories only, without touching the user's config.
        setenv("GIT_CONFIG_GLOBAL", folder.appendingPathComponent("gitconfig").path, 1)
        try """
        [user]
            name = Test
            email = test@example.com
        [init]
            defaultBranch = main
        [commit]
            gpgsign = false
        """.write(to: folder.appendingPathComponent("gitconfig"), atomically: true, encoding: .utf8)
        try GitRepository.run(["init", "--quiet", "--bare", remote.path], in: folder)
        try GitRepository.run(["clone", "--quiet", remote.path, work.path], in: folder)
    }

    override func tearDown() async throws {
        unsetenv("GIT_CONFIG_GLOBAL")
        try FileManager.default.removeItem(at: folder)
    }

    private func write(_ text: String, _ name: String, in dir: URL? = nil) throws -> URL {
        let url = (dir ?? work).appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testStatusCommitAndFirstPush() throws {
        _ = try write("a\n", "a.txt")
        _ = try write("b\n", "b.txt")
        let repo = try XCTUnwrap(GitRepository.containing(work.appendingPathComponent("a.txt")))
        XCTAssertEqual(try repo.changes().map(\.path).sorted(), ["a.txt", "b.txt"])
        XCTAssertEqual(try repo.changes().map(\.kind), [.untracked, .untracked])

        XCTAssertThrowsError(try repo.commit(paths: ["a.txt"], message: "  "))
        XCTAssertThrowsError(try repo.commit(paths: [], message: "x"))
        try repo.commit(paths: ["a.txt"], message: "Add a")
        XCTAssertEqual(try repo.changes().map(\.path), ["b.txt"], "only the chosen file was committed")

        XCTAssertNil(repo.upstream())
        try repo.push()
        XCTAssertEqual(repo.upstream(), "origin/main")
        let log = try GitRepository.run(["log", "--format=%s", "main"], in: remote)
        XCTAssertEqual(log, "Add a\n")
    }

    func testCommitDeletionAndRename() throws {
        _ = try write("1\n", "keep.txt")
        _ = try write("2\n", "gone.txt")
        let repo = try XCTUnwrap(GitRepository.containing(work))
        try repo.commit(paths: ["keep.txt", "gone.txt"], message: "first")
        try FileManager.default.removeItem(at: work.appendingPathComponent("gone.txt"))
        try GitRepository.run(["mv", "keep.txt", "kept.txt"], in: work)
        let changes = try repo.changes()
        XCTAssertEqual(Set(changes.map(\.kind)), [.deleted, .renamed])
        let rename = try XCTUnwrap(changes.first { $0.kind == .renamed })
        XCTAssertEqual(rename.oldPath, "keep.txt")
        try repo.commit(paths: changes.flatMap { [$0.path] + ($0.oldPath.map { [$0] } ?? []) }, message: "tidy")
        XCTAssertEqual(try repo.changes(), [])
    }

    func testPullFastForwardsAndReloadsOpenFiles() throws {
        let file = try write("v1\n", "shared.txt")
        let repo = try XCTUnwrap(GitRepository.containing(work))
        try repo.commit(paths: ["shared.txt"], message: "v1")
        try repo.push()

        // Someone else pushes a change.
        try GitRepository.run(["clone", "--quiet", remote.path, other.path], in: folder)
        let theirs = try XCTUnwrap(GitRepository.containing(other))
        _ = try write("v2\n", "shared.txt", in: other)
        try theirs.commit(paths: ["shared.txt"], message: "v2")
        try theirs.push()

        let state = AppState()
        try state.open(file)
        let clean = state.activeDocumentID!
        let notes = try write("mine\n", "notes.txt")
        try state.open(notes)
        state.updateContent(for: state.activeDocumentID!, newContent: "unsaved")
        _ = try write("changed elsewhere\n", "notes.txt")

        try repo.pull()
        let skipped = state.reloadChangedFiles(under: work)
        XCTAssertEqual(state.documents[clean]?.content, "v2\n")
        XCTAssertFalse(state.documents[clean]!.isModified)
        XCTAssertEqual(skipped, ["notes.txt"], "unsaved edits are never replaced")
        XCTAssertEqual(state.activeDocument?.content, "unsaved")
    }

    func testDivergedPullChangesNothing() throws {
        _ = try write("base\n", "f.txt")
        let repo = try XCTUnwrap(GitRepository.containing(work))
        try repo.commit(paths: ["f.txt"], message: "base")
        try repo.push()
        try GitRepository.run(["clone", "--quiet", remote.path, other.path], in: folder)
        let theirs = try XCTUnwrap(GitRepository.containing(other))
        _ = try write("theirs\n", "f.txt", in: other)
        try theirs.commit(paths: ["f.txt"], message: "theirs")
        try theirs.push()
        _ = try write("mine\n", "f.txt")
        try repo.commit(paths: ["f.txt"], message: "mine")

        XCTAssertThrowsError(try repo.pull())
        XCTAssertEqual(try String(contentsOf: work.appendingPathComponent("f.txt"), encoding: .utf8), "mine\n")
        XCTAssertEqual(try repo.changes(), [])
    }

    func testSwitchAndCreateBranches() throws {
        _ = try write("main\n", "f.txt")
        let repo = try XCTUnwrap(GitRepository.containing(work))
        try repo.commit(paths: ["f.txt"], message: "main")
        try repo.switchTo("feature", create: true)
        XCTAssertEqual(repo.currentBranch(), "feature")
        _ = try write("feature\n", "f.txt")
        try repo.commit(paths: ["f.txt"], message: "feature")
        XCTAssertEqual(try repo.branches().sorted(), ["feature", "main"])
        try repo.switchTo("main")
        XCTAssertEqual(try String(contentsOf: work.appendingPathComponent("f.txt"), encoding: .utf8), "main\n")
        XCTAssertThrowsError(try repo.switchTo("no-such-branch"))
    }

    func testPushWithoutRemoteExplains() throws {
        let lonely = folder.appendingPathComponent("lonely")
        try GitRepository.run(["init", "--quiet", lonely.path], in: folder)
        _ = try write("x\n", "x.txt", in: lonely)
        let repo = try XCTUnwrap(GitRepository.containing(lonely))
        try repo.commit(paths: ["x.txt"], message: "x")
        XCTAssertThrowsError(try repo.push()) { error in
            XCTAssertEqual(error.localizedDescription, "This repository has no remote to push to.")
        }
        XCTAssertNil(GitRepository.containing(FileManager.default.temporaryDirectory))
    }

    func testGitMenu() throws {
        let delegate = AppDelegate(store: nil)
        let menu = MainMenu.make(target: delegate)
        let git = try XCTUnwrap(menu.items.first { $0.title == "Git" }?.submenu)
        XCTAssertEqual(git.items.filter { !$0.isSeparatorItem }.map(\.title),
                       ["Commit…", "Push", "Pull", "Fetch", "Switch Branch…", "Show Changes Since Last Commit"])
        // No file from a repository is open, so the commands are off.
        XCTAssertFalse(delegate.validateMenuItem(git.items[0]))
    }
}
