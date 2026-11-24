import AppKit

/// What the About window and Help menu say about Slate.
enum AboutSlate {
    static let publisher = "NexaSecure Cloud and AI"
    static let repository = URL(string: "https://github.com/atifrather001/slate")!
    static let releases = URL(string: "https://github.com/atifrather001/slate/releases")!
    static let issues = URL(string: "https://github.com/atifrather001/slate/issues")!
    static let license = URL(string: "https://github.com/atifrather001/slate/blob/main/LICENSE")!

    static let credits: [(name: String, license: String, url: String)] = [
        ("SwiftTerm", "MIT", "https://github.com/migueldeicaza/SwiftTerm"),
        ("Highlightr", "MIT", "https://github.com/raspu/Highlightr"),
        ("highlight.js", "BSD-3-Clause", "https://highlightjs.org"),
        ("Swift Collections", "Apache-2.0", "https://github.com/apple/swift-collections"),
    ]

    /// The text under the app name and version in the About window.
    static func creditsText() -> NSAttributedString {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.paragraphSpacing = 6
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: centered,
        ]
        let small: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centered,
        ]
        let text = NSMutableAttributedString()
        func add(_ string: String, _ attributes: [NSAttributedString.Key: Any], link: URL? = nil) {
            var attributes = attributes
            if let link { attributes[.link] = link }
            text.append(NSAttributedString(string: string, attributes: attributes))
        }

        var heading = body
        heading[.font] = NSFont.systemFont(ofSize: 12, weight: .semibold)
        add("An app by \(publisher)\n", heading)
        add("A fast, native text and code editor for macOS.\n", body)
        add("Free and open source under the ", body)
        add("MIT License", body, link: license)
        add(".\n", body)
        add("Source code", body, link: repository)
        add("  ·  ", body)
        add("Download updates", body, link: releases)
        add("  ·  ", body)
        add("Report an issue", body, link: issues)
        add("\n\nBuilt with ", small)
        for (index, credit) in credits.enumerated() {
            add(credit.name, small, link: URL(string: credit.url))
            add(" (\(credit.license))" + (index < credits.count - 1 ? ", " : ".\n"), small)
        }
        add("Inspired by Notepad++. Slate is an independent project, not affiliated with Notepad++.", small)
        return text
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"
    }

    static var copyright: String {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        return "© \(year) \(publisher)"
    }

    @MainActor
    static func show() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Slate",
            .credits: creditsText(),
            .init(rawValue: "Copyright"): copyright,
        ]
        // Run from Xcode or swift run there is no app bundle, so name the version directly.
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") == nil {
            options[.applicationVersion] = version
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }
}
