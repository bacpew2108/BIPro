import Foundation
import PBIXKit

/// Điều kiện sửa trang (D5): cùng điều kiện sửa bố cục của D1 (chế độ Sửa, báo cáo PBIR, tab Báo cáo).
enum PageEditing {
    static func blocker(editMode: Bool, canEditLayout: Bool, mode: WorkspaceMode) -> String? {
        if mode != .report { return "Chỉ sửa trang được ở chế độ Báo cáo." }
        if !canEditLayout { return "Báo cáo định dạng cũ (Report/Layout) chưa sửa được trang." }
        if !editMode { return "Bật chế độ Sửa (⌘E) để sửa trang." }
        return nil
    }
}

/// Dữ liệu kéo của một tab trang (D5). Mang dấu của tài liệu để chỉ tab của chính cửa sổ đó thả được: chữ kéo từ nơi khác,
/// tab của tài liệu khác hay trang không còn trong dãy đều bị bỏ qua.
enum PageTabDrag {
    private static let scheme = "bipro-page"

    static func payload(page: String, document: UUID) -> String { "\(scheme):\(document.uuidString):\(page)" }

    /// Mã trang được kéo, hoặc nil khi `text` không phải tab của tài liệu `document` hay trang không có trong `pages`.
    static func page(from text: String, document: UUID, pages: [String]) -> String? {
        let prefix = "\(scheme):\(document.uuidString):"
        guard text.hasPrefix(prefix) else { return nil }
        let id = String(text.dropFirst(prefix.count))
        return pages.contains(id) ? id : nil
    }
}

extension LayoutEditor {
    private func refuse(_ message: String) -> String {
        noteFieldRefusal(message)
        return message
    }

    /// `$schema` của `page.json` đầu tiên có trong file (để trang mới khớp báo cáo); nil: dùng mặc định.
    private func pageSchema() -> String? {
        for page in baseline.pages {
            if let data = pageSource(page.id), let value = try? JSONValue.parse(data), let schema = value["$schema"]?.string { return schema }
        }
        return nil
    }

    // MARK: Thêm

    /// Thêm một trang trống "Page N" (1920×1080, `FitToPage`) ở cuối dãy và mở nó. Trả mã trang mới.
    @discardableResult
    func addPage() -> String? {
        resetMessages()
        let id = PBIRLayoutPatch.makeObjectName(avoiding: usedPageIDs)
        usedPageIDs.insert(id)
        let name = PageStructure.nextDefaultName(existing: pages.map(\.displayName))
        let page = NewPage(id: id, displayName: name, pageJSON: PBIRPagePatch.newPageJSON(id: id, displayName: name, schema: pageSchema()),
                           sourcePage: nil, width: 1920, height: 1080)
        let changed = commitStructure { structure, _ in
            structure.created[id] = page
            structure.order.append(id)
        }
        guard changed else { return nil }
        openPage(id)
        return id
    }

    // MARK: Đổi tên

    /// Đặt tên hiển thị của trang. Trả lý do từ chối hoặc nil (kể cả khi tên không đổi: không tạo bước).
    @discardableResult
    func renamePage(_ id: String, to name: String) -> String? {
        resetMessages()
        guard let current = page(id) else { return refuse("Không tìm thấy trang.") }
        let wanted: String
        switch PageStructure.validatedName(name) {
        case .failure(let error): return refuse(error.description)
        case .success(let value): wanted = value
        }
        guard wanted != current.displayName else { return nil }
        if let created = structure.created[id] {
            guard let json = try? PBIRPagePatch.setPageDisplayName(wanted, in: created.pageJSON) else {
                return refuse("Không ghi được tên trang.")
            }
            commitStructure { structure, _ in
                structure.created[id]?.displayName = wanted
                structure.created[id]?.pageJSON = json
            }
        } else {
            let original = baseline.pages.first { $0.id == id }?.displayName
            commitStructure { structure, _ in structure.renamed[id] = wanted == original ? nil : wanted }
        }
        return nil
    }

    // MARK: Nhân bản

