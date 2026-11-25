import AppKit
import SwiftUI

/// What the About window and Help menu say about Slate.
enum AboutSlate {
    static let publisher = "NexaSecure Cloud and AI"
    static let repository = URL(string: "https://github.com/atifrather001/slate")!
    static let releases = URL(string: "https://github.com/atifrather001/slate/releases")!
    static let issues = URL(string: "https://github.com/atifrather001/slate/issues")!
    static let license = URL(string: "https://github.com/atifrather001/slate/blob/main/LICENSE")!

    static let summary = "A fast, native text and code editor for macOS. Tabs, syntax highlighting, "
        + "split view, Git and a built-in terminal, inspired by Notepad++."

    /// The libraries built into Slate, at the versions in Package.resolved (a test keeps these in step).
    static let libraries: [(name: String, version: String, license: String)] = [
        ("SwiftTerm", "1.99.3", "MIT"),
        ("Highlightr", "2.3.0", "MIT"),
        ("Swift Collections", "1.7.6", "Apache-2.0"),
    ]

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    static var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    static var copyright: String {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        return "© \(year) \(publisher)"
    }

    /// The details to paste into a bug report.
    static var versionInfo: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var machine = utsname()
        uname(&machine)
        let architecture = withUnsafeBytes(of: &machine.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return [
            "Slate \(version)" + (build.map { " (\($0))" } ?? ""),
            libraries.prefix(2).map { "\($0.name) \($0.version)" }.joined(separator: " · "),
            libraries.dropFirst(2).map { "\($0.name) \($0.version)" }.joined(separator: " · ") + " · highlight.js",
            "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) (\(architecture))",
        ].joined(separator: "\n")
    }

    /// Slate's own license, then each bundled library's.
    static func licensesText() -> String {
        var sections = ["Slate\n\n" + slateLicense]
        if let folder = Bundle.main.resourceURL?.appendingPathComponent("Licenses"),
           let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for name in names.sorted() {
                if let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) {
                    let title = name.replacingOccurrences(of: "-LICENSE.txt", with: "").replacingOccurrences(of: "-LICENSE", with: "")
                    sections.append(title + "\n\n" + text)
                }
            }
        }
        if sections.count == 1 {
            sections.append("The licenses of SwiftTerm (MIT), Highlightr (MIT), highlight.js (BSD-3-Clause) and "
                            + "Swift Collections (Apache-2.0) are included in the app download.")
        }
        return sections.joined(separator: "\n\n" + String(repeating: "─", count: 40) + "\n\n")
    }

    static let slateLicense = """
    MIT License

    Copyright (c) 2026 NexaSecure Cloud and AI

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and \
    associated documentation files (the "Software"), to deal in the Software without restriction, including \
    without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
    copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the \
    following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial \
    portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT \
    LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO \
    EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER \
    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR \
    THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

    // MARK: Windows

    @MainActor private static var aboutWindow: NSWindow?
    @MainActor private static var licensesWindow: NSWindow?

    @MainActor
    static func show() {
        if aboutWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 610),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(srgbRed: 0.075, green: 0.082, blue: 0.098, alpha: 1)
            window.contentView = NSHostingView(rootView: AboutView())
            window.center()
            aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    static func showLicenses() {
        if licensesWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Licenses"
            window.isReleasedWhenClosed = false
            let scroll = NSTextView.scrollableTextView()
            let text = scroll.documentView as! NSTextView
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.textContainerInset = NSSize(width: 12, height: 12)
            text.string = licensesText()
            window.contentView = scroll
            window.center()
            licensesWindow = window
        }
        licensesWindow?.makeKeyAndOrderFront(nil)
    }
}

/// The About window, a dark card in the style of NexaSecure's other apps.
struct AboutView: View {
    @StateObject private var copied = CopiedFlag()

    final class CopiedFlag: ObservableObject {
        @Published var value = false
    }

    private let accent = Color(red: 0.38, green: 0.78, blue: 1.0)
    private let card = Color.white.opacity(0.05)
    private let border = Color.white.opacity(0.10)

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.top, 44)
            Text("Slate")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 14)
            Text("Version \(AboutSlate.version)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Text("An App by \(AboutSlate.publisher)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
                .padding(.top, 18)
            Text(AboutSlate.summary)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 10)

            HStack(spacing: 8) {
                linkButton("GitHub", systemImage: "globe") { NSWorkspace.shared.open(AboutSlate.repository) }
                linkButton("Report issue", systemImage: "ladybug") { NSWorkspace.shared.open(AboutSlate.issues) }
                linkButton("Licenses", systemImage: "doc.text") { AboutSlate.showLicenses() }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            Text(AboutSlate.versionInfo)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(card))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border))
                .padding(.horizontal, 24)
                .padding(.top, 16)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(AboutSlate.versionInfo, forType: .string)
                copied.value = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied.value = false }
            } label: {
                Label(copied.value ? "Copied" : "Copy version info",
                      systemImage: copied.value ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer(minLength: 20)

            VStack(spacing: 5) {
                Text(AboutSlate.copyright)
                HStack(spacing: 4) {
                    Text("Free and open source under the MIT License.")
                    Button {
                        NSWorkspace.shared.open(AboutSlate.repository)
                    } label: {
                        HStack(spacing: 2) {
                            Text("Source")
                            Image(systemName: "arrow.up.right.square").font(.system(size: 10))
                        }
                        .foregroundStyle(Color.primary.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
                Text("Includes SwiftTerm, Highlightr and other open-source software.")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 22)
        }
        .frame(width: 460, height: 610)
    }

    private func linkButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(card))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
