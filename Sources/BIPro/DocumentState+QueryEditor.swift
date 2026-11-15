// Phase F (T060): nối Query Editor vào tài liệu. Mở từ Ribbon "Biến đổi dữ liệu" (liệt kê truy vấn đã có trong file, bước đọc từ file
// bị khoá) hoặc từ Navigator "Chuyển đổi dữ liệu" (truy vấn mới từ bảng đang chọn). "Close & Apply" đi qua `closeAndApply`
// (một bước ⌘Z, tất cả hoặc không); bị từ chối thì cửa sổ ở lại và hiện lý do ở thanh dưới.

import ColumnStore
import Foundation
import PBIXKit

extension DocumentState {
    /// Lý do nút "Biến đổi dữ liệu" chưa dùng được, nil khi dùng được.
    var queryEditorBlocker: String? {
        if getDataBlocker != nil { return "File không có mô hình dữ liệu để biến đổi" }
        return queryEditorState == nil ? nil : "Query Editor đang mở"
    }

    /// Mở Query Editor. `loaded` rỗng: liệt kê truy vấn của bảng trong file; có `loaded` (từ Get Data): chỉ các truy vấn mới đó.
    func showQueryEditor(loaded: [LoadedTable] = []) {
        guard queryEditorState == nil, getDataBlocker == nil else { return }
        let editor = QueryEditorState()
        if loaded.isEmpty {
            if let metadata = workspace.metadata {
                editor.addQueries(from: metadata) { [workspace] name in
                    (try? workspace.table(name)).flatMap(TableDataEncoding.tableData(from:))
                }
            }
        } else {
            for table in loaded { editor.addQuery(from: table) }
        }
        queryEditorState = editor
    }

    /// Đóng Query Editor mà không áp dụng (người dùng đã xác nhận bỏ thay đổi nếu có).
    func closeQueryEditor() {
        queryEditorState = nil
    }

    /// "Close & Apply": áp dụng mọi truy vấn vào mô hình rồi đóng; bị từ chối thì giữ cửa sổ và ghi lý do vào `applyMessage`.
    func applyQueryEditor() {
        guard let editor = queryEditorState, !editor.isApplying else { return }
        editor.isApplying = true
        editor.applyMessage = nil
        Task { @MainActor in
            let reason = await editor.closeAndApply(to: modelEditor, existingTableNames: existingTableNames)
            editor.isApplying = false
            if let reason {
                editor.applyMessage = reason
            } else {
                if table == nil { table = workspace.userTables.first?.name }
                queryEditorState = nil
            }
        }
    }
}
