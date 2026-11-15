import DAXEngine
import Foundation
import PBIXKit

/// Một tệp JSON của báo cáo (visual, trang, báo cáo, bookmark) để quét tham chiếu trường.
struct ModelDocument {
    let label: String
    let json: JSONValue
}

/// Một nơi đang dùng một measure hoặc cột.
struct ModelUsage: Equatable {
    enum Kind: Equatable {
        /// Visual, trang, báo cáo hoặc bookmark.
        case document
        /// Biểu thức DAX của measure, cột tính toán hoặc định dạng động.
        case measure
        case relationship
        case sortBy
        case hierarchy
    }

    let kind: Kind
    let detail: String
}

/// Phase E (R6): ai đang dùng một measure hoặc cột. Xoá và đổi tên bị chặn khi kết quả không rỗng (FR-004, FR-020).
enum ModelReferences {
    static func usages(ofMeasure table: String, name: String, in model: ModelMetadata, documents: [ModelDocument]) -> [ModelUsage] {
        var found: [ModelUsage] = []
        for other in model.measures where !(other.tableName == table && other.name == name) {
            let texts = [other.expression, other.formatStringDefinition].compactMap { $0 }
            // `[Tên]` không có bảng là measure (tên measure duy nhất trong mô hình); `Bảng[Tên]` phải đúng bảng.
            if texts.contains(where: { text in
                DAXEngine.references(in: text).contains { $0.name == name && ($0.table == nil || $0.table == table) }
            }) {
                found.append(ModelUsage(kind: .measure, detail: "\(other.tableName)[\(other.name)]"))
            }
        }
        for column in model.columns where column.kind == .calculated {
            guard let expression = column.expression else { continue }
            if DAXEngine.references(in: expression).contains(where: { $0.name == name && ($0.table == nil || $0.table == table) }) {
                found.append(ModelUsage(kind: .measure, detail: "cột \(column.tableName)[\(column.name)]"))
            }
        }
        found += documentUsages(entityKind: "Measure", table: table, name: name, documents: documents)
        return found
    }

    static func usages(ofColumn table: String, name: String, in model: ModelMetadata, documents: [ModelDocument]) -> [ModelUsage] {
        var found: [ModelUsage] = []
        let hasMeasureWithName = model.measures.contains { $0.name == name }
        func mentions(_ text: String, inTable owner: String) -> Bool {
            DAXEngine.references(in: text).contains { reference in
                if let referenced = reference.table { return referenced == table && reference.name == name }
                return reference.name == name && owner == table && !hasMeasureWithName
            }
        }
        for measure in model.measures {
            let texts = [measure.expression, measure.formatStringDefinition].compactMap { $0 }
            if texts.contains(where: { mentions($0, inTable: measure.tableName) }) {
                found.append(ModelUsage(kind: .measure, detail: "\(measure.tableName)[\(measure.name)]"))
            }
        }
        for column in model.columns where column.kind == .calculated && !(column.tableName == table && column.name == name) {
            if let expression = column.expression, mentions(expression, inTable: column.tableName) {
                found.append(ModelUsage(kind: .measure, detail: "cột \(column.tableName)[\(column.name)]"))
            }
        }
        for relationship in model.relationships {
            if (relationship.fromTable == table && relationship.fromColumn == name) || (relationship.toTable == table && relationship.toColumn == name) {
                found.append(ModelUsage(kind: .relationship,
                                        detail: "quan hệ \(relationship.fromTable)[\(relationship.fromColumn)] → \(relationship.toTable)[\(relationship.toColumn)]"))
            }
        }
        if let column = model.columns.first(where: { $0.tableName == table && $0.name == name }) {
            for sorted in model.columns where sorted.sortByColumnID == column.id {
                found.append(ModelUsage(kind: .sortBy, detail: "cột \(sorted.tableName)[\(sorted.name)] sắp xếp theo cột này"))
            }
        }
        for hierarchy in model.hierarchies where hierarchy.tableName == table && hierarchy.levels.contains(where: { $0.columnName == name }) {
            found.append(ModelUsage(kind: .hierarchy, detail: "phân cấp \(hierarchy.tableName)[\(hierarchy.name)]"))
        }
        found += documentUsages(entityKind: "Column", table: table, name: name, documents: documents)
        return found
    }

    /// Lời giải thích khi bị chặn: tối đa 10 nơi, rồi "và N nơi nữa".
    static func message(_ usages: [ModelUsage], what: String) -> String {
        let shown = usages.prefix(10).map(\.detail).joined(separator: ", ")
        let rest = usages.count > 10 ? ", và \(usages.count - 10) nơi nữa" : ""
        return "\(what) còn được dùng ở: \(shown)\(rest)."
    }

    private static func documentUsages(entityKind: String, table: String, name: String, documents: [ModelDocument]) -> [ModelUsage] {
        documents.compactMap { document in
            mentionsField(document.json, kind: entityKind, table: table, name: name) ? ModelUsage(kind: .document, detail: document.label) : nil
        }
    }

    /// Có chỗ nào trong `json` là `{ "<kind>": { "Expression": { "SourceRef": { "Entity": table } }, "Property": name } }`
    /// (kể cả khi nằm trong `Aggregation`, `filterConfig`, `sortDefinition`, `Where`...).
    private static func mentionsField(_ json: JSONValue, kind: String, table: String, name: String) -> Bool {
        switch json {
        case .object(let dict):
            if let node = dict[kind], node["Property"]?.string == name,
               let entity = node["Expression"]?["SourceRef"]?["Entity"]?.string, entity == table {
                return true
            }
            return dict.values.contains { mentionsField($0, kind: kind, table: table, name: name) }
        case .array(let items):
            return items.contains { mentionsField($0, kind: kind, table: table, name: name) }
        default:
            return false
        }
    }
}

extension ModelReferences {
    /// Mọi tệp JSON của báo cáo có thể nhắc tới trường: visual (bản đang sửa), trang, báo cáo, bookmark.
    @MainActor
    static func documents(layout: LayoutEditor, workspace: Workspace) -> [ModelDocument] {
        var documents: [ModelDocument] = []
        for page in layout.pages {
            for visual in layout.visuals(of: page.id) {
                documents.append(ModelDocument(label: "visual \(visual.id) (trang \(page.displayName))", json: visual.raw))
            }
        }
        let archive = workspace.pbix.archive
        for entry in archive.entries {
            let path = entry.path
            let label: String
            if path.hasSuffix("/page.json"), path.hasPrefix("Report/definition/pages/") {
                label = "bộ lọc của trang \(path.split(separator: "/").dropLast().last.map(String.init) ?? path)"
            } else if path == "Report/definition/report.json" {
                label = "bộ lọc cấp báo cáo"
            } else if path.hasPrefix("Report/definition/bookmarks/"), path.hasSuffix(".bookmark.json") {
                label = "bookmark \(path.split(separator: "/").last.map(String.init) ?? path)"
            } else { continue }
            if let data = try? archive.read(entry), let json = try? JSONValue.parse(data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(data.dropFirst(3)) : data) {
                documents.append(ModelDocument(label: label, json: json))
            }
        }
        return documents
    }
}
