import AppKit

final class LineNumberRuler: NSRulerView {
    private weak var pane: EditorPane?

    init(pane: EditorPane) {
        self.pane = pane
        super.init(scrollView: pane.scrollView, orientation: .verticalRuler)
        clientView = pane.textView
        ruleThickness = 44
        clipsToBounds = true // Since macOS 14 views can draw over their siblings without this.
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("Not used: the editor is built in code") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let pane, let session = pane.session, let layout = pane.textView.layoutManager,
              let container = pane.textView.textContainer else { return }
        let textView = pane.textView
        let labelSize = max(9, session.fontSize - 2)
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: labelSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let diff = session.gitDiff
        let history = session.changeHistory
        func draw(_ number: Int, at y: CGFloat, height: CGFloat) {
            let label = String(number) as NSString
            let x = bounds.width - label.size(withAttributes: attributes).width - 6
            let top = convert(NSPoint(x: 0, y: y + textView.textContainerOrigin.y), from: textView).y
            label.draw(at: NSPoint(x: x, y: top + 1), withAttributes: attributes)
            // Git: a bar for added or changed lines, a red wedge where lines were deleted.
            if let change = diff?.changes[number - 1] {
                (change == .added ? NSColor.systemGreen : NSColor.systemBlue).setFill()
                NSRect(x: 1, y: top, width: 3, height: height).fill()
            }
            // Change history, next to the text: orange for unsaved edits, green once saved.
            if history.unsaved.contains(number - 1) {
                NSColor.systemOrange.setFill()
                NSRect(x: bounds.width - 3, y: top, width: 3, height: height).fill()
            } else if history.saved.contains(number - 1) {
                NSColor.systemGreen.withAlphaComponent(0.8).setFill()
                NSRect(x: bounds.width - 3, y: top, width: 3, height: height).fill()
            }
            if diff?.deletionsAbove.contains(number - 1) == true {
                NSColor.systemRed.setFill()
                let wedge = NSBezierPath()
                wedge.move(to: NSPoint(x: 0, y: top - 4))
                wedge.line(to: NSPoint(x: 6, y: top))
                wedge.line(to: NSPoint(x: 0, y: top + 4))
                wedge.close()
                wedge.fill()
            }
        }

        let starts = session.lineStarts
        let glyphs = layout.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let length = session.storage.length
        var index = max(0, session.lineNumber(at: characters.location) - 1)

        while index < starts.count, starts[index] < length, starts[index] <= NSMaxRange(characters) {
            let glyph = layout.glyphIndexForCharacter(at: starts[index])
            let end = index + 1 < starts.count ? starts[index + 1] : length
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: starts[index], length: end - starts[index]),
                                           actualCharacterRange: nil)
            let first = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let last = glyphs.length > 0
                ? layout.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil) : first
            draw(index + 1, at: first.minY, height: last.maxY - first.minY)
            index += 1
        }
        // The empty line at the end of the file has no glyph.
        if starts.last == length, NSMaxRange(characters) >= length {
            draw(starts.count, at: layout.extraLineFragmentRect.minY, height: layout.extraLineFragmentRect.height)
        }
    }

    func update(lineCount: Int) {
        let digit = max(9, (pane?.session?.fontSize ?? 13) - 2) * 0.62
        let width = max(44, CGFloat(String(lineCount).count) * digit + 16)
        if ruleThickness != width { ruleThickness = width }
        needsDisplay = true
    }
}
