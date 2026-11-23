import Foundation
import PBIXKit

/// Một chỗ trong `visual.json` (ngoài `queryState`) nhắc tới một trường. Quan sát VM-D2: bỏ trường thì Desktop xoá
/// các mục định dạng riêng của trường (`selector.metadata`) và giữ nguyên thẻ lọc, nên chỉ còn sắp xếp là chặn việc bỏ
/// (Desktop chưa quan sát được trường hợp `sortDefinition` trỏ tới trường bị bỏ; research R7).
struct FieldReference: Equatable {
    enum Kind: Equatable { case sort, filter, format }
    let kind: Kind
    let detail: String

    var reason: String {
        switch kind {
        case .sort: biN("đang dùng để sắp xếp visual", "used to sort the visual")
        case .filter: biN("đang có bộ lọc cấp visual", "has a visual-level filter")
        case .format: biN("đang có định dạng riêng (\(detail))", "has its own formatting (\(detail))")
        }
    }
}

enum FieldReferences {
    /// Các chỗ nhắc còn chặn việc bỏ trường (hoặc đổi loại làm mất trường): chỉ sắp xếp.
    /// Sắp xếp mặc định theo **measure** (`isDefaultSort: true`) không chặn: Desktop tự thêm nó khi thả measure và dọn đi khi
    /// bỏ measure (VM-D3 mục B: bỏ hết trường của card không để lại `sortDefinition`); `PBIRQueryPatch` bỏ hoặc dựng lại nó
    /// sau khi đổi trường. Sắp xếp mặc định theo cột và sắp xếp người dùng đặt vẫn chặn (chưa quan sát).
    static func blocking(in json: Data, entity: String, property: String, queryRef: String) -> [FieldReference] {
        let sorts = find(in: json, entity: entity, property: property, queryRef: queryRef).filter { $0.kind == .sort }
        guard !sorts.isEmpty, let root = try? JSONValue.parse(json), let sort = root["visual"]?["query"]?["sortDefinition"],
              sort["isDefaultSort"]?.bool == true,
              (sort["sort"]?.array ?? []).allSatisfy({ $0["field"]?["Measure"] != nil }) else { return sorts }
        return []
    }

    /// Các nơi trong `json` nhắc tới trường (`entity`, `property`, `queryRef`): sắp xếp, thẻ lọc cấp visual, định dạng
    /// theo trường (`selector.metadata` bằng `queryRef`). Không đọc được thì trả rỗng.
    static func find(in json: Data, entity: String, property: String, queryRef: String) -> [FieldReference] {
        guard let root = try? JSONValue.parse(json) else { return [] }
        var found: [FieldReference] = []
        let visual = root["visual"]
        for sort in visual?["query"]?["sortDefinition"]?["sort"]?.array ?? [] {
            if let target = target(of: sort["field"]), target.entity == entity, target.property == property {
                found.append(FieldReference(kind: .sort, detail: "\(entity)[\(property)]"))
            }
        }
        for filter in root["filterConfig"]?["filters"]?.array ?? [] {
            if let target = target(of: filter["field"]), target.entity == entity, target.property == property {
                found.append(FieldReference(kind: .filter, detail: filter["name"]?.string ?? "\(entity)[\(property)]"))
            }
        }
        for (key, value) in visual?["objects"]?.object ?? [:] {
            collectMetadata(value, queryRef: queryRef, object: key, into: &found)
        }
        for (key, value) in visual?["visualContainerObjects"]?.object ?? [:] {
            collectMetadata(value, queryRef: queryRef, object: key, into: &found)
        }
        return found
    }

    /// Bảng và tên của một biểu thức trường (`Column`, `Measure`, `Aggregation`, `HierarchyLevel`).
    private static func target(of field: JSONValue?) -> (entity: String, property: String)? {
        guard let field else { return nil }
        for key in ["Column", "Measure"] {
            if let node = field[key], let property = node["Property"]?.string,
               let entity = node["Expression"]?["SourceRef"]?["Entity"]?.string ?? node["Expression"]?["SourceRef"]?["Source"]?.string {
                return (entity, property)
            }
        }
        if let aggregation = field["Aggregation"] { return target(of: aggregation["Expression"]) }
        if let level = field["HierarchyLevel"], let name = level["Level"]?.string {
            let source = level["Expression"]?["Hierarchy"]?["Expression"]?["SourceRef"]
            if let entity = source?["Entity"]?.string { return (entity, name) }
        }
        return nil
    }

    private static func collectMetadata(_ value: JSONValue, queryRef: String, object: String, into found: inout [FieldReference]) {
        switch value {
        case .object(let dict):
            if dict["metadata"]?.string == queryRef {
                found.append(FieldReference(kind: .format, detail: object))
            }
            for child in dict.values { collectMetadata(child, queryRef: queryRef, object: object, into: &found) }
        case .array(let items):
            for item in items { collectMetadata(item, queryRef: queryRef, object: object, into: &found) }
        default:
            break
        }
    }
}
