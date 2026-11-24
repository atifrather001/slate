import AppKit

final class EditorTextView: NSTextView {
    var appearanceChanged: (() -> Void)?
    var focused: (() -> Void)?
    /// Sees typing and editing keys, for macro recording.
    var performed: ((MacroAction) -> Void)?
    /// Files dragged in from Finder are opened as tabs instead of being pasted in as paths.
    var filesDropped: (([URL]) -> Void)?

    /// The files, not folders, on a pasteboard from Finder.
    static func droppedFiles(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { url in
            var folder: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) && !folder.boolValue
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !Self.droppedFiles(on: sender.draggingPasteboard).isEmpty { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !Self.droppedFiles(on: sender.draggingPasteboard).isEmpty { return .copy }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if openDroppedFiles(from: sender.draggingPasteboard) { return true }
        return super.performDragOperation(sender)
    }

    func openDroppedFiles(from pasteboard: NSPasteboard) -> Bool {
        let files = Self.droppedFiles(on: pasteboard)
        guard !files.isEmpty, let filesDropped else { return false }
        filesDropped(files)
        return true
    }

    private var commandDepth = 0

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? string as? String
        super.insertText(string, replacementRange: replacementRange)
        // Commands like insertNewline: type through here; they are recorded as the command.
        if let text, commandDepth == 0 { performed?(.insert(text)) }
    }

    override func doCommand(by selector: Selector) {
        commandDepth += 1
        super.doCommand(by: selector)
        commandDepth -= 1
        if commandDepth == 0 { performed?(.command(NSStringFromSelector(selector))) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focused?() }
        return accepted
    }
}

/// One tab's text, undo history, line index and highlighting.
/// It is shown in one pane, or two when the tab is in both halves of a split.
@MainActor
final class EditorSession: NSObject {
    let storage = NSTextStorage()
    let undo = UndoManager()
    private(set) var primary: EditorPane!
    private(set) var secondary: EditorPane?
    /// The pane the user worked in last; editing commands act on it.
    private(set) var currentPane: EditorPane!

    var onEdit: ((String, NSRange) -> Void)?
    var onSelect: ((NSRange) -> Void)?
    var onFocus: ((EditorPane) -> Void)?
    var onAction: ((MacroAction) -> Void)?
    var onFilesDropped: (([URL]) -> Void)?

    var language: Language = .plainText {
        didSet { if language != oldValue { scheduleHighlight() } }
    }

    private(set) var fontSize: CGFloat = 13
    private(set) var wordWrap = true
    private var cachedLineStarts: [Int]?
    private var pendingHighlight: DispatchWorkItem?
    private var spans: [SyntaxHighlighter.Span] = []
    var highlightSpans: [SyntaxHighlighter.Span] { spans }
    /// Lines changed since the last commit, drawn in the line number margin.
    var gitDiff: LineDiff? {
        didSet { panes.forEach { $0.lineCountChanged() } }
    }
    /// Lines edited since the tab was opened, as in Notepad++'s Change History (counted from 0).
    var changeHistory = ChangeHistory() {
        didSet { if changeHistory != oldValue { panes.forEach { $0.lineCountChanged() } } }
    }
    private(set) var showsMinimap = true
    private var revision = 0
    private(set) var isLoading = false

    var textView: EditorTextView { currentPane.textView }
    var scrollView: NSScrollView { primary.scrollView }
    var panes: [EditorPane] { [primary] + (secondary.map { [$0] } ?? []) }

    override init() {
        super.init()
        primary = EditorPane(session: self)
        currentPane = primary
        NotificationCenter.default.addObserver(self, selector: #selector(storageEdited),
                                               name: NSTextStorage.didProcessEditingNotification, object: storage)
    }

    func load(_ text: String) {
        isLoading = true
        primary.textView.string = text
        panes.forEach { $0.textView.setSelectedRange(NSRange(location: 0, length: 0)) }
        undo.removeAllActions()
        isLoading = false
        cachedLineStarts = nil
        panes.forEach { $0.lineCountChanged() }
        scheduleHighlight()
    }

