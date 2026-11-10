import Foundation

/// Phạm vi định dạng của một visual trong PBIR `visual.json`: `visual.objects` (Visual) hoặc
/// `visual.visualContainerObjects` (Chung).
public enum FormatScope: String, Sendable, Equatable, Hashable, CaseIterable {
    case objects
    case container

    /// Tên khoá trong `visual`.
    public var key: String { self == .objects ? "objects" : "visualContainerObjects" }
}

/// Một thay đổi định dạng của một visual (D4): `specs/006-d4-format-pane/data-model.md`.
public struct FormatEdit: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Đặt thuộc tính; `value` là chuỗi JSON của giá trị, ví dụ `{"expr":{"Literal":{"Value":"16D"}}}`.
        case set(property: String, value: String)
        case removeProperty(String)
        case removeObject
    }

    public var scope: FormatScope
    /// Khoá trong file, ví dụ `labels`, `title`.
    public var object: String
    public var action: Action
    /// Khi tạo mục mới của khoá: ghi `"selector":{"id":"default"}` sau `properties` (`cardVisual`).
    public var selectorDefault: Bool

    public init(scope: FormatScope, object: String, action: Action, selectorDefault: Bool = false) {
        self.scope = scope; self.object = object; self.action = action; self.selectorDefault = selectorDefault
    }

    var property: String? {
        switch action {
        case .set(let property, _): property
        case .removeProperty(let property): property
        case .removeObject: nil
        }
    }

    /// `list` thêm `new`: mỗi `(phạm vi, khoá, thuộc tính)` giữ lệnh cuối; bỏ cả khoá xoá mọi lệnh của khoá và đứng một mình;
    /// lệnh bỏ thuộc tính huỷ `set` cùng thuộc tính nhưng vẫn ở lại (thuộc tính có thể đã nằm trong file).
    public static func merging(_ list: [FormatEdit], adding new: FormatEdit) -> [FormatEdit] {
        var out = list.filter { old in
            guard old.scope == new.scope, old.object == new.object else { return true }
            switch new.action {
            case .removeObject: return false
            case .set, .removeProperty:
                if case .removeObject = old.action { return true }
                return old.property != new.property
            }
        }
        out.append(new)
        return out
    }
}

/// Ghép byte định dạng vào `visual.json` (D4). Thay đúng đoạn byte của giá trị, thêm khoá và thuộc tính ở cuối,
/// tạo phạm vi mới đúng chỗ như Power BI Desktop ghi; phần còn lại giữ từng byte. Xem `contracts/format-save.md`.
public enum PBIRFormatPatch {
    /// Khoá của `visual` đứng sau từng phạm vi khi Desktop ghi: `objects` trước `visualContainerObjects` trước `drillFilterOtherVisuals`.
    private static func followers(of scope: FormatScope) -> [String] {
        scope == .objects ? ["visualContainerObjects", "drillFilterOtherVisuals"] : ["drillFilterOtherVisuals"]
    }

    public static func apply(_ edits: [FormatEdit], to json: Data) throws -> Data {
        guard !edits.isEmpty else { return json }
        let parsed = try parse(json)
        guard parsed["visual"] is [String: Any] else { throw WriteError.invalid("visual.json has no visual object") }
        var bytes = [UInt8](json)
        let model = try deepMutableCopy(of: json)
        for edit in edits {
            try applyBytes(edit, &bytes)
            try applyModel(edit, model)
        }
        // Kiểm: đọc lại bằng bộ đọc khác và so với cấu trúc mong đợi.
        let actual = try parse(Data(bytes))
        guard (model as NSDictionary).isEqual(actual as NSDictionary) else {
            throw WriteError.verificationFailed("visual.json format splice changed other content")
        }
        return Data(bytes)
    }

    // MARK: - Byte

    private static let visualPath: [JSONPathStep] = [.key("visual")]

    private static func key(of child: JSONCursor.Child, in bytes: [UInt8]) -> String? {
        child.key.flatMap { JSONCursor.string(in: bytes, $0) }
    }

    /// Giá trị ở `path` là object (`{`) hay mảng (`[`).
    private static func opening(at path: [JSONPathStep], in bytes: [UInt8]) -> UInt8? {
        JSONCursor.locate(path[...], in: bytes).map { bytes[$0.lowerBound] }
    }

    private static func insert(_ text: [UInt8], at offset: Int, into bytes: inout [UInt8]) {
        bytes.insert(contentsOf: text, at: offset)
    }

