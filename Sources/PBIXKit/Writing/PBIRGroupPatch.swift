import Foundation

/// Visual groups of a PBIR report (D7): the `visual.json` of a group container and the `parentGroupName` of its members.
///
/// Shape observed in Power BI Desktop 2.159 (docs/phase-d-evidence/vm-d7/QUAN-SAT.md): a group is a container
/// `{"$schema", "name", "position": {x, y, z, height, width, tabOrder}, "visualGroup": {displayName, groupMode}}`; a member
/// keeps its own `visual.json`, with `position.x` and `position.y` relative to the group and `"parentGroupName"` as the last
/// key of the root object. Edits splice bytes like `PBIRLayoutPatch`; everything not touched keeps its bytes.
public enum PBIRGroupPatch {
    /// The `$schema` Desktop wrote for the group container.
    public static let groupSchema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.14.0/schema.json"
    public static let groupMode = "ScaleMode"

    /// The `visual.json` of a new group, written the way Desktop writes it (compact, key order as observed).
    public static func groupJSON(name: String, displayName: String, x: Double, y: Double, width: Double, height: Double,
                                 z: Double, schema: String = groupSchema) throws -> Data {
        guard PBIRLayoutPatch.isValidVisualName(name) else { throw WriteError.invalid("group name must be 20 lowercase hex characters") }
        guard width >= 1, height >= 1, x >= 0, y >= 0 else { throw WriteError.invalid("group frame is not valid") }
        func n(_ v: Double) -> String { PBIRLayoutPatch.numberText(v) }
        func s(_ text: String) -> String { String(decoding: PBIRPatch.jsonStringToken(text), as: UTF8.self) }
        let text = "{\"$schema\":\(s(schema)),\"name\":\(s(name)),\"position\":{\"x\":\(n(x)),\"y\":\(n(y)),\"z\":\(n(z)),"
            + "\"height\":\(n(height)),\"width\":\(n(width)),\"tabOrder\":\(n(z))},"
            + "\"visualGroup\":{\"displayName\":\(s(displayName)),\"groupMode\":\(s(groupMode))}}"
        return Data(text.utf8)
    }

    /// `parentGroupName` of a `visual.json`, or nil.
    public static func parentGroupName(in json: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: json, options: []) as? [String: Any])?["parentGroupName"] as? String
    }

    /// `json` with `parentGroupName` set to `group` (added as the last key of the root object, or replaced in place), or
    /// removed when `group` is nil. Same bytes when it already is that.
    public static func settingParentGroup(_ group: String?, in json: Data) throws -> Data {
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? [String: Any] else {
            throw WriteError.invalid("part is not a JSON object")
        }
        let current = root["parentGroupName"] as? String
        if current == group, (group != nil) == (root["parentGroupName"] != nil) { return json }
        let bytes = [UInt8](json)
        var out = bytes
        guard let kids = JSONCursor.children(at: [], in: bytes), !kids.isEmpty else { throw WriteError.invalid("part is an empty object") }
        if let index = kids.firstIndex(where: { $0.key.flatMap { JSONCursor.string(in: bytes, $0) } == "parentGroupName" }) {
            if let group {
                out.replaceSubrange(kids[index].value, with: PBIRPatch.jsonStringToken(group))
            } else {
                out = JSONCursor.removing([index], from: kids, in: bytes)
            }
        } else if let group, let last = kids.last {
            out.insert(contentsOf: Array(",\"parentGroupName\":".utf8) + PBIRPatch.jsonStringToken(group), at: last.value.upperBound)
        }
        var expected = root
        if let group { expected["parentGroupName"] = group } else { expected["parentGroupName"] = nil }
        try verify(Data(out), equals: expected, what: "parentGroupName splice")
        return Data(out)
    }

    /// The first "Group N" (N from 1) not in `used`.
    public static func nextDisplayName(avoiding used: Set<String>) -> String {
        var n = 1
        while used.contains("Group \(n)") { n += 1 }
        return "Group \(n)"
    }

    private static func verify(_ data: Data, equals expected: [String: Any], what: String) throws {
        guard let actual = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              (expected as NSDictionary).isEqual(to: actual) else {
            throw WriteError.verificationFailed("\(what) changed other content")
        }
    }
}
