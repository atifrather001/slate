import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    let state: AppState

    /// Pass nil in tests, so they never touch Slate's or the test runner's settings.
    init(store: UserDefaults? = .standard) {
        state = AppState(store: store)
        super.init()
        state.openDroppedFiles = { [weak self] files in
            self?.files.open(files)
            self?.showWindow()
        }
    }
    private(set) lazy var files = FileActions(state: state)
    private(set) lazy var gitActions = GitActions(state: state, files: files) { [weak self] in self?.window }
    private var window: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenu.make(target: self)
        // Before Finder's open requests arrive, so a file opened from Finder becomes the active tab.
        state.reopenTabs()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Slate"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 640, height: 400)
        window.contentView = NSHostingView(rootView: ContentView(state: state, files: files))
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    // Commits, branch switches and edits made elsewhere show up when you come back to Slate.
    func applicationDidBecomeActive(_ notification: Notification) {
        state.refreshAllGit()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        files.open(urls.filter(\.isFileURL))
        // Finder can send files while the window is closed, minimized or behind others.
        showWindow()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard files.canQuit() else { return .terminateCancel }
        state.saveOpenTabs()
        return .terminateNow
    }

    // Like other Mac apps, closing the window closes its files (asking about unsaved ones first)
    // and leaves Slate running. Files are opened again from the menus or the Dock menu.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if files.closeAll() { sender.orderOut(nil) }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isWindowVisible: Bool { window?.isVisible ?? false }

    // Clicking the Dock icon with no window open just brings Slate forward; it doesn't open a file.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        flag
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for (title, action) in [("New", #selector(newFile)), ("Open…", #selector(openFile))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Open Recent")
        // Filled now: the Dock doesn't ask a menu delegate to update.
        menuNeedsUpdate(submenu)
        recent.submenu = submenu
        menu.addItem(recent)
        return menu
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleWordWrap) { item.state = state.wordWrap ? .on : .off }
        if item.action == #selector(toggleMacroRecording) {
            item.title = state.isRecordingMacro ? "Stop Recording" : "Start Recording"
        }
        if [#selector(playMacro), #selector(playMacroManyTimes), #selector(saveMacro)].contains(item.action) {
            return !state.isRecordingMacro && !state.recordedMacro.isEmpty
        }
        if item.action == #selector(playSavedMacro(_:)) { return !state.isRecordingMacro }
        if item.action == #selector(saveFile) || item.action == #selector(saveFileAs) {
            return state.focusedDocument?.isReadOnly != true
        }
        if item.action == #selector(performLineOperation(_:)) {
            return state.focusedDocument.map { !$0.isReadOnly } ?? false
        }
        if [#selector(gitCommit), #selector(gitPush), #selector(gitPull), #selector(gitFetch),
            #selector(gitSwitchBranch)].contains(item.action) {
            return state.gitActivity == nil && state.focusedDocumentID.flatMap { state.git[$0] } != nil
        }
        if item.action == #selector(showChanges) {
            return state.focusedDocumentID.flatMap { state.git[$0]?.committedText } != nil
        }
        if item.action == #selector(toggleChangeHistory) { item.state = state.showsChangeHistory ? .on : .off }
        if item.action == #selector(toggleTerminal) { item.state = state.showsTerminal ? .on : .off }
        if item.action == #selector(toggleMinimap) { item.state = state.showsMinimap ? .on : .off }
        if item.action == #selector(toggleSplit) { item.state = state.isSplit ? .on : .off }
        if item.action == #selector(toggleSplitDirection) {
            item.state = state.splitVertically ? .on : .off
            return state.isSplit
        }
        if item.action == #selector(openRecent(_:)) { return item.representedObject is URL }
        if item.action == #selector(clearRecent) { return !state.recentFiles.isEmpty }
        if item.action == #selector(selectLanguage(_:)) {
            let language = item.representedObject as? String
            item.state = language != nil && language == state.focusedDocument?.language.rawValue ? .on : .off
        }
        return true
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let language = Language(rawValue: name) else { return }
        state.setLanguage(language)
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            files.open([url])
            showWindow()
        }
    }
    @objc func clearRecent() { state.clearRecentFiles() }
    @objc func goToLine() { files.askForLine() }
    @objc func zoomIn() { state.zoom(by: 1) }
    @objc func zoomOut() { state.zoom(by: -1) }
    @objc func actualSize() { state.resetZoom() }

    // Rebuilds File > Open Recent and the saved macro list each time they open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == MainMenu.savedMacrosTitle || menu.title == MainMenu.deleteMacrosTitle {
            let deleting = menu.title == MainMenu.deleteMacrosTitle
            menu.removeAllItems()
            for macro in state.savedMacros {
                let item = NSMenuItem(title: macro.name,
                                      action: deleting ? #selector(deleteSavedMacro(_:)) : #selector(playSavedMacro(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = macro.id
                menu.addItem(item)
            }
            if state.savedMacros.isEmpty {
                menu.addItem(NSMenuItem(title: "No Saved Macros", action: nil, keyEquivalent: ""))
            }
            return
        }
        menu.removeAllItems()
        for url in state.recentFiles {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
        if !state.recentFiles.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecent), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc func newFile() {
        // After the window was closed, its empty Untitled tab is the new file.
        if isWindowVisible || !state.isPristine { state.createNewDocument() }
        showWindow()
    }
    @objc func openFile() {
        files.open()
        // Show the window only if a file was opened, not if the panel was cancelled.
        if !isWindowVisible, !state.isPristine { showWindow() }
    }
    @objc func saveFile() { if let id = state.focusedDocumentID { files.save(id) } }
    @objc func saveFileAs() { if let id = state.focusedDocumentID { files.saveAs(id) } }
    @objc func saveAllFiles() { files.saveAll() }
    // In the second pane, ⌘W closes the split, not the tab.
    @objc func closeTab() {
        // ⌘W in another window, such as About, closes that window, not a tab.
        if let key = NSApp.keyWindow, key !== window {
            key.performClose(nil)
            return
        }
        if state.isSplit && state.splitFocused {
            state.closeSplit()
        } else if let id = state.activeDocumentID {
            files.close(id)
        }
    }
    @objc func toggleSplit() { state.toggleSplit() }
    @objc func toggleMinimap() { state.toggleMinimap() }
    @objc func showChanges() { state.showChanges() }
    @objc func showAbout() { AboutSlate.show() }
    @objc func openRepository() { NSWorkspace.shared.open(AboutSlate.repository) }
    @objc func openReleases() { NSWorkspace.shared.open(AboutSlate.releases) }
    @objc func openIssues() { NSWorkspace.shared.open(AboutSlate.issues) }
    @objc func toggleTerminal() { state.toggleTerminal() }
    @objc func openTerminalHere() { state.openTerminalInFileFolder() }
    @objc func gitCommit() { gitActions.commit() }
    @objc func gitPush() { gitActions.push() }
    @objc func gitPull() { gitActions.pull() }
    @objc func gitFetch() { gitActions.fetch() }
    @objc func gitSwitchBranch() { gitActions.switchBranch() }
    @objc func toggleChangeHistory() { state.toggleChangeHistory() }
    @objc func performLineOperation(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String, let operation = LineOperation(rawValue: name) {
            state.perform(operation)
        }
    }
    @objc func toggleMacroRecording() {
        state.isRecordingMacro ? state.stopRecordingMacro() : state.startRecordingMacro()
    }
    @objc func playMacro() { state.playRecordedMacro() }
    @objc func playMacroManyTimes() { files.askForMacroRuns() }
    @objc func saveMacro() { files.askForMacroName() }
    @objc func playSavedMacro(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID, let macro = state.savedMacros.first(where: { $0.id == id }) {
            state.play(macro.actions)
        }
    }
    @objc func deleteSavedMacro(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { state.deleteMacro(id) }
    }
    @objc func toggleSplitDirection() { state.splitVertically.toggle() }
    @objc func showFind() { state.showFind() }
    @objc func showReplace() { state.showFind(replace: true) }
    @objc func findNext() { state.findNext() }
    @objc func findPrevious() { state.findPrevious() }
    @objc func toggleWordWrap() { state.toggleWordWrap() }
    @objc func nextTab() { state.selectNextTab() }
    @objc func previousTab() { state.selectPreviousTab() }
}
