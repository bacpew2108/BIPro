import Foundation

/// Edits to `visual.query.queryState` of a PBIR `visual.json`: which fields sit in which well, in what order,
/// and the display name of each. Like `PBIRPatch` and `PBIRLayoutPatch`, every edit splices bytes, so what is not
/// touched stays byte-for-byte as it was, and the result is re-parsed and compared with the expected structure.
///
/// Contract: `specs/003-d2-build-pane-field-well/contracts/query-state-patch.md`.
public enum PBIRQueryPatch {
    /// One element of a well's `projections` array.
    public struct Element: Sendable, Equatable {
        public var field: ReportField
        /// The element's bytes as found in the file. Nil for an element that is new: it is written from the template.
        public var source: Data?

        public init(field: ReportField, source: Data?) {
            self.field = field
            self.source = source
        }
    }

    /// A well (`Category`, `Y`, `Values`…) with its fields in order.
    public struct Well: Sendable, Equatable {
        public var role: String
        public var elements: [Element]

        public init(role: String, elements: [Element]) {
            self.role = role
            self.elements = elements
        }
    }

    // MARK: - Read

    private static let statePath: [JSONPathStep] = [.key("visual"), .key("query"), .key("queryState")]

    /// The wells of the visual, in file order, with the bytes of every element.
    public static func wells(in json: Data) throws -> [Well] {
        _ = try parseObject(json)
        let bytes = [UInt8](json)
        guard let roles = JSONCursor.children(at: statePath, in: bytes) else {
            if JSONCursor.locate(statePath[...], in: bytes) == nil { return [] }
            throw WriteError.invalid("queryState is not an object")
        }
        var wells: [Well] = []
        for role in roles {
            guard let keyRange = role.key, let name = JSONCursor.string(in: bytes, keyRange) else {
                throw WriteError.invalid("queryState has a malformed key")
            }
            let kids = try projections(of: name, in: bytes)
            var elements: [Element] = []
            for kid in kids {
                let slice = Data(bytes[kid.value])
                guard let value = try? JSONValue.parse(slice), let field = PBIXFile.pbirField(value, role: name) else {
                    throw WriteError.invalid("a projection of \(name) is not a field")
                }
                elements.append(Element(field: field, source: slice))
            }
            wells.append(Well(role: name, elements: elements))
        }
        return wells
    }

    /// The fields of the visual as `PBIXFile.loadReport()` lists them (roles by name, elements in file order).
    public static func fields(in json: Data) throws -> [ReportField] {
        let value = try JSONValue.parse(json)
        return PBIXFile.pbirFields(value["visual"]?["query"]?["queryState"])
    }

    /// A new element in the shape Power BI Desktop writes (observed in Nhom6): field, queryRef, nativeQueryRef,
    /// then displayName when the user renamed it.
    public static func newElement(kind: ReportField.Kind, entity: String, property: String, displayName: String?, role: String) -> Element {
        let field = ReportField(role: role, kind: kind, entity: entity, property: property, displayName: displayName,
                                queryRef: "\(entity).\(property)", nativeQueryRef: property)
        return Element(field: field, source: nil)
    }

    // MARK: - Apply

