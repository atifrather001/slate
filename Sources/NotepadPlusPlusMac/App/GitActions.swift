import AppKit
import SwiftUI

/// Commit, push, pull, fetch and branch switching, for the repository of the file you're working in.
@MainActor
final class GitActions {
    private let state: AppState
    private let files: FileActions
    private let window: () -> NSWindow?

    init(state: AppState, files: FileActions, window: @escaping () -> NSWindow?) {
        self.state = state
        self.files = files
        self.window = window
    }

    /// The repository of the focused tab's file.
    func repository() -> GitRepository? {
        guard let url = state.focusedDocument?.fileURL, let repository = GitRepository.containing(url) else {
            alert("Open a file from a Git repository first.",
                  detail: "Git commands work on the repository of the file you're editing.")
            return nil
        }
        return repository
    }

    // MARK: Commands

    func commit() {
        guard let repository = repository(), saveUnsavedFiles(in: repository, before: "committing") else { return }
        let changes: [GitChange]
        do { changes = try repository.changes() } catch { return show(error) }
        guard !changes.isEmpty else {
            return alert("Nothing to commit.", detail: "There are no changes in \(repository.root.lastPathComponent).")
        }
        let branch = repository.currentBranch() ?? "detached HEAD"
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                             styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        sheet.title = "Commit"
        let view = CommitView(repositoryName: repository.root.lastPathComponent, branch: branch, changes: changes) {
            [weak self, weak sheet] result in
            guard let self, let sheet else { return }
            (sheet.sheetParent ?? sheet).endSheet(sheet)
            sheet.orderOut(nil)
            guard let result else { return }
            self.runCommit(result, in: repository)
        }
        sheet.contentViewController = NSHostingController(rootView: view)
        if let parent = window(), parent.isVisible {
            parent.beginSheet(sheet)
        } else {
            sheet.center()
            sheet.makeKeyAndOrderFront(nil)
        }
    }

    private func runCommit(_ result: CommitView.Result, in repository: GitRepository) {
        let paths = result.changes.flatMap { [$0.path] + ($0.oldPath.map { [$0] } ?? []) }
        perform(result.push ? "Committing and pushing…" : "Committing…", in: repository) {
            try repository.commit(paths: paths, message: result.message)
            if result.push { try repository.push() }
        }
    }

    func push() {
        guard let repository = repository() else { return }
        perform("Pushing…", in: repository) { try repository.push() }
    }

    func pull() {
        guard let repository = repository(), saveUnsavedFiles(in: repository, before: "pulling") else { return }
        perform("Pulling…", in: repository, reloadFiles: true) { try repository.pull() }
    }

    func fetch() {
        guard let repository = repository() else { return }
        perform("Fetching…", in: repository) { try repository.fetch() }
    }

