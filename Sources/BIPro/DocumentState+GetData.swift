// Phase F (T043): Get Data từ Ribbon. Mở hộp thoại, nạp bảng đã chọn vào mô hình qua `ModelEditor` (một bước ⌘Z).
// "Chuyển đổi dữ liệu" (Query Editor) chưa có nên hộp thoại chưa hiện nút đó.

import ColumnStore
import Connectors
import Foundation
import PBIXKit

extension DocumentState {
    /// Lý do nút "Lấy dữ liệu" chưa dùng được, nil khi dùng được.
    var getDataBlocker: String? {
        workspace.runtime == nil ? biN("File không có mô hình dữ liệu để nạp bảng", "The file has no data model to load the table into") : nil
    }

    /// Tên mọi bảng của mô hình hiệu lực (kể cả bảng hệ thống), để tên bảng nạp mới không trùng.
    var existingTableNames: Set<String> {
        Set((workspace.metadata?.tables ?? []).map(\.name))
    }

    /// Mở hộp thoại Get Data. Có `kind` (nút "Excel" ở Ribbon) thì chọn tệp ngay và vào thẳng Navigator; huỷ chọn tệp thì không mở gì.
    func showGetData(kind: SourceKind? = nil, pickFile: (SourceKind) -> String? = GetDataFilePicker.pick,
                     credentials: CredentialVault = .shared) {
        guard getDataBlocker == nil, getDataState == nil else { return }
        let navigator = NavigatorState(credentials: credentials)
        if kind == .postgres {
            navigator.beginDatabase(.postgres)   // hộp kết nối máy chủ, không chọn tệp
            getDataState = navigator
        } else if let kind {
            guard let location = pickFile(kind) else { return }
            getDataState = navigator
            Task { await navigator.openSource(kind: kind, location: location) }
        } else {
            getDataState = navigator
        }
    }

    func closeGetData() {
        getDataState = nil
    }

    /// "Tải": đưa bảng vào mô hình. Trả lý do bị từ chối (hộp thoại ở lại) hoặc nil. Bảng đầu tiên thành bảng đang xem nếu chưa có.
    func loadFromGetData(_ tables: [LoadedTable]) -> String? {
        if let reason = TableLoader.apply(tables, to: modelEditor) { return reason }
        if table == nil { table = tables.first?.name }
        return nil
    }

    /// Cột số thực, tiền tệ, ngày của mô hình hiệu lực (định dạng ô và trục của visual). Gọi lại khi mô hình đổi (bảng mới có cột mới).
    static func applyColumnKinds(to layout: LayoutEditor, metadata: ModelMetadata?) {
        let columns = metadata?.columns ?? []
        func keys(_ type: ModelMetadata.DataType) -> Set<String> {
            Set(columns.filter { $0.dataType == type }.map { "\($0.tableName)[\($0.name)]" })
        }
        layout.decimalColumns = keys(.double)
        layout.currencyColumns = keys(.decimal)
        layout.dateColumns = keys(.dateTime)
        layout.modelColumns = columns
    }
}