    /// Thêm `"key":value` vào cuối object ở `path`.
    private static func appendMember(_ member: String, to path: [JSONPathStep], in bytes: inout [UInt8]) throws {
        guard let range = JSONCursor.locate(path[...], in: bytes), bytes[range.lowerBound] == UInt8(ascii: "{"),
              let kids = JSONCursor.children(at: path, in: bytes) else {
            throw WriteError.invalid("cannot find the object to extend in visual.json")
        }
        if let last = kids.last { insert(Array(("," + member).utf8), at: last.value.upperBound, into: &bytes) }
        else { insert(Array(member.utf8), at: range.lowerBound + 1, into: &bytes) }
    }

    private static func isEditable(_ entry: [String: Any]) -> Bool {
        guard let selector = entry["selector"] else { return true }
        guard let dict = selector as? [String: Any] else { return false }
        return dict.keys.allSatisfy { $0 == "id" } && dict["id"] as? String == "default"
    }

    /// Chỉ số mục chung (không selector hoặc `id: default`) đầu tiên của mảng ở `arrayPath`.
    private static func editableIndex(at arrayPath: [JSONPathStep], in bytes: [UInt8]) throws -> Int? {
        guard opening(at: arrayPath, in: bytes) == UInt8(ascii: "["),
              let kids = JSONCursor.children(at: arrayPath, in: bytes), !kids.isEmpty else {
            throw WriteError.invalid("format entries are not a non-empty array in visual.json")
        }
        for (index, kid) in kids.enumerated() {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(bytes[kid.value])) as? [String: Any] else {
                throw WriteError.invalid("a format entry is not an object")
            }
            if isEditable(entry) { return index }
        }
        return nil
    }

    private static func removeChild(_ index: Int, atPath path: [JSONPathStep], in bytes: inout [UInt8]) {
        guard let kids = JSONCursor.children(at: path, in: bytes) else { return }
        bytes = JSONCursor.removing([index], from: kids, in: bytes)
    }

    private static func removeObjectKey(scope: FormatScope, object: String, in bytes: inout [UInt8]) throws {
        let scopePath = visualPath + [.key(scope.key)]
        guard JSONCursor.locate(scopePath[...], in: bytes) != nil else { return }
        guard opening(at: scopePath, in: bytes) == UInt8(ascii: "{"),
              let kids = JSONCursor.children(at: scopePath, in: bytes) else { throw WriteError.invalid("\(scope.key) is not an object") }
        guard let index = kids.firstIndex(where: { key(of: $0, in: bytes) == object }) else { return }
        if kids.count == 1 {
            guard let visualKids = JSONCursor.children(at: visualPath, in: bytes),
                  let scopeIndex = visualKids.firstIndex(where: { key(of: $0, in: bytes) == scope.key }) else { return }
            bytes = JSONCursor.removing([scopeIndex], from: visualKids, in: bytes)
        } else {
            bytes = JSONCursor.removing([index], from: kids, in: bytes)
        }
    }

    private static func applyBytes(_ edit: FormatEdit, _ bytes: inout [UInt8]) throws {
        let scopePath = visualPath + [.key(edit.scope.key)]
        let objectPath = scopePath + [.key(edit.object)]
        switch edit.action {
        case .removeObject:
            try removeObjectKey(scope: edit.scope, object: edit.object, in: &bytes)

        case .removeProperty(let property):
            guard JSONCursor.locate(objectPath[...], in: bytes) != nil else { return }
            guard JSONCursor.locate(scopePath[...], in: bytes) != nil,
                  let index = try editableIndex(at: objectPath, in: bytes) else { return }
            let propsPath = objectPath + [.index(index), .key("properties")]
            guard let kids = JSONCursor.children(at: propsPath, in: bytes) else { throw WriteError.invalid("properties is not an object") }
            guard let at = kids.firstIndex(where: { key(of: $0, in: bytes) == property }) else { return }
            if kids.count > 1 { removeChild(at, atPath: propsPath, in: &bytes); return }
            let entries = JSONCursor.children(at: objectPath, in: bytes) ?? []
            if entries.count > 1 { removeChild(index, atPath: objectPath, in: &bytes) }
            else { try removeObjectKey(scope: edit.scope, object: edit.object, in: &bytes) }

        case .set(let property, let value):
            let member = "\"\(edit.object)\":[" + entryText(property: property, value: value, selectorDefault: edit.selectorDefault) + "]"
            if JSONCursor.locate(scopePath[...], in: bytes) == nil {
                // Phạm vi chưa có: tạo, đặt trước khoá đứng sau nó trong `visual` (nếu có).
                let text = "\"\(edit.scope.key)\":{\(member)}"
                guard let kids = JSONCursor.children(at: visualPath, in: bytes) else { throw WriteError.invalid("visual is not an object") }
                let later = followers(of: edit.scope)
                if let next = kids.first(where: { later.contains(key(of: $0, in: bytes) ?? "") }) {
                    insert(Array((text + ",").utf8), at: next.start, into: &bytes)
                } else {
                    try appendMember(text, to: visualPath, in: &bytes)
                }
                return
            }
            guard opening(at: scopePath, in: bytes) == UInt8(ascii: "{"),
                  let scopeKids = JSONCursor.children(at: scopePath, in: bytes) else {
                throw WriteError.invalid("\(edit.scope.key) is not an object")
            }
            guard scopeKids.contains(where: { key(of: $0, in: bytes) == edit.object }) else {
                try appendMember(member, to: scopePath, in: &bytes)
                return
            }
            guard let index = try editableIndex(at: objectPath, in: bytes) else {
                throw WriteError.invalid("\(edit.object) has only entries bound to a field or data point; not editable")
            }
            let propsPath = objectPath + [.index(index), .key("properties")]
            guard let kids = JSONCursor.children(at: propsPath, in: bytes) else { throw WriteError.invalid("properties is not an object") }
            if let existing = kids.first(where: { key(of: $0, in: bytes) == property }) {
                bytes.replaceSubrange(existing.value, with: Array(value.utf8))
            } else {
                try appendMember("\"\(property)\":\(value)", to: propsPath, in: &bytes)
            }
        }
    }

    private static func entryText(property: String, value: String, selectorDefault: Bool) -> String {
        "{\"properties\":{\"\(property)\":\(value)}" + (selectorDefault ? ",\"selector\":{\"id\":\"default\"}" : "") + "}"
    }

    // MARK: - Mô hình (cấu trúc mong đợi)

    private static func parse(_ json: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw WriteError.invalid("visual.json is not a JSON object")
        }
        return root
    }

    private static func deepMutableCopy(of json: Data) throws -> NSMutableDictionary {
        guard let root = try? JSONSerialization.jsonObject(with: json, options: [.mutableContainers]) as? NSMutableDictionary else {
            throw WriteError.invalid("visual.json is not a JSON object")
        }
        return root
    }

    private static func modelEditable(_ array: NSMutableArray) throws -> NSMutableDictionary? {
        guard array.count > 0 else { throw WriteError.invalid("format entries are not a non-empty array in visual.json") }
        for item in array {
            guard let entry = item as? NSMutableDictionary else { throw WriteError.invalid("a format entry is not an object") }
            if isEditable(entry as? [String: Any] ?? [:]) { return entry }
        }
        return nil
    }

    private static func applyModel(_ edit: FormatEdit, _ root: NSMutableDictionary) throws {
        guard let visual = root["visual"] as? NSMutableDictionary else { throw WriteError.invalid("visual.json has no visual object") }
        let key = edit.scope.key
        func dropObject() {
            guard let scope = visual[key] as? NSMutableDictionary else { return }
            scope.removeObject(forKey: edit.object)
            if scope.count == 0 { visual.removeObject(forKey: key) }
        }
        switch edit.action {
        case .removeObject:
            dropObject()
        case .removeProperty(let property):
            guard let scope = visual[key] as? NSMutableDictionary, let array = scope[edit.object] as? NSMutableArray,
                  let entry = try modelEditable(array),
                  let props = entry["properties"] as? NSMutableDictionary, props[property] != nil else { return }
            props.removeObject(forKey: property)
            if props.count == 0 {
                array.remove(entry)
                if array.count == 0 { dropObject() }
            }
        case .set(let property, let valueText):
            let value = try JSONSerialization.jsonObject(with: Data(valueText.utf8), options: [.fragmentsAllowed, .mutableContainers])
            var scope: NSMutableDictionary
            if let existing = visual[key] {
                guard let dict = existing as? NSMutableDictionary else { throw WriteError.invalid("\(key) is not an object") }
                scope = dict
            } else {
                scope = NSMutableDictionary()
                visual[key] = scope
            }
            if let existing = scope[edit.object] {
                guard let array = existing as? NSMutableArray else { throw WriteError.invalid("\(edit.object) is not an array") }
                guard let entry = try modelEditable(array) else {
                    throw WriteError.invalid("\(edit.object) has only entries bound to a field or data point; not editable")
                }
                guard let props = entry["properties"] as? NSMutableDictionary else { throw WriteError.invalid("properties is not an object") }
                props[property] = value
            } else {
                let entry = NSMutableDictionary(dictionary: ["properties": NSMutableDictionary(dictionary: [property: value])])
                if edit.selectorDefault { entry["selector"] = NSMutableDictionary(dictionary: ["id": "default"]) }
                scope[edit.object] = NSMutableArray(array: [entry])
            }
        }
    }
}
