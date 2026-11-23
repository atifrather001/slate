import AppKit
import XCTest
@testable import NotepadPlusPlusMac

@MainActor
final class MinimapTests: XCTestCase {
    private func hosted(_ state: AppState) -> (NSWindow, PaneHost) {
        // Never ordered in, so nothing appears on screen.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: true)
        let host = PaneHost(frame: window.contentView!.bounds)
        window.contentView = host
        host.show(state.activeSession!.primary, takingFocus: false)
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }

    func testMinimapSitsBesideTheTextAndToggles() {
        let state = AppState()
        let (_, host) = hosted(state)
        let pane: EditorPane = state.activeSession!.primary
        XCTAssertEqual(pane.minimap.frame.width, MinimapView.width)
        XCTAssertEqual(pane.scrollView.frame.width, 800 - MinimapView.width)
        state.toggleMinimap()
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(pane.minimap.isHidden)
        XCTAssertEqual(pane.scrollView.frame.width, 800)
    }

    func testClickingScrollsTheTextNotTheCursor() {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: (1...400).map { "line \($0)" }.joined(separator: "\n"))
        state.updateSelection(for: id, to: NSRange(location: 0, length: 0))
        let (_, _) = hosted(state)
        let pane: EditorPane = state.activeSession!.primary
        pane.textView.scroll(.zero)
        XCTAssertEqual(pane.visibleLines().lowerBound, 0)
        pane.center(onLine: 300)
        let visible = pane.visibleLines()
        XCTAssertTrue(visible.contains(300), "\(visible)")
        XCTAssertEqual(state.activeDocument?.selectionRange.location, 0)
        pane.center(onLine: 10_000)
        XCTAssertTrue(pane.visibleLines().contains(399))
    }

    func testDrawsColoredCodeAndMarkers() async throws {
        let state = AppState()
        let id = state.activeDocumentID!
        state.updateContent(for: id, newContent: "// TODO: tidy\nlet a = \"text\"\n\n    let b = 2\n")
        state.setLanguage(.swift, for: id)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let (_, _) = hosted(state)
        let map = state.activeSession!.primary!.minimap
        let rep = map.bitmapImageRepForCachingDisplay(in: map.bounds)!
        map.cacheDisplay(in: map.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / map.bounds.width
        func color(_ x: CGFloat, _ y: CGFloat) -> NSColor { rep.colorAt(x: Int(x * scale), y: Int(y * scale))! }
        let background = color(90, 200)
        XCTAssertGreaterThan(color(1, 1).redComponent, 0.8, "orange TODO marker")
        XCTAssertNotEqual(color(5, 3.5 + 1), background, "code on line 2")
        XCTAssertEqual(color(5, 3 * 2.5 + 1), color(5, 2 * 2.5 + 1), "indent on line 4 is empty like blank line 3")
        XCTAssertNotEqual(color(4 + 5 * 1.2, 3 * 2.5 + 1), background, "code after the indent")
    }

    func testSecondPaneHasItsOwnMinimap() {
        let state = AppState()
        state.showInSplit(state.activeDocumentID!)
        let session = state.activeSession!
        XCTAssertFalse(session.primary.minimap === session.secondary!.minimap)
        state.toggleMinimap()
        XCTAssertFalse(session.secondary!.showsMinimap)
    }
}
