import Foundation

/// Notepad++-style line operations. Each works on the lines the selection touches; the sorting
/// and cleanup ones work on the whole file when nothing is selected, as in Notepad++.
enum LineOperation: String, CaseIterable {
    case duplicate = "Duplicate Line"
    case delete = "Delete Line"
    case moveUp = "Move Line Up"
    case moveDown = "Move Line Down"
    case insertAbove = "Insert Blank Line Above"
    case insertBelow = "Insert Blank Line Below"
    case join = "Join Lines"
    case sortAscending = "Sort Lines Ascending"
    case sortDescending = "Sort Lines Descending"
    case sortIgnoringCase = "Sort Lines Ascending, Ignoring Case"
    case reverse = "Reverse Line Order"
    case removeDuplicates = "Remove Duplicate Lines"
    case removeConsecutiveDuplicates = "Remove Consecutive Duplicate Lines"
    case removeEmpty = "Remove Empty Lines"
    case removeBlank = "Remove Empty Lines (Including Blank Characters)"
    case trimTrailing = "Trim Trailing Space"
    case trimLeading = "Trim Leading Space"
    case trimBoth = "Trim Leading and Trailing Space"

    /// Works on the whole file when nothing is selected.
    var usesWholeFileWithoutSelection: Bool {
        switch self {
        case .duplicate, .delete, .moveUp, .moveDown, .insertAbove, .insertBelow, .join: return false
        default: return true
        }
    }

    struct Edit: Equatable {
        /// The range to replace, in UTF-16 units, and what replaces it.
        var range: NSRange
        var text: String
        /// The selection afterwards.
        var selection: NSRange
    }

