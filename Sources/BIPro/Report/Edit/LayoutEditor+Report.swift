// D6: thao tác bookmark và bộ lọc ở lớp tài liệu, và phần ghi vào file (contracts/bookmark-editing.md, filter-editing.md,
// bookmark-filter-save.md). Mỗi thao tác là đúng một bước hoàn tác (`commitReport`).
import Foundation
import PBIXKit

extension LayoutEditor {
    nonisolated static let reportJSONPath = "Report/definition/report.json"
    nonisolated static func bookmarkPathForTests(_ name: String) -> String { "\(bookmarksFolder)\(name).bookmark.json" }

    // MARK: Bookmark

    /// Mã bookmark mới: 20 hex không trùng mã nào trong file, trong phiên hay đã xoá.
    func makeBookmarkID(existing: Set<String>) -> String {
        PBIRLayoutPatch.makeVisualName(avoiding: existing.union(reportEdits.bookmarks.added.map(\.id)).union(reportEdits.bookmarks.deleted))
    }

    @discardableResult
    func addBookmark(_ bookmark: UserBookmark) -> Bool {
        commitReport { edits in
            edits.bookmarks.added.append(bookmark)
            if edits.bookmarks.order != nil { edits.bookmarks.order?.append(bookmark.id) }
        }
    }

    /// Cập nhật theo trạng thái hiện tại (`fresh` đã chụp lại, giữ mã, tên và tuỳ chọn do người gọi đặt).
    @discardableResult
    func updateBookmark(_ fresh: UserBookmark) -> Bool {
        commitReport { edits in
            if let index = edits.bookmarks.added.firstIndex(where: { $0.id == fresh.id }) {
                edits.bookmarks.added[index] = fresh
            } else {
                edits.bookmarks.updated[fresh.id] = fresh
            }
        }
    }

    /// Đổi tên; trả lý do từ chối (nil nếu được). `others`: tên các bookmark khác để chặn trùng.
    func renameBookmark(id: String, to proposed: String, others: [String]) -> String? {
        switch BookmarkExport.validateName(proposed, others: others) {
        case .sessionOnly(let reason): return reason
        case .writable(let name):
            commitReport { edits in
                if let index = edits.bookmarks.added.firstIndex(where: { $0.id == id }) {
                    edits.bookmarks.added[index].name = name
                } else {
                    edits.bookmarks.renamed[id] = name
                    if edits.bookmarks.updated[id] != nil { edits.bookmarks.updated[id]?.name = name }
                }
            }
            return nil
        }
    }

    @discardableResult
    func deleteBookmark(id: String) -> Bool {
        commitReport { edits in
            edits.bookmarks.added.removeAll { $0.id == id }
            edits.bookmarks.updated[id] = nil
            edits.bookmarks.renamed[id] = nil
            // Dấu xoá luôn ghi: bookmark thêm trong phiên có thể đã nằm trong file từ lần lưu trước.
            edits.bookmarks.deleted.insert(id)
            edits.bookmarks.order?.removeAll { $0 == id }
            // Nhóm tạo trong phiên mất thành viên này; nhóm hết thành viên thì không còn.
            for index in edits.bookmarks.groupsAdded.indices { edits.bookmarks.groupsAdded[index].children.removeAll { $0 == id } }
            edits.bookmarks.groupsAdded.removeAll { $0.children.isEmpty }
        }
    }

    /// Gom các bookmark `ids` (đang ở ngoài nhóm tạo trong phiên) vào nhóm mới `id` tên `name`, như lệnh Group ở Bookmarks
    /// pane của Desktop (VM-D8 mục 5). Cần từ 2 bookmark. Người gọi lo việc bookmark chưa nằm trong nhóm của file.
    @discardableResult
    func groupBookmarks(_ ids: [String], id: String, name: String) -> Bool {
        var seen = Set<String>()
        let members = ids.filter { seen.insert($0).inserted }
        let grouped = Set(reportEdits.bookmarks.groupsAdded.flatMap(\.children))
        guard members.count >= 2, grouped.isDisjoint(with: members), !reportEdits.bookmarks.groupsAdded.contains(where: { $0.id == id }) else { return false }
        return commitReport { $0.bookmarks.groupsAdded.append(BookmarkGroupEdit(id: id, name: name, children: members)) }
    }

