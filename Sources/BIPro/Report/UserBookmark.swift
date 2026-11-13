// Bookmark do người dùng thêm trong phiên (Phase C). Power BI ghi bookmark vào file; BI Pro chưa ghi lại .pbix nên các bookmark này
// sống trong phiên làm việc. Tuỳ chọn Data, Display, Current page giống menu "..." của bookmark trong Power BI.
import DAXEngine
import Foundation

struct UserBookmark: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    /// Id bookmark trong file mà bản này thay thế (khi "Cập nhật" một bookmark của file).
    var group: String?
    var data = true
    var display = true
    var currentPage = true

    // Ảnh chụp trạng thái.
    var pageID: String?
    var userFilters: [UserFilterKey: UserFilter] = [:]
    var removedFilters: Set<UserFilterKey> = []
    var states: [String: FilterState] = [:]
    var drillDepth: [String: Int] = [:]
    var slicerExpansion: [String: [Value]] = [:]
    var matrixExpansion: [String: [[Value]]] = [:]
    var visibility = VisibilityState()
}

extension ReportInteraction {
    /// Bookmark hiện có theo thứ tự: bookmark trong file (trừ cái đã xoá, bản người dùng cập nhật thế chỗ), rồi bookmark mới thêm.
    struct BookmarkRow: Identifiable, Hashable {
        let id: String
        let name: String
        let group: String?
        /// Mã nhóm (`name` của mục nhóm trong `bookmarks.json`), nil khi ở ngoài nhóm.
        var groupID: String? = nil
        let isUser: Bool
        let suppressData: Bool
    }

    var bookmarkRows: [BookmarkRow] {
        var rows: [BookmarkRow] = []
        let doc = documentEdits.bookmarks
        let pageRemoved = removedBookmarksProvider?() ?? []
        /// Nhóm của bookmark sau khi áp nhóm tạo hoặc bỏ trong phiên (VM-D8 mục 5).
        func placed(_ row: BookmarkRow, fileGroup: (id: String, name: String)?) -> BookmarkRow {
            let group = doc.group(of: row.id, inFile: fileGroup)
            return BookmarkRow(id: row.id, name: row.name, group: group?.name, groupID: group?.id, isUser: row.isUser, suppressData: row.suppressData)
        }
        for bookmark in workspace.bookmarks where !deletedBookmarkIDs.contains(bookmark.id) && !doc.deleted.contains(bookmark.id) && !pageRemoved.contains(bookmark.id) {
            let fileGroup = bookmark.group.map { (id: bookmark.groupID ?? $0, name: $0) }
            if let mine = userBookmarks.first(where: { $0.id == bookmark.id }) {
                rows.append(placed(BookmarkRow(id: mine.id, name: mine.name, group: nil, isUser: true, suppressData: !mine.data), fileGroup: fileGroup))
            } else if let updated = doc.updated[bookmark.id] {
                rows.append(placed(BookmarkRow(id: bookmark.id, name: doc.renamed[bookmark.id] ?? updated.name, group: nil, isUser: true,
                                               suppressData: !updated.data), fileGroup: fileGroup))
            } else {
                rows.append(placed(BookmarkRow(id: bookmark.id, name: renamedBookmarks[bookmark.id] ?? doc.renamed[bookmark.id] ?? bookmark.displayName,
                                               group: nil, isUser: false, suppressData: bookmark.suppressData), fileGroup: fileGroup))
            }
        }
        let fileIDs = Set(workspace.bookmarks.map(\.id))
        for added in doc.added {
            rows.append(placed(BookmarkRow(id: added.id, name: added.name, group: nil, isUser: true, suppressData: !added.data), fileGroup: nil))
        }
        for mine in userBookmarks where !fileIDs.contains(mine.id) && !doc.deleted.contains(mine.id) {
            rows.append(placed(BookmarkRow(id: mine.id, name: mine.name, group: nil, isUser: true, suppressData: !mine.data), fileGroup: nil))
        }
        if let order = doc.order {
            let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            rows = rows.enumerated().sorted { (rank[$0.element.id] ?? Int.max, $0.offset) < (rank[$1.element.id] ?? Int.max, $1.offset) }.map(\.element)
        }
        return rows
    }

    /// Bookmark người dùng (thêm hoặc cập nhật) theo mã: lớp tài liệu trước, rồi lớp phiên.
    func userBookmark(id: String) -> UserBookmark? {
        let doc = documentEdits.bookmarks
        return doc.added.first { $0.id == id } ?? doc.updated[id] ?? userBookmarks.first { $0.id == id }
    }

