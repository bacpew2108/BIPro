// Phase F, T062: "Close & Apply" của Query Editor. Mỗi truy vấn bật "Enable load" mà chưa nạp hoặc đã sửa được đánh giá đủ (không cắt
// 1000 dòng) rồi thành `.addTable` (chưa có bảng) hoặc `.replaceTable` (đã nạp: quan hệ, measure, định dạng của cột còn lại được giữ);
// tắt "Enable load" cho truy vấn đã nạp thì `.dropTable`. Cả lần áp dụng là một bước ⌘Z chung với Phase D/E (FR-080) và tất cả hoặc không.
// Cột bị mất mà còn được dùng (quan hệ, measure, visual…) làm `replaceTable` bị từ chối kèm danh sách nơi dùng (FR-054, ModelMetadata+TableEdit).

import ColumnStore
import Foundation
import MEngine
import PBIXKit

extension QueryEditorState {
    /// Có truy vấn nào cần đưa vào mô hình không (nút "Close & Apply" sáng, hộp "Pending changes").
    var hasUnappliedQueries: Bool {
        queries.contains { query in
            query.enableLoad ? (query.isModified || query.savedQueryName != nil) : (query.loadedTableName != nil || query.isModified)
        }
    }

    /// Áp dụng mọi truy vấn vào mô hình. Trả lý do (tiếng Việt) khi bị từ chối hoặc có truy vấn lỗi (không đổi gì), `nil` khi xong.
    @MainActor
    func closeAndApply(to editor: ModelEditor, existingTableNames: Set<String>) async -> String? {
        var taken = existingTableNames
        for query in queries { if let name = query.loadedTableName { taken.remove(name) } }
        var loadedTables: [LoadedTable] = []
        var drops: [ModelEdit] = []
        var queryEdits: [ModelEdit] = []
        var updates: [UUID: (tableName: String?, source: String, savedQueryName: String?)] = [:]

        for query in queries {
            // Truy vấn từng lưu không nạp (dòng `Expression`): bỏ dòng cũ khi bật nạp lại hoặc đổi tên (tắt nạp thì ghi lại bên dưới).
            if let saved = query.savedQueryName, query.enableLoad || saved != query.name { drops.append(.dropQuery(name: saved)) }
            if !query.enableLoad {
                if let name = query.loadedTableName { drops.append(.dropTable(name: name)) }
                if query.loadedTableName != nil || query.isModified || query.savedQueryName != query.name {
                    queryEdits.append(.setQuery(name: query.name, expression: query.source))
                    updates[query.id] = (nil, query.source, query.name)
                }
                continue
            }
            guard query.isModified || query.savedQueryName != nil else { continue }
            let data: TableData
            do { data = try await evaluateFull(query) } catch {
                return biN("Truy vấn \"\(query.name)\" lỗi: \(message(for: error, in: query))", "Query \"\(query.name)\" has an error: \(message(for: error, in: query))")
            }
            let name = query.loadedTableName ?? TableNaming.uniqueName(query.name, taken: taken)
            taken.insert(name)
            loadedTables.append(LoadedTable(name: name, queryName: query.name, data: data,
                                            status: query.loadedTableName == nil ? .new : .replaced, queryText: query.source))
            updates[query.id] = (name, query.source, nil)
        }
        let edits = drops + TableLoader.edits(for: loadedTables) + queryEdits
        if let reason = editor.apply(edits) { return reason }
        markApplied(updates)
        return nil
    }
}