    /// Bỏ nhóm: các bookmark của nhóm về cấp gốc. Dấu bỏ luôn ghi (nhóm tạo trong phiên có thể đã nằm trong file từ lần lưu trước).
    @discardableResult
    func ungroupBookmarks(_ group: BookmarkGroupEdit) -> Bool {
        commitReport { edits in
            edits.bookmarks.groupsAdded.removeAll { $0.id == group.id }
            if !edits.bookmarks.groupsRemoved.contains(where: { $0.id == group.id }) { edits.bookmarks.groupsRemoved.append(group) }
        }
    }

    /// Thứ tự hiển thị mong muốn của các bookmark (mã).
    @discardableResult
    func moveBookmarks(order: [String]) -> Bool {
        commitReport { $0.bookmarks.order = order }
    }

    /// Bật/tắt Data, Display, Current page của bookmark thêm hoặc cập nhật trong phiên.
    @discardableResult
    func setBookmarkOption(id: String, data: Bool? = nil, display: Bool? = nil, currentPage: Bool? = nil) -> Bool {
        commitReport { edits in
            func apply(_ bookmark: inout UserBookmark) {
                if let data { bookmark.data = data }
                if let display { bookmark.display = display }
                if let currentPage { bookmark.currentPage = currentPage }
            }
            if let index = edits.bookmarks.added.firstIndex(where: { $0.id == id }) { apply(&edits.bookmarks.added[index]) }
            else if edits.bookmarks.updated[id] != nil { apply(&edits.bookmarks.updated[id]!) }
        }
    }

    // MARK: Bộ lọc

    /// Đặt một thẻ lọc; `coalesce`: chọn giá trị liên tiếp trong cùng thẻ gộp một bước.
    @discardableResult
    func setFilter(_ filter: UserFilter, for key: UserFilterKey, coalesce: Bool = true) -> Bool {
        commitReport(coalesceKey: coalesce ? "filter|\(key.level.rawValue)|\(key.scope)|\(key.filterID)" : nil) {
            $0.filters[key] = .set(filter)
        }
    }

    /// Bỏ thẻ: dấu bỏ luôn ghi (thẻ thêm trong phiên có thể đã nằm trong file từ lần lưu trước).
    @discardableResult
    func removeFilter(_ key: UserFilterKey, column: QueryColumn? = nil) -> Bool {
        let isGenerated = key.filterID.hasPrefix("added-") || key.filterID.hasPrefix("implicit-")
        let name = isGenerated ? column.map { FilterExport.cardName(for: key, column: $0) } : key.filterID
        return commitReport { $0.filters[key] = .remove(name: name) }
    }

    /// Bỏ thay đổi của một thẻ (về bản trong file): chỉ có nghĩa với thẻ của file.
    @discardableResult
    func resetFilter(_ key: UserFilterKey) -> Bool {
        commitReport { $0.filters[key] = nil }
    }

    // MARK: Ghi vào file

    /// Thêm thay đổi bookmark và bộ lọc vào `changes`, so với bytes trên đĩa (`archive`) và với `changes` đã dựng cho phần khác (D1, D5).
    /// Trả các ghi chú (phần bị bỏ qua vì chưa lưu được).
    func addReportChanges(to changes: inout PBIXChanges, archive: ZipArchive) throws -> [String] {
        var notes: [String] = []
        try addBookmarkChanges(to: &changes, archive: archive, notes: &notes)
        try addFilterChanges(to: &changes, archive: archive, notes: &notes)
        try addResourceChanges(to: &changes, archive: archive)
        return notes
    }

    func current(_ path: String, in changes: PBIXChanges, archive: ZipArchive) -> Data? {
        if changes.removedParts.contains(path) { return nil }
        return changes.reportParts[path] ?? changes.addedParts[path] ?? (archive.entry(path) != nil ? try? archive.read(path) : nil)
    }