    /// Tên của bookmark theo mã (hiện ở Bookmarks pane), nil nếu không có.
    func bookmarkName(id: String) -> String? { bookmarkRows.first { $0.id == id }?.name }

    /// Chụp trạng thái hiện tại thành bookmark mới. Trả id.
    @discardableResult
    func addBookmark(currentPageID: String?) -> String {
        let n = bookmarkRows.count + 1
        var name = "Bookmark \(n)"
        let used = Set(bookmarkRows.map(\.name))
        var k = n
        while used.contains(name) { k += 1; name = "Bookmark \(k)" }
        var bookmark = capture(id: "user-" + UUID().uuidString, name: name, pageID: currentPageID)
        bookmark.group = nil
        userBookmarks.append(bookmark)
        visibility.markActive(bookmark.id)
        return bookmark.id
    }

    /// Ghi lại trạng thái hiện tại vào bookmark đã có (giữ tên và tuỳ chọn).
    func updateBookmark(id: String, currentPageID: String?) {
        let existing = userBookmarks.first { $0.id == id }
        let name = existing?.name ?? renamedBookmarks[id] ?? workspace.bookmarks.first { $0.id == id }?.displayName ?? id
        var fresh = capture(id: id, name: name, pageID: currentPageID)
        if let existing { fresh.data = existing.data; fresh.display = existing.display; fresh.currentPage = existing.currentPage }
        if let i = userBookmarks.firstIndex(where: { $0.id == id }) { userBookmarks[i] = fresh } else { userBookmarks.append(fresh) }
        visibility.markActive(id)
    }

    func renameBookmark(id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let i = userBookmarks.firstIndex(where: { $0.id == id }) { userBookmarks[i].name = trimmed }
        if workspace.bookmarks.contains(where: { $0.id == id }) { renamedBookmarks[id] = trimmed }
    }

    func deleteBookmark(id: String) {
        userBookmarks.removeAll { $0.id == id }
        if workspace.bookmarks.contains(where: { $0.id == id }) { deletedBookmarkIDs.insert(id) }
        if visibility.activeBookmarkID == id { visibility.markActive(nil) }
    }

    /// Bật hoặc tắt Data, Display, Current page của bookmark do người dùng thêm.
    func setBookmarkOption(id: String, data: Bool? = nil, display: Bool? = nil, currentPage: Bool? = nil) {
        guard let i = userBookmarks.firstIndex(where: { $0.id == id }) else { return }
        if let data { userBookmarks[i].data = data }
        if let display { userBookmarks[i].display = display }
        if let currentPage { userBookmarks[i].currentPage = currentPage }
    }

    /// Áp bookmark theo id, cả bookmark người dùng thêm và bookmark trong file. Trả id trang cần chuyển tới.
    func applyAnyBookmark(id: String) -> String? {
        if let mine = userBookmark(id: id) { return apply(mine) }
        return applyBookmark(id: id)
    }

    func apply(_ bookmark: UserBookmark) -> String? {
        if bookmark.data {
            userFilters = bookmark.userFilters
            removedFilters = bookmark.removedFilters
            states = bookmark.states
            drillDepth = bookmark.drillDepth
            slicerExpansion = bookmark.slicerExpansion
            matrixExpansion = bookmark.matrixExpansion
        }
        if bookmark.display { visibility.restore(bookmark.visibility) }
        visibility.markActive(bookmark.id)
        return bookmark.currentPage ? bookmark.pageID : nil
    }

    /// Chụp trạng thái hiện tại (trang, bộ lọc hiệu lực, slicer, drill, ẩn/hiện) thành bookmark chưa lưu vào đâu cả.
    func captureBookmark(id: String, name: String, pageID: String?) -> UserBookmark { capture(id: id, name: name, pageID: pageID) }

    /// Tên mặc định "Bookmark N" không trùng tên nào hiện có.
    func nextBookmarkName() -> String {
        let used = Set(bookmarkRows.map(\.name))
        var k = bookmarkRows.count + 1
        while used.contains("Bookmark \(k)") { k += 1 }
        return "Bookmark \(k)"
    }

    private func capture(id: String, name: String, pageID: String?) -> UserBookmark {
        var bookmark = UserBookmark(id: id, name: name)
        bookmark.pageID = pageID
        bookmark.userFilters = effectiveUserFilters
        bookmark.removedFilters = effectiveRemovedFilters
        bookmark.states = states
        bookmark.drillDepth = drillDepth
        bookmark.slicerExpansion = slicerExpansion
        bookmark.matrixExpansion = matrixExpansion
        bookmark.visibility = visibility
        return bookmark
    }
}
