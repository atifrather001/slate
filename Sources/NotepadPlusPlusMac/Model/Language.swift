import Foundation

enum Language: String, CaseIterable, Identifiable {
    case plainText = "Plain Text", swift = "Swift", objectiveC = "Objective-C", c = "C", cpp = "C++"
    case python = "Python", javascript = "JavaScript", typescript = "TypeScript", html = "HTML", css = "CSS"
    case json = "JSON", xml = "XML", yaml = "YAML", markdown = "Markdown", shell = "Bash / Shell", sql = "SQL"
    case rust = "Rust", go = "Go", java = "Java", kotlin = "Kotlin", ruby = "Ruby", php = "PHP", perl = "Perl"
    case lua = "Lua", r = "R", dart = "Dart", scala = "Scala", haskell = "Haskell"
    case powershell = "PowerShell", batch = "Windows Batch", csharp = "C#", dockerfile = "Dockerfile", ini = "INI"
    case diff = "Diff"

    /// Plain Text first, then alphabetical, for the menu and the picker.
    static let menuOrder: [Language] = [.plainText] + allCases
        .filter { $0 != .plainText }
        .sorted { $0.rawValue.lowercased() < $1.rawValue.lowercased() }

    var id: String { rawValue }

    /// highlight.js name, or nil when the text should not be colored.
    var highlighterName: String? {
        switch self {
        case .plainText: return nil
        case .objectiveC: return "objectivec"
        case .cpp: return "cpp"
        case .html: return "xml"
        case .shell: return "bash"
        case .batch: return "dos"
        case .csharp: return "csharp"
        default: return rawValue.lowercased()
        }
    }

    static func from(url: URL) -> Language? {
        let name = url.lastPathComponent.lowercased()
        switch name {
        case ".bashrc", ".bash_profile", ".bash_aliases", ".profile", ".zshrc", ".zprofile", ".zshenv":
            return .shell
        case "dockerfile":
            return .dockerfile
        default:
            // Dockerfile.dev and similar, unless the extension already means something.
            return from(fileExtension: url.pathExtension) ?? (name.hasPrefix("dockerfile.") ? .dockerfile : nil)
        }
    }

    static func from(fileExtension: String) -> Language? {
        let map: [String: Language] = [
            "txt": .plainText, "swift": .swift, "m": .objectiveC, "h": .c, "c": .c,
            "cpp": .cpp, "cc": .cpp, "cxx": .cpp, "hpp": .cpp, "py": .python,
            "js": .javascript, "jsx": .javascript, "ts": .typescript, "tsx": .typescript,
            "html": .html, "htm": .html, "css": .css, "scss": .css, "json": .json, "xml": .xml,
            "yaml": .yaml, "yml": .yaml, "md": .markdown, "markdown": .markdown,
            "sh": .shell, "bash": .shell, "zsh": .shell, "sql": .sql, "rs": .rust, "go": .go,
            "java": .java, "kt": .kotlin, "rb": .ruby, "php": .php, "pl": .perl, "lua": .lua,
            "r": .r, "dart": .dart, "scala": .scala, "hs": .haskell,
            "ps1": .powershell, "psm1": .powershell, "psd1": .powershell,
            "bat": .batch, "cmd": .batch, "cs": .csharp, "dockerfile": .dockerfile,
            "ini": .ini, "cfg": .ini, "diff": .diff, "patch": .diff,
        ]
        return map[fileExtension.lowercased()]
    }
}
