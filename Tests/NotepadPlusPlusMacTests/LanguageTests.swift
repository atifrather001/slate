import AppKit
import SwiftUI
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

@MainActor
final class AboutTests: XCTestCase {
    func testAboutDetails() throws {
        XCTAssertEqual(AboutSlate.publisher, "NexaSecure Cloud and AI")
        XCTAssertTrue(AboutSlate.copyright.hasSuffix("NexaSecure Cloud and AI"))
        let info = AboutSlate.versionInfo
        XCTAssertTrue(info.hasPrefix("Slate "))
        XCTAssertTrue(info.contains("SwiftTerm "))
        XCTAssertTrue(info.contains("macOS "))
        let licenses = AboutSlate.licensesText()
        XCTAssertTrue(licenses.hasPrefix("Slate\n\nMIT License"))
        XCTAssertTrue(licenses.contains("Copyright (c) 2026 NexaSecure Cloud and AI"))
        XCTAssertEqual(AboutSlate.repository.absoluteString, "https://github.com/atifrather001/slate")
        XCTAssertEqual(AboutSlate.issues.absoluteString, "https://github.com/atifrather001/slate/issues")
    }

    /// The versions shown in About must match what Slate is actually built with.
    func testLibraryVersionsMatchPackageResolved() throws {
        let resolved = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Package.resolved")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: resolved)) as? [String: Any]
        let pins = try XCTUnwrap(json?["pins"] as? [[String: Any]])
        var versions: [String: String] = [:]
        for pin in pins {
            if let identity = pin["identity"] as? String, let state = pin["state"] as? [String: Any],
               let version = state["version"] as? String { versions[identity] = version }
        }
        let identities = ["SwiftTerm": "swiftterm", "Highlightr": "highlightr", "Swift Collections": "swift-collections"]
        for library in AboutSlate.libraries {
            XCTAssertEqual(versions[identities[library.name]!], library.version, library.name)
        }
    }

    func testAboutWindowRenders() throws {
        let host = NSHostingView(rootView: AboutView())
        host.frame = NSRect(x: 0, y: 0, width: 460, height: 610)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, 460)
    }

    func testLicenseTextMatchesTheRepository() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LICENSE")
        let squash = { (s: String) in s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        XCTAssertEqual(squash(AboutSlate.slateLicense), squash(try String(contentsOf: file, encoding: .utf8)))
    }

    func testHelpMenu() throws {
        let delegate = AppDelegate(store: nil)
        let menu = MainMenu.make(target: delegate)
        XCTAssertEqual(menu.items.last?.title, "Help")
        XCTAssertEqual(menu.items.last?.submenu?.items.map(\.title),
                       ["Slate on GitHub", "Check for Updates…", "Report an Issue…"])
        XCTAssertEqual(menu.items.first?.submenu?.items.first?.action, #selector(AppDelegate.showAbout))
    }
}