    /// Nhân bản trang `id`: trang mới "Duplicate of <tên>" ở cuối dãy, mọi visual mã mới (vị trí, `z` và phần sửa chưa
    /// lưu giữ nguyên), được mở. Bản sao không mang `pageBinding` (có báo). Trả mã trang mới.
    @discardableResult
    func duplicatePage(_ id: String) -> String? {
        resetMessages()
        guard let source = page(id) else { _ = refuse("Không tìm thấy trang."); return nil }
        guard let sourcePageJSON = structure.created[id]?.pageJSON ?? pageSource(id) else {
            _ = refuse("Không đọc được page.json của trang (báo cáo định dạng cũ chưa nhân bản được).")
            return nil
        }
        // Container không phải visual (nhóm): của trang trong file, hoặc đã sao sang trang nhân bản trước đó.
        // Nhóm visual (D7) có mặt trong `source.groups`; ở đây chỉ còn container khác (không phải nhóm).
        let containers: [(id: String, json: Data)] = (edited[id]?.extraParts.map { (id: $0.key, json: $0.value) }
            ?? (structure.created[id] == nil ? containerSource(id) : []))
            .filter { (try? JSONValue.parse($0.json))?["visualGroup"] == nil }
        var idMap: [String: String] = [:]
        for visual in source.visuals + source.groups { idMap[visual.id] = reserveVisualID(avoiding: Set(idMap.values)) }
        for container in containers { idMap[container.id] = reserveVisualID(avoiding: Set(idMap.values)) }

        var copies: [ReportVisual] = []
        var groupCopies: [ReportVisual] = []
        var data: [String: Data] = [:]
        var extras: [String: Data] = [:]
        do {
            for visual in source.visuals {
                guard let json = currentVisualJSON(visual, page: id), let newID = idMap[visual.id] else {
                    _ = refuse("Không đọc được visual.json của \(visual.id).")
                    return nil
                }
                let group = visual.parentGroup.flatMap { idMap[$0] }
                let renamed = try PBIRPagePatch.renamedVisualJSON(json, newName: newID, parentGroupName: group)
                var copy = visual
                copy = ReportVisual(id: newID, type: visual.type, x: visual.x, y: visual.y, z: visual.z, width: visual.width,
                                    height: visual.height, isHidden: visual.isHidden, objects: visual.objects,
                                    containerObjects: visual.containerObjects, fields: visual.fields,
                                    raw: (try? JSONValue.parse(renamed)) ?? visual.raw, parentGroup: group)
                copies.append(copy)
                data[newID] = renamed
            }
            for group in source.groups {
                guard let json = currentVisualJSON(group, page: id), let newID = idMap[group.id] else {
                    _ = refuse("Không đọc được visual.json của nhóm \(group.id).")
                    return nil
                }
                // Nhóm lồng nhau (VM-D8): nhóm con trỏ tới bản sao của nhóm cha.
                let outer = group.parentGroup.flatMap { idMap[$0] }
                let renamed = try PBIRPagePatch.renamedVisualJSON(json, newName: newID, parentGroupName: outer)
                groupCopies.append(ReportVisual(id: newID, type: group.type, x: group.x, y: group.y, z: group.z, width: group.width,
                                                height: group.height, isHidden: group.isHidden,
                                                raw: (try? JSONValue.parse(renamed)) ?? group.raw, parentGroup: outer))
                data[newID] = renamed
            }
            for container in containers {
                guard let newID = idMap[container.id] else { continue }
                let parent = (try? JSONValue.parse(container.json))?["parentGroupName"]?.string.flatMap { idMap[$0] }
                extras[newID] = try PBIRPagePatch.renamedVisualJSON(container.json, newName: newID, parentGroupName: parent)
            }
        } catch {
            _ = refuse("Không nhân bản được visual: \(error)")
            return nil
        }

        let newID = PBIRLayoutPatch.makeObjectName(avoiding: usedPageIDs)
        usedPageIDs.insert(newID)
        let name = "Duplicate of \(source.displayName)"
        let pageJSON: Data
        do {
            pageJSON = try PBIRPagePatch.duplicatedPageJSON(sourcePageJSON, newName: newID, displayName: name, visualIDMap: idMap)
        } catch {
            _ = refuse("Không nhân bản được page.json: \(error)")
            return nil
        }
        let hadBinding = (try? JSONValue.parse(sourcePageJSON))?["pageBinding"] != nil
        let page = NewPage(id: newID, displayName: name, pageJSON: pageJSON, sourcePage: id, width: source.width, height: source.height)
        var edit = PageEdit(visuals: copies, groups: groupCopies, added: data)
        edit.extraParts = extras
        let changed = commitStructure { structure, edited in
            structure.created[newID] = page
            structure.order.append(newID)
            edited[newID] = edit
        }
        guard changed else { return nil }
        registerCreatedVisuals(Set(data.keys), page: newID)
        openPage(newID)
        if hadBinding { setNotice("Bản sao không mang cấu hình drillthrough.") }
        return newID
    }

    // MARK: Xoá