    func store(_ data: Data, at path: String, changes: inout PBIXChanges, archive: ZipArchive) {
        if archive.entry(path) != nil {
            if (try? archive.read(path)) == data { changes.reportParts[path] = nil } else { changes.reportParts[path] = data }
        } else {
            changes.addedParts[path] = data
        }
    }

    private func addBookmarkChanges(to changes: inout PBIXChanges, archive: ZipArchive, notes: inout [String]) throws {
        let edits = reportEdits.bookmarks
        let saved = savedEdits.bookmarks
        // Đã ghi ở lần lưu trước mà nay không còn trong thay đổi (hoàn tác sau khi lưu): đưa về như lúc mở.
        let savedIDs = Set(saved.added.map(\.id)).union(saved.updated.keys).union(saved.renamed.keys).union(saved.deleted)
        let currentIDs = Set(edits.added.map(\.id)).union(edits.updated.keys).union(edits.renamed.keys).union(edits.deleted)
        let reverted = savedIDs.subtracting(currentIDs)
        let groupsChanged = saved.groupsAdded != edits.groupsAdded || saved.groupsRemoved != edits.groupsRemoved
        guard !edits.isEmpty || !reverted.isEmpty || groupsChanged else { return }
        let alive = Set(structure.order)
        let folder = Self.bookmarksFolder
        // Bookmark có trong file: mã → đường dẫn.
        var onDisk: [String: String] = [:]
        for entry in archive.entries where entry.path.hasPrefix(folder) && entry.path.hasSuffix(".bookmark.json") {
            if let name = BookmarkInfo(json: try archive.read(entry))?.name { onDisk[name] = entry.path }
        }
        func path(for id: String) -> String { onDisk[id] ?? "\(folder)\(id).bookmark.json" }
        var index = current(Self.bookmarksJSONPath, in: changes, archive: archive)
        var skipped = 0

        // Hoàn tác sau khi lưu: bookmark của file về bản lúc mở; bookmark thêm trong phiên bị bỏ.
        let originals = Dictionary(bookmarkSource().map { ($0.name, $0.json) }, uniquingKeysWith: { a, _ in a })
        var revertedRemovals = Set<String>()
        for id in reverted.sorted() {
            if let original = originals[id] {
                let target = path(for: id)
                changes.removedParts.remove(target)
                store(original, at: target, changes: &changes, archive: archive)
                if !(index.map { PBIRBookmarkPatch.itemNames(in: $0).contains(id) } ?? false) { index = try PBIRBookmarkPatch.addingItem(id, to: index) }
            } else if let existing = onDisk[id], !changes.removedParts.contains(existing) {
                changes.reportParts[existing] = nil
                changes.removedParts.insert(existing)
                revertedRemovals.insert(id)
            }
        }
        if !revertedRemovals.isEmpty, let data = index { index = try PBIRPagePatch.bookmarkItemsRemoving(revertedRemovals, from: data) }

        // Xoá.
        var removedItems = Set<String>()
        for id in edits.deleted.sorted() {
            if let existing = onDisk[id], !changes.removedParts.contains(existing) {
                changes.reportParts[existing] = nil
                changes.removedParts.insert(existing)
                removedItems.insert(id)
            }
        }
        if !removedItems.isEmpty, let data = index { index = try PBIRPagePatch.bookmarkItemsRemoving(removedItems, from: data) }

        // Cập nhật, thêm.
        var writes: [(id: String, bookmark: UserBookmark, displayName: String)] = []
        for (id, fresh) in edits.updated.sorted(by: { $0.key < $1.key }) where !edits.deleted.contains(id) {
            if onDisk[id] == nil {
                notes.append(biN("Bookmark \"\(edits.renamed[id] ?? fresh.name)\": không có trong file nên chưa cập nhật được.", "Bookmark \"\(edits.renamed[id] ?? fresh.name)\": it isn't in the file, so it can't be updated yet."))
                continue
            }
            writes.append((id, fresh, edits.renamed[id] ?? fresh.name))
        }
        var writtenIDs = Set<String>()
        for added in edits.added where !edits.deleted.contains(added.id) { writes.append((added.id, added, added.name)) }
        for write in writes {
            let target = path(for: write.id)
            guard !changes.removedParts.contains(target) else { continue }
            let pageVisuals: [ReportVisual]? = write.bookmark.pageID.flatMap { alive.contains($0) ? self.visuals(of: $0) : nil }
            switch BookmarkExport.spec(for: write.bookmark, name: write.id, displayName: write.displayName, pageVisuals: pageVisuals) {
            case .writable(let spec):
                writtenIDs.insert(write.id)
                store(PBIRBookmarkPatch.newBookmarkJSON(spec), at: target, changes: &changes, archive: archive)
                if onDisk[write.id] == nil, !(index.map { PBIRBookmarkPatch.itemNames(in: $0).contains(write.id) } ?? false) {
                    index = try PBIRBookmarkPatch.addingItem(write.id, to: index)
                }
            case .sessionOnly(let reason):
                skipped += 1
                notes.append("Bookmark \"\(write.displayName)\": \(reason)")
            }
        }

        // Đổi tên bookmark của file chưa cập nhật.
        for (id, name) in edits.renamed.sorted(by: { $0.key < $1.key }) where !writtenIDs.contains(id) && !edits.deleted.contains(id) {
            guard let existing = onDisk[id], let data = current(existing, in: changes, archive: archive) else { continue }
            if PBIRBookmarkPatch.identity(of: data)?.displayName != name {
                store(try PBIRBookmarkPatch.renamingDisplayName(name, in: data), at: existing, changes: &changes, archive: archive)
            }
        }

        // Nhóm bookmark (VM-D8 mục 5), so với nhóm đang có trong `bookmarks.json`.
        if var data = index {
            func has(_ id: String) -> Bool { PBIRBookmarkPatch.groups(in: data).contains { $0.id == id } }
            // Hoàn tác sau khi lưu: nhóm đã ghi mà nay không còn trong thay đổi thì bỏ.
            for group in saved.groupsAdded where !edits.groupsAdded.contains(where: { $0.id == group.id }) {
                data = try PBIRBookmarkPatch.ungroupingItem(group.id, in: data)
            }
            for group in edits.groupsRemoved { data = try PBIRBookmarkPatch.ungroupingItem(group.id, in: data) }
            // Hoàn tác việc bỏ nhóm sau khi lưu: dựng lại nhóm với thành viên lúc bỏ.
            for group in saved.groupsRemoved where !edits.groupsRemoved.contains(where: { $0.id == group.id }) && !has(group.id) {
                data = try PBIRBookmarkPatch.groupingItems(group.children, id: group.id, displayName: group.name, in: data)
            }
            for group in edits.groupsAdded where !has(group.id) {
                let before = data
                data = try PBIRBookmarkPatch.groupingItems(group.children, id: group.id, displayName: group.name, in: data)
                if data == before { notes.append(biN("Nhóm bookmark \"\(group.name)\": các bookmark trong nhóm chưa lưu được vào file nên chưa ghi nhóm.", "Bookmark group \"\(group.name)\": its bookmarks can't be saved to the file yet, so the group wasn't written.")) }
            }
            index = data
        }

        // Thứ tự.
        if let order = edits.order, let data = index { index = try PBIRBookmarkPatch.reorderingItems(order, in: data) }

        // bookmarks.json: bỏ khi hết bookmark, thêm hoặc sửa khi có.
        let indexPath = Self.bookmarksJSONPath
        if let data = index, PBIRBookmarkPatch.itemNames(in: data).isEmpty, archive.entry(indexPath) != nil {
            changes.reportParts[indexPath] = nil
            changes.removedParts.insert(indexPath)
        } else if let data = index, !PBIRBookmarkPatch.itemNames(in: data).isEmpty {
            changes.removedParts.remove(indexPath)
            store(data, at: indexPath, changes: &changes, archive: archive)
        }
    }

