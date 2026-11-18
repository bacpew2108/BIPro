// Đợt tồn đọng sau Phase F, T035: tự phát hiện quan hệ sau khi nạp, như "Autodetect new relationships after data is loaded" của Desktop
// 2.159 (VM-F11c, `docs/phase-f2-evidence/vm-f11/QUAN-SAT.md` mục c, research R4).
//
// Quan sát được:
// - cột cùng tên, cùng kiểu (số với chữ thì bỏ); đúng một phía có giá trị duy nhất → nhiều–một, lọc một chiều;
// - cả hai phía lặp thì bỏ;
// - quan hệ mới tạo đường thứ hai giữa hai bảng (qua các quan hệ hoạt động) thì vẫn tạo nhưng không hoạt động;
// - tên `AutoDetected_<guid>`.
// Gate VM-F11 (T037, `vm-f11/KET-QUA.md`): so tên không phân biệt hoa thường (`K` nối `k`); cột số thực (Decimal) vẫn làm khoá;
// cột logic thì bỏ; mỗi cặp bảng một quan hệ, lấy cột đầu tiên theo thứ tự cột (`k` trước `d`).
// `[SUY ĐOÁN]`: hai phía cùng duy nhất thì bỏ; chỉ xét cặp có ít nhất một bảng mới nạp (bảng thay dữ liệu không xét);
// thứ tự cặp theo thứ tự bảng trong mô hình.

import ColumnStore
import Foundation
import PBIXKit

enum RelationshipDetector {
    static let namePrefix = "AutoDetected_"

    /// Quan hệ tự tạo cho các bảng `newTables` vừa có trong `model` (mô hình sau khi nạp). `isUnique`: cột không có giá trị trùng.
    static func detect(model: ModelMetadata, newTables: Set<String>, isUnique: (RelationshipDraft.ColumnRef) -> Bool,
                       id: () -> UUID = UUID.init) -> [NewRelationship] {
        guard !newTables.isEmpty else { return [] }
        let tables = model.userTables.map(\.name)
        var working = model
        var result: [NewRelationship] = []
        func keyColumns(_ table: String) -> [ModelMetadata.Column] {
            model.columns.filter {
                $0.tableName == table && $0.kind != .rowNumber && $0.kind != .calculated
                    && ![.boolean, .unknown].contains($0.dataType)
            }
        }
        for (i, a) in tables.enumerated() {
            for b in tables[(i + 1)...] where newTables.contains(a) || newTables.contains(b) {
                let joined = working.relationships.contains { Set([$0.fromTable, $0.toTable]) == Set([a, b]) }
                if joined { continue }
                let others = keyColumns(b)
                for column in keyColumns(a) {
                    guard let match = others.first(where: { $0.name.lowercased() == column.name.lowercased() }),
                          match.dataType == column.dataType,
                          case .success(let draft) = RelationshipDraft.propose(
                              model: working, drag: .init(table: a, column: column.name), drop: .init(table: b, column: match.name),
                              isUnique: isUnique)
                    else { continue }
                    var relationship = draft.relationship
                    relationship.name = namePrefix + id().uuidString.lowercased()
                    guard let next = try? working.applying(ModelEdits([.addRelationship(relationship)])) else { continue }
                    working = next
                    result.append(relationship)
                    break
                }
            }
        }
        return result
    }

    /// Các giá trị không trùng nhau (BLANK tính là một giá trị).
    static func isUnique(_ values: VertiPaqWriter.Values) -> Bool {
        func distinct<T: Hashable>(_ items: [T?]) -> Bool { Set(items.map { $0.map(AnyHashable.init) }).count == items.count }
        switch values {
        case .int64(let v): return distinct(v)
        case .boolean(let v): return distinct(v)
        case .double(let v): return distinct(v)
        case .dateTime(let v): return distinct(v)
        case .string(let v): return distinct(v)
        case .currency(let v): return distinct(v)
        }
    }

    /// Cột `column` của bảng nạp trong phiên không có giá trị trùng.
    static func isUnique(_ table: TableData, column: String) -> Bool {
        guard let data = table.columns.first(where: { $0.name == column })?.data else { return false }
        var seen = Set<StoredValue>()
        for row in 0..<data.rowCount where !seen.insert(data.value(at: row)).inserted { return false }
        return true
    }

    /// Thao tác tự tạo quan hệ cho lô `edits` (đã kèm phần Auto date/time) trên mô hình `before`: chỉ khi lô có bảng mới (`addTable`).
    static func expand(_ edits: [ModelEdit], before: ModelMetadata, isUnique existing: (RelationshipDraft.ColumnRef) -> Bool,
                       id: () -> UUID = UUID.init) -> [ModelEdit] {
        var added: [String: NewTable] = [:]
        for edit in edits { if case .addTable(let table) = edit { added[table.name] = table } }
        guard !added.isEmpty, let after = try? before.applying(ModelEdits(edits)) else { return edits }
        let detected = detect(model: after, newTables: Set(added.keys), isUnique: { ref in
            if let table = added[ref.table] {
                if let data = table.attachment as? TableData { return isUnique(data, column: ref.column) }
                guard let values = table.columns.first(where: { $0.name == ref.column })?.values else { return false }
                return isUnique(values)
            }
            return existing(ref)
        }, id: id)
        return edits + detected.map { .addRelationship($0) }
    }
}