    /// Xoá trang `id`. Trả lý do từ chối hoặc nil. Trang liền kề thành trang đang mở; bookmark trỏ trang đó bị gỡ (hoặc
    /// chỉ bỏ mục của trang); `notice` nói bookmark nào. Hoàn tác phục hồi trang, phần sửa và bookmark.
    @discardableResult
    func removePage(_ id: String) -> String? {
        resetMessages()
        guard let target = page(id), structure.order.contains(id) else { return refuse("Không tìm thấy trang.") }
        if let reason = PageStructure.removalRefusal(pageCount: structure.order.count) { return refuse(reason) }
        let otherVisible = pages.filter { $0.id != id && !$0.isHidden }.count
        if let reason = PageStructure.removalRefusal(removingHidden: target.isHidden, otherVisiblePages: otherVisible) { return refuse(reason) }
        // Nút điều hướng trang ở các trang còn lại trỏ tới trang này: Desktop để nguyên (VM-D8), BI Pro làm theo và báo nút nào.
        var buttons: [String] = []
        for other in pages where other.id != id {
            for visual in other.visuals {
                // Vị trí không liên quan tới nút điều hướng: không cần `currentVisualJSON` (phải phân tích từng visual).
                guard let base = jsonBeforeFormats(of: visual.id, page: other.id),
                      let json = try? withFormats(base, page: other.id, id: visual.id) else { continue }
                if !PBIRPagePatch.pageNavigationTargets(in: json, knownPages: [id]).isEmpty { buttons.append(visual.id) }
            }
        }

        // Bookmark: chỉ trang của file mới có bookmark trỏ tới.
        let isFilePage = structure.created[id] == nil
        let sources = bookmarkSource()
        let infos = isFilePage ? sources.compactMap { BookmarkInfo(json: $0.json) }.filter { !structure.removedBookmarks.contains($0.name) } : []
        let impact = PageStructure.bookmarkImpact(removing: [id], bookmarks: infos)
        let next = PageStructure.neighbour(afterRemoving: id, in: structure.order)
        let changed = commitStructure { structure, edited in
            structure.order.removeAll { $0 == id }
            if structure.created[id] != nil { structure.created[id] = nil } else { structure.removed.insert(id); structure.renamed[id] = nil }
            edited[id] = nil
            structure.removedBookmarks.formUnion(impact.removed)
            for (name, pages) in impact.trimmed { structure.trimmedBookmarkSections[name, default: []].formUnion(pages) }
        }
        guard changed else { return nil }
        if let next { openPage(next) }

        func title(_ name: String) -> String {
            sources.first { $0.name == name }.flatMap { (try? JSONValue.parse($0.json))?["displayName"]?.string } ?? name
        }
        var parts = ["Đã xoá trang \"\(target.displayName)\""]
        if !impact.removed.isEmpty {
            parts.append("gỡ \(impact.removed.count) bookmark trỏ tới trang: " + impact.removed.sorted().map(title).joined(separator: ", "))
        }
        if !impact.trimmed.isEmpty {
            parts.append("bỏ trang khỏi \(impact.trimmed.count) bookmark: " + impact.trimmed.keys.sorted().map(title).joined(separator: ", "))
        }
        if !buttons.isEmpty {
            parts.append("\(buttons.count) nút điều hướng vẫn trỏ tới trang này (như Power BI Desktop): " + buttons.joined(separator: ", "))
        }
        setNotice(parts.joined(separator: "; ") + ".")
        return nil
    }

    // MARK: Đổi thứ tự

    /// Dời trang `id` tới chỉ số `index` của dãy mới. Trang đang mở giữ nguyên.
    @discardableResult
    func movePage(_ id: String, to index: Int) -> String? {
        resetMessages()
        guard let from = structure.order.firstIndex(of: id) else { return refuse("Không tìm thấy trang.") }
        guard structure.order.indices.contains(index) else { return refuse("Vị trí ngoài dãy trang.") }
        guard from != index else { return nil }
        commitStructure { structure, _ in
            structure.order.remove(at: from)
            structure.order.insert(id, at: index)
        }
        return nil
    }
}

extension DocumentState {
    var pageEditingBlocker: String? {
        PageEditing.blocker(editMode: editMode, canEditLayout: canEditLayout, mode: mode)
    }

    private func followPage() {
        if let page = layout.currentPageID, page != pageID { pageID = page }
        visualID = nil
    }

    private func refused(_ message: String) -> String {
        layout.noteFieldRefusal(message)
        return message
    }

    @discardableResult
    func addPage() -> String? {
        if let blocker = pageEditingBlocker { _ = refused(blocker); return nil }
        let id = layout.addPage()
        followPage()
        return id
    }

    @discardableResult
    func renamePage(_ id: String, to name: String) -> String? {
        if let blocker = pageEditingBlocker { return refused(blocker) }
        return layout.renamePage(id, to: name)
    }

    @discardableResult
    func movePage(_ id: String, to index: Int) -> String? {
        if let blocker = pageEditingBlocker { return refused(blocker) }
        return layout.movePage(id, to: index)
    }

    @discardableResult
    func removePage(_ id: String) -> String? {
        if let blocker = pageEditingBlocker { return refused(blocker) }
        let reason = layout.removePage(id)
        followPage()
        return reason
    }

    @discardableResult
    func duplicatePage(_ id: String) -> String? {
        if let blocker = pageEditingBlocker { _ = refused(blocker); return nil }
        let new = layout.duplicatePage(id)
        followPage()
        return new
    }
}