    /// An edit that can be undone.
    func replace(_ range: NSRange, with text: String) {
        let textView = self.textView
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.breakUndoCoalescing()
        storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: textView.typingAttributes))
        textView.didChangeText()
        textView.breakUndoCoalescing()
    }

    func select(_ range: NSRange) { currentPane.select(range) }

    func setFontSize(_ size: CGFloat) {
        fontSize = size
        panes.forEach { $0.setFontSize(size) }
    }

    func setWordWrap(_ wrap: Bool) {
        wordWrap = wrap
        panes.forEach { $0.setWordWrap(wrap) }
    }

    func setShowsMinimap(_ show: Bool) {
        showsMinimap = show
        panes.forEach { $0.setShowsMinimap(show) }
    }

    /// Moves the cursor to the start of a line, clamped to the file.
    func goTo(line: Int) {
        let starts = lineStarts
        let index = min(max(line, 1), starts.count) - 1
        select(NSRange(location: min(starts[index], storage.length), length: 0))
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: Split

    /// A second view of the same text, sharing its edits and undo history.
    func makeSecondaryPane() -> EditorPane {
        if let secondary { return secondary }
        let pane = EditorPane(session: self, isSecondary: true)
        pane.setFontSize(fontSize)
        pane.setWordWrap(wordWrap)
        pane.setShowsMinimap(showsMinimap)
        pane.textView.setSelectedRange(primary.textView.selectedRange())
        pane.apply(spans)
        secondary = pane
        return pane
    }

    func removeSecondaryPane() {
        guard let pane = secondary else { return }
        secondary = nil
        if currentPane === pane { currentPane = primary }
        pane.detach()
    }

    func use(_ pane: EditorPane) {
        guard pane === primary || pane === secondary else { return }
        currentPane = pane
    }

    // MARK: Lines

    var lineStarts: [Int] {
        if let cachedLineStarts { return cachedLineStarts }
        var starts = [0]
        var afterCR = false
        for (index, unit) in storage.string.utf16.enumerated() {
            if unit == 10 && afterCR {
                starts[starts.count - 1] = index + 1
            } else if unit == 10 || unit == 13 {
                starts.append(index + 1)
            }
            afterCR = unit == 13
        }
        cachedLineStarts = starts
        return starts
    }

    func lineNumber(at location: Int) -> Int {
        let starts = lineStarts
        var low = 0, high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= location { low = middle + 1 } else { high = middle }
        }
        return max(1, low)
    }

    func cursorPosition(at location: Int) -> (line: Int, column: Int) {
        let line = lineNumber(at: location)
        return (line, location - lineStarts[line - 1] + 1)
    }

    @objc private func storageEdited() { cachedLineStarts = nil }

    // MARK: From the panes

    func paneDidEdit(_ pane: EditorPane) {
        guard !isLoading else { return }
        currentPane = pane
        cachedLineStarts = nil
        panes.forEach { $0.lineCountChanged() }
        onEdit?(storage.string, pane.textView.selectedRange())
        scheduleHighlight()
    }

    func paneDidSelect(_ pane: EditorPane) {
        guard !isLoading, pane === currentPane else { return }
        onSelect?(pane.textView.selectedRange())
    }

    func paneDidFocus(_ pane: EditorPane) {
        currentPane = pane
        onSelect?(pane.textView.selectedRange())
        onFocus?(pane)
    }

    // MARK: Highlighting

    func scheduleHighlight() {
        revision += 1
        pendingHighlight?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.highlightNow() }
        }
        pendingHighlight = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func highlightNow() {
        let text = storage.string
        let length = storage.length
        guard let name = language.highlighterName, length > 0, length <= SyntaxHighlighter.maximumLength else {
            apply([])
            return
        }
        let requested = revision
        let appearance = primary.textView.effectiveAppearance
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        SyntaxHighlighter.shared.highlight(text, language: name, dark: dark) { [weak self] spans in
            MainActor.assumeIsolated {
                guard let self, self.revision == requested else { return }
                self.apply(spans)
            }
        }
    }

    private func apply(_ spans: [SyntaxHighlighter.Span]) {
        self.spans = spans
        panes.forEach { $0.apply(spans) }
    }
}

/// A scrolling text view with line numbers, showing a session's text.
@MainActor
final class EditorPane: NSObject, NSTextViewDelegate {
    let scrollView = NSScrollView()
    let textView: EditorTextView
    let isSecondary: Bool
    private(set) lazy var minimap = MinimapView(pane: self)
    private(set) var showsMinimap = true
    /// Called when the minimap is shown or hidden, so the host can lay out again.
    var layoutChanged: (() -> Void)?
    private(set) weak var session: EditorSession?
    private let layout = NSLayoutManager()
    private var ruler: LineNumberRuler?

