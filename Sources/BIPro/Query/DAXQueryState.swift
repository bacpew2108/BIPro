import DAXEngine
import Foundation
import Observation

// MARK: - Trạng thái một tab truy vấn DAX

/// Trạng thái chạy của một tab truy vấn.
enum DAXQueryRunState: Equatable, Sendable {
    /// Chưa chạy lần nào.
    case idle
    /// Đang chạy.
    case running
    /// Lần chạy gần nhất thành công và có kết quả.
    case done
    /// Lần chạy gần nhất lỗi.
    case failed
    /// Lần chạy gần nhất bị huỷ.
    case cancelled
}

/// Trạng thái và kết quả của MỘT tab truy vấn DAX. `QueryRunner` gọi `beginRun()`, `finish(_:)`, `fail(_:)`
/// và `markCancelled()`; giao diện chỉ đọc.
@Observable
final class DAXQueryState: Identifiable {
    let id: UUID
    var title: String
    var text: String

    /// Trạng thái của lần chạy gần nhất.
    private(set) var status: DAXQueryRunState = .idle
    /// Kết quả của lần chạy thành công gần nhất. Nil khi chưa có lần chạy thành công.
    private(set) var result: QueryResult?
    /// Lỗi của lần chạy gần nhất. Nil khi lần chạy đó không lỗi.
    private(set) var error: DAXError?
    /// Văn bản đã chạy (cả tab hoặc vùng chọn). Vị trí lỗi tính trên văn bản này.
    private(set) var ranText = ""
    /// Offset UTF-16 của văn bản đã chạy trong tab (khác 0 khi chạy vùng chọn).
    private(set) var ranOffset = 0
    /// Lúc bắt đầu lần chạy gần nhất.
    private(set) var startedAt: Date?
    /// Bảng kết quả đang xem khi có nhiều EVALUATE.
    var resultIndex = 0

    init(id: UUID = UUID(), title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }

    /// Tạo từ một tab hiện có, giữ nguyên `id` để nhận diện trong `ForEach`.
    convenience init(tab: DAXQueryTab) {
        self.init(id: tab.id, title: tab.title, text: tab.text)
    }

    /// Chuyển sang trạng thái đang chạy. Xoá lỗi cũ; kết quả cũ được giữ cho đến khi có kết quả mới.
    func beginRun(text: String, offset: Int) {
        status = .running
        error = nil
        ranText = text
        ranOffset = offset
        startedAt = Date()
    }

    /// Ghi kết quả của lần chạy thành công.
    func finish(_ result: QueryResult) {
        self.result = result
        self.error = nil
        resultIndex = 0
        status = .done
    }

    /// Ghi lỗi của lần chạy thất bại. Xoá kết quả cũ để không hiển thị số liệu của lần chạy trước.
    func fail(_ error: DAXError) {
        self.result = nil
        self.error = error
        status = .failed
    }

    /// Ghi nhận lần chạy đã bị huỷ. Kết quả cũ bị xoá vì không còn khớp văn bản đang chạy.
    func markCancelled() {
        result = nil
        error = nil
        status = .cancelled
    }

    /// Đưa về trạng thái chưa chạy, xoá kết quả và lỗi.
    func reset() {
        status = .idle
        result = nil
        error = nil
    }
}
