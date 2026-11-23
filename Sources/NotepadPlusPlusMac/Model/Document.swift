import Foundation

struct Document: Identifiable {
    let id = UUID()
    let untitledNumber: Int
    var content = ""
    var savedContent = ""
    /// The text when the tab was opened, for the change history margin.
    var openedContent = ""
    var fileURL: URL?
    /// The bytes last read or written, used to notice edits made by other apps.
    var diskData: Data?
    var language: Language = .plainText
    var encoding: FileEncoding = .utf8
    var savedEncoding: FileEncoding = .utf8
    var lineEnding: LineEnding = .lf
    var selectionRange = NSRange(location: 0, length: 0)
    /// For generated tabs, such as a file's changes. They can't be edited or saved.
    var isReadOnly = false
    var title: String?

    // String's == treats differently composed accents as equal; a file on disk does not.
    var isModified: Bool { !content.utf8.elementsEqual(savedContent.utf8) || encoding != savedEncoding }

    var displayName: String { title ?? fileURL?.lastPathComponent ?? "Untitled \(untitledNumber)" }
}
