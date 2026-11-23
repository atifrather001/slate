import AppKit

/// A small overview of the text beside a pane, like Notepad++'s Document Map.
/// Each line is drawn as colored bars. Click or drag to scroll there.
final class MinimapView: NSView {
    static let width: CGFloat = 96
    static let lineHeight: CGFloat = 2.5
    static let charWidth: CGFloat = 1.2
    private static let maximumColumns = 72
    private static let marker = try! NSRegularExpression(pattern: "\\b(TODO|FIXME|XXX|HACK)\\b")

    private weak var pane: EditorPane?

    init(pane: EditorPane) {
        self.pane = pane
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 100))
        clipsToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.scrollBar)
        setAccessibilityLabel("Document map")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used: the editor is built in code") }

    override var isFlipped: Bool { true }

    /// The first line drawn at the top, so long files scroll along with the text.
    private func firstLine(lineCount: Int, visible: Range<Int>) -> Int {
        let fits = Int(bounds.height / Self.lineHeight)
        guard lineCount > fits else { return 0 }
        let scrollable = max(1, lineCount - visible.count)
        let fraction = Double(visible.lowerBound) / Double(scrollable)
        return Int((Double(lineCount - fits) * min(max(fraction, 0), 1)).rounded())
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        guard let pane, let session = pane.session else { return }
        let text = session.storage.string as NSString
        let starts = session.lineStarts
        let visible = pane.visibleLines()
        let top = firstLine(lineCount: starts.count, visible: visible)
        let spans = session.highlightSpans
        let plain = NSColor.textColor.withAlphaComponent(0.45)

        // The visible part of the text.
        let box = NSRect(x: 0, y: CGFloat(visible.lowerBound - top) * Self.lineHeight,
                         width: bounds.width, height: max(CGFloat(visible.count), 1) * Self.lineHeight)
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        box.fill()

        var spanIndex = 0
        let rows = Int(bounds.height / Self.lineHeight) + 1
        for line in top..<min(starts.count, top + rows) {
            let start = starts[line]
            let end = line + 1 < starts.count ? starts[line + 1] : text.length
            let length = min(end - start, Self.maximumColumns)
            guard length > 0 else { continue }
            let y = CGFloat(line - top) * Self.lineHeight
            let lineText = text.substring(with: NSRange(location: start, length: length))
            while spanIndex < spans.count, NSMaxRange(spans[spanIndex].range) <= start { spanIndex += 1 }

            var column = 0, index = spanIndex
            for unit in lineText.utf16 {
                defer { column += 1 }
                if unit == 32 || unit == 9 || unit == 10 || unit == 13 { continue }
                let location = start + column
                while index < spans.count, NSMaxRange(spans[index].range) <= location { index += 1 }
                let color = index < spans.count && spans[index].range.location <= location ? spans[index].color : plain
                color.withAlphaComponent(0.85).setFill()
                NSRect(x: 4 + CGFloat(column) * Self.charWidth, y: y, width: Self.charWidth, height: Self.lineHeight - 0.5).fill()
            }
            if Self.marker.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length)) != nil {
                NSColor.systemOrange.setFill()
                NSRect(x: 0, y: y - 0.5, width: 3, height: Self.lineHeight + 1).fill()
            }
        }

        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }

    override func mouseDown(with event: NSEvent) { scroll(to: event) }
    override func mouseDragged(with event: NSEvent) { scroll(to: event) }

    private func scroll(to event: NSEvent) {
        guard let pane, let session = pane.session else { return }
        let point = convert(event.locationInWindow, from: nil)
        let visible = pane.visibleLines()
        let top = firstLine(lineCount: session.lineStarts.count, visible: visible)
        pane.center(onLine: top + Int(point.y / Self.lineHeight))
    }
}
