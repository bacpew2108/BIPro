// D6: bookmark và bộ lọc sửa được ở chế độ Sửa, ghi vào file khi lưu (specs/007-d6-bookmark-filter).
import Foundation
import PBIXKit

extension DocumentState {
    /// Lý do chưa sửa bookmark hoặc bộ lọc được (chế độ Xem, báo cáo định dạng cũ), hoặc nil. Xem chỉ để xem: bấm bookmark để áp vẫn được.
    var reportEditingBlocker: String? {
        if mode != .report { return "Chỉ sửa bookmark và bộ lọc được ở chế độ Báo cáo." }
        if !canEditLayout { return "Báo cáo định dạng cũ (Report/Layout) chưa sửa được." }
        if !editMode { return "Bật chế độ Sửa (⌘E) để sửa bookmark và bộ lọc." }
        return nil
    }

    /// Nối `ReportInteraction` với bộ sửa: gọi một lần sau khi tạo `DocumentState`.
    func wireReportEditing() {
        let layout = layout
        interaction.editing = ReportEditing(
            blocker: { [weak self] in self?.reportEditingBlocker },
            edits: { layout.reportEdits },
            setFilter: { filter, key in layout.setFilter(filter, for: key) },
            removeFilter: { key, column in layout.removeFilter(key, column: column) },
            resetFilter: { key in layout.resetFilter(key) })
    }

    /// Thêm bookmark từ trạng thái hiện tại. Trả lý do từ chối hoặc nil.
    @discardableResult
    func addBookmark() -> String? {
        if let blocker = reportEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        let id = layout.makeBookmarkID(existing: Set(workspace.bookmarks.map(\.id)))
        let bookmark = interaction.captureBookmark(id: id, name: interaction.nextBookmarkName(), pageID: pageID)
        layout.addBookmark(bookmark)
        interaction.visibility.markActive(id)
        layout.noteFieldRefusal(nil)
        return nil
    }

    @discardableResult
    func updateBookmark(id: String) -> String? {
        if let blocker = reportEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        guard let name = interaction.bookmarkName(id: id) else { return nil }
        var fresh = interaction.captureBookmark(id: id, name: name, pageID: pageID)
        if let existing = interaction.userBookmark(id: id) { fresh.data = existing.data; fresh.display = existing.display; fresh.currentPage = existing.currentPage }
        layout.updateBookmark(fresh)
        interaction.visibility.markActive(id)
        return nil
    }

    @discardableResult
    func renameBookmark(id: String, to name: String) -> String? {
        if let blocker = reportEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        let others = interaction.bookmarkRows.filter { $0.id != id }.map(\.name)
        let reason = layout.renameBookmark(id: id, to: name, others: others)
        layout.noteFieldRefusal(reason)
        return reason
    }

    @discardableResult
    func deleteBookmark(id: String) -> String? {
        if let blocker = reportEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        layout.deleteBookmark(id: id)
        if interaction.visibility.activeBookmarkID == id { interaction.visibility.markActive(nil) }
        return nil
    }

    /// Chuyển bookmark lên (`-1`) hoặc xuống (`+1`) một vị trí.
    @discardableResult
    func moveBookmark(id: String, by delta: Int) -> String? {
        if let blocker = reportEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        var ids = interaction.bookmarkRows.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + delta) else { return nil }
        ids.swapAt(index, index + delta)
        layout.moveBookmarks(order: ids)
        return nil
    }

    /// Gom các bookmark vào một nhóm mới "Group N" (lệnh Group của Bookmarks pane, VM-D8 mục 5). Trả lý do từ chối hoặc nil.
    @discardableResult
    func groupBookmarks(_ ids: [String]) -> String? {
        if let blocker = reportEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        let rows = interaction.bookmarkRows
        // Chỉ bookmark còn hiện và chưa nằm trong nhóm (mã cũ trong vùng chọn, bookmark đã xoá, bị bỏ).
        let chosen = ids.filter { id in rows.first { $0.id == id }.map { $0.groupID == nil } ?? false }
        guard chosen.count >= 2 else {
            let reason = "Nhóm bookmark cần chọn từ 2 bookmark chưa nằm trong nhóm."
            layout.noteFieldRefusal(reason)
            return reason
        }
        // Thứ tự trong nhóm theo thứ tự đang hiện.
        let ordered = rows.map(\.id).filter(chosen.contains)
        let used = Set(rows.compactMap(\.group))
        var n = 1
        while used.contains("Group \(n)") { n += 1 }
        let id = PBIRLayoutPatch.makeVisualName(avoiding: Set(workspace.bookmarks.map(\.id)).union(rows.compactMap(\.groupID)))
        guard layout.groupBookmarks(ordered, id: id, name: "Group \(n)") else {
            let reason = "Không nhóm được các bookmark này."
            layout.noteFieldRefusal(reason)
            return reason
        }
        layout.noteFieldRefusal(nil)
        return nil
    }

    /// Bỏ nhóm bookmark: các bookmark của nhóm về cấp gốc.
    @discardableResult
    func ungroupBookmarks(groupID: String) -> String? {
        if let blocker = reportEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        let rows = interaction.bookmarkRows.filter { $0.groupID == groupID }
        guard let first = rows.first, let name = first.group else { return nil }
        layout.ungroupBookmarks(BookmarkGroupEdit(id: groupID, name: name, children: rows.map(\.id)))
        return nil
    }

    @discardableResult
    func setBookmarkOption(id: String, data: Bool? = nil, display: Bool? = nil, currentPage: Bool? = nil) -> String? {
        if let blocker = reportEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        layout.setBookmarkOption(id: id, data: data, display: display, currentPage: currentPage)
        return nil
    }

    /// Lý do bookmark chưa lưu vào file được (nil nếu ghi được hoặc không phải bookmark người dùng).
    func bookmarkSaveBlocker(id: String) -> String? {
        guard let mine = interaction.userBookmark(id: id) else { return nil }
        let visuals = mine.pageID.flatMap { pageID in pages.contains { $0.id == pageID } ? layout.visuals(of: pageID) : nil }
        return BookmarkExport.spec(for: mine, name: id, displayName: mine.name, pageVisuals: visuals).reason
    }
}
