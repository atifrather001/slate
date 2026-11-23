import Foundation

/// What Git knows about a file: its branch and its text in the last commit.
struct GitSnapshot: Equatable {
    var branch: String
    /// nil when the file isn't in the last commit (new, or the repository has no commits).
    var committedText: String?
}

/// Runs read-only Git commands. Nothing here changes a repository: no index refresh, no locks, no hooks.
enum GitTracker {
    static var gitPath = "/usr/bin/git"

    static func snapshot(for file: URL) async -> GitSnapshot? {
        await Task.detached(priority: .utility) { snapshotNow(for: file) }.value
    }

    static func snapshotNow(for file: URL) -> GitSnapshot? {
        let folder = file.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: gitPath),
              run(["rev-parse", "--is-inside-work-tree"], in: folder)?.text == "true\n" else { return nil }
        let branch = run(["symbolic-ref", "--quiet", "--short", "HEAD"], in: folder)?.text
            ?? run(["rev-parse", "--short", "HEAD"], in: folder)?.text
            ?? "HEAD"
        // A path starting with ./ is relative to the folder given by -C.
        let committed = run(["show", "HEAD:./\(file.lastPathComponent)"], in: folder)
            .flatMap { try? TextFile(data: $0.data).text }
        return GitSnapshot(branch: branch.trimmingCharacters(in: .whitespacesAndNewlines), committedText: committed)
    }

    private static func run(_ arguments: [String], in folder: URL) -> (data: Data, text: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["-C", folder.path, "--no-pager", "-c", "core.fsmonitor=false"] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return (data, String(decoding: data, as: UTF8.self))
    }
}
