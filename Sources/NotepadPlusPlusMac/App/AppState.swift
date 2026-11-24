import AppKit
import Collections

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var documents: OrderedDictionary<UUID, Document> = [:]
    /// The tab shown in the main pane.
    @Published private(set) var activeDocumentID: UUID?
    /// The tab shown in the second pane, when the editor is split.
    @Published private(set) var splitDocumentID: UUID?
    @Published private(set) var splitFocused = false
    @Published var splitVertically = false
    @Published var findPanelVisible = false
    @Published var replacePanelVisible = false
    @Published private(set) var findFocusRequest = 0
    @Published var findText = ""
    @Published var replaceText = ""
    @Published var findOptions = FindOptions()
    @Published private(set) var findMessage = ""
    @Published private(set) var wordWrap = true
    @Published private(set) var showsMinimap = true
    @Published private(set) var showsChangeHistory = true
    @Published private(set) var showsTerminal = false
    @Published private(set) var terminalTitle = ""
    let terminal = TerminalController()
    @Published private(set) var fontSize: CGFloat = AppState.defaultFontSize
    @Published private(set) var recentFiles: [URL] = []
    @Published private(set) var isRecordingMacro = false
    @Published private(set) var recordedMacro: [MacroAction] = []
    @Published private(set) var savedMacros: [Macro] = []
    private var isPlayingMacro = false
    @Published private(set) var git: [UUID: GitSnapshot] = [:]
    /// A Git command in progress, shown in the status bar.
    @Published var gitActivity: String?
    private var pendingDiffs: [UUID: DispatchWorkItem] = [:]
    /// Opens files dropped from Finder, with an alert for any that can't be opened. Set by the app.
    var openDroppedFiles: (([URL]) -> Void)?

    static let defaultFontSize: CGFloat = 13
    static let fontSizes: ClosedRange<CGFloat> = 8...48
    static let maximumRecentFiles = 15

    /// Where settings, recent files and the open tabs are kept. nil keeps nothing, as in tests.
    private let store: UserDefaults?

    private var sessions: [UUID: EditorSession] = [:]

    init(store: UserDefaults? = nil) {
        self.store = store
        defer { terminal.onTitleChange = { [weak self] title in self?.terminalTitle = title } }
        if let store {
            let size = store.double(forKey: Keys.fontSize)
            if size > 0 { fontSize = min(max(CGFloat(size), Self.fontSizes.lowerBound), Self.fontSizes.upperBound) }
            if store.object(forKey: Keys.wordWrap) != nil { wordWrap = store.bool(forKey: Keys.wordWrap) }
            if store.object(forKey: Keys.minimap) != nil { showsMinimap = store.bool(forKey: Keys.minimap) }
            if store.object(forKey: Keys.changeHistory) != nil {
                showsChangeHistory = store.bool(forKey: Keys.changeHistory)
            }
            recentFiles = (store.stringArray(forKey: Keys.recentFiles) ?? []).map { URL(fileURLWithPath: $0) }
            if let data = store.data(forKey: Keys.macros),
               let macros = try? JSONDecoder().decode([Macro].self, from: data) { savedMacros = macros }
        }
        createNewDocument()
    }

    private enum Keys {
        static let fontSize = "fontSize"
        static let wordWrap = "wordWrap"
        static let minimap = "showMinimap"
        static let changeHistory = "showChangeHistory"
        static let recentFiles = "recentFiles"
        static let session = "openTabs"
        static let macros = "macros"
    }

    var activeDocument: Document? { activeDocumentID.flatMap { documents[$0] } }

    /// The tab in the pane the user is working in, which commands act on.
    var focusedDocumentID: UUID? { splitFocused ? splitDocumentID ?? activeDocumentID : activeDocumentID }
    var focusedDocument: Document? { focusedDocumentID.flatMap { documents[$0] } }

    /// The focused tab's session, pointed at the focused pane.
    var activeSession: EditorSession? {
        guard let id = focusedDocumentID, let session = sessions[id] else { return nil }
        if let pane = splitFocused ? session.secondary : session.primary { session.use(pane) }
        return session
    }

    func session(for id: UUID) -> EditorSession? { sessions[id] }
    var modifiedDocumentIDs: [UUID] { documents.values.filter(\.isModified).map(\.id) }

    // MARK: Tabs

    /// A new empty tab, named with the lowest Untitled number not already open, as in Notepad++.
    func createNewDocument() {
        let used = Set(documents.values.filter { $0.fileURL == nil && $0.title == nil }.map(\.untitledNumber))
        let number = (1...).first { !used.contains($0) }!
        add(Document(untitledNumber: number))
    }

    private func add(_ document: Document) {
        let id = document.id
        let session = EditorSession()
        session.load(document.content)
        session.language = document.language
        session.setWordWrap(wordWrap)
        session.setFontSize(fontSize)
        session.setShowsMinimap(showsMinimap)
        session.onEdit = { [weak self] text, selection in
            guard let self, var changed = self.documents[id] else { return }
            changed.content = text
            changed.selectionRange = selection
            self.documents[id] = changed
            self.scheduleMarks(id)
        }
        session.onSelect = { [weak self] selection in
            self?.documents[id]?.selectionRange = selection
        }
        session.onAction = { [weak self] action in self?.record(action) }
        session.onFilesDropped = { [weak self] files in self?.openDroppedFiles?(files) }
        session.onFocus = { [weak self] pane in
            guard let self else { return }
            let split = pane.isSecondary && self.splitDocumentID == id
            if self.splitFocused != split { self.splitFocused = split }
        }
        sessions[id] = session
        documents[id] = document
        activeDocumentID = id
    }

    func setActiveDocument(_ id: UUID) {
        guard documents[id] != nil else { return }
        activeDocumentID = id
        splitFocused = false
        findMessage = ""
    }

    // MARK: Split

    var isSplit: Bool { splitDocumentID != nil }

    /// Shows a tab in the second pane. The same tab can be in both panes.
    func showInSplit(_ id: UUID) {
        guard let session = sessions[id] else { return }
        if let old = splitDocumentID, old != id { sessions[old]?.removeSecondaryPane() }
        _ = session.makeSecondaryPane()
        splitDocumentID = id
        splitFocused = true
        findMessage = ""
    }

    func toggleSplit() {
        if isSplit {
            closeSplit()
        } else if let id = activeDocumentID {
            showInSplit(id)
        }
    }

    func closeSplit() {
        guard let id = splitDocumentID else { return }
        sessions[id]?.removeSecondaryPane()
        splitDocumentID = nil
        splitFocused = false
    }

    func focusMainPane() { splitFocused = false }

    func selectNextTab() { selectTab(offset: 1) }
    func selectPreviousTab() { selectTab(offset: -1) }

    private func selectTab(offset: Int) {
        guard let id = activeDocumentID, let index = documents.index(forKey: id) else { return }
        setActiveDocument(documents.keys[(index + offset + documents.count) % documents.count])
    }

    /// Closes without asking. The UI asks first; see FileActions.
    func removeDocument(_ id: UUID) {
        guard let index = documents.index(forKey: id) else { return }
        if splitDocumentID == id { closeSplit() }
        documents.removeValue(forKey: id)
        git.removeValue(forKey: id)
        pendingDiffs.removeValue(forKey: id)?.cancel()
        sessions.removeValue(forKey: id)
        if documents.isEmpty {
            createNewDocument()
        } else if activeDocumentID == id {
            setActiveDocument(documents.keys[min(index, documents.count - 1)])
        }
    }

    /// Closes every tab without asking, leaving one empty Untitled tab for the next time the window opens.
    func closeAllDocuments() {
        closeSplit()
        documents.removeAll()
        sessions.removeAll()
        git.removeAll()
        pendingDiffs.values.forEach { $0.cancel() }
        pendingDiffs.removeAll()
        findPanelVisible = false
        createNewDocument()
    }

    /// The only tab is an empty Untitled one, as after closing the window.
    var isPristine: Bool {
        guard documents.count == 1, let document = documents.values.first else { return false }
        return document.fileURL == nil && !document.isModified && document.content.isEmpty && !document.isReadOnly
    }

    // MARK: Editing

    func updateContent(for id: UUID, newContent: String) {
        guard let session = sessions[id] else { return }
        session.replace(NSRange(location: 0, length: (session.textView.string as NSString).length), with: newContent)
    }

    func updateSelection(for id: UUID, to range: NSRange) {
        sessions[id]?.select(range)
    }

    func setLanguage(_ language: Language, for id: UUID) {
        documents[id]?.language = language
        sessions[id]?.language = language
    }

    func setLanguage(_ language: Language) {
        if let id = focusedDocumentID { setLanguage(language, for: id) }
    }

    func setEncoding(_ encoding: FileEncoding, for id: UUID) {
        documents[id]?.encoding = encoding
    }

    func toggleWordWrap() {
        wordWrap.toggle()
        sessions.values.forEach { $0.setWordWrap(wordWrap) }
        store?.set(wordWrap, forKey: Keys.wordWrap)
    }

    func toggleMinimap() {
        showsMinimap.toggle()
        sessions.values.forEach { $0.setShowsMinimap(showsMinimap) }
        store?.set(showsMinimap, forKey: Keys.minimap)
    }

    func zoom(by step: CGFloat) { setFontSize(fontSize + step) }
    func resetZoom() { setFontSize(Self.defaultFontSize) }

    private func setFontSize(_ size: CGFloat) {
        fontSize = min(max(size, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        sessions.values.forEach { $0.setFontSize(fontSize) }
        terminal.setFontSize(fontSize)
        store?.set(Double(fontSize), forKey: Keys.fontSize)
    }

    // MARK: Terminal

    /// The focused file's folder, or the home folder for an untitled tab.
    var terminalFolder: URL {
        focusedDocument?.fileURL?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func toggleTerminal() {
        showsTerminal.toggle()
        if !showsTerminal, let textView = activeSession?.textView { textView.window?.makeFirstResponder(textView) }
    }

    /// Shows the terminal and moves its shell to the focused file's folder.
    func openTerminalInFileFolder() {
        let wasRunning = terminal.isRunning
        showsTerminal = true
        if wasRunning { terminal.changeDirectory(to: terminalFolder) }
    }

    func goTo(line: Int) {
        activeSession?.goTo(line: line)
    }

    // MARK: Line operations

    func perform(_ operation: LineOperation) {
        guard let session = activeSession, focusedDocument?.isReadOnly != true else { return }
        let textView = session.textView
        guard let edit = operation.edit(in: textView.string, selection: textView.selectedRange()) else { return }
        session.replace(edit.range, with: edit.text)
        textView.undoManager?.setActionName(operation.rawValue)
        session.select(edit.selection)
    }

    // MARK: Macros

    func startRecordingMacro() {
        recordedMacro = []
        isRecordingMacro = true
    }

    func stopRecordingMacro() {
        isRecordingMacro = false
    }

    private func record(_ action: MacroAction) {
        guard isRecordingMacro, !isPlayingMacro else { return }
        if case .command(let name) = action, !MacroAction.isRecordable(name) { return }
        // Typing arrives a character at a time; keep it as one step.
        if case .insert(let text) = action, case .insert(let previous)? = recordedMacro.last {
            recordedMacro[recordedMacro.count - 1] = .insert(previous + text)
        } else {
            recordedMacro.append(action)
        }
    }

    /// Plays actions into the focused editor. One undo reverses every run.
    func play(_ actions: [MacroAction], times: Int = 1) {
        guard !isRecordingMacro, !actions.isEmpty, let textView = activeSession?.textView else { return }
        let undo = textView.undoManager
        isPlayingMacro = true
        undo?.beginUndoGrouping()
        for _ in 0..<max(times, 1) {
            for action in actions {
                switch action {
                case .insert(let text):
                    textView.insertText(text, replacementRange: textView.selectedRange())
                case .command(let name):
                    let selector = NSSelectorFromString(name)
                    if MacroAction.isRecordable(name), textView.responds(to: selector) { textView.doCommand(by: selector) }
                }
            }
        }
        undo?.endUndoGrouping()
        undo?.setActionName("Macro")
        isPlayingMacro = false
    }

    func playRecordedMacro(times: Int = 1) { play(recordedMacro, times: times) }

    func saveRecordedMacro(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !recordedMacro.isEmpty else { return }
        savedMacros.removeAll { $0.name == name }
        savedMacros.append(Macro(name: name, actions: recordedMacro))
        storeMacros()
    }

    func deleteMacro(_ id: UUID) {
        savedMacros.removeAll { $0.id == id }
        storeMacros()
    }

    private func storeMacros() {
        if let data = try? JSONEncoder().encode(savedMacros) { store?.set(data, forKey: Keys.macros) }
    }

    // MARK: Recent files and the open tabs

    func noteRecent(_ url: URL) {
        let path = url.standardizedFileURL.path
        recentFiles.removeAll { $0.standardizedFileURL.path == path }
        recentFiles.insert(url.standardizedFileURL, at: 0)
        recentFiles = Array(recentFiles.prefix(Self.maximumRecentFiles))
        store?.set(recentFiles.map(\.path), forKey: Keys.recentFiles)
    }

    func forgetRecent(_ url: URL) {
        recentFiles.removeAll { $0.standardizedFileURL.path == url.standardizedFileURL.path }
        store?.set(recentFiles.map(\.path), forKey: Keys.recentFiles)
    }

    func clearRecentFiles() {
        recentFiles = []
        store?.set([String](), forKey: Keys.recentFiles)
    }

    /// Remembers which saved files are open, like Notepad++'s session. Unsaved edits are not kept.
    func saveOpenTabs() {
        guard let store else { return }
        let tabs: [[String: Any]] = documents.values.compactMap { document in
            guard let url = document.fileURL else { return nil }
            return ["path": url.path, "active": document.id == activeDocumentID,
                    "cursor": document.selectionRange.location]
        }
        store.set(tabs, forKey: Keys.session)
    }

    /// Reopens the files from last time. Files that are gone or unreadable are skipped.
    func reopenTabs() {
        guard let tabs = store?.array(forKey: Keys.session) as? [[String: Any]] else { return }
        var active: UUID?
        for tab in tabs {
            guard let path = tab["path"] as? String else { continue }
            let url = URL(fileURLWithPath: path)
            guard (try? open(url)) != nil, let id = activeDocumentID else { continue }
            if let cursor = tab["cursor"] as? Int, let session = sessions[id] {
                let length = (session.textView.string as NSString).length
                session.select(NSRange(location: min(max(cursor, 0), length), length: 0))
            }
            if tab["active"] as? Bool == true { active = id }
        }
        if let active { setActiveDocument(active) }
    }

    // MARK: Files

    private func canonical(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }

    func document(at url: URL) -> Document? {
        let target = canonical(url)
        return documents.values.first { $0.fileURL.map(canonical) == target }
    }

    func open(_ url: URL) throws {
        if let existing = document(at: url) {
            setActiveDocument(existing.id)
            noteRecent(url)
            return
        }
        let data = try Data(contentsOf: url)
        let file = try TextFile(data: data)
        var document = Document(untitledNumber: 0)
        document.content = file.text
        document.savedContent = file.text
        document.openedContent = file.text
        document.fileURL = url
        document.diskData = data
        document.encoding = file.encoding
        document.savedEncoding = file.encoding
        document.lineEnding = file.lineEnding
        document.language = Language.from(url: url) ?? .plainText

        // Reuse the empty tab that the app starts with.
        let empty = activeDocument.flatMap {
            $0.fileURL == nil && !$0.isModified && $0.content.isEmpty ? $0.id : nil
        }
        add(document)
        if let empty { removeDocument(empty) }
        noteRecent(url)
        refreshGit(document.id)
    }

    /// Opens generated text in a tab that can't be edited or saved.
    func openReadOnly(title: String, text: String, language: Language) {
        var document = Document(untitledNumber: 0)
        document.title = title
        document.content = text
        document.savedContent = text
        document.language = language
        document.isReadOnly = true
        add(document)
        sessions[document.id]?.panes.forEach { $0.textView.isEditable = false }
    }

    // MARK: Git

    /// Reads the file's branch and committed text from Git, then marks changed lines.
    @discardableResult
    func refreshGit(_ id: UUID) -> Task<Void, Never>? {
        guard let url = documents[id]?.fileURL else { return nil }
        return Task {
            let snapshot = await GitTracker.snapshot(for: url)
            guard documents[id]?.fileURL == url else { return }
            git[id] = snapshot
            updateDiff(id)
        }
    }

    func refreshAllGit() {
        documents.keys.forEach { refreshGit($0) }
    }

    /// Git and change history marks are recomputed shortly after typing stops.
    private func scheduleMarks(_ id: UUID) {
        pendingDiffs[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.updateDiff(id) }
        }
        pendingDiffs[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func updateDiff(_ id: UUID) {
        guard let session = sessions[id], let document = documents[id] else { return }
        session.gitDiff = git[id]?.committedText.flatMap { LineDiff(old: $0, new: document.content) }
        updateChangeHistory(id)
        objectWillChange.send()
    }

    func updateChangeHistory(_ id: UUID) {
        guard let session = sessions[id], let document = documents[id] else { return }
        session.changeHistory = showsChangeHistory && !document.isReadOnly
            ? ChangeHistory(opened: document.openedContent, saved: document.savedContent, current: document.content)
                ?? ChangeHistory()
            : ChangeHistory()
    }

    func toggleChangeHistory() {
        showsChangeHistory.toggle()
        documents.keys.forEach(updateChangeHistory)
        store?.set(showsChangeHistory, forKey: Keys.changeHistory)
    }

    func showChanges() {
        guard let id = focusedDocumentID, let document = documents[id], let committed = git[id]?.committedText,
              let diff = LineDiff(old: committed, new: document.content) else { return }
        let name = document.displayName
        let text = diff.isEmpty ? "No changes since the last commit.\n"
            : diff.unified(oldName: "a/\(name) (last commit)", newName: "b/\(name)")
        openReadOnly(title: "\(name) changes", text: text, language: .diff)
    }

    func hasChangedOnDisk(_ id: UUID) -> Bool {
        guard let document = documents[id], let url = document.fileURL,
              let known = document.diskData, let current = try? Data(contentsOf: url) else { return false }
        return current != known
    }

    /// Rereads open files that changed on disk, as after a pull or branch switch. Tabs with unsaved
    /// edits are left alone; their names are returned so the user can be told.
    @discardableResult
    func reloadChangedFiles(under folder: URL) -> [String] {
        let root = canonical(folder).path + "/"
        var skipped: [String] = []
        for (id, document) in documents {
            guard let url = document.fileURL, canonical(url).path.hasPrefix(root),
                  let data = try? Data(contentsOf: url), data != document.diskData else { continue }
            if document.isModified {
                skipped.append(document.displayName)
                continue
            }
            guard let file = try? TextFile(data: data), let session = sessions[id] else { continue }
            var updated = document
            updated.content = file.text
            updated.savedContent = file.text
            updated.openedContent = file.text
            updated.diskData = data
            updated.encoding = file.encoding
            updated.savedEncoding = file.encoding
            updated.lineEnding = file.lineEnding
            updated.selectionRange = NSRange(location: 0, length: 0)
            documents[id] = updated
            session.load(file.text)
        }
        refreshAllGit()
        return skipped
    }

    func save(_ id: UUID, to url: URL) throws {
        guard var document = documents[id] else { return }
        let data = try TextFile(text: document.content, encoding: document.encoding,
                                lineEnding: document.lineEnding).data()
        // An atomic write to a symlink would replace the link, so write to what it points at.
        try data.write(to: url.resolvingSymlinksInPath(), options: .atomic)

        let renamed = document.fileURL != url
        document.fileURL = url
        document.diskData = data
        document.savedContent = document.content
        document.savedEncoding = document.encoding
        if renamed, let language = Language.from(url: url) {
            document.language = language
            sessions[id]?.language = language
        }
        documents[id] = document
        if renamed { noteRecent(url) }
        updateChangeHistory(id)
        refreshGit(id)
    }

    // MARK: Find and replace

    func showFind(replace: Bool = false) {
        if let session = activeSession {
            let selection = session.textView.selectedRange()
            let text = (session.textView.string as NSString).substring(with: selection)
            if !text.isEmpty, !text.contains(where: \.isNewline) {
                findText = findOptions.regex ? NSRegularExpression.escapedPattern(for: text) : text
            }
        }
        findMessage = ""
        findPanelVisible = true
        replacePanelVisible = replace
        findFocusRequest += 1
    }

    func hideFind() {
        findPanelVisible = false
        if let textView = activeSession?.textView { textView.window?.makeFirstResponder(textView) }
    }

    private func makeSearch() -> TextSearch? {
        if let search = TextSearch(query: findText, replacement: replaceText, options: findOptions) { return search }
        findMessage = findText.isEmpty ? "" : "Invalid pattern"
        return nil
    }

    func findNext() { find(forward: true) }
    func findPrevious() { find(forward: false) }

    private func find(forward: Bool) {
        guard let session = activeSession, let search = makeSearch() else { return }
        let current = session.textView.selectedRange()
        // Ignore an empty match under the cursor, or searches like ^ would never move.
        let matches = search.matches(in: session.textView.string).map(\.range)
        let candidates = matches.filter { !($0.length == 0 && $0 == current) }
        var found = forward
            ? candidates.first { $0.location >= NSMaxRange(current) }
            : candidates.last { NSMaxRange($0) <= current.location }
        if found == nil, findOptions.wrapAround { found = forward ? matches.first : matches.last }

        guard let found, let index = matches.firstIndex(of: found) else {
            findMessage = "Not found"
            return
        }
        session.select(found)
        findMessage = "\(index + 1) of \(matches.count)"
    }

    func replaceCurrent() {
        guard let session = activeSession, let search = makeSearch() else { return }
        let text = session.textView.string
        let selection = session.textView.selectedRange()
        // Match against the whole text so anchors and word boundaries see their surroundings.
        if let match = search.matches(in: text).first(where: { $0.range == selection }) {
            let replacement = search.replacement(for: match, in: text)
            session.replace(selection, with: replacement)
            session.select(NSRange(location: selection.location + (replacement as NSString).length, length: 0))
        }
        findNext()
    }

    func replaceAll() {
        guard let session = activeSession, let search = makeSearch() else { return }
        let text = session.textView.string
        let result = search.replacingAll(in: text)
        if result.count > 0 {
            let cursor = session.textView.selectedRange().location
            session.replace(NSRange(location: 0, length: (text as NSString).length), with: result.text)
            session.select(NSRange(location: min(cursor, (result.text as NSString).length), length: 0))
        }
        findMessage = "Replaced \(result.count)"
    }
}
