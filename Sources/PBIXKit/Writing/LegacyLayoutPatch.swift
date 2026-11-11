import Foundation

/// Edits to the layout of a report in the legacy format (D7): the single part `Report/Layout`, UTF-16LE JSON whose
/// `sections[i].visualContainers[j]` hold `x, y, z, width, height` and a `config` that is itself a JSON string with the same
/// numbers in `layouts[0].position`. Like the PBIR patchers every edit splices bytes: a container that is not edited, and
/// everything outside the replaced numbers, keeps its bytes. Observed in two real files (docs/phase-d-evidence/vm-d7).
public enum LegacyLayoutPatch {
    public struct Position: Sendable, Equatable {
        public var x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    }

    /// What to change in one section (page): new positions by container name, containers to remove, containers to append.
    public struct SectionEdit: Sendable {
        public var section: String
        public var set: [String: Position] = [:]
        public var remove: Set<String> = []
        public var add: [Data] = []
        public init(section: String, set: [String: Position] = [:], remove: Set<String> = [], add: [Data] = []) {
            self.section = section; self.set = set; self.remove = remove; self.add = add
        }
    }

    /// One container of a section as it is in the file.
    public struct Container: Sendable {
        public let name: String
        /// The bytes of the container object (UTF-8).
        public let json: Data
        public let isGroup: Bool
    }

    // MARK: Text

    /// The layout as UTF-8 bytes. Throws when it is not UTF-16LE text that converts back to the same bytes.
    static func decode(_ layout: Data) throws -> [UInt8] {
        let hasBOM = layout.starts(with: [0xFF, 0xFE])
        let body = hasBOM ? layout.dropFirst(2) : layout[...]
        guard let text = String(data: body, encoding: .utf16LittleEndian) else { throw WriteError.invalid("Report/Layout is not UTF-16LE text") }
        let utf8 = Array(text.utf8)
        guard encode(utf8, bom: hasBOM) == layout else { throw WriteError.invalid("Report/Layout does not convert back to the same bytes") }
        return utf8
    }

    /// Chỉ cho test: UTF-8 của layout.
    static func decodeForTest(_ layout: Data) throws -> Data { Data(try decode(layout)) }

    static func encode(_ utf8: [UInt8], bom: Bool) -> Data {
        var out = Data()
        if bom { out.append(contentsOf: [0xFF, 0xFE]) }
        out.append(String(decoding: utf8, as: UTF8.self).data(using: .utf16LittleEndian)!)
        return out
    }

    // MARK: Reading

    private static func sectionPaths(_ bytes: [UInt8]) throws -> [(name: String, containers: [JSONCursor.Child])] {
        guard let sections = JSONCursor.children(at: [.key("sections")], in: bytes) else { throw WriteError.invalid("Report/Layout has no sections") }
        var out: [(String, [JSONCursor.Child])] = []
        for index in sections.indices {
            guard let nameRange = JSONCursor.locate([.key("sections"), .index(index), .key("name")][...], in: bytes),
                  let name = JSONCursor.string(in: bytes, nameRange),
                  let kids = JSONCursor.children(at: [.key("sections"), .index(index), .key("visualContainers")], in: bytes) else {
                throw WriteError.invalid("section \(index) of Report/Layout is not as expected")
            }
            out.append((name, kids))
        }
        return out
    }

