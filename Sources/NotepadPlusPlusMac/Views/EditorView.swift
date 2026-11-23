import SwiftUI

/// Shows one long-lived editor pane.
struct EditorView: NSViewRepresentable {
    let pane: EditorPane
    /// Whether this pane should take the keyboard when it appears.
    let takesFocus: Bool

    func makeNSView(context: Context) -> PaneHost {
        PaneHost()
    }

    func updateNSView(_ host: PaneHost, context: Context) {
        host.show(pane, takingFocus: takesFocus)
    }
}

/// Holds a pane's scroll view. SwiftUI can build a new host before it drops the old one,
/// for example when the split changes direction, so the host in the window claims the pane.
final class PaneHost: NSView {
    private weak var pane: EditorPane?
    private var takesFocus = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used: the editor is built in code") }

    func show(_ pane: EditorPane, takingFocus: Bool) {
        self.pane = pane
        takesFocus = takingFocus
        attach()
    }

    override func layout() {
        super.layout()
        layoutPane()
    }

    private func layoutPane() {
        guard let pane, pane.scrollView.superview === self else { return }
        let mapWidth = pane.showsMinimap && bounds.width > 400 ? MinimapView.width : 0
        pane.minimap.isHidden = mapWidth == 0
        pane.scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width - mapWidth, height: bounds.height)
        pane.minimap.frame = NSRect(x: bounds.width - mapWidth, y: 0, width: mapWidth, height: bounds.height)
        pane.minimap.needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attach()
    }

    private func attach() {
        guard let pane, window != nil else { return }
        pane.layoutChanged = { [weak self, weak pane] in
            guard let self, let pane, pane.scrollView.superview === self else { return }
            self.needsLayout = true
        }
        let editor = pane.scrollView
        guard editor.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        editor.autoresizingMask = []
        addSubview(editor)
        addSubview(pane.minimap)
        layoutPane()
        guard takesFocus else { return }
        let textView = pane.textView
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
    }
}
