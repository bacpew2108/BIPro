import Foundation

/// Edits to the layout parts of a PBIR report: where a visual sits (`position` in `visual.json`),
/// copies of a visual, and the references other parts hold to a visual that is removed.
///
/// Like `PBIRPatch`, every edit splices bytes, so key order, spacing and everything not touched stay
/// byte-for-byte as they were. Each result is re-parsed and compared with the expected structure.
public enum PBIRLayoutPatch {
    public struct Position: Sendable, Equatable {
        public var x: Double, y: Double, z: Double
        public var width: Double, height: Double
        public var tabOrder: Double?
    }

    // MARK: - Position

    /// The `position` of a visual.json.
    public static func position(in json: Data) throws -> Position {
        let root = try parseObject(json)
        guard let position = root["position"] as? [String: Any] else {
            throw WriteError.invalid("visual.json has no position")
        }
        func number(_ key: String) -> Double? { (position[key] as? NSNumber)?.doubleValue }
        guard let x = number("x"), let y = number("y"), let width = number("width"), let height = number("height") else {
            throw WriteError.invalid("visual.json position is incomplete")
        }
        return Position(x: x, y: y, z: number("z") ?? 0, width: width, height: height, tabOrder: number("tabOrder"))
    }

    /// Replaces the given numbers of `position`. Values must be whole numbers; `x`, `y` are not negative and
    /// `width`, `height` are at least 1. A field the document does not have is an error.
    public static func setPosition(in json: Data, x: Int? = nil, y: Int? = nil, width: Int? = nil, height: Int? = nil,
                                   z: Int? = nil, tabOrder: Int? = nil) throws -> Data {
        if let x, x < 0 { throw WriteError.invalid("x must not be negative") }
        if let y, y < 0 { throw WriteError.invalid("y must not be negative") }
        if let width, width < 1 { throw WriteError.invalid("width must be at least 1") }
        if let height, height < 1 { throw WriteError.invalid("height must be at least 1") }
        let wanted: [(key: String, value: Int?)] = [("x", x), ("y", y), ("width", width), ("height", height), ("z", z), ("tabOrder", tabOrder)]

        let root = try parseObject(json)
        guard root["position"] is [String: Any] else { throw WriteError.invalid("visual.json has no position") }
        let bytes = [UInt8](json)

        var edits: [(range: Range<Int>, value: Int, key: String)] = []
        for (key, requested) in wanted {
            guard let value = requested else { continue }
            guard let range = JSONCursor.locate([.key("position"), .key(key)][...], in: bytes),
                  let first = bytes[safe: range.lowerBound], first == UInt8(ascii: "-") || (first >= 0x30 && first <= 0x39) else {
                throw WriteError.invalid("position.\(key) not found in visual.json")
            }
            edits.append((range, value, key))
        }
        var out = bytes
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            out.replaceSubrange(edit.range, with: Array(String(edit.value).utf8))
        }

