import Foundation

enum LineEnding: String {
    case lf = "LF", crlf = "CRLF", cr = "CR"
    /// Files that mix endings are left exactly as they are.
    case mixed = "Mixed"

    static func detect(in text: String) -> LineEnding {
        var lf = false, crlf = false, cr = false, afterCR = false
        for unit in text.utf16 {
            if unit == 10 {
                if afterCR { crlf = true } else { lf = true }
            } else if afterCR {
                cr = true
            }
            afterCR = unit == 13
        }
        if afterCR { cr = true }
        switch (lf, crlf, cr) {
        case (false, true, false): return .crlf
        case (false, false, true): return .cr
        case (_, false, false): return .lf
        default: return .mixed
        }
    }

    /// The editor always works in LF, except for mixed files.
    func decode(_ text: String) -> String {
        switch self {
        case .crlf: return text.replacingOccurrences(of: "\r\n", with: "\n")
        case .cr: return text.replacingOccurrences(of: "\r", with: "\n")
        case .lf, .mixed: return text
        }
    }

    func encode(_ text: String) -> String {
        guard self == .crlf || self == .cr else { return text }
        // Pasted CRLF text must not turn into CR CR LF.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.replacingOccurrences(of: "\n", with: self == .crlf ? "\r\n" : "\r")
    }
}

enum FileEncoding: String {
    case utf8 = "UTF-8", utf8BOM = "UTF-8 BOM", utf16LE = "UTF-16 LE", utf16BE = "UTF-16 BE"
    case windows1252 = "Windows-1252", latin1 = "ISO Latin-1"

    var bom: [UInt8] {
        switch self {
        case .utf8BOM: return [0xEF, 0xBB, 0xBF]
        case .utf16LE: return [0xFF, 0xFE]
        case .utf16BE: return [0xFE, 0xFF]
        default: return []
        }
    }

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8, .utf8BOM: return .utf8
        case .utf16LE: return .utf16LittleEndian
        case .utf16BE: return .utf16BigEndian
        case .windows1252: return .windowsCP1252
        case .latin1: return .isoLatin1
        }
    }
}

enum TextFileError: LocalizedError {
    case binary
    case cannotEncode(FileEncoding)

    var errorDescription: String? {
        switch self {
        case .binary:
            return "This doesn't look like a text file, so it wasn't opened."
        case .cannotEncode(let encoding):
            return "Some characters can't be saved as \(encoding.rawValue)."
        }
    }
}

struct TextFile {
    var text: String
    var encoding: FileEncoding = .utf8
    var lineEnding: LineEnding = .lf

    init(text: String, encoding: FileEncoding = .utf8, lineEnding: LineEnding = .lf) {
        self.text = text
        self.encoding = encoding
        self.lineEnding = lineEnding
    }

    init(data: Data) throws {
        let marked = [FileEncoding.utf8BOM, .utf16LE, .utf16BE].first { data.starts(with: $0.bom) }
        if marked == nil && data.contains(0) { throw TextFileError.binary }

        let candidates = marked.map { [$0] } ?? [.utf8, .windows1252, .latin1]
        for candidate in candidates {
            let body = Data(data.dropFirst(candidate.bom.count))
            // Accept only a decoding that writes back to the identical bytes, so saving can't corrupt a file.
            // String(data:) swallows a leading U+FEFF, which is content once the BOM is removed.
            let decoded = candidate.stringEncoding == .utf8
                ? String(decoding: body, as: UTF8.self)
                : String(data: body, encoding: candidate.stringEncoding)
            guard let raw = decoded,
                  raw.data(using: candidate.stringEncoding) == body else { continue }
            encoding = candidate
            lineEnding = LineEnding.detect(in: raw)
            text = lineEnding.decode(raw)
            return
        }
        throw TextFileError.binary
    }

    func data() throws -> Data {
        guard let body = lineEnding.encode(text).data(using: encoding.stringEncoding) else {
            throw TextFileError.cannotEncode(encoding)
        }
        return Data(encoding.bom) + body
    }
}
