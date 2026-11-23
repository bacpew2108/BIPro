import Foundation
import PBIXKit

/// Một trang tạo trong phiên (thêm mới hoặc nhân bản), chưa có (hoặc mới có một phần) trong file đang mở.
struct NewPage: Equatable {
    let id: String
    var displayName: String
    /// Byte `page.json` sẽ ghi (mẫu Desktop, hoặc trang gốc đã đổi `name`, `displayName`, bỏ `pageBinding`).
    var pageJSON: Data
    /// Trang được nhân bản (nil: trang trống).
    let sourcePage: String?
    var width: Double
    var height: Double

    init(id: String, displayName: String, pageJSON: Data, sourcePage: String?, width: Double, height: Double) {
        self.id = id; self.displayName = displayName; self.pageJSON = pageJSON; self.sourcePage = sourcePage
        self.width = width; self.height = height
    }
}

/// Những gì một bookmark trong file nhắc tới về trang (đủ để biết xoá trang thì bookmark ra sao).
struct BookmarkInfo: Equatable {
    var name: String
    var activeSection: String?
    var sections: Set<String>

    init(name: String, activeSection: String?, sections: Set<String>) {
        self.name = name; self.activeSection = activeSection; self.sections = sections
    }

    init?(json: Data) {
        guard let value = try? JSONValue.parse(json), let name = value["name"]?.string else { return nil }
        self.name = name
        activeSection = value["explorationState"]?["activeSection"]?.string
        sections = Set((value["explorationState"]?["sections"]?.object ?? [:]).keys)
    }
}

/// Bookmark nào bị gỡ, bookmark nào chỉ bỏ mục của trang, khi xoá một tập trang.
struct BookmarkImpact: Equatable {
    var removed: Set<String> = []
    /// Tên bookmark → các mã trang bỏ khỏi `explorationState.sections`.
    var trimmed: [String: Set<String>] = [:]
}

/// Cấu trúc trang đang sửa (D5, `specs/005-d5-quan-ly-trang/data-model.md`): thứ tự tab, tên đổi, trang tạo trong phiên,
/// trang của file đã xoá, bookmark bị ảnh hưởng, trang mở khi lưu. Giá trị thuần: chụp và hoàn tác rẻ.
struct PageStructure: Equatable {
    /// Mã trang theo thứ tự tab (trang của file chưa xoá và trang tạo trong phiên).
    var order: [String]
    /// Mã trang của file → tên hiển thị mới (trang tạo trong phiên giữ tên trong `created`).
    var renamed: [String: String] = [:]
    var created: [String: NewPage] = [:]
    /// Mã trang của file đã xoá.
    var removed: Set<String> = []
    /// Bookmark gỡ khi xoá trang (để hoàn tác phục hồi và để báo người dùng).
    var removedBookmarks: Set<String> = []
    /// Tên bookmark → mã trang đã bỏ khỏi `sections`.
    var trimmedBookmarkSections: [String: Set<String>] = [:]
    /// Trang mở khi lưu (ghi vào `activePageName` khi cấu trúc đổi); nil: không đổi.
    var activePageID: String?

    init(order: [String]) { self.order = order }

    // MARK: Luật thuần

    /// Tên mặc định "Page N": N là số lớn nhất của các tên dạng `Page <số>` cộng một (VM-D5: Page 1, Page 2).
    static func nextDefaultName(existing names: [String]) -> String {
        var largest = 0
        for name in names where name.hasPrefix("Page ") {
            let digits = name.dropFirst(5)
            if !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber), let n = Int(digits) { largest = max(largest, n) }
        }
        return "Page \(largest + 1)"
    }

    static let maxNameLength = 100

    /// Tên đã cắt khoảng trắng, hoặc lý do từ chối.
    static func validatedName(_ raw: String) -> Result<String, ValidationError> {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .failure(ValidationError(biN("Tên trang không được để trống.", "The page name can't be empty."))) }
        if name.count > maxNameLength { return .failure(ValidationError(biN("Tên trang tối đa \(maxNameLength) ký tự.", "A page name can be up to \(maxNameLength) characters."))) }
        return .success(name)
    }

    struct ValidationError: Error, Equatable, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
        var contains: (String) -> Bool { { description.contains($0) } }
    }

    /// Trang thành trang đang mở sau khi xoá `id`: bên phải, hoặc bên trái nếu là trang cuối; nil nếu không còn trang nào.
    static func neighbour(afterRemoving id: String, in order: [String]) -> String? {
        guard let index = order.firstIndex(of: id), order.count > 1 else { return nil }
        return index + 1 < order.count ? order[index + 1] : order[index - 1]
    }

    /// Lý do không xoá được trang, hoặc nil: chỉ còn một trang. Nút điều hướng trỏ tới trang không chặn (VM-D8: Desktop
    /// xoá trang và để nguyên nút).
    static func removalRefusal(pageCount: Int) -> String? {
        pageCount <= 1 ? biN("Báo cáo phải còn ít nhất một trang.", "The report must keep at least one page.") : nil
    }

    /// Desktop không cho xoá trang hiển thị duy nhất (menu của tab chỉ có "Set as landing page", "Duplicate", "Rename"; VM-D13):
    /// trang cần xoá không ẩn và không còn trang hiển thị nào khác (trang ẩn như trang drillthrough không tính).
    static func removalRefusal(removingHidden: Bool, otherVisiblePages: Int) -> String? {
        !removingHidden && otherVisiblePages == 0
            ? biN("Đây là trang hiển thị duy nhất; Power BI Desktop không cho xoá (còn trang ẩn thì vẫn không).", "This is the only visible page; Power BI Desktop doesn't allow deleting it (even if hidden pages remain).") : nil
    }

    static func bookmarkImpact(removing ids: Set<String>, bookmarks: [BookmarkInfo]) -> BookmarkImpact {
        var impact = BookmarkImpact()
        guard !ids.isEmpty else { return impact }
        for bookmark in bookmarks {
            if let active = bookmark.activeSection, ids.contains(active) {
                impact.removed.insert(bookmark.name)
            } else if !ids.isDisjoint(with: bookmark.sections) {
                impact.trimmed[bookmark.name] = ids.intersection(bookmark.sections)
            }
        }
        return impact
    }

    // MARK: Bất biến và so sánh

    /// `order` không rỗng, không trùng; mỗi mã là của file (`fileIDs`, không thuộc `removed`) hoặc thuộc `created`,
    /// và không trang của file nào bị mất khỏi cả `order` lẫn `removed`.
    func isConsistent(fileIDs: Set<String>) -> Bool {
        guard !order.isEmpty, Set(order).count == order.count else { return false }
        guard order.allSatisfy({ !removed.contains($0) && (created[$0] != nil || fileIDs.contains($0)) }) else { return false }
        return fileIDs.allSatisfy { order.contains($0) || removed.contains($0) }
    }

    /// Cấu trúc có khác trạng thái của file (thứ tự `fileOrder`) không: thêm, bớt, đổi thứ tự hoặc đổi tên.
    func changesStructure(comparedTo fileOrder: [String]) -> Bool {
        order != fileOrder || !renamed.isEmpty || !created.isEmpty || !removed.isEmpty
    }
}
