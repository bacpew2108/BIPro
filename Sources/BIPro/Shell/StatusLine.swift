import Foundation
import PBIXKit

/// Nội dung dòng trạng thái bên trái thanh trạng thái toàn cửa sổ (`UIMetrics.statusBar` = 23 pt).
/// Chuỗi EN bám sát Power BI Desktop (`o_now.png`, `t_colsel.png`, `v_dax_1.png`, `v_tmdl_2.png`).
enum StatusLine {
    @MainActor
    static func text(
        mode: WorkspaceMode,
        state: DocumentState,
        language: ResolvedLanguage? = nil
    ) -> String {
        let isEN = (language ?? AppPreferences.shared.effectiveLanguage) == .en
        switch mode {
        case .report:
            let pages = state.pages
            guard !pages.isEmpty else {
                return isEN ? "No pages" : "Không có trang"
            }
            let index = pages.firstIndex(where: { $0.id == state.pageID }) ?? 0
            return isEN ? "Page \(index + 1) of \(pages.count)" : "Trang \(index + 1) / \(pages.count)"

        case .table:
            guard let table = state.table else {
                return isEN ? "No table selected" : "Chưa chọn bảng"
            }
            let rows = state.workspace.rowCount(table)
            let rowUnit = isEN ? (rows == 1 ? "row" : "rows") : "dòng"
            var result = isEN
                ? "Table: \(table) (\(rows.formatted()) \(rowUnit))"
                : biN("Bảng: \(table) (\(rows.formatted()) \(rowUnit))", "Table: \(table) (\(rows.formatted()) \(rowUnit))")
            if let col = state.column {
                let distinct = distinctCount(table: table, column: col, workspace: state.workspace)
                let distUnit = isEN ? (distinct == 1 ? "distinct value" : "distinct values") : "giá trị phân biệt"
                result += isEN
                    ? " Column: \(col) (\(distinct.formatted()) \(distUnit))"
                    : biN(" Cột: \(col) (\(distinct.formatted()) \(distUnit))", " Column: \(col) (\(distinct.formatted()) \(distUnit))")
            }
            return result

        case .model:
            let tableCount = state.workspace.userTables.count
            let relCount = state.workspace.metadata?.relationships.count ?? 0
            let tableWord = tableCount == 1 ? "table" : "tables"
            let relWord = relCount == 1 ? "relationship" : "relationships"
            return isEN
                ? "\(tableCount) \(tableWord) · \(relCount) \(relWord)"
                : biN("\(tableCount) bảng · \(relCount) quan hệ", "\(tableCount) \(tableWord) · \(relCount) \(relWord)")

        case .daxQuery:
            let total = max(1, state.daxQueries.count)
            let index = min(total, max(1, state.daxSelection + 1))
            return isEN ? "Query \(index) of \(total)" : "Truy vấn \(index) / \(total)"

        case .tmdl:
            let docs = state.workspace.tmdlDocuments
            let total = max(1, docs.count)
            let index = (docs.firstIndex(where: { $0.path == state.tmdlPath }) ?? 0) + 1
            return isEN ? "Script \(index) of \(total)" : "Kịch bản \(index) / \(total)"
        }
    }

    @MainActor
    private static func distinctCount(table: String, column: String, workspace: Workspace) -> Int {
        if let storage = workspace.metadata?.storage(table: table, column: column), storage.cardinality > 0 {
            return storage.cardinality
        }
        if let overlay = workspace.runtime?.overlay(named: table),
           let colData = overlay.columns.first(where: { $0.name == column }) {
            let dictCount = colData.data.dictionaryCount
            if dictCount > 0 { return dictCount }
        }
        return workspace.rowCount(table)
    }
}
