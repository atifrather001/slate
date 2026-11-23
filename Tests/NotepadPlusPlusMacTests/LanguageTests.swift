import AppKit
import XCTest
@testable import NotepadPlusPlusMac

@MainActor
final class LanguageTests: XCTestCase {
    func testDetectionByFileName() {
        let cases: [String: Language] = [
            "a.sh": .shell, "a.bash": .shell, ".bashrc": .shell, ".zshrc": .shell,
            "a.ps1": .powershell, "A.PSM1": .powershell, "a.psd1": .powershell,
            "a.bat": .batch, "a.cmd": .batch, "A.cs": .csharp, "a.ini": .ini, "a.cfg": .ini,
            "Dockerfile": .dockerfile, "Dockerfile.dev": .dockerfile, "web.dockerfile": .dockerfile,
            "dockerfile.md": .markdown,
        ]
        for (name, language) in cases {
            XCTAssertEqual(Language.from(url: URL(fileURLWithPath: "/tmp/\(name)")), language, name)
        }
    }

    func testMenuSelectsAndChecksEveryLanguage() throws {
        let delegate = AppDelegate(store: nil)
        let main = MainMenu.make(target: delegate)
        let items = try XCTUnwrap(main.items.first { $0.submenu?.title == "Language" }?.submenu).items
        XCTAssertEqual(items.count, Language.allCases.count)
        for item in items {
            XCTAssertTrue(NSApplication.shared.sendAction(item.action!, to: item.target, from: item))
            XCTAssertEqual(delegate.state.activeDocument?.language.rawValue, item.title)
            for other in items { XCTAssertTrue(delegate.validateMenuItem(other)) }
            XCTAssertEqual(items.filter { $0.state == .on }.map(\.title), [item.title])
        }
    }

    func testNewLanguagesGetColored() async {
        let samples: [Language: String] = [
            .shell: "# note\nexport A=\"hi\"\nif true; then echo $A; fi\n",
            .powershell: "# note\n$x = \"hi\"\nGet-ChildItem -Path .\n",
            .batch: "@echo off\nREM note\nset X=1\necho %X%\n",
            .csharp: "// note\nclass A { string s = \"hi\"; int n = 1; }\n",
            .dockerfile: "# note\nFROM ubuntu:24.04\nRUN echo \"hi\"\n",
            .ini: "; note\n[section]\nkey = \"value\"\ncount = 2\n",
        ]
        for (language, text) in samples {
            let spans: [SyntaxHighlighter.Span] = await withCheckedContinuation { continuation in
                SyntaxHighlighter.shared.highlight(text, language: language.highlighterName!, dark: true) {
                    continuation.resume(returning: $0)
                }
            }
            XCTAssertGreaterThan(Set(spans.map { $0.color.description }).count, 1, language.rawValue)
        }
    }
}
