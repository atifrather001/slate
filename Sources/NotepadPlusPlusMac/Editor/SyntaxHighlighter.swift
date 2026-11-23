import AppKit
import Highlightr

/// Highlightr runs JavaScript, so it lives on one background queue.
final class SyntaxHighlighter {
    struct Span {
        let range: NSRange
        let color: NSColor
    }

    static let shared = SyntaxHighlighter()
    static let maximumLength = 300_000

    private let queue = DispatchQueue(label: "Slate.highlighting", qos: .userInitiated)
    private var engine: Highlightr?
    private var themeName: String?

    func highlight(_ text: String, language: String, dark: Bool, completion: @escaping ([Span]) -> Void) {
        queue.async {
            let spans = self.spans(text, language: language, theme: dark ? "atom-one-dark" : "xcode")
            DispatchQueue.main.async { completion(spans) }
        }
    }

    private func spans(_ text: String, language: String, theme: String) -> [Span] {
        if engine == nil { engine = Highlightr() }
        guard let engine else { return [] }
        if themeName != theme, engine.setTheme(to: theme) { themeName = theme }
        // If the output length differs, its ranges don't apply to the text being edited.
        guard let result = engine.highlight(text, as: language),
              result.length == (text as NSString).length else { return [] }

        var spans: [Span] = []
        let all = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.foregroundColor, in: all) { value, range, _ in
            if let color = value as? NSColor { spans.append(Span(range: range, color: color)) }
        }
        return spans
    }
}
