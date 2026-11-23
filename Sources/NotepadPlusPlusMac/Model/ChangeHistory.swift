import Foundation

/// Edited lines since a tab was opened: unsaved ones, and ones that have been saved since.
struct ChangeHistory: Equatable {
    var unsaved: Set<Int> = []
    var saved: Set<Int> = []

    init() {}

    /// nil when the file is too long to compare quickly.
    init?(opened: String, saved savedText: String, current: String) {
        guard let sinceSave = LineDiff(old: savedText, new: current),
              let sinceOpen = LineDiff(old: opened, new: current) else { return nil }
        unsaved = Set(sinceSave.changes.keys)
        saved = Set(sinceOpen.changes.keys).subtracting(unsaved)
    }
}