    nonisolated private static func sortKey(_ key: UserFilterKey) -> String { [key.level.rawValue, key.scope, key.filterID].joined(separator: "|") }

    private func pagePath(forVisual id: String) -> String? {
        structure.order.first { page in visuals(of: page).contains { $0.id == id } }
    }

    private func addFilterChanges(to changes: inout PBIXChanges, archive: ZipArchive, notes: inout [String]) throws {
        // Thẻ đã ghi ở lần lưu trước mà nay không còn thay đổi (hoàn tác sau khi lưu).
        var revertOps: [(key: UserFilterKey, op: PBIRFilterPatch.Change)] = []
        for (key, change) in savedEdits.filters where reportEdits.filters[key] == nil {
            let generated = key.filterID.hasPrefix("added-") || key.filterID.hasPrefix("implicit-")
            if generated, case .set(let filter) = change {
                revertOps.append((key, .remove(name: FilterExport.cardName(for: key, column: filter.column))))
            } else if !generated {
                notes.append(biN("Bộ lọc \(key.filterID): hoàn tác sau khi lưu chưa khôi phục được thẻ có sẵn trong file; mở lại file gốc để đưa về như cũ.", "Filter \(key.filterID): undoing after saving can't restore a card that was already in the file; reopen the original file to get back to the original."))
            }
        }
        guard !reportEdits.filters.isEmpty || !revertOps.isEmpty else { return }
        // Nhóm theo part.
        var groups: [String: (level: PBIRFilterPatch.Level, changes: [PBIRFilterPatch.Change])] = [:]
        var order: [String] = []
        for (key, op) in revertOps {
            let path: String, level: PBIRFilterPatch.Level
            switch key.level {
            case .report: path = Self.reportJSONPath; level = .report
            case .page:
                guard structure.order.contains(key.scope) else { continue }
                path = Self.pagePath(key.scope); level = .page
            case .visual:
                guard let page = pagePath(forVisual: key.scope) else { continue }
                path = Self.visualPath(page: page, id: key.scope); level = .visual
            }
            if groups[path] == nil { order.append(path) }
            groups[path, default: (level, [])].changes.append(op)
        }
        for (key, change) in reportEdits.filters.sorted(by: { Self.sortKey($0.key) < Self.sortKey($1.key) }) {
            let path: String, level: PBIRFilterPatch.Level
            switch key.level {
            case .report: path = Self.reportJSONPath; level = .report
            case .page:
                guard structure.order.contains(key.scope) else { continue }
                path = Self.pagePath(key.scope); level = .page
            case .visual:
                guard let page = pagePath(forVisual: key.scope) else { continue }
                path = Self.visualPath(page: page, id: key.scope); level = .visual
            }
            var op: PBIRFilterPatch.Change?
            switch change {
            case .remove(let name):
                if let name { op = .remove(name: name) }
            case .set(let filter):
                switch FilterExport.card(for: filter, key: key, decimal: decimalColumns.contains("\(filter.column.table)[\(filter.column.column)]"), currency: currencyColumns.contains("\(filter.column.table)[\(filter.column.column)]")) {
                case .writable(let card): op = .upsert(card)
                case .sessionOnly(let reason): notes.append(biN("Bộ lọc \(filter.column.column): \(reason)", "Filter \(filter.column.column): \(reason)"))
                }
            }
            guard let op else { continue }
            if groups[path] == nil { order.append(path) }
            groups[path, default: (level, [])].changes.append(op)
        }
        for path in order {
            guard let group = groups[path] else { continue }
            var base = current(path, in: changes, archive: archive)
            if base == nil, group.level == .page, let created = structure.created[URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent] {
                base = created.pageJSON
            }
            guard let data = base else { continue }
            let patched = try PBIRFilterPatch.apply(group.changes, level: group.level, to: data)
            if patched != data { store(patched, at: path, changes: &changes, archive: archive) }
        }
    }
}
