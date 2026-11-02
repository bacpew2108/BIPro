import Foundation

/// Edits to PBIR `visual.json` parts.
///
/// The title is changed by splicing the bytes of one string literal, so key order,
/// spacing and the rest of the document stay byte-for-byte as they were. The result is
/// checked by re-parsing it and comparing its structure with the expected structure.
public enum PBIRPatch {
    /// Where a visual's title text lives: `visual.visualContainerObjects.title[0].properties.text.expr.Literal.Value`.
    /// The value is a DAX string literal, e.g. `'Doanh thu'`.
    private static let titlePath: [JSONPathStep] = [
        .key("visual"), .key("visualContainerObjects"), .key("title"), .index(0),
        .key("properties"), .key("text"), .key("expr"), .key("Literal"), .key("Value"),
    ]

    /// Returns the visual.json with its title text replaced. Throws `WriteError.invalid`
    /// when the visual has no title text (adding a title is not supported yet).
    public static func setVisualTitle(in json: Data, title: String) throws -> Data {
        let root = try parseRoot(json)
        guard let current = lookup(titlePath[...], in: root), current is String else {
            throw WriteError.invalid("visual has no title text")
        }
        let bytes = [UInt8](json)
        guard let range = JSONCursor.locate(titlePath[...], in: bytes),
              bytes[range.lowerBound] == UInt8(ascii: "\"") else {
            throw WriteError.invalid("title text not found in visual.json")
        }

        let literal = daxStringLiteral(title)
        var out = bytes
        out.replaceSubrange(range, with: jsonStringToken(literal))

        // Check the splice: the new document must equal the old one with only the title changed.
        let expected = try replacing(root, titlePath[...], with: literal)
        let actual = try parseRoot(Data(out))
        guard (expected as AnyObject).isEqual(actual as AnyObject) else {
            throw WriteError.verificationFailed("visual.json title splice changed other content")
        }
        return Data(out)
    }

    /// The current title text of a visual.json, or nil when it has none.
    public static func visualTitle(in json: Data) throws -> String? {
        let root = try parseRoot(json)
        guard let value = lookup(titlePath[...], in: root) as? String else { return nil }
        return unwrapDAXString(value)
    }

    // MARK: - DAX literal

    /// `Doanh thu` becomes `'Doanh thu'`; each `'` inside the text is doubled.
    static func daxStringLiteral(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
    }

    /// Reverses `daxStringLiteral`. A value that is not wrapped in single quotes is returned as is.
    static func unwrapDAXString(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") else { return value }
        return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
    }

    /// A JSON string token (with quotes) for `text`. Non-ASCII text is written as UTF-8.
    static func jsonStringToken(_ text: String) -> [UInt8] {
        var out: [UInt8] = [UInt8(ascii: "\"")]
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += [UInt8(ascii: "\\"), UInt8(ascii: "\"")]
            case "\\": out += [UInt8(ascii: "\\"), UInt8(ascii: "\\")]
            case "\n": out += [UInt8(ascii: "\\"), UInt8(ascii: "n")]
            case "\r": out += [UInt8(ascii: "\\"), UInt8(ascii: "r")]
            case "\t": out += [UInt8(ascii: "\\"), UInt8(ascii: "t")]
            default:
                if scalar.value < 0x20 {
                    out += Array(String(format: "\\u%04X", scalar.value).utf8)
                } else {
                    out += Array(String(scalar).utf8)
                }
            }
        }
        out.append(UInt8(ascii: "\""))
        return out
    }

    // MARK: - Tree helpers

    private static func parseRoot(_ json: Data) throws -> Any {
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []), root is [String: Any] else {
            throw WriteError.invalid("visual.json is not a JSON object")
        }
        return root
    }

    private static func lookup(_ path: ArraySlice<JSONPathStep>, in node: Any) -> Any? {
        guard let step = path.first else { return node }
        let rest = path.dropFirst()
        switch step {
        case .key(let key):
            guard let dict = node as? [String: Any], let child = dict[key] else { return nil }
            return lookup(rest, in: child)
        case .index(let index):
            guard let array = node as? [Any], array.indices.contains(index) else { return nil }
            return lookup(rest, in: array[index])
        }
    }

    /// A copy of `node` with the value at `path` replaced.
    private static func replacing(_ node: Any, _ path: ArraySlice<JSONPathStep>, with value: Any) throws -> Any {
        guard let step = path.first else { return value }
        let rest = path.dropFirst()
        switch step {
        case .key(let key):
            guard var dict = node as? [String: Any], let child = dict[key] else {
                throw WriteError.invalid("visual.json path not found")
            }
            dict[key] = try replacing(child, rest, with: value)
            return dict
        case .index(let index):
            guard var array = node as? [Any], array.indices.contains(index) else {
                throw WriteError.invalid("visual.json path not found")
            }
            array[index] = try replacing(array[index], rest, with: value)
            return array
        }
    }
}

