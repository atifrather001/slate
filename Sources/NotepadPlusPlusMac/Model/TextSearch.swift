import Foundation

struct FindOptions: Equatable {
    var caseSensitive = false
    var wholeWord = false
    var regex = false
    var wrapAround = true
}

struct TextSearch {
    private let expression: NSRegularExpression
    private let template: String

    init?(query: String, replacement: String = "", options: FindOptions) {
        guard !query.isEmpty else { return nil }
        var pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
        if options.wholeWord { pattern = "(?<!\\w)(?:\(pattern))(?!\\w)" }
        var flags: NSRegularExpression.Options = [.anchorsMatchLines]
        if !options.caseSensitive { flags.insert(.caseInsensitive) }
        guard let expression = try? NSRegularExpression(pattern: pattern, options: flags) else { return nil }
        self.expression = expression
        template = options.regex
            ? TextSearch.expandEscapes(replacement)
            : NSRegularExpression.escapedTemplate(for: replacement)
    }

    /// NSRegularExpression reads \n in a replacement as the letter n; editors mean a newline.
    private static func expandEscapes(_ value: String) -> String {
        var result = ""
        var escaped = false
        for character in value {
            if escaped {
                switch character {
                case "n": result += "\n"
                case "t": result += "\t"
                case "r": result += "\r"
                default: result += "\\\(character)"
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return escaped ? result + "\\\\" : result
    }

    func matches(in text: String) -> [NSTextCheckingResult] {
        expression.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    func replacement(for match: NSTextCheckingResult, in text: String) -> String {
        expression.replacementString(for: match, in: text, offset: 0, template: template)
    }

    func replacingAll(in text: String) -> (text: String, count: Int) {
        let range = NSRange(location: 0, length: (text as NSString).length)
        let count = expression.numberOfMatches(in: text, range: range)
        return (expression.stringByReplacingMatches(in: text, range: range, withTemplate: template), count)
    }
}