    /// `json` with the wells replaced by `wells` (the final state of every well). A well whose elements are exactly
    /// the ones in the file, in the same order and without renames, keeps its bytes; wells not mentioned in `wells`
    /// (or with no elements) are removed; wells that are new are added at the end of `queryState`.
    public static func apply(_ wells: [Well], to json: Data) throws -> Data {
        let root = try parseObject(json)
        var bytes = [UInt8](json)
        guard JSONCursor.locate(statePath[...], in: bytes) != nil,
              let roles = JSONCursor.children(at: statePath, in: bytes) else {
            throw WriteError.invalid("visual.json has no query.queryState")
        }
        try validate(wells)

        // Current state: role name → (children of its object, children of its projections).
        struct Current { var role: String; var kids: [JSONCursor.Child]; var projections: [JSONCursor.Child]?; var extraKeys: Bool }
        var current: [String: Current] = [:]
        var order: [String] = []
        for role in roles {
            guard let keyRange = role.key, let name = JSONCursor.string(in: bytes, keyRange) else {
                throw WriteError.invalid("queryState has a malformed key")
            }
            let objectKids = JSONCursor.children(at: statePath + [.key(name)], in: bytes) ?? []
            let projectionKids = objectKids.contains { key(of: $0, in: bytes) == "projections" }
                ? try projections(of: name, in: bytes) : nil
            current[name] = Current(role: name, kids: objectKids, projections: projectionKids,
                                    extraKeys: objectKids.contains { key(of: $0, in: bytes) != "projections" })
            order.append(name)
        }

        let wanted = wells.filter { !$0.elements.isEmpty }
        var expectedElements: [String: [Any]] = [:]   // for the final check

        // 1. Replace the projections array of every well that exists and changed (last to first).
        var replacements: [(range: Range<Int>, text: [UInt8])] = []
        for well in wanted {
            let texts = try well.elements.map { try elementBytes($0) }
            expectedElements[well.role] = try texts.map { try JSONSerialization.jsonObject(with: Data($0), options: [.fragmentsAllowed]) }
            guard let existing = current[well.role] else { continue }
            let old = existing.projections ?? []
            let unchanged = old.count == texts.count && zip(old, texts).allSatisfy { Array(bytes[$0.value]) == $1 }
            if unchanged { continue }
            guard existing.projections != nil,
                  let arrayRange = JSONCursor.locate((statePath + [.key(well.role), .key("projections")])[...], in: bytes) else {
                throw WriteError.invalid("\(well.role) has no projections array")
            }
            replacements.append((arrayRange, arrayText(texts, replacing: old, array: arrayRange, in: bytes)))
        }
        for edit in replacements.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: edit.text)
        }

        // 2. Remove wells that are gone (a well with other keys keeps them and just gets an empty array).
        let keep = Set(wanted.map(\.role))
        var emptied: [String] = []
        if let kids = JSONCursor.children(at: statePath, in: bytes) {
            var drop = Set<Int>()
            for (index, kid) in kids.enumerated() {
                guard let name = key(of: kid, in: bytes), !keep.contains(name) else { continue }
                if current[name]?.extraKeys == true { emptied.append(name) } else { drop.insert(index) }
            }
            bytes = JSONCursor.removing(drop, from: kids, in: bytes)
        }
        for name in emptied {
            guard let arrayRange = JSONCursor.locate((statePath + [.key(name), .key("projections")])[...], in: bytes) else { continue }
            bytes.replaceSubrange(arrayRange, with: Array("[]".utf8))
            expectedElements[name] = []
        }

        // 3. Add new wells at the end of queryState.
        let added = wanted.filter { current[$0.role] == nil }
        if !added.isEmpty {
            guard let stateRange = JSONCursor.locate(statePath[...], in: bytes) else { throw WriteError.invalid("queryState vanished") }
            let kids = JSONCursor.children(at: statePath, in: bytes) ?? []
            var text: [UInt8] = []
            for (index, well) in added.enumerated() {
                if index > 0 || !kids.isEmpty { text.append(UInt8(ascii: ",")) }
                text += PBIRPatch.jsonStringToken(well.role)
                text += Array(#":{"projections":["#.utf8)
                text += Array(try well.elements.map { try elementBytes($0) }.joined(separator: [UInt8(ascii: ",")]))
                text += Array("]}".utf8)
            }
            let insertAt = kids.last?.value.upperBound ?? (stateRange.lowerBound + 1)
            bytes.insert(contentsOf: text, at: insertAt)
        }

        // 4. Check: the result is the old document with queryState changed as asked and nothing else.
        let result = Data(bytes)
        var expected = root
        guard var visual = expected["visual"] as? [String: Any], var query = visual["query"] as? [String: Any],
              var state = query["queryState"] as? [String: Any] else {
            throw WriteError.invalid("visual.json has no query.queryState")
        }
        for name in order where !keep.contains(name) {
            if current[name]?.extraKeys == true {
                var object = (state[name] as? [String: Any]) ?? [:]
                object["projections"] = [Any]()
                state[name] = object
            } else {
                state[name] = nil
            }
        }
        for well in wanted {
            var object = (state[well.role] as? [String: Any]) ?? [:]
            object["projections"] = expectedElements[well.role] ?? []
            state[well.role] = object
        }
        query["queryState"] = state
        visual["query"] = query
        expected["visual"] = visual
        guard let actual = try? JSONSerialization.jsonObject(with: result, options: []) as? [String: Any],
              (expected as NSDictionary).isEqual(to: actual) else {
            throw WriteError.verificationFailed("queryState splice changed other content")
        }
        return result
    }

    // MARK: - Helpers

    private static func validate(_ wells: [Well]) throws {
        for well in wells {
            guard !well.role.isEmpty else { throw WriteError.invalid("a well has no name") }
            var seen = Set<String>()
            for element in well.elements {
                let field = element.field
                if element.source == nil {
                    guard !field.entity.isEmpty, !field.property.isEmpty else {
                        throw WriteError.invalid("a new field needs a table and a name")
                    }
                } else if (try? JSONValue.parse(element.source!)).map({ $0.object.isEmpty }) ?? true {
                    throw WriteError.invalid("the source of a field of \(well.role) is not a JSON object")
                }
                guard seen.insert(field.queryRef).inserted else {
                    throw WriteError.invalid("\(field.queryRef) appears twice in \(well.role)")
                }
            }
        }
    }

    /// The bytes to write for one element: the source with its `displayName` brought up to date, or the template.
    private static func elementBytes(_ element: Element) throws -> [UInt8] {
        let field = element.field
        guard let source = element.source else {
            let kindKey: String
            switch field.kind {
            case .measure: kindKey = "Measure"
            case .column: kindKey = "Column"
            default: throw WriteError.invalid("only columns and measures can be added")
            }
            let ref = field.queryRef.isEmpty ? "\(field.entity).\(field.property)" : field.queryRef
            var out = Array(#"{"field":{"\#(kindKey)":{"Expression":{"SourceRef":{"Entity":"#.utf8)
            out += PBIRPatch.jsonStringToken(field.entity)
            out += Array(#"}},"Property":"#.utf8)
            out += PBIRPatch.jsonStringToken(field.property)
            out += Array(#"}},"queryRef":"#.utf8) + PBIRPatch.jsonStringToken(ref)
            out += Array(#","nativeQueryRef":"#.utf8) + PBIRPatch.jsonStringToken(field.nativeQueryRef ?? field.property)
            if let name = field.displayName, !name.isEmpty {
                out += Array(#","displayName":"#.utf8) + PBIRPatch.jsonStringToken(name)
            }
            out.append(UInt8(ascii: "}"))
            return out
        }
        let current = (try? JSONValue.parse(source))?["displayName"]?.string
        let wanted = (field.displayName?.isEmpty ?? true) ? nil : field.displayName
        guard current != wanted else { return [UInt8](source) }
        var bytes = [UInt8](source)
        if let existing = JSONCursor.locate([.key("displayName")][...], in: bytes) {
            if let wanted {
                bytes.replaceSubrange(existing, with: PBIRPatch.jsonStringToken(wanted))
            } else if let kids = JSONCursor.children(at: [], in: bytes), let index = kids.firstIndex(where: { key(of: $0, in: bytes) == "displayName" }) {
                bytes = JSONCursor.removing([index], from: kids, in: bytes)
            } else {
                throw WriteError.invalid("cannot remove displayName")
            }
        } else if let wanted {
            guard let close = bytes.lastIndex(of: UInt8(ascii: "}")) else { throw WriteError.invalid("element is not an object") }
            bytes.insert(contentsOf: Array(#","displayName":"#.utf8) + PBIRPatch.jsonStringToken(wanted), at: close)
        }
        return bytes
    }

    /// The array text for a well: elements joined the way the existing array joins them (compact stays compact,
    /// indented stays indented).
    private static func arrayText(_ texts: [[UInt8]], replacing old: [JSONCursor.Child], array: Range<Int>, in bytes: [UInt8]) -> [UInt8] {
        var prefix: [UInt8] = [], separator: [UInt8] = [UInt8(ascii: ",")], suffix: [UInt8] = []
        if let first = old.first, let last = old.last {
            prefix = Array(bytes[(array.lowerBound + 1)..<first.value.lowerBound])
            suffix = Array(bytes[last.value.upperBound..<(array.upperBound - 1)])
            separator = old.count >= 2 ? Array(bytes[old[0].value.upperBound..<old[1].value.lowerBound])
                                       : [UInt8(ascii: ",")] + prefix
        }
        var out: [UInt8] = [UInt8(ascii: "[")]
        if !texts.isEmpty { out += prefix }
        for (index, text) in texts.enumerated() {
            if index > 0 { out += separator }
            out += text
        }
        if !texts.isEmpty { out += suffix }
        out.append(UInt8(ascii: "]"))
        return out
    }

    private static func projections(of role: String, in bytes: [UInt8]) throws -> [JSONCursor.Child] {
        let path = statePath + [.key(role), .key("projections")]
        if JSONCursor.locate(path[...], in: bytes) == nil { return [] }
        guard let kids = JSONCursor.children(at: path, in: bytes) else {
            throw WriteError.invalid("\(role).projections is not an array")
        }
        return kids
    }

    private static func key(of child: JSONCursor.Child, in bytes: [UInt8]) -> String? {
        child.key.flatMap { JSONCursor.string(in: bytes, $0) }
    }

    private static func parseObject(_ json: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? [String: Any] else {
            throw WriteError.invalid("part is not a JSON object")
        }
        return root
    }
}