    func switchBranch() {
        guard let repository = repository(), saveUnsavedFiles(in: repository, before: "switching branches") else { return }
        let branches: [String]
        do { branches = try repository.branches() } catch { return show(error) }
        let current = repository.currentBranch()

        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 280, height: 26))
        picker.addItems(withTitles: branches)
        if let current { picker.selectItem(withTitle: current) }
        let newName = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        newName.placeholderString = "Or type a new branch name"
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        accessory.addSubview(picker)
        accessory.addSubview(newName)

        let alert = NSAlert()
        alert.messageText = "Switch Branch"
        alert.informativeText = "In \(repository.root.lastPathComponent), on \(current ?? "no branch")."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Switch")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let typed = newName.stringValue.trimmingCharacters(in: .whitespaces)
        let target = typed.isEmpty ? picker.titleOfSelectedItem ?? "" : typed
        guard !target.isEmpty, target != current || !typed.isEmpty else { return }
        let create = !typed.isEmpty && !branches.contains(typed)
        perform("Switching to \(target)…", in: repository, reloadFiles: true) {
            try repository.switchTo(target, create: create)
        }
    }

    // MARK: Helpers

    /// Runs Git off the main thread, showing progress in the status bar and any error in an alert.
    private func perform(_ activity: String, in repository: GitRepository, reloadFiles: Bool = false,
                         _ work: @escaping @Sendable () throws -> Void) {
        state.gitActivity = activity
        Task {
            let failure: Error? = await Task.detached(priority: .userInitiated) {
                do { try work(); return nil } catch { return error }
            }.value
            state.gitActivity = nil
            let skipped = reloadFiles ? state.reloadChangedFiles(under: repository.root) : []
            if !reloadFiles { state.refreshAllGit() }
            if let failure { return show(failure) }
            if !skipped.isEmpty {
                alert("Some open files changed on disk but weren't reloaded.",
                      detail: "\(skipped.joined(separator: ", ")) has unsaved edits in Slate. Saving will overwrite the version from Git.")
            }
        }
    }

    /// Git works on files on disk, so unsaved tabs in the repository are saved first, with the user's OK.
    private func saveUnsavedFiles(in repository: GitRepository, before action: String) -> Bool {
        let root = repository.root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let unsaved = state.documents.values.filter { document in
            guard document.isModified, let url = document.fileURL else { return false }
            return url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root)
        }
        guard !unsaved.isEmpty else { return true }
        let names = unsaved.map(\.displayName).joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = "Save changes before \(action)?"
        alert.informativeText = "\(names) has unsaved edits."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return unsaved.allSatisfy { files.save($0.id) }
    }

    private func show(_ error: Error) {
        alert("Git couldn't finish.", detail: error.localizedDescription)
    }

    private func alert(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}

/// Choose files and write a message.
struct CommitView: View {
    struct Result {
        var changes: [GitChange]
        var message: String
        var push: Bool
    }

    let repositoryName: String
    let branch: String
    let changes: [GitChange]
    let finish: (Result?) -> Void
    @State private var chosen: Set<String>
    @State private var message = ""

    init(repositoryName: String, branch: String, changes: [GitChange], finish: @escaping (Result?) -> Void) {
        self.repositoryName = repositoryName
        self.branch = branch
        self.changes = changes
        self.finish = finish
        _chosen = State(initialValue: Set(changes.map(\.id)))
    }

    private var canCommit: Bool {
        !chosen.isEmpty && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commit to \(branch) in \(repositoryName)").font(.headline)
            HStack {
                Text("\(chosen.count) of \(changes.count) files").foregroundStyle(.secondary)
                Spacer()
                Button(chosen.count == changes.count ? "Select None" : "Select All") {
                    chosen = chosen.count == changes.count ? [] : Set(changes.map(\.id))
                }
                .buttonStyle(.link)
            }
            List(changes) { change in
                Toggle(isOn: Binding(
                    get: { chosen.contains(change.id) },
                    set: { if $0 { chosen.insert(change.id) } else { chosen.remove(change.id) } }
                )) {
                    HStack {
                        Text(label(change.kind)).font(.caption.monospaced()).foregroundStyle(color(change.kind))
                            .frame(width: 70, alignment: .leading)
                        Text(change.path).lineLimit(1).truncationMode(.middle)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .frame(minHeight: 140)
            Text("Message")
            TextEditor(text: $message)
                .font(.body.monospaced())
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction)
                Button("Commit and Push") { done(push: true) }.disabled(!canCommit)
                Button("Commit") { done(push: false) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canCommit)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 400)
    }

    private func done(push: Bool) {
        finish(Result(changes: changes.filter { chosen.contains($0.id) }, message: message, push: push))
    }

    private func label(_ kind: GitChange.Kind) -> String {
        switch kind {
        case .modified: return "modified"
        case .added: return "added"
        case .deleted: return "deleted"
        case .renamed: return "renamed"
        case .untracked: return "new"
        case .conflicted: return "conflict"
        }
    }

    private func color(_ kind: GitChange.Kind) -> Color {
        switch kind {
        case .added, .untracked: return .green
        case .deleted, .conflicted: return .red
        default: return .blue
        }
    }
}
