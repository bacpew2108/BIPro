import Foundation

/// Edits to a PBIR `visual.json` that are not about position or fields: the type of the visual, the keys of its
/// `objects` (formatting), and the text of a text box. Like the other patches, every edit splices bytes, so what is not
/// touched stays byte-for-byte as it was, and the result is re-parsed and compared with the expected structure.
///
/// Contract: `specs/004-d3-them-visual-doi-loai/contracts/visual-json-patches.md`.
public enum PBIRVisualPatch {
    private static let typePath: [JSONPathStep] = [.key("visual"), .key("visualType")]
    private static let objectsPath: [JSONPathStep] = [.key("visual"), .key("objects")]
    private static let paragraphsPath: [JSONPathStep] = [
        .key("visual"), .key("objects"), .key("general"), .index(0), .key("properties"), .key("paragraphs"),
    ]

    // MARK: - Read

    public static func visualType(in json: Data) throws -> String {
        let root = try parseObject(json)
        guard let type = (root["visual"] as? [String: Any])?["visualType"] as? String else {
            throw WriteError.invalid("visual.json has no visualType")
        }
        return type
    }

    /// The keys of `visual.objects` in file order (empty when there is no `objects`).
    public static func objectKeys(in json: Data) throws -> [String] {
        _ = try parseObject(json)
        let bytes = [UInt8](json)
        guard let kids = JSONCursor.children(at: objectsPath, in: bytes) else { return [] }
        return kids.compactMap { $0.key.flatMap { JSONCursor.string(in: bytes, $0) } }
    }

    /// The text of each paragraph of a text box (the runs of a paragraph joined).
    public static func paragraphs(in json: Data) throws -> [String] {
        let root = try parseObject(json)
        guard let list = paragraphList(root) else { throw WriteError.invalid("visual.json has no paragraphs") }
        return list.map { paragraph in
            ((paragraph["textRuns"] as? [[String: Any]]) ?? []).map { $0["value"] as? String ?? "" }.joined()
        }
    }

    // MARK: - Type and formatting keys

    /// `json` with `visual.visualType` set to `type`, and every key in `dropObjectKeys` removed from `visual.objects`.
    public static func setVisualType(in json: Data, to type: String, dropObjectKeys: Set<String>) throws -> Data {
        let root = try parseObject(json)
        guard (root["visual"] as? [String: Any])?["visualType"] is String else {
            throw WriteError.invalid("visual.json has no visualType")
        }
        guard !type.isEmpty else { throw WriteError.invalid("visualType must not be empty") }
        var bytes = [UInt8](json)
        guard let range = JSONCursor.locate(typePath[...], in: bytes), bytes[range.lowerBound] == UInt8(ascii: "\"") else {
            throw WriteError.invalid("visualType not found in visual.json")
        }
        bytes.replaceSubrange(range, with: PBIRPatch.jsonStringToken(type))

        var kept: [String]?
        if !dropObjectKeys.isEmpty, let kids = JSONCursor.children(at: objectsPath, in: bytes) {
            let names = kids.map { $0.key.flatMap { JSONCursor.string(in: bytes, $0) } ?? "" }
            let drop = Set(names.indices.filter { dropObjectKeys.contains(names[$0]) })
            if !drop.isEmpty {
                bytes = JSONCursor.removing(drop, from: kids, in: bytes)
                kept = names.filter { !dropObjectKeys.contains($0) }
            }
        }

        var expected = root
        var visual = root["visual"] as! [String: Any]
        visual["visualType"] = type
        if kept != nil, var objects = visual["objects"] as? [String: Any] {
            for key in dropObjectKeys { objects[key] = nil }
            visual["objects"] = objects
        }
        expected["visual"] = visual
        try verify(Data(bytes), equals: expected, what: "visual type splice")
        return Data(bytes)
    }

    // MARK: - Shape map

    private static let shapeText = #"[{"properties":{"datasourceType":{"expr":{"Literal":{"Value":"'file_upload'"}}},"map":{"geoJson":{"type":{"expr":{"Literal":{"Value":"'shared'"}}},"name":{"expr":{"Literal":{"Value":"'usa.states.topo'"}}},"content":{"expr":{"ResourcePackageItem":{"PackageName":"SharedResources","PackageType":2,"ItemName":"usa.states.topo"}}}}},"projectionEnum":{"expr":{"Literal":{"Value":"'albersUsa'"}}}}}]"#
    private static let gradientText = #"{"properties":{"fillRule":{"linearGradient2":{"min":{"color":{"expr":{"Literal":{"Value":"'minColor'"}}}},"max":{"color":{"expr":{"Literal":{"Value":"'maxColor'"}}}},"nullColoringStrategy":{"strategy":{"expr":{"Literal":{"Value":"'asZero'"}}}}}}}}"#

