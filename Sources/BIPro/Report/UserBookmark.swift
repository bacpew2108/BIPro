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
    var visibility = VisibilityState()
}

extension ReportInteraction {
    /// Bookmark hiện có theo thứ tự: bookmark trong file (trừ cái đã xoá, bản người dùng cập nhật thế chỗ), rồi bookmark mới thêm.
    struct BookmarkRow: Identifiable, Hashable {
        let id: String
        let name: String
        let group: String?
        let isUser: Bool
        let suppressData: Bool
    }

    var bookmarkRows: [BookmarkRow] {
        var rows: [BookmarkRow] = []
        for bookmark in workspace.bookmarks where !deletedBookmarkIDs.contains(bookmark.id) {
            if let mine = userBookmarks.first(where: { $0.id == bookmark.id }) {
                rows.append(BookmarkRow(id: mine.id, name: mine.name, group: bookmark.group, isUser: true, suppressData: !mine.data))
            } else {
                rows.append(BookmarkRow(id: bookmark.id, name: renamedBookmarks[bookmark.id] ?? bookmark.displayName, group: bookmark.group,
                                        isUser: false, suppressData: bookmark.suppressData))
            }
        }
        let fileIDs = Set(workspace.bookmarks.map(\.id))
        for mine in userBookmarks where !fileIDs.contains(mine.id) {
            rows.append(BookmarkRow(id: mine.id, name: mine.name, group: nil, isUser: true, suppressData: !mine.data))
        }
        return rows
    }

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
        if let mine = userBookmarks.first(where: { $0.id == id }) { return apply(mine) }
        return applyBookmark(id: id)
    }

    func apply(_ bookmark: UserBookmark) -> String? {
        if bookmark.data {
            userFilters = bookmark.userFilters
            removedFilters = bookmark.removedFilters
            states = bookmark.states
            drillDepth = bookmark.drillDepth
            slicerExpansion = bookmark.slicerExpansion
        }
        if bookmark.display { visibility.restore(bookmark.visibility) }
        visibility.markActive(bookmark.id)
        return bookmark.currentPage ? bookmark.pageID : nil
    }

    private func capture(id: String, name: String, pageID: String?) -> UserBookmark {
        var bookmark = UserBookmark(id: id, name: name)
        bookmark.pageID = pageID
        bookmark.userFilters = userFilters
        bookmark.removedFilters = removedFilters
        bookmark.states = states
        bookmark.drillDepth = drillDepth
        bookmark.slicerExpansion = slicerExpansion
        bookmark.visibility = visibility
        return bookmark
    }
}
