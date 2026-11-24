import Foundation

/// A file Git reports as changed, for the commit sheet.
struct GitChange: Identifiable, Equatable {
    enum Kind: String { case modified = "M", added = "A", deleted = "D", renamed = "R", untracked = "?", conflicted = "U" }
    var path: String
    /// For a rename, the old path, which is committed with the new one.
    var oldPath: String?
    var kind: Kind
    /// Already in the index, from git add or a previous stage.
    var staged: Bool
    var id: String { path }
}

struct GitError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Git commands that change a repository. Each runs only when the user asks for it.
struct GitRepository {
    let root: URL

    /// The repository holding a file or folder, or nil.
    static func containing(_ url: URL) -> GitRepository? {
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        let folder = exists && isFolder.boolValue ? url : url.deletingLastPathComponent()
        guard let result = try? run(["rev-parse", "--show-toplevel"], in: folder) else { return nil }
        return GitRepository(root: URL(fileURLWithPath: result.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    // MARK: Reading

    func currentBranch() -> String? {
        (try? run(["symbolic-ref", "--quiet", "--short", "HEAD"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func branches() throws -> [String] {
        try run(["for-each-ref", "--format=%(refname:short)", "refs/heads"])
            .split(separator: "\n").map(String.init)
    }

    func upstream() -> String? {
        (try? run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remotes() -> [String] {
        ((try? run(["remote"])) ?? "").split(separator: "\n").map(String.init)
    }

    func changes() throws -> [GitChange] {
        let output = try run(["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        var entries = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var changes: [GitChange] = []
        while !entries.isEmpty {
            let entry = entries.removeFirst()
            guard entry.count > 3 else { continue }
            let index = entry[entry.startIndex], tree = entry[entry.index(after: entry.startIndex)]
            let path = String(entry.dropFirst(3))
            // A rename is followed by its old path.
            var oldPath: String?
            if index == "R" || index == "C", !entries.isEmpty { oldPath = entries.removeFirst() }
            let kind: GitChange.Kind
            switch (index, tree) {
            case ("?", "?"): kind = .untracked
            case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): kind = .conflicted
            case ("A", _): kind = .added
            case ("R", _), ("C", _): kind = .renamed
            case ("D", _), (_, "D"): kind = .deleted
            default: kind = .modified
            }
            changes.append(GitChange(path: path, oldPath: index == "R" ? oldPath : nil, kind: kind,
                                     staged: index != " " && index != "?"))
        }
        return changes
    }

    // MARK: Changing

    /// Stages exactly these paths (including deletions) and commits them.
    func commit(paths: [String], message: String) throws {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw GitError(message: "Write a commit message first.") }
        guard !paths.isEmpty else { throw GitError(message: "Choose at least one file to commit.") }
        // A path that's gone from both disk and index (the old side of a staged rename) has nothing to add.
        let indexed = Set(try run(["ls-files", "-z", "--"] + paths).split(separator: "\0").map(String.init))
        let toAdd = paths.filter {
            indexed.contains($0) || FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        if !toAdd.isEmpty { try run(["add", "--all", "--"] + toAdd) }
        try run(["commit", "--quiet", "-m", message, "--"] + paths)
    }

    /// Pushes the current branch, setting its upstream on the first push.
    func push() throws {
        guard let branch = currentBranch() else { throw GitError(message: "Switch to a branch before pushing.") }
        if upstream() != nil {
            try run(["push", "--quiet"], timeout: 120)
        } else {
            guard let remote = remotes().contains("origin") ? "origin" : remotes().first else {
                throw GitError(message: "This repository has no remote to push to.")
            }
            try run(["push", "--quiet", "--set-upstream", remote, branch], timeout: 120)
        }
    }

    /// Pulls without creating merge commits; if the branches have diverged, Git says so and nothing changes.
    func pull() throws {
        try run(["pull", "--ff-only", "--quiet"], timeout: 120)
    }

    func fetch() throws {
        try run(["fetch", "--all", "--prune", "--quiet"], timeout: 120)
    }

    func switchTo(_ branch: String, create: Bool = false) throws {
        try run(["switch", "--quiet"] + (create ? ["-c", branch] : [branch]))
    }

    // MARK: Running

    @discardableResult
    private func run(_ arguments: [String], timeout: TimeInterval = 30) throws -> String {
        try Self.run(arguments, in: root, timeout: timeout)
    }

    @discardableResult
    static func run(_ arguments: [String], in folder: URL, timeout: TimeInterval = 30) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: GitTracker.gitPath)
        process.arguments = ["-C", folder.path, "--no-pager"] + arguments
        var environment = ProcessInfo.processInfo.environment
        // Never wait for a password prompt nobody can see; use the keychain or SSH agent instead.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_EDITOR"] = "true"
        process.environment = environment
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        // Read both pipes while Git runs, so a full pipe can't stall it.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = output.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = errors.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        process.waitUntilExit()
        group.wait()
        deadline.cancel()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData + outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationReason == .uncaughtSignal {
                throw GitError(message: "Git took too long and was stopped.")
            }
            throw GitError(message: message.isEmpty ? "Git failed (\(arguments.first ?? "")) with code \(process.terminationStatus)." : message)
        }
        return String(decoding: outData, as: UTF8.self)
    }
}