    /// What Power BI Desktop adds when a visual becomes a shape map (VM-D12, `docs/phase-d-evidence/vm-d12/`): `objects.shape`
    /// (the shared `usa.states.topo` map, Albers USA projection), and an entry of `objects.dataPoint` with a two-colour
    /// gradient `fillRule` (appended after the entries already there). Does nothing when the visual already has `objects.shape`.
    /// The caller makes sure the report has the `usa.states.topo` resource.
    public static func addingShapeMapDefaults(to json: Data) throws -> Data {
        let root = try parseObject(json)
        guard let visual = root["visual"] as? [String: Any] else { throw WriteError.invalid("visual.json has no visual") }
        let objects = visual["objects"] as? [String: Any]
        if objects?["shape"] != nil { return json }
        var bytes = [UInt8](json)
        let gradient = Array(gradientText.utf8)
        var appended: [String] = []
        if objects == nil {
            guard let kids = JSONCursor.children(at: [.key("visual")], in: bytes),
                  let query = kids.first(where: { $0.key.flatMap { JSONCursor.string(in: bytes, $0) } == "query" }) else {
                throw WriteError.invalid("visual has no query to put objects after")
            }
            let text = Array(#","objects":{"dataPoint":["#.utf8) + gradient + Array(#"],"shape":"#.utf8) + Array(shapeText.utf8) + [UInt8(ascii: "}")]
            bytes.insert(contentsOf: text, at: query.value.upperBound)
        } else {
            let dataPointPath: [JSONPathStep] = objectsPath + [.key("dataPoint")]
            if let entries = JSONCursor.children(at: dataPointPath, in: bytes) {
                guard let range = JSONCursor.locate(dataPointPath[...], in: bytes) else { throw WriteError.invalid("dataPoint not found") }
                if let last = entries.last {
                    bytes.insert(contentsOf: [UInt8(ascii: ",")] + gradient, at: last.value.upperBound)
                } else {
                    bytes.insert(contentsOf: gradient, at: range.lowerBound + 1)
                }
            } else {
                appended.append(#""dataPoint":["# + gradientText + "]")
            }
            appended.append(#""shape":"# + shapeText)
            guard let range = JSONCursor.locate(objectsPath[...], in: bytes), let kids = JSONCursor.children(at: objectsPath, in: bytes) else {
                throw WriteError.invalid("objects not found")
            }
            let text = (kids.isEmpty ? "" : ",") + appended.joined(separator: ",")
            bytes.insert(contentsOf: Array(text.utf8), at: range.upperBound - 1)
        }
        var expected = root
        var newVisual = visual
        var newObjects = objects ?? [:]
        let gradientJSON = try JSONSerialization.jsonObject(with: Data(gradientText.utf8))
        newObjects["dataPoint"] = ((newObjects["dataPoint"] as? [Any]) ?? []) + [gradientJSON]
        newObjects["shape"] = try JSONSerialization.jsonObject(with: Data(shapeText.utf8))
        newVisual["objects"] = newObjects
        expected["visual"] = newVisual
        try verify(Data(bytes), equals: expected, what: "shape map defaults splice")
        return Data(bytes)
    }

    // MARK: - Text box

    /// `json` with the paragraphs of a text box set to `lines`. A paragraph with one run keeps its style and only its
    /// `value` changes; a paragraph with several runs keeps its first run; extra lines copy the bytes of the last
    /// paragraph; fewer lines drop the last paragraphs. No lines leaves one empty paragraph.
    public static func setText(in json: Data, lines requested: [String]) throws -> Data {
        let root = try parseObject(json)
        guard paragraphList(root) != nil else { throw WriteError.invalid("visual.json has no paragraphs") }
        let lines = requested.isEmpty ? [""] : requested
        let bytes = [UInt8](json)
        guard let arrayRange = JSONCursor.locate(paragraphsPath[...], in: bytes),
              let old = JSONCursor.children(at: paragraphsPath, in: bytes) else {
            throw WriteError.invalid("paragraphs not found in visual.json")
        }
        let existing = old.map { Array(bytes[$0.value]) }
        let current = try paragraphs(in: json)
        var texts: [[UInt8]] = []
        for (index, line) in lines.enumerated() {
            if index < existing.count {
                // Đoạn không đổi chữ thì giữ nguyên byte (kể cả đoạn nhiều lượt).
                texts.append(current[index] == line ? existing[index] : try paragraph(existing[index], with: line))
            } else if let last = existing.last {
                texts.append(try paragraph(last, with: line))
            } else {
                texts.append(Array(#"{"textRuns":[{"value":"#.utf8) + PBIRPatch.jsonStringToken(line) + Array("}]}".utf8))
            }
        }
        if texts == existing { return json }

        var prefix: [UInt8] = [], separator: [UInt8] = [UInt8(ascii: ",")], suffix: [UInt8] = []
        if let first = old.first, let last = old.last {
            prefix = Array(bytes[(arrayRange.lowerBound + 1)..<first.value.lowerBound])
            suffix = Array(bytes[last.value.upperBound..<(arrayRange.upperBound - 1)])
            separator = old.count >= 2 ? Array(bytes[old[0].value.upperBound..<old[1].value.lowerBound]) : [UInt8(ascii: ",")] + prefix
        }
        var array: [UInt8] = [UInt8(ascii: "[")] + prefix
        for (index, text) in texts.enumerated() {
            if index > 0 { array += separator }
            array += text
        }
        array += suffix
        array.append(UInt8(ascii: "]"))
        var out = bytes
        out.replaceSubrange(arrayRange, with: array)

        var expected = root
        var visual = root["visual"] as! [String: Any]
        var objects = visual["objects"] as! [String: Any]
        var general = objects["general"] as! [[String: Any]]
        var first = general[0]
        var properties = first["properties"] as! [String: Any]
        properties["paragraphs"] = try texts.map { try JSONSerialization.jsonObject(with: Data($0)) }
        first["properties"] = properties
        general[0] = first
        objects["general"] = general
        visual["objects"] = objects
        expected["visual"] = visual
        try verify(Data(out), equals: expected, what: "text splice")
        guard try paragraphs(in: Data(out)) == lines else { throw WriteError.verificationFailed("text does not read back") }
        return Data(out)
    }

    /// One paragraph with its text set to `line`: the first run's `value` replaced, later runs dropped.
    private static func paragraph(_ source: [UInt8], with line: String) throws -> [UInt8] {
        var bytes = source
        let runsPath: [JSONPathStep] = [.key("textRuns")]
        guard let runs = JSONCursor.children(at: runsPath, in: bytes), !runs.isEmpty else {
            return Array(#"{"textRuns":[{"value":"#.utf8) + PBIRPatch.jsonStringToken(line) + Array("}]}".utf8)
        }
        if runs.count > 1 {
            bytes = JSONCursor.removing(Set(1..<runs.count), from: runs, in: bytes)
        }
        let valuePath: [JSONPathStep] = [.key("textRuns"), .index(0), .key("value")]
        if let value = JSONCursor.locate(valuePath[...], in: bytes), bytes[value.lowerBound] == UInt8(ascii: "\"") {
            if JSONCursor.string(in: bytes, value) == line { return bytes }
            bytes.replaceSubrange(value, with: PBIRPatch.jsonStringToken(line))
        } else if let runStart = JSONCursor.locate([.key("textRuns"), .index(0)][...], in: bytes), bytes[runStart.lowerBound] == UInt8(ascii: "{") {
            bytes.insert(contentsOf: Array(#""value":"#.utf8) + PBIRPatch.jsonStringToken(line) + [UInt8(ascii: ",")], at: runStart.lowerBound + 1)
        } else {
            throw WriteError.invalid("a text run has no value")
        }
        return bytes
    }

    // MARK: - Helpers

    private static func paragraphList(_ root: [String: Any]) -> [[String: Any]]? {
        let visual = root["visual"] as? [String: Any]
        let general = (visual?["objects"] as? [String: Any])?["general"] as? [[String: Any]]
        return (general?.first?["properties"] as? [String: Any])?["paragraphs"] as? [[String: Any]]
    }

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