/// One step of a path into a JSON document: an object key or an array index.
fileprivate enum JSONPathStep {
    case key(String)
    case index(Int)
}

/// Finds the byte range of a value inside a JSON document without re-serialising it.
private struct JSONCursor {
    let b: [UInt8]
    var i = 0

    /// The byte range (including quotes) of the value at `path`, or nil if the path is absent.
    static func locate(_ path: ArraySlice<JSONPathStep>, in bytes: [UInt8]) -> Range<Int>? {
        var cursor = JSONCursor(b: bytes)
        return cursor.find(path)
    }

    private var peek: UInt8? { i < b.count ? b[i] : nil }

    private mutating func skipWhitespace() {
        while let c = peek, c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { i += 1 }
    }

    private mutating func expect(_ c: UInt8) -> Bool {
        skipWhitespace()
        guard peek == c else { return false }
        i += 1
        return true
    }

    private mutating func find(_ path: ArraySlice<JSONPathStep>) -> Range<Int>? {
        skipWhitespace()
        guard let step = path.first else {
            let start = i
            guard skipValue() else { return nil }
            return start..<i
        }
        let rest = path.dropFirst()
        switch step {
        case .key(let wanted):
            guard expect(UInt8(ascii: "{")) else { return nil }
            skipWhitespace()
            if peek == UInt8(ascii: "}") { return nil }
            while true {
                skipWhitespace()
                guard let keyRange = scanString() else { return nil }
                guard let key = decodeString(keyRange) else { return nil }
                guard expect(UInt8(ascii: ":")) else { return nil }
                if key == wanted { return find(rest) }
                guard skipValue() else { return nil }
                skipWhitespace()
                if peek == UInt8(ascii: ",") { i += 1; continue }
                return nil
            }
        case .index(let wanted):
            guard expect(UInt8(ascii: "[")) else { return nil }
            for _ in 0..<wanted {
                skipWhitespace()
                guard skipValue(), expect(UInt8(ascii: ",")) else { return nil }
            }
            return find(rest)
        }
    }

    /// Advances past one JSON value. Returns false on malformed input.
    private mutating func skipValue() -> Bool {
        skipWhitespace()
        guard let c = peek else { return false }
        switch c {
        case UInt8(ascii: "\""):
            return scanString() != nil
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            let close: UInt8 = c == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
            i += 1
            skipWhitespace()
            if peek == close { i += 1; return true }
            while true {
                if close == UInt8(ascii: "}") {
                    skipWhitespace()
                    guard scanString() != nil, expect(UInt8(ascii: ":")) else { return false }
                }
                guard skipValue() else { return false }
                skipWhitespace()
                if peek == UInt8(ascii: ",") { i += 1; continue }
                if peek == close { i += 1; return true }
                return false
            }
        default:
            // Number, true, false or null: a run of token characters.
            let start = i
            while let t = peek, isTokenByte(t) { i += 1 }
            return i > start
        }
    }

    private func isTokenByte(_ c: UInt8) -> Bool {
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
            || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".")
    }

    /// Scans a string token starting at the opening quote. Returns its range including quotes.
    private mutating func scanString() -> Range<Int>? {
        guard peek == UInt8(ascii: "\"") else { return nil }
        let start = i
        i += 1
        while i < b.count {
            let c = b[i]
            if c == UInt8(ascii: "\\") { i += 2; continue }
            i += 1
            if c == UInt8(ascii: "\"") { return start..<i }
        }
        return nil
    }

    private func decodeString(_ range: Range<Int>) -> String? {
        let token = Data(b[range])
        return (try? JSONSerialization.jsonObject(with: token, options: [.fragmentsAllowed])) as? String
    }
}