    init(session: EditorSession, isSecondary: Bool = false) {
        self.session = session
        self.isSecondary = isSecondary
        // TextKit 1, for temporary color attributes, the line number ruler and shared text in a split.
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        session.storage.addLayoutManager(layout)
        textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        super.init()

        let unlimited = CGFloat.greatestFiniteMagnitude
        textView.minSize = .zero
        textView.maxSize = NSSize(width: unlimited, height: unlimited)
        textView.isVerticallyResizable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: session.fontSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .textColor
        // A code editor must never rewrite what was typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.delegate = self
        textView.appearanceChanged = { [weak session] in session?.scheduleHighlight() }
        textView.performed = { [weak session] action in session?.onAction?(action) }
        textView.filesDropped = { [weak session] files in session?.onFilesDropped?(files) }
        textView.focused = { [weak self, weak session] in
            guard let self else { return }
            session?.paneDidFocus(self)
        }

        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        let ruler = LineNumberRuler(pane: self)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        self.ruler = ruler

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        setWordWrap(session.wordWrap)
        showsMinimap = session.showsMinimap
    }

    func detach() {
        NotificationCenter.default.removeObserver(self)
        scrollView.removeFromSuperview()
        minimap.removeFromSuperview()
        session?.storage.removeLayoutManager(layout)
    }

    func select(_ range: NSRange) {
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        if textView.window != nil, range.length > 0 { textView.showFindIndicator(for: range) }
    }

    func setFontSize(_ size: CGFloat) {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        textView.font = font
        textView.typingAttributes[.font] = font
        lineCountChanged()
    }

    func setWordWrap(_ wrap: Bool) {
        guard let container = textView.textContainer else { return }
        scrollView.hasHorizontalScroller = !wrap
        textView.isHorizontallyResizable = !wrap
        textView.autoresizingMask = wrap ? [.width] : []
        container.widthTracksTextView = wrap
        let visibleWidth = max(scrollView.contentSize.width, 100)
        container.size = NSSize(width: wrap ? visibleWidth : .greatestFiniteMagnitude,
                                height: .greatestFiniteMagnitude)
        if wrap { textView.setFrameSize(NSSize(width: visibleWidth, height: textView.frame.height)) }
        ruler?.needsDisplay = true
    }

    func lineCountChanged() {
        ruler?.update(lineCount: session?.lineStarts.count ?? 1)
        minimap.needsDisplay = true
    }

    func setShowsMinimap(_ show: Bool) {
        guard show != showsMinimap else { return }
        showsMinimap = show
        layoutChanged?()
    }

    /// Lines (counted from 0) that are at least partly on screen.
    func visibleLines() -> Range<Int> {
        guard let session, let layout = textView.layoutManager, let container = textView.textContainer else { return 0..<1 }
        let glyphs = layout.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let first = session.lineNumber(at: characters.location) - 1
        let last = session.lineNumber(at: max(characters.location, NSMaxRange(characters) - 1)) - 1
        return first..<(last + 1)
    }

    /// Scrolls so a line (counted from 0) is in the middle, without moving the cursor.
    func center(onLine line: Int) {
        guard let session, let layout = textView.layoutManager else { return }
        let starts = session.lineStarts
        let location = min(starts[min(max(line, 0), starts.count - 1)], session.storage.length)
        let lineRect: NSRect
        if location >= session.storage.length, session.storage.length > 0, layout.extraLineFragmentTextContainer != nil {
            lineRect = layout.extraLineFragmentRect
        } else {
            layout.ensureLayout(forCharacterRange: NSRange(location: 0, length: location))
            let glyph = layout.glyphIndexForCharacter(at: location)
            lineRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        let y = min(max(lineRect.midY + textView.textContainerOrigin.y - clip.bounds.height / 2, 0), maxY)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    func apply(_ spans: [SyntaxHighlighter.Span]) {
        let length = textView.textStorage?.length ?? 0
        // Temporary attributes don't touch the text or its undo history.
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        for span in spans where NSMaxRange(span.range) <= length {
            layout.addTemporaryAttribute(.foregroundColor, value: span.color, forCharacterRange: span.range)
        }
        minimap.needsDisplay = true
    }

    @objc private func scrolled() {
        ruler?.needsDisplay = true
        minimap.needsDisplay = true
    }

    func undoManager(for view: NSTextView) -> UndoManager? { session?.undo }
    func textDidChange(_ notification: Notification) { session?.paneDidEdit(self) }
    func textViewDidChangeSelection(_ notification: Notification) { session?.paneDidSelect(self) }
}