        var expected = root
        var position = root["position"] as! [String: Any]
        for edit in edits { position[edit.key] = edit.value }
        expected["position"] = position
        try verify(Data(out), equals: expected, what: "position splice")
        return Data(out)
    }

    // MARK: - Duplicate

    /// A copy of a visual.json with a new `name` and position. `tabOrder` is set equal to `z`.
    public static func duplicated(_ json: Data, newName: String, x: Int, y: Int, width: Int, height: Int, z: Int) throws -> Data {
        guard isValidVisualName(newName) else { throw WriteError.invalid("visual name must be 20 lowercase hex characters") }
        let root = try parseObject(json)
        guard root["name"] is String else { throw WriteError.invalid("visual.json has no name") }
        let bytes = [UInt8](json)
        guard let range = JSONCursor.locate([.key("name")][...], in: bytes), bytes[range.lowerBound] == UInt8(ascii: "\"") else {
            throw WriteError.invalid("name not found in visual.json")
        }
        var named = bytes
        named.replaceSubrange(range, with: PBIRPatch.jsonStringToken(newName))
        let renamed = Data(named)

        let result = try setPosition(in: renamed, x: x, y: y, width: width, height: height, z: z, tabOrder: z)
        var expected = root
        expected["name"] = newName
        var position = (root["position"] as? [String: Any]) ?? [:]
        position["x"] = x; position["y"] = y; position["width"] = width; position["height"] = height
        position["z"] = z; position["tabOrder"] = z
        expected["position"] = position
        try verify(result, equals: expected, what: "visual copy")
        return result
    }

    /// Visual names made by Power BI Desktop are 20 lowercase hex characters.
    public static func isValidVisualName(_ name: String) -> Bool {
        name.utf8.count == 20 && name.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// A random visual name that is not in `taken`.
    public static func makeVisualName(avoiding taken: Set<String>) -> String {
        var generator = SystemRandomNumberGenerator()
        while true {
            let name = (0..<20).map { _ in String(UInt8.random(in: 0..<16, using: &generator), radix: 16) }.joined()
            if !taken.contains(name) { return name }
        }
    }

    // MARK: - References to removed visuals

    /// A bookmark with every mention of the visuals in `ids` removed: from `options.targetVisualNames` and from
    /// `explorationState.sections.<page>.visualContainers`. Returns the same bytes when nothing mentions them.
    public static func removingVisualReferences(_ ids: Set<String>, fromBookmark json: Data) throws -> Data {
        guard !ids.isEmpty else { return json }
        let root = try parseObject(json)
        var bytes = [UInt8](json)

        // options.targetVisualNames
        if let kids = JSONCursor.children(at: [.key("options"), .key("targetVisualNames")], in: bytes) {
            let drop = Set(kids.indices.filter { index in
                JSONCursor.string(in: bytes, kids[index].value).map(ids.contains) ?? false
            })
            bytes = JSONCursor.removing(drop, from: kids, in: bytes)
        }
        // explorationState.sections.<page>.visualContainers.<id>
        if let sections = JSONCursor.children(at: [.key("explorationState"), .key("sections")], in: bytes) {
            let pages = sections.compactMap { child in child.key.flatMap { JSONCursor.string(in: bytes, $0) } }
            for page in pages {
                let path: [JSONPathStep] = [.key("explorationState"), .key("sections"), .key(page), .key("visualContainers")]
                guard let kids = JSONCursor.children(at: path, in: bytes) else { continue }
                let drop = Set(kids.indices.filter { index in
                    kids[index].key.flatMap { JSONCursor.string(in: bytes, $0) }.map(ids.contains) ?? false
                })
                bytes = JSONCursor.removing(drop, from: kids, in: bytes)
            }
        }
        let result = Data(bytes)
        if result == json { return json }

        // Expected structure: the same tree with those entries filtered out.
        var expected = root
        if var options = expected["options"] as? [String: Any], let names = options["targetVisualNames"] as? [String] {
            options["targetVisualNames"] = names.filter { !ids.contains($0) }
            expected["options"] = options
        }
        if var exploration = expected["explorationState"] as? [String: Any],
           var sections = exploration["sections"] as? [String: Any] {
            for (page, value) in sections {
                guard var section = value as? [String: Any], var containers = section["visualContainers"] as? [String: Any] else { continue }
                for id in ids { containers[id] = nil }
                section["visualContainers"] = containers
                sections[page] = section
            }
            exploration["sections"] = sections
            expected["explorationState"] = exploration
        }
        try verify(result, equals: expected, what: "bookmark clean-up")
        return result
    }

    /// A page.json with the `visualInteractions` rows that name one of `ids` (as source or target) removed.
    public static func removingVisualReferences(_ ids: Set<String>, fromPage json: Data) throws -> Data {
        guard !ids.isEmpty else { return json }
        let root = try parseObject(json)
        guard root["visualInteractions"] is [Any] else { return json }
        let bytes = [UInt8](json)
        guard let kids = JSONCursor.children(at: [.key("visualInteractions")], in: bytes) else { return json }
        var drop = Set<Int>()
        for (index, kid) in kids.enumerated() {
            guard let row = (try? JSONSerialization.jsonObject(with: Data(bytes[kid.value]), options: [])) as? [String: Any] else { continue }
            if let source = row["source"] as? String, ids.contains(source) { drop.insert(index) }
            else if let target = row["target"] as? String, ids.contains(target) { drop.insert(index) }
        }
        guard !drop.isEmpty else { return json }
        let result = Data(JSONCursor.removing(drop, from: kids, in: bytes))
        var expected = root
        expected["visualInteractions"] = (root["visualInteractions"] as? [[String: Any]] ?? []).filter { row in
            !ids.contains(row["source"] as? String ?? "") && !ids.contains(row["target"] as? String ?? "")
        }
        try verify(result, equals: expected, what: "page clean-up")
        return result
    }

    // MARK: - Helpers

    private static func parseObject(_ json: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? [String: Any] else {
            throw WriteError.invalid("part is not a JSON object")
        }
        return root
    }

    private static func verify(_ data: Data, equals expected: [String: Any], what: String) throws {
        guard let actual = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              (expected as NSDictionary).isEqual(to: actual) else {
            throw WriteError.verificationFailed("\(what) changed other content")
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - JSON children and removal

extension JSONCursor {
    struct Child {
        var key: Range<Int>?
        var value: Range<Int>
        var start: Int { key?.lowerBound ?? value.lowerBound }
    }

    /// The children of the object or array at `path`, in order, or nil when the path is absent or not a container.
    static func children(at path: [JSONPathStep], in bytes: [UInt8]) -> [Child]? {
        guard let range = locate(path[...], in: bytes), let open = bytes[safe: range.lowerBound],
              open == UInt8(ascii: "{") || open == UInt8(ascii: "[") else { return nil }
        let isObject = open == UInt8(ascii: "{")
        let close: UInt8 = isObject ? UInt8(ascii: "}") : UInt8(ascii: "]")
        var cursor = JSONCursor(b: bytes, i: range.lowerBound + 1)
        var out: [Child] = []
        cursor.skipWhitespace()
        if cursor.peek == close { return out }
        while true {
            cursor.skipWhitespace()
            var key: Range<Int>?
            if isObject {
                guard let k = cursor.scanString(), cursor.expect(UInt8(ascii: ":")) else { return nil }
                key = k
            }
            cursor.skipWhitespace()
            let start = cursor.i
            guard cursor.skipValue() else { return nil }
            out.append(Child(key: key, value: start..<cursor.i))
            cursor.skipWhitespace()
            if cursor.peek == UInt8(ascii: ",") { cursor.i += 1; continue }
            return cursor.peek == close ? out : nil
        }
    }

    /// The decoded string at `range`, or nil when it is not a string token.
    static func string(in bytes: [UInt8], _ range: Range<Int>) -> String? {
        guard bytes[safe: range.lowerBound] == UInt8(ascii: "\"") else { return nil }
        return JSONCursor(b: bytes).decodeString(range)
    }

    /// `bytes` without the children at `indices`, taking the commas around them along.
    static func removing(_ indices: Set<Int>, from kids: [Child], in bytes: [UInt8]) -> [UInt8] {
        guard !indices.isEmpty else { return bytes }
        var deletions: [Range<Int>] = []
        var retainedBefore = false
        for (k, kid) in kids.enumerated() {
            if !indices.contains(k) { retainedBefore = true; continue }
            if retainedBefore {
                deletions.append(kids[k - 1].value.upperBound..<kid.value.upperBound)
            } else if k + 1 < kids.count {
                deletions.append(kid.start..<kids[k + 1].start)
            } else {
                deletions.append(kid.start..<kid.value.upperBound)
            }
        }
        var out = bytes
        for range in deletions.sorted(by: { $0.lowerBound > $1.lowerBound }) { out.removeSubrange(range) }
        return out
    }
}