    /// The edit to make, or nil when the operation changes nothing.
    func edit(in text: String, selection: NSRange) -> Edit? {
        let string = text as NSString
        let length = string.length
        let lineBreak: (Int) -> Bool = { string.character(at: $0) == 10 }

        // The block of whole lines the selection touches, without its final line break.
        var start = 0, end = length
        if !(usesWholeFileWithoutSelection && selection.length == 0) {
            start = string.lineRange(for: NSRange(location: selection.location, length: 0)).location
            var last = NSMaxRange(selection)
            // A selection ending at the start of a line doesn't include that line.
            if selection.length > 0, last > start, lineBreak(last - 1) { last -= 1 }
            let lastLine = string.lineRange(for: NSRange(location: min(last, length), length: 0))
            end = NSMaxRange(lastLine)
        }
        if end > start, lineBreak(end - 1) { end -= 1 }
        let block = NSRange(location: start, length: end - start)
        let lines = string.substring(with: block).components(separatedBy: "\n")
        let hasBreakAfter = end < length
        let offsetInBlock = selection.location - start

        func replaceBlock(_ newLines: [String], keepSelection: Bool = false) -> Edit? {
            let newText = newLines.joined(separator: "\n")
            guard newText != string.substring(with: block) else { return nil }
            let newLength = (newText as NSString).length
            // A cursor after the block (past the file's last line break) moves with the text after it.
            let cursor = selection.location > end
                ? selection.location + newLength - block.length
                : start + min(offsetInBlock, newLength)
            let selection = keepSelection
                ? NSRange(location: cursor, length: 0)
                : NSRange(location: start, length: newLength)
            return Edit(range: block, text: newText, selection: selection)
        }

        switch self {
        case .duplicate:
            let copy = string.substring(with: block)
            let shift = (copy as NSString).length + 1
            return Edit(range: NSRange(location: end, length: 0), text: "\n" + copy,
                        selection: NSRange(location: selection.location + shift, length: selection.length))

        case .delete:
            // Take the line break after the block, or before it on the last line.
            var range = block
            if hasBreakAfter {
                range.length += 1
            } else if start > 0 {
                range = NSRange(location: start - 1, length: block.length + 1)
            }
            guard range.length > 0 else { return nil }
            let cursor = min(range.location, length - range.length)
            return Edit(range: range, text: "", selection: NSRange(location: max(cursor, 0), length: 0))

        case .moveUp:
            guard start > 0 else { return nil }
            let previous = string.lineRange(for: NSRange(location: start - 1, length: 0))
            let above = string.substring(with: NSRange(location: previous.location, length: previous.length - 1))
            let moved = string.substring(with: block)
            let range = NSRange(location: previous.location, length: end - previous.location)
            return Edit(range: range, text: moved + "\n" + above,
                        selection: NSRange(location: selection.location - previous.length, length: selection.length))

        case .moveDown:
            guard hasBreakAfter else { return nil }
            let next = string.lineRange(for: NSRange(location: end + 1, length: 0))
            var below = string.substring(with: next)
            if below.hasSuffix("\n") { below.removeLast() }
            let moved = string.substring(with: block)
            let range = NSRange(location: start, length: next.location + (below as NSString).length - start)
            let shift = (below as NSString).length + 1
            return Edit(range: range, text: below + "\n" + moved,
                        selection: NSRange(location: selection.location + shift, length: selection.length))

        case .insertAbove:
            return Edit(range: NSRange(location: start, length: 0), text: "\n",
                        selection: NSRange(location: start, length: 0))

        case .insertBelow:
            return Edit(range: NSRange(location: end, length: 0), text: "\n",
                        selection: NSRange(location: end + 1, length: 0))

        case .join:
            // With one line, join it with the next one.
            var joined = lines
            var range = block
            if joined.count == 1 {
                guard hasBreakAfter else { return nil }
                let next = string.lineRange(for: NSRange(location: end + 1, length: 0))
                var below = string.substring(with: next)
                if below.hasSuffix("\n") { below.removeLast() }
                joined.append(below)
                range = NSRange(location: start, length: next.location + (below as NSString).length - start)
            }
            let text = joined.enumerated().map { index, line in
                index == 0 ? line : String(line.drop { $0 == " " || $0 == "\t" })
            }
            .reduce("") { result, line in
                result.isEmpty || line.isEmpty || result.hasSuffix(" ") ? result + line : result + " " + line
            }
            guard text != string.substring(with: range) else { return nil }
            return Edit(range: range, text: text, selection: NSRange(location: start + (text as NSString).length, length: 0))

        case .sortAscending: return replaceBlock(lines.sorted())
        case .sortDescending: return replaceBlock(lines.sorted(by: >))
        case .sortIgnoringCase:
            return replaceBlock(lines.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending })
        case .reverse: return replaceBlock(lines.reversed())
        case .removeDuplicates:
            var seen = Set<String>()
            return replaceBlock(lines.filter { seen.insert($0).inserted })
        case .removeConsecutiveDuplicates:
            return replaceBlock(lines.enumerated().filter { $0.offset == 0 || lines[$0.offset - 1] != $0.element }.map(\.element))
        case .removeEmpty: return replaceBlock(lines.filter { !$0.isEmpty })
        case .removeBlank:
            return replaceBlock(lines.filter { !$0.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" } })
        case .trimTrailing:
            return replaceBlock(lines.map { trimmed($0, leading: false, trailing: true) }, keepSelection: true)
        case .trimLeading:
            return replaceBlock(lines.map { trimmed($0, leading: true, trailing: false) }, keepSelection: true)
        case .trimBoth:
            return replaceBlock(lines.map { trimmed($0, leading: true, trailing: true) }, keepSelection: true)
        }
    }

    private func trimmed(_ line: String, leading: Bool, trailing: Bool) -> String {
        var result = Substring(line)
        // A carriage return ending a line in a mixed-ending file is kept.
        let keepCR = result.hasSuffix("\r")
        if keepCR { result.removeLast() }
        if leading { result = result.drop { $0 == " " || $0 == "\t" } }
        if trailing { while let last = result.last, last == " " || last == "\t" { result.removeLast() } }
        return String(result) + (keepCR ? "\r" : "")
    }
}
