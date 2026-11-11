// D6: thay đổi cấp tài liệu của bookmark và bộ lọc (specs/007-d6-bookmark-filter/data-model.md).
// Giá trị thuần nằm trong ảnh chụp hoàn tác của `LayoutEditor`; lưu so với file trên đĩa (research R4).
import Foundation
import PBIXKit

/// Một thay đổi thẻ lọc so với file: đặt (thay hoặc thêm) hoặc bỏ.
enum FilterChange: Equatable {
    case set(UserFilter)
    /// `name`: tên thẻ trong file để bỏ (thẻ của file: mã của nó; thẻ thêm trong phiên: tên suy ra từ cột); nil khi không có thẻ nào để bỏ.
    case remove(name: String?)
}

/// Bookmark thay đổi so với file: thêm trong phiên, cập nhật, đổi tên, xoá, thứ tự mong muốn.
struct BookmarkEdits: Equatable {
    /// Bookmark mới (chưa có trong file), theo thứ tự thêm.
    var added: [UserBookmark] = []
    /// Mã bookmark của file → bản chụp mới (Cập nhật).
    var updated: [String: UserBookmark] = [:]
    var renamed: [String: String] = [:]
    var deleted: Set<String> = []
    /// Thứ tự hiển thị mong muốn (mã); nil = thứ tự trong file rồi bookmark mới.
    var order: [String]?

    var isEmpty: Bool { added.isEmpty && updated.isEmpty && renamed.isEmpty && deleted.isEmpty && order == nil }
}

struct ReportEdits: Equatable {
    var bookmarks = BookmarkEdits()
    var filters: [UserFilterKey: FilterChange] = [:]

    var isEmpty: Bool { bookmarks.isEmpty && filters.isEmpty }

    /// Bộ lọc người dùng đã đặt ở lớp tài liệu.
    var filterSets: [UserFilterKey: UserFilter] {
        var out: [UserFilterKey: UserFilter] = [:]
        for (key, change) in filters { if case .set(let filter) = change { out[key] = filter } }
        return out
    }

    /// Thẻ của file đã bỏ ở lớp tài liệu (kể cả dấu bỏ của thẻ người dùng thêm).
    var filterRemovals: Set<UserFilterKey> {
        var out = Set<UserFilterKey>()
        for (key, change) in filters { if case .remove = change { out.insert(key) } }
        return out
    }

    /// Bộ lọc hiệu lực = lớp tài liệu rồi lớp phiên (phiên thắng): áp bookmark hoặc trạng thái xem đè lên thay đổi đã đặt.
    static func effectiveFilters(edits: ReportEdits, session: [UserFilterKey: UserFilter]) -> [UserFilterKey: UserFilter] {
        edits.filterSets.merging(session) { _, mine in mine }
    }

    static func effectiveRemovals(edits: ReportEdits, session: Set<UserFilterKey>) -> Set<UserFilterKey> {
        edits.filterRemovals.union(session)
    }
}

/// Kết quả xuất trạng thái phiên sang dạng ghi vào file.
enum ExportResult<Value> {
    case writable(Value)
    /// Không ghi được vào file (dạng chưa quan sát, hoặc thiếu thông tin) kèm lý do cho người dùng.
    case sessionOnly(String)

    var value: Value? { if case .writable(let value) = self { value } else { nil } }
    var reason: String? { if case .sessionOnly(let reason) = self { reason } else { nil } }
}
