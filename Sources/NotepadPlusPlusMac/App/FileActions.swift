import AppKit

/// Everything that needs a panel or an alert.
@MainActor
final class FileActions: ObservableObject {
    private let state: AppState

    init(state: AppState) {
        self.state = state
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK { open(panel.urls) }
    }

    func open(_ urls: [URL]) {
        for url in urls {
            do {
                try state.open(url)
            } catch {
                show(error, title: "Couldn't open \(url.lastPathComponent)")
                if !FileManager.default.fileExists(atPath: url.path) { state.forgetRecent(url) }
            }
        }
    }

    func askForMacroName() {
        guard let name = askForText("Save Macro", detail: "Name this macro.", placeholder: "My macro") else { return }
        state.saveRecordedMacro(named: name)
    }

    func askForMacroRuns() {
        guard let text = askForText("Run Macro Multiple Times", detail: "How many times? (1 to 10,000)",
                                    placeholder: "10"),
              let count = Int(text), (1...10_000).contains(count) else { return }
        state.playRecordedMacro(times: count)
    }

    private func askForText(_ title: String, detail: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespaces)
    }

    func askForLine() {
        guard let document = state.focusedDocument, let session = state.activeSession else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        let count = session.lineStarts.count
        alert.informativeText = "Enter a line number from 1 to \(count)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = String(session.cursorPosition(at: document.selectionRange.location).line)
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let line = Int(text.split(separator: ":").first ?? "") else { return }
        state.goTo(line: line)
    }

    @discardableResult
    func save(_ id: UUID) -> Bool {
        guard let document = state.documents[id], !document.isReadOnly else { return false }
        guard let url = document.fileURL else { return saveAs(id) }
        if state.hasChangedOnDisk(id) {
            let choice = ask("\(document.displayName) was changed by another app.",
                             detail: "Saving will overwrite those changes.",
                             buttons: ["Cancel", "Overwrite"])
            guard choice == .alertSecondButtonReturn else { return false }
        }
        return write(id, to: url)
    }

    @discardableResult
    func saveAs(_ id: UUID) -> Bool {
        guard let document = state.documents[id], !document.isReadOnly else { return false }
        state.setActiveDocument(id)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.fileURL?.lastPathComponent ?? "\(document.displayName).txt"
        panel.directoryURL = document.fileURL?.deletingLastPathComponent()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        if let other = state.document(at: url), other.id != id {
            _ = ask("\(url.lastPathComponent) is open in another tab.",
                    detail: "Close that tab first, or choose another name.", buttons: ["OK"])
            return false
        }
        return write(id, to: url)
    }

    func saveAll() {
        for id in state.modifiedDocumentIDs where !save(id) { return }
    }

    private func write(_ id: UUID, to url: URL) -> Bool {
        do {
            try state.save(id, to: url)
            return true
        } catch let error as TextFileError {
            guard case .cannotEncode = error else {
                show(error, title: "Couldn't save")
                return false
            }
            let choice = ask(error.localizedDescription, detail: "Save the file as UTF-8 instead?",
                             buttons: ["Save as UTF-8", "Cancel"])
            guard choice == .alertFirstButtonReturn else { return false }
            state.setEncoding(.utf8, for: id)
            return write(id, to: url)
        } catch {
            show(error, title: "Couldn't save \(url.lastPathComponent)")
            return false
        }
    }

    func close(_ id: UUID) {
        if confirmDiscardingChanges(id) { state.removeDocument(id) }
    }

    /// Asks about each unsaved tab, then closes them all. false if the user cancelled.
    func closeAll() -> Bool {
        guard state.modifiedDocumentIDs.allSatisfy(confirmDiscardingChanges) else { return false }
        state.closeAllDocuments()
        return true
    }

    func canQuit() -> Bool {
        state.modifiedDocumentIDs.allSatisfy(confirmDiscardingChanges)
    }

    private func confirmDiscardingChanges(_ id: UUID) -> Bool {
        guard let document = state.documents[id], document.isModified else { return true }
        state.setActiveDocument(id)
        switch ask("Save changes to \(document.displayName)?",
                   detail: "Your changes will be lost if you don't save them.",
                   buttons: ["Save", "Cancel", "Don't Save"]) {
        case .alertFirstButtonReturn: return save(id)
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func show(_ error: Error, title: String) {
        _ = ask(title, detail: error.localizedDescription, buttons: ["OK"])
    }

    private func ask(_ title: String, detail: String, buttons: [String]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert.runModal()
    }
}