    private static func containerName(_ json: ArraySlice<UInt8>) -> (name: String, isGroup: Bool)? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json)) as? [String: Any],
              let config = object["config"] as? String,
              let parsed = try? JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any],
              let name = parsed["name"] as? String else { return nil }
        return (name, parsed["singleVisualGroup"] != nil)
    }

    /// Containers of every section, by section name, in file order.
    public static func containers(in layout: Data) throws -> [String: [Container]] {
        let bytes = try decode(layout)
        var out: [String: [Container]] = [:]
        for (name, kids) in try sectionPaths(bytes) {
            out[name] = kids.compactMap { kid in
                containerName(bytes[kid.value]).map { Container(name: $0.name, json: Data(bytes[kid.value]), isGroup: $0.isGroup) }
            }
        }
        return out
    }

    /// The position of a container (`x, y, width, height` at container level).
    public static func position(of container: Data) throws -> Position {
        guard let object = try? JSONSerialization.jsonObject(with: container) as? [String: Any] else { throw WriteError.invalid("container is not an object") }
        func n(_ key: String) -> Double? { (object[key] as? NSNumber)?.doubleValue }
        guard let x = n("x"), let y = n("y"), let w = n("width"), let h = n("height") else { throw WriteError.invalid("container position is incomplete") }
        return Position(x: x, y: y, width: w, height: h)
    }

    // MARK: Number splicing

    /// Replacements of the numbers of a container laid at `base` in the document: container level and the escaped
    /// `config` string's `layouts[0].position`. `z` also rewrites `tabOrder` (a copy sits on top).
    private static func numberEdits(in bytes: [UInt8], container: Range<Int>, position: Position, z: Double? = nil) throws -> [(Range<Int>, [UInt8])] {
        var edits: [(Range<Int>, [UInt8])] = []
        let slice = Array(bytes[container])
        func text(_ v: Double) -> [UInt8] { Array(PBIRLayoutPatch.numberText(v).utf8) }
        let wanted: [(String, Double?)] = [("x", position.x), ("y", position.y), ("width", position.width), ("height", position.height), ("z", z), ("tabOrder", z)]
        // Container level: direct children numbers.
        guard let kids = JSONCursor.children(at: [], in: slice) else { throw WriteError.invalid("container is not an object") }
        for kid in kids {
            guard let key = kid.key.flatMap({ JSONCursor.string(in: slice, $0) }), let value = wanted.first(where: { $0.0 == key })?.1 else { continue }
            guard let first = slice[safe: kid.value.lowerBound], first == UInt8(ascii: "-") || (first >= 0x30 && first <= 0x39) else {
                throw WriteError.invalid("container \(key) is not a number")
            }
            edits.append(((container.lowerBound + kid.value.lowerBound)..<(container.lowerBound + kid.value.upperBound), text(value)))
        }
        // config: the escaped string token; numbers sit in `\"position\":{ ... }`.
        guard let config = kids.first(where: { $0.key.flatMap { JSONCursor.string(in: slice, $0) } == "config" }) else {
            throw WriteError.invalid("container has no config")
        }
        let token = Array(slice[config.value])
        let marker = Array(#"\"position\":{"#.utf8)
        guard let at = token.firstRange(of: marker), let end = token[at.upperBound...].firstIndex(of: UInt8(ascii: "}")) else {
            throw WriteError.invalid("config has no layouts[0].position")
        }
        for (key, value) in wanted {
            guard let value else { continue }
            let needle = Array(#"\""#.utf8) + Array(key.utf8) + Array(#"\":"#.utf8)
            guard let k = token[at.upperBound..<end].firstRange(of: needle) else {
                if key == "tabOrder" || key == "z" { continue }
                throw WriteError.invalid("config position has no \(key)")
            }
            var stop = k.upperBound
            while stop < end, token[stop] != UInt8(ascii: ","), token[stop] != UInt8(ascii: "}") { stop += 1 }
            let base = container.lowerBound + config.value.lowerBound
            edits.append(((base + k.upperBound)..<(base + stop), text(value)))
        }
        return edits
    }

    private static func apply(_ edits: [(Range<Int>, [UInt8])], to bytes: [UInt8]) -> [UInt8] {
        var out = bytes
        for (range, replacement) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) { out.replaceSubrange(range, with: replacement) }
        return out
    }

    /// `container` with its position set (container level and `config`).
    public static func settingPosition(in container: Data, to position: Position) throws -> Data {
        let bytes = [UInt8](container)
        let edits = try numberEdits(in: bytes, container: 0..<bytes.count, position: position)
        return Data(apply(edits, to: bytes))
    }

    /// A copy of a container with a new `config.name` and a new position, `z` and `tabOrder` (like `PBIRLayoutPatch.duplicated`).
    public static func duplicated(_ container: Data, newName: String, x: Double, y: Double, width: Double, height: Double, z: Double) throws -> Data {
        guard PBIRLayoutPatch.isValidVisualName(newName) else { throw WriteError.invalid("name must be 20 lowercase hex characters") }
        guard let old = containerName(ArraySlice(container))?.name else { throw WriteError.invalid("container has no config name") }
        var bytes = [UInt8](container)
        var edits = try numberEdits(in: bytes, container: 0..<bytes.count, position: Position(x: x, y: y, width: width, height: height), z: z)
        let needle = Array(#"\"name\":\""#.utf8) + Array(old.utf8) + Array(#"\""#.utf8)
        guard let at = bytes.firstRange(of: needle) else { throw WriteError.invalid("config name not found") }
        let start = at.lowerBound + 11   // \"name\":\" are 11 bytes
        edits.append((start..<(start + old.utf8.count), Array(newName.utf8)))
        bytes = apply(edits, to: bytes)
        guard containerName(bytes[...])?.name == newName else { throw WriteError.verificationFailed("copy name did not read back") }
        return Data(bytes)
    }

    // MARK: Applying edits

    /// `layout` with `edits` applied. Verified: it parses, the container names match the intent, containers not edited keep
    /// their bytes, and an edited container equals the original but for its position numbers.
    public static func apply(_ edits: [SectionEdit], to layout: Data) throws -> Data {
        let hasBOM = layout.starts(with: [0xFF, 0xFE])
        var bytes = try decode(layout)
        let original = bytes
        let before = Dictionary(try sectionPaths(original).map { ($0.name, $0.containers.map { Array(original[$0.value]) }) }, uniquingKeysWith: { first, _ in first })

        // 1. Numbers, all at once (offsets of the original).
        var numberReplacements: [(Range<Int>, [UInt8])] = []
        for edit in edits where !edit.set.isEmpty {
            guard let section = try sectionPaths(original).first(where: { $0.name == edit.section }) else { throw WriteError.invalid("no section \(edit.section)") }
            for kid in section.containers {
                guard let name = containerName(original[kid.value])?.name, let position = edit.set[name], !edit.remove.contains(name) else { continue }
                numberReplacements += try numberEdits(in: original, container: kid.value, position: position)
            }
        }
        bytes = apply(numberReplacements, to: bytes)

        // 2. Removals and additions, per section, on the current bytes.
        for edit in edits where !edit.remove.isEmpty || !edit.add.isEmpty {
            guard let index = try sectionPaths(bytes).firstIndex(where: { $0.name == edit.section }) else { throw WriteError.invalid("no section \(edit.section)") }
            let path: [JSONPathStep] = [.key("sections"), .index(index), .key("visualContainers")]
            if !edit.remove.isEmpty, let kids = JSONCursor.children(at: path, in: bytes) {
                let drop = Set(kids.indices.filter { containerName(bytes[kids[$0].value]).map { edit.remove.contains($0.name) } ?? false })
                guard drop.count == edit.remove.count else { throw WriteError.invalid("a container to remove is not in section \(edit.section)") }
                bytes = JSONCursor.removing(drop, from: kids, in: bytes)
            }
            if !edit.add.isEmpty {
                guard let array = JSONCursor.locate(path[...], in: bytes), bytes[array.lowerBound] == UInt8(ascii: "[") else { throw WriteError.invalid("visualContainers is not an array") }
                let kids = JSONCursor.children(at: path, in: bytes) ?? []
                var insertion: [UInt8] = []
                for (n, data) in edit.add.enumerated() { insertion += (kids.isEmpty && n == 0 ? [] : [UInt8(ascii: ",")]) + Array(data) }
                bytes.insert(contentsOf: insertion, at: kids.last?.value.upperBound ?? (array.lowerBound + 1))
            }
        }

        // 3. Verify.
        guard (try? JSONSerialization.jsonObject(with: Data(bytes))) != nil else { throw WriteError.verificationFailed("edited Report/Layout does not parse") }
        for (name, kids) in try sectionPaths(bytes) {
            let edit = edits.first { $0.section == name }
            let old = (before[name] ?? []).filter { containerName(ArraySlice($0)) != nil }   // chỉ container đọc được tên
            let oldNames = old.compactMap { containerName(ArraySlice($0))?.name }
            let removed = edit?.remove ?? []
            let added = (edit?.add ?? []).compactMap { containerName(ArraySlice($0))?.name }
            let expected = oldNames.filter { !removed.contains($0) } + added
            // Container không đọc được tên bị bỏ qua cả hai phía (giữ nguyên byte, không sửa được).
            let named = kids.compactMap { kid in containerName(bytes[kid.value]).map { (kid, $0.name) } }
            let now = named.map(\.1)
            guard now == expected else { throw WriteError.verificationFailed("containers of section \(name) are not as intended") }
            for (kid, name) in named {
                let data = Array(bytes[kid.value])
                if let position = edit?.set[name], let i = oldNames.firstIndex(of: name) {
                    try expectOnlyPositionChanged(old[i], data, position: position)
                } else if let i = oldNames.firstIndex(of: name), !added.contains(name), data != old[i] {
                    throw WriteError.verificationFailed("container \(name) changed although it was not edited")
                }
            }
        }
        return encode(bytes, bom: hasBOM)
    }

    private static func expectOnlyPositionChanged(_ old: [UInt8], _ new: [UInt8], position: Position) throws {
        func normalized(_ bytes: [UInt8]) throws -> NSDictionary {
            guard var object = try JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any],
                  let config = object["config"] as? String,
                  var parsed = try JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any] else {
                throw WriteError.verificationFailed("container does not parse")
            }
            func set(_ d: inout [String: Any]) { d["x"] = position.x; d["y"] = position.y; d["width"] = position.width; d["height"] = position.height }
            set(&object)
            if var layouts = parsed["layouts"] as? [[String: Any]], var first = layouts.first, var p = first["position"] as? [String: Any] {
                set(&p); first["position"] = p; layouts[0] = first; parsed["layouts"] = layouts
            }
            object["config"] = parsed as NSDictionary
            return object as NSDictionary
        }
        guard try normalized(old).isEqual(normalized(new)) else { throw WriteError.verificationFailed("a container changed beyond its position") }
        let read = try Self.position(of: Data(new))
        guard read == position else { throw WriteError.verificationFailed("container position did not read back") }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

private extension Array where Element == UInt8 {
    func firstRange(of needle: [UInt8]) -> Range<Int>? {
        guard !needle.isEmpty, count >= needle.count else { return nil }
        var i = 0
        while i <= count - needle.count {
            if self[i] == needle[0], self[i..<(i + needle.count)].elementsEqual(needle) { return i..<(i + needle.count) }
            i += 1
        }
        return nil
    }
}

private extension ArraySlice where Element == UInt8 {
    func firstRange(of needle: [UInt8]) -> Range<Int>? {
        guard !needle.isEmpty, count >= needle.count else { return nil }
        var i = startIndex
        while i <= endIndex - needle.count {
            if self[i] == needle[0], self[i..<(i + needle.count)].elementsEqual(needle) { return i..<(i + needle.count) }
            i += 1
        }
        return nil
    }
}
