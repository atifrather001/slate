import Foundation

/// A recorded run of typing and editing keys, played back into the focused editor.
struct Macro: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var actions: [MacroAction]
}

enum MacroAction: Codable, Equatable {
    case insert(String)
    /// An NSTextView key command such as moveDown: or deleteBackward:.
    case command(String)

    /// Only editing and cursor commands are recorded, so a macro can't trigger anything else.
    static func isRecordable(_ selector: String) -> Bool {
        let prefixes = ["move", "delete", "insert", "select", "page", "scroll", "transpose",
                        "capitalize", "uppercase", "lowercase", "centerSelection", "yank"]
        return selector.hasSuffix(":") && prefixes.contains { selector.hasPrefix($0) }
    }
}
