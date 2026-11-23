// Đợt tồn đọng sau Phase F, T028: Ribbon "Nhập dữ liệu" mở hộp "Tạo bảng"; "Tải" chạy M Enter Data bằng MEngine rồi nạp bảng qua đường
// T3 có sẵn (`TableLoader.apply`, một bước ⌘Z). Desktop không cần Refresh sau khi nạp (VM-F11a).

import ColumnStore
import Foundation
import MEngine

extension DocumentState {
    /// Lý do nút "Nhập dữ liệu" chưa dùng được, nil khi dùng được.
    var enterDataBlocker: String? { getDataBlocker }

    /// Mở hộp với tên mặc định chưa trùng ("Table", "Table (2)"…).
    func showEnterData() {
        guard enterDataBlocker == nil, enterData == nil else { return }
        enterData = EnterDataTable(name: EnterDataTable.defaultName(taken: existingTableNames))
    }

    func closeEnterData() { enterData = nil }

    /// "Tải": trả lý do bị từ chối (hộp ở lại) hoặc nil (hộp đóng). Tên bảng trùng thì thêm hậu tố như Get Data.
    func loadEnterData(_ table: EnterDataTable) async -> String? {
        let data: TableData
        do {
            data = try await EnterDataTable.evaluate(table.m)
        } catch let error as MError {
            return error.message
        } catch {
            return "\(error)"
        }
        let name = TableNaming.uniqueName(table.name, taken: existingTableNames)
        if let reason = loadFromGetData([LoadedTable(name: name, data: data, queryText: table.m)]) { return reason }
        enterData = nil
        return nil
    }
}

extension EnterDataTable {
    /// Bảng mà M Enter Data cho ra, tên cột bỏ U+FEFF đầu như tên cột Desktop ghi vào mô hình (VM-F11a; M vẫn giữ nguyên).
    static func evaluate(_ m: String) async throws -> TableData {
        guard case .table(let table) = try await MEvaluator(environment: MEnvironment()).evaluate(source: m, upTo: nil, rowLimit: nil) else {
            throw MError.expression(biN("M của bảng nhập tay không ra bảng", "The M for the entered table didn't produce a table"))
        }
        return try TableData(columns: table.columns.map { column in
            let name = column.name.hasPrefix("\u{FEFF}") ? String(column.name.dropFirst()) : column.name
            return TableColumn(name: name.isEmpty ? column.name : name, data: column.data, sourceType: column.sourceType)
        }, errorMask: table.errorMask)
    }
}
