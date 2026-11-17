import Foundation
import Observation

/// Phase E (R11): bản nháp công thức của một measure ở thanh công thức. Chỉ vào mô hình khi áp dụng.
@MainActor
@Observable
final class MeasureDraft {
    enum Mode: Equatable {
        case new(table: String)
        case edit(table: String, name: String)
        /// Phase F (T083): "Cột mới" (cột tính toán của `table`) và "Bảng mới" (bảng tính toán).
        case newColumn(table: String)
        case newTable
        /// Phase F (T116): sửa công thức cột tính toán `table[name]` và bảng tính toán `name` đã có.
        case editColumn(table: String, name: String)
        case editTable(name: String)

        var table: String {
            switch self {
            case .new(let table), .edit(let table, _), .newColumn(let table), .editColumn(let table, _), .editTable(let table): table
            case .newTable: ""
            }
        }

        /// Bản nháp chưa có trong mô hình (✗ đóng hẳn).
        var isNew: Bool {
            switch self {
            case .edit, .editColumn, .editTable: false
            default: true
            }
        }

        /// Bản nháp cột hoặc bảng tính toán (áp dụng qua `CalculatedEditor`).
        var isCalculated: Bool {
            switch self {
            case .newColumn, .newTable, .editColumn, .editTable: true
            default: false
            }
        }
    }

    var mode: Mode
    /// Văn bản thanh công thức, dạng `Tên = biểu thức`.
    var text: String
    /// Văn bản lúc mở hoặc áp dụng gần nhất: để biết có sửa dở không.
    private(set) var original: String
    /// Lỗi hoặc lý do bị từ chối (tiếng Việt); nil khi đang ổn.
    var message: String?
    /// Giá trị xem thử sau lần áp dụng thành công gần nhất.
    var preview: String?
    var isApplying = false

    init(mode: Mode, text: String) {
        self.mode = mode
        self.text = text
        original = text
    }

    var isChanged: Bool { text != original }

    /// Sau khi áp dụng thành công: coi văn bản hiện tại là bản gốc và chuyển sang chế độ sửa measure vừa lưu.
    func didApply(table: String, name: String) {
        mode = .edit(table: table, name: name)
        original = text
        message = nil
    }

    /// Sau khi sửa công thức cột/bảng tính toán thành công: văn bản hiện tại là bản gốc của `mode` mới (tên có thể đã đổi).
    func didApply(mode: Mode) {
        self.mode = mode
        original = text
        message = nil
    }

    /// Bỏ phần sửa dở, về văn bản lúc mở.
    func revert() {
        text = original
        message = nil
    }
}
