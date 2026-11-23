import Foundation

enum LineChange: Equatable {
    case added, modified
}

/// A line-by-line comparison of the last commit with the text being edited.
struct LineDiff {
    /// Changed lines in the new text, counted from 0.
    private(set) var changes: [Int: LineChange] = [:]
    /// New-text lines (counted from 0) that have lines deleted just above them.
    private(set) var deletionsAbove: Set<Int> = []
    private(set) var added = 0, modified = 0, deleted = 0
    private let old: [Substring], new: [Substring]
    private let oldKept: [Bool], newKept: [Bool]

    static let maximumLines = 50_000

    static func lines(_ text: String) -> [Substring] {
        text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    init?(old oldText: String, new newText: String) {
        old = Self.lines(oldText)
        new = Self.lines(newText)
        guard old.count + new.count <= Self.maximumLines * 2 else { return nil }
        let difference = new.difference(from: old)
        var oldKept = Array(repeating: true, count: old.count)
        var newKept = Array(repeating: true, count: new.count)
        for change in difference {
            switch change {
            case .remove(let offset, _, _): oldKept[offset] = false
            case .insert(let offset, _, _): newKept[offset] = false
            }
        }
        self.oldKept = oldKept
        self.newKept = newKept

        // Walk both texts; a run of removals followed by insertions is a modification.
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, oldKept[i], newKept[j] {
                i += 1; j += 1
                continue
            }
            var removed = 0, inserted = 0
            while i < old.count, !oldKept[i] { removed += 1; i += 1 }
            let firstInsert = j
            while j < new.count, !newKept[j] { inserted += 1; j += 1 }
            let paired = min(removed, inserted)
            for line in firstInsert..<(firstInsert + inserted) {
                changes[line] = line - firstInsert < paired ? .modified : .added
            }
            modified += paired
            added += inserted - paired
            if removed > inserted {
                deleted += removed - inserted
                deletionsAbove.insert(firstInsert + inserted)
            }
            if removed == 0 && inserted == 0 { break } // unreachable with a valid difference
        }
    }

    var isEmpty: Bool { added == 0 && modified == 0 && deleted == 0 }

    /// The changes as a unified diff with three lines of context.
    func unified(oldName: String, newName: String, context: Int = 3) -> String {
        // Edit script: (" ", old, new), ("-", old, nil), ("+", nil, new).
        var script: [(Character, Int?, Int?)] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, oldKept[i], newKept[j] {
                script.append((" ", i, j)); i += 1; j += 1
            } else if i < old.count, !oldKept[i] {
                script.append(("-", i, nil)); i += 1
            } else if j < new.count, !newKept[j] {
                script.append(("+", nil, j)); j += 1
            } else {
                break
            }
        }
        var output = "--- \(oldName)\n+++ \(newName)\n"
        var index = 0
        while let start = script[index...].firstIndex(where: { $0.0 != " " }) {
            var end = start
            // Like git, join changes separated by no more than two contexts of unchanged lines.
            while let next = script[(end + 1)...].firstIndex(where: { $0.0 != " " }), next - end - 1 <= context * 2 {
                end = next
            }
            let from = max(start - context, index == 0 ? 0 : index)
            let to = min(end + context, script.count - 1)
            let slice = script[from...to]
            let oldStart = (slice.first { $0.1 != nil }?.1 ?? (slice.first?.2 ?? 0)) + 1
            let newStart = (slice.first { $0.2 != nil }?.2 ?? (slice.first?.1 ?? 0)) + 1
            let oldCount = slice.filter { $0.1 != nil }.count
            let newCount = slice.filter { $0.2 != nil }.count
            output += "@@ -\(oldCount == 0 ? oldStart - 1 : oldStart),\(oldCount) +\(newCount == 0 ? newStart - 1 : newStart),\(newCount) @@\n"
            for (kind, o, n) in slice {
                let line = kind == "+" ? new[n!] : old[o!]
                output += "\(kind)\(line)\n"
            }
            index = to + 1
            if index >= script.count { break }
        }
        return output
    }
}
