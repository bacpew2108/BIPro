import Foundation
import Observation
import PBIXKit

/// Phần sửa của một trang: bố cục hiện tại, mã đã xoá khỏi bản gốc, và `visual.json` của các bản sao chưa lưu.
struct PageEdit: Equatable {
    var visuals: [ReportVisual]
    /// Mã visual có trong file gốc mà đã bị xoá (khi lưu thì bỏ phần của chúng).
    var deleted: Set<String> = []
    /// `visual.json` của bản sao mới (khoá là mã bản sao), chưa có trong file.
    var added: [String: Data] = [:]
    /// Cấu hình trường đã sửa của visual (mã visual → các ô theo thứ tự), D2. Chỉ có khoá cho visual đã sửa trường.
    var queries: [String: [PBIRQueryPatch.Well]] = [:]
}

/// Một bước hoàn tác: trạng thái sửa của một trang (nil = trang chưa bị sửa) cùng vùng chọn, tại một thời điểm.
struct LayoutSnapshot {
    var pageID: String
    var edit: PageEdit?
    var selection: Set<String>
    var primary: String?
}

/// Bố cục có thể sửa của báo cáo. `Workspace` giữ bản gốc bất biến; mọi thay đổi nằm ở đây
/// và chỉ cho các trang đã bị đụng tới. Xem `specs/002-d1-canvas-luu-t1/data-model.md`.
@MainActor
@Observable
final class LayoutEditor {
    /// Bản gốc lúc mở (hoặc lúc lưu gần nhất).
    private(set) var baseline: ReportDefinition
    /// Trang đã sửa → phần sửa. Trang chưa đụng tới không có mục.
    private(set) var edited: [String: PageEdit] = [:]
    private(set) var selection: Set<String> = []
    private(set) var primary: String?
    private(set) var currentPageID: String?
    /// Lý do gần nhất thao tác bị bỏ qua (ví dụ visual trong nhóm), để giao diện hiện cho người dùng.
    private(set) var lockedReason: String?
    /// Lý do gần nhất một thao tác sửa trường bị từ chối (D2); nil khi thao tác gần nhất được chấp nhận.
    private(set) var fieldRefusal: String?

    // Hoàn tác
    private var undoStack: [LayoutSnapshot] = []
    private var redoStack: [LayoutSnapshot] = []
    /// Độ sâu `undoStack` tại lần lưu gần nhất. -1: không còn quay về được trạng thái đã lưu.
    private var cleanMark = 0
    static let historyLimit = 200
    static let coalesceWindow: TimeInterval = 0.5
    @ObservationIgnored var now: () -> Date = Date.init
    private var lastCoalesce: (pageID: String, ids: Set<String>, at: Date)?

    /// `visual.json` của một visual có trong file đã mở: `(mã trang, mã visual)` → byte. Dùng khi nhân bản.
    @ObservationIgnored private let sourceJSON: (String, String) -> Data?
    /// Mọi mã visual đã có hoặc đã được sinh trong phiên (không bao giờ dùng lại, kể cả sau hoàn tác).
    @ObservationIgnored private var usedIDs: Set<String>
    /// Mã bản sao đã tạo, theo trang (không hoàn tác được): để biết phần nào có thể đã nằm trong file khi xoá.
    @ObservationIgnored private var createdIDs: [String: Set<String>] = [:]
    /// Bộ nhớ tạm cho Chép/Dán trong cùng tài liệu.
    private var clipboard: [(visual: ReportVisual, json: Data)] = []
    private var pasteCount = 0

    init(report: ReportDefinition, sourceJSON: @escaping (String, String) -> Data? = { _, _ in nil }) {
        baseline = report
        self.sourceJSON = sourceJSON
        usedIDs = Set(report.pages.flatMap { $0.visuals.map(\.id) })
    }

    // MARK: Đọc

    var undoDepth: Int { undoStack.count }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isDirty: Bool { undoStack.count != cleanMark }

    func visuals(of pageID: String) -> [ReportVisual] {
        edited[pageID]?.visuals ?? baseline.pages.first { $0.id == pageID }?.visuals ?? []
    }

    /// Trang gốc với bố cục đã sửa.
    func page(_ pageID: String) -> ReportPage? {
        guard var page = baseline.pages.first(where: { $0.id == pageID }) else { return nil }
        if let edit = edited[pageID] { page.visuals = edit.visuals }
        return page
    }

    func visual(_ id: String, page pageID: String? = nil) -> ReportVisual? {
        guard let pageID = pageID ?? currentPageID else { return nil }
        return visuals(of: pageID).first { $0.id == id }
    }

    func isLockedByGroup(_ id: String) -> Bool {
        guard let visual = visual(id) else { return false }
        return visual.raw["parentGroupName"]?.string != nil
    }

    static let groupLockedMessage = "Nằm trong nhóm, chưa sửa được ở D1."

    // MARK: Chọn

    func showPage(_ pageID: String?) {
        guard pageID != currentPageID else { return }
        currentPageID = pageID
        selection = []
        primary = nil
        lockedReason = nil
    }

    func select(_ id: String, extend: Bool = false) {
        guard visual(id) != nil else { return }
        lockedReason = nil
        if extend {
            if selection.contains(id) {
                selection.remove(id)
                if primary == id { primary = selection.first }
            } else {
                selection.insert(id)
                primary = id
            }
        } else {
            selection = [id]
            primary = id
        }
        if selection.isEmpty { primary = nil }
    }

    func setSelection(_ ids: [String], extend: Bool) {
        guard let pageID = currentPageID else { return }
        let valid = Set(visuals(of: pageID).map(\.id))
        let chosen = ids.filter(valid.contains)
        if extend { selection.formUnion(chosen) } else { selection = Set(chosen) }
        if let last = chosen.last { primary = last } else if !extend { primary = nil }
        lockedReason = nil
    }

    func clearSelection() {
        selection = []
        primary = nil
        lockedReason = nil
    }

    // MARK: Di chuyển, đổi cỡ

    /// Dời các visual (bỏ qua visual trong nhóm). `dx`, `dy` tính theo điểm của trang.
    func move(_ ids: Set<String>, dx: Int, dy: Int, snap: Bool, coalescing: Bool = false) {
        guard let pageID = currentPageID, let bounds = pageBounds(pageID) else { return }
        let movable = unlocked(ids)
        guard !movable.isEmpty else { return }
        let ordered = visuals(of: pageID).filter { movable.contains($0.id) }
        let moved = LayoutGeometry.move(ordered.map(Frame.init), dx: dx, dy: dy, page: bounds, snap: snap)
        var frames: [String: Frame] = [:]
        for (visual, frame) in zip(ordered, moved) { frames[visual.id] = frame }
        apply(frames: frames, coalescing: coalescing)
    }

    /// Kéo một tay nắm của một visual.
    func resize(_ id: String, handle: ResizeHandle, dx: Int, dy: Int, snap: Bool) {
        guard let pageID = currentPageID, let bounds = pageBounds(pageID), let visual = visual(id) else { return }
        guard !unlocked([id]).isEmpty else { return }
        let frame = LayoutGeometry.resize(Frame(visual), handle: handle, dx: dx, dy: dy, page: bounds, snap: snap)
        apply(frames: [id: frame])
    }

    /// Đặt khung cho nhiều visual cùng lúc (cuối một lần kéo) thành đúng một bước hoàn tác.
    /// Visual trong nhóm bị bỏ qua; không có gì đổi thì không tạo bước.
    func apply(frames: [String: Frame], coalescing: Bool = false) {
        guard let pageID = currentPageID else { return }
        let allowed = unlocked(Set(frames.keys))
        guard !allowed.isEmpty else { return }
        commit(pageID: pageID, coalesceIDs: coalescing ? allowed : nil) { edit in
            for index in edit.visuals.indices where allowed.contains(edit.visuals[index].id) {
                guard let frame = frames[edit.visuals[index].id] else { continue }
                edit.visuals[index].x = Double(frame.x)
                edit.visuals[index].y = Double(frame.y)
                edit.visuals[index].width = Double(frame.width)
                edit.visuals[index].height = Double(frame.height)
            }
        }
    }

    // MARK: Xoá, nhân bản, chép, dán

    /// Xoá các visual (bỏ qua visual trong nhóm). Vùng chọn trống sau khi xoá.
    func delete(_ ids: Set<String>) {
        guard let pageID = currentPageID, let basePage = baseline.pages.first(where: { $0.id == pageID }) else { return }
        let present = Set(visuals(of: pageID).map(\.id))
        let target = unlocked(ids).intersection(present)
        guard !target.isEmpty else { return }
        let baselineIDs = Set(basePage.visuals.map(\.id))
        let changed = commit(pageID: pageID) { edit in
            edit.visuals.removeAll { target.contains($0.id) }
            for id in target {
                if edit.added[id] != nil { edit.added[id] = nil } else if baselineIDs.contains(id) { edit.deleted.insert(id) }
            }
        }
        if changed { clearSelection(keepingMessage: true) }
    }

    /// Nhân bản các visual: mã mới, lệch `duplicateOffset`, nằm trên cùng, được chọn. Trả mã các bản sao.
    @discardableResult
    func duplicate(_ ids: Set<String>) -> [String] {
        guard let pageID = currentPageID else { return [] }
        let sources = visuals(of: pageID).filter { unlocked(ids).contains($0.id) }
        let entries = sources.compactMap { visual in json(of: visual, page: pageID).map { (visual, $0) } }
        return makeCopies(entries.map { (visual: $0.0, json: $0.1) }, shifts: 1)
    }

    /// Chép các visual đang chọn (không có tác dụng lên bố cục).
    func copy() {
        guard let pageID = currentPageID else { return }
        let chosen = visuals(of: pageID).filter { selection.contains($0.id) && !isLockedByGroup($0.id) }
        clipboard = chosen.compactMap { visual in json(of: visual, page: pageID).map { (visual: visual, json: $0) } }
        pasteCount = 0
    }

    /// Dán vào trang hiện tại; mỗi lần dán lệch thêm một bậc.
    @discardableResult
    func paste() -> [String] {
        guard !clipboard.isEmpty else { return [] }
        pasteCount += 1
        return makeCopies(clipboard, shifts: pasteCount)
    }

    var hasClipboard: Bool { !clipboard.isEmpty }

    /// `visual.json` hiện tại của visual (đã áp phần sửa trường, chưa áp vị trí): dùng khi nhân bản và dán.
    private func json(of visual: ReportVisual, page pageID: String) -> Data? {
        if let added = edited[pageID]?.added[visual.id] { return added }
        guard let source = sourceJSON(pageID, visual.id) else { return nil }
        if let wells = edited[pageID]?.queries[visual.id], let applied = try? PBIRQueryPatch.apply(wells, to: source) { return applied }
        return source
    }

    private func makeCopies(_ entries: [(visual: ReportVisual, json: Data)], shifts: Int) -> [String] {
        guard let pageID = currentPageID, let bounds = pageBounds(pageID), !entries.isEmpty else { return [] }
        let offset = LayoutGeometry.duplicateOffset * shifts
        let frames = LayoutGeometry.move(entries.map { Frame($0.visual) }, dx: offset, dy: offset, page: bounds, snap: false)
        var z = visuals(of: pageID).map(\.z).max() ?? 0
        var copies: [ReportVisual] = []
        var data: [String: Data] = [:]
        for (index, entry) in entries.enumerated() {
            let id = PBIRLayoutPatch.makeVisualName(avoiding: usedIDs)
            let frame = frames[index]
            z += Double(LayoutGeometry.zStep)
            guard let patched = try? PBIRLayoutPatch.duplicated(entry.json, newName: id, x: frame.x, y: frame.y,
                                                                width: frame.width, height: frame.height, z: Int(z)) else {
                z -= Double(LayoutGeometry.zStep)
                continue
            }
            usedIDs.insert(id)
            let source = entry.visual
            copies.append(ReportVisual(id: id, type: source.type, x: Double(frame.x), y: Double(frame.y), z: z,
                                       width: Double(frame.width), height: Double(frame.height), isHidden: source.isHidden,
                                       objects: source.objects, containerObjects: source.containerObjects, fields: source.fields,
                                       raw: (try? JSONValue.parse(patched)) ?? source.raw))
            data[id] = patched
        }
        guard !copies.isEmpty else {
            lockedReason = "Không đọc được dữ liệu của visual nguồn để nhân bản."
            return []
        }
        commit(pageID: pageID) { edit in
            edit.visuals.append(contentsOf: copies)
            edit.added.merge(data) { _, new in new }
        }
        createdIDs[pageID, default: []].formUnion(data.keys)
        selection = Set(data.keys)
        primary = copies.last?.id
        return copies.map(\.id)
    }

    private func clearSelection(keepingMessage: Bool) {
        selection = []
        primary = nil
        if !keepingMessage { lockedReason = nil }
    }

    // MARK: Sửa trường (D2)

    /// Các ô và trường hiện tại của visual (đã áp phần sửa), theo thứ tự trong file. Rỗng khi không đọc được.
    func fieldWells(of id: String) -> [PBIRQueryPatch.Well] {
        guard let pageID = currentPageID else { return [] }
        if let wells = edited[pageID]?.queries[id] { return wells }
        guard let base = baseJSON(of: id, page: pageID) else { return [] }
        return (try? PBIRQueryPatch.wells(in: base)) ?? []
    }

    /// Lý do visual này chưa sửa được trường, hoặc nil nếu sửa được.
    func fieldEditingBlocker(for id: String) -> String? {
        guard let pageID = currentPageID, visual(id) != nil else { return "Chọn một visual để sửa trường." }
        if isLockedByGroup(id) { return "Visual nằm trong nhóm, chưa sửa trường được." }
        guard let base = baseJSON(of: id, page: pageID) else { return "Không đọc được visual.json của visual này (báo cáo định dạng cũ chưa sửa được)." }
        guard (try? PBIRQueryPatch.wells(in: base)) != nil, hasQueryState(base) else {
            return "Visual này chưa có cấu hình trường, D2 chưa tạo mới được."
        }
        return nil
    }

    private func baseJSON(of id: String, page pageID: String) -> Data? {
        edited[pageID]?.added[id] ?? sourceJSON(pageID, id)
    }

    func clearFieldRefusal() { fieldRefusal = nil }
    func noteFieldRefusal(_ message: String) { fieldRefusal = message }

    /// Thêm `field` vào ô `role`. Trả lý do nếu bị từ chối (và ghi vào `fieldRefusal`), nil nếu thành công.
    @discardableResult
    func addField(_ field: FieldRef, to role: String, visual id: String) -> String? {
        editFields(id) { wells, visual, _ in FieldEditor.add(field, to: role, wells: wells, visual: visual) }
    }

    @discardableResult
    func removeField(role: String, index: Int, visual id: String) -> String? {
        editFields(id) { wells, visual, base in
            FieldEditor.remove(role: role, index: index, wells: wells, visual: visual) { field in
                FieldReferences.find(in: base, entity: field.entity, property: field.property, queryRef: field.queryRef)
            }
        }
    }

    @discardableResult
    func moveField(role: String, index: Int, to target: String, visual id: String) -> String? {
        editFields(id) { wells, visual, _ in FieldEditor.move(role: role, index: index, to: target, wells: wells, visual: visual) }
    }

    @discardableResult
    func reorderField(role: String, from: Int, to: Int, visual id: String) -> String? {
        editFields(id) { wells, _, _ in FieldEditor.reorder(role: role, from: from, to: to, wells: wells) }
    }

    @discardableResult
    func renameField(role: String, index: Int, to name: String, visual id: String) -> String? {
        editFields(id) { wells, _, _ in FieldEditor.rename(role: role, index: index, to: name, wells: wells) }
    }

    /// Chạy một thao tác sửa trường như đúng một `commit`: dựng `visual.json` mới từ bản gốc, rồi cập nhật `raw` và
    /// `fields` của visual từ chính chuỗi byte đó (cái vẽ chính là cái sẽ lưu).
    private func editFields(_ id: String, _ body: ([PBIRQueryPatch.Well], ReportVisual, Data) -> FieldEditor.Result) -> String? {
        fieldRefusal = nil
        func refuse(_ message: String) -> String { fieldRefusal = message; return message }
        guard let pageID = currentPageID else { return refuse("Chưa mở trang nào.") }
        if let blocker = fieldEditingBlocker(for: id) { return refuse(blocker) }
        guard let visual = visual(id), let base = baseJSON(of: id, page: pageID) else { return refuse("Không tìm thấy visual.") }
        let wells = edited[pageID]?.queries[id] ?? ((try? PBIRQueryPatch.wells(in: base)) ?? [])
        switch body(wells, visual, base) {
        case .refused(let message):
            return refuse(message)
        case .unchanged:
            return nil
        case .changed(let next):
            let bytes: Data, raw: JSONValue, fields: [ReportField]
            do {
                bytes = try PBIRQueryPatch.apply(next, to: base)
                raw = try JSONValue.parse(bytes)
                fields = try PBIRQueryPatch.fields(in: bytes)
            } catch {
                return refuse("Không ghi được cấu hình trường: \(error)")
            }
            commit(pageID: pageID) { edit in
                guard let index = edit.visuals.firstIndex(where: { $0.id == id }) else { return }
                edit.visuals[index].raw = raw
                edit.visuals[index].fields = fields
                edit.queries[id] = next
                if edit.added[id] != nil { edit.added[id] = bytes }
            }
            return nil
        }
    }

    // MARK: Hoàn tác

    func undo() {
        guard let step = undoStack.popLast() else { return }
        redoStack.append(snapshot(of: step.pageID))
        restore(step)
        lastCoalesce = nil
    }

    func redo() {
        guard let step = redoStack.popLast() else { return }
        undoStack.append(snapshot(of: step.pageID))
        restore(step)
        lastCoalesce = nil
    }

    /// Gọi sau khi lưu thành công: trạng thái hiện tại là trạng thái sạch.
    func markSaved() {
        cleanMark = undoStack.count
        lastCoalesce = nil
    }

    // MARK: Nội bộ

    private func pageBounds(_ pageID: String) -> PageBounds? {
        baseline.pages.first { $0.id == pageID }.map(PageBounds.init)
    }

    /// Bỏ visual trong nhóm; nếu có bỏ thì ghi lý do.
    private func unlocked(_ ids: Set<String>) -> Set<String> {
        let allowed = ids.filter { !isLockedByGroup($0) }
        lockedReason = allowed.count < ids.count ? Self.groupLockedMessage : nil
        return allowed
    }

    private func snapshot(of pageID: String) -> LayoutSnapshot {
        LayoutSnapshot(pageID: pageID, edit: edited[pageID], selection: selection, primary: primary)
    }

    private func restore(_ step: LayoutSnapshot) {
        edited[step.pageID] = step.edit
        if currentPageID != step.pageID { currentPageID = step.pageID }
        selection = step.selection
        primary = step.primary
    }

    /// Chạy `body` trên bản sao sửa được của trang. Không đổi gì thì không tạo bước và không tạo bản sao trang.
    /// `coalesceIDs` khác nil: nhiều lần gọi liên tiếp trong 0,5 s cho cùng nhóm chọn gộp thành một bước.
    @discardableResult
    func commit(pageID: String, coalesceIDs: Set<String>? = nil, _ body: (inout PageEdit) -> Void) -> Bool {
        let before = edited[pageID]
        var working = before ?? PageEdit(visuals: baseline.pages.first { $0.id == pageID }?.visuals ?? [])
        body(&working)
        guard working != (before ?? PageEdit(visuals: baseline.pages.first { $0.id == pageID }?.visuals ?? [])) else { return false }

        let time = now()
        var merged = false
        if let key = coalesceIDs, let last = lastCoalesce, last.pageID == pageID, last.ids == key,
           time.timeIntervalSince(last.at) < Self.coalesceWindow, !undoStack.isEmpty {
            merged = true
        }
        if !merged {
            // Quay lại trạng thái "sạch" nằm trong nhánh làm lại đã bị xoá: không còn là sạch.
            if !redoStack.isEmpty, cleanMark > undoStack.count { cleanMark = -1 }
            undoStack.append(snapshot(of: pageID))
            if undoStack.count > Self.historyLimit {
                undoStack.removeFirst()
                cleanMark = cleanMark > 0 ? cleanMark - 1 : -1
            }
        }
        redoStack.removeAll()
        edited[pageID] = working
        lastCoalesce = coalesceIDs.map { (pageID, $0, time) }
        return true
    }

    // MARK: Gói thay đổi để lưu

    nonisolated static func visualPath(page: String, id: String) -> String {
        "Report/definition/pages/\(page)/visuals/\(id)/visual.json"
    }

    /// Các thay đổi cần ghi vào file `archive` (file đang có trên đĩa, không nhất thiết bản lúc mở), chỉ cho
    /// trang đã sửa: `visual.json` ghép byte cho visual đổi vị trí, phần mới cho bản sao, bỏ phần của visual đã xoá,
    /// và dọn tham chiếu tới visual đã xoá trong bookmark và `page.json`.
    func makeChanges(archive: ZipArchive) throws -> PBIXChanges {
        var changes = PBIXChanges()
        var removedIDs = Set<String>()
        for pageID in edited.keys.sorted() {
            guard let edit = edited[pageID], let basePage = baseline.pages.first(where: { $0.id == pageID }) else { continue }
            for visual in edit.visuals {
                let path = Self.visualPath(page: pageID, id: visual.id)
                if archive.entry(path) != nil {
                    let onDisk = try archive.read(path)
                    var json = onDisk
                    if let wells = edit.queries[visual.id] { json = try PBIRQueryPatch.apply(wells, to: json) }
                    if let patched = try Self.patch(json, to: visual) { json = patched }
                    if json != onDisk { changes.reportParts[path] = json }
                } else if let data = edit.added[visual.id] {
                    changes.addedParts[path] = try Self.patch(data, to: visual) ?? data
                }
            }
            // Bị xoá: visual của file gốc hoặc bản sao đã tạo trong phiên mà không còn trong bố cục, và có trong file.
            let current = Set(edit.visuals.map(\.id))
            let candidates = Set(basePage.visuals.map(\.id)).union(createdIDs[pageID] ?? [])
            for id in candidates.sorted() where !current.contains(id) {
                let path = Self.visualPath(page: pageID, id: id)
                if archive.entry(path) != nil {
                    changes.removedParts.insert(path)
                    removedIDs.insert(id)
                }
            }
        }
        if !removedIDs.isEmpty {
            for entry in archive.entries {
                let isBookmark = entry.path.hasSuffix(".bookmark.json")
                let isPage = entry.path.hasSuffix("/page.json") && entry.path.hasPrefix("Report/definition/pages/")
                guard isBookmark || isPage else { continue }
                let data = try archive.read(entry)
                let cleaned = isBookmark
                    ? try PBIRLayoutPatch.removingVisualReferences(removedIDs, fromBookmark: data)
                    : try PBIRLayoutPatch.removingVisualReferences(removedIDs, fromPage: data)
                if cleaned != data { changes.reportParts[entry.path] = cleaned }
            }
        }
        return changes
    }

    /// `visual.json` với vị trí của `visual`, hoặc nil khi vị trí trong file đã đúng.
    private static func patch(_ json: Data, to visual: ReportVisual) throws -> Data? {
        let current = try PBIRLayoutPatch.position(in: json)
        func differs(_ a: Double, _ b: Double) -> Bool { a != b }
        let frame = Frame(visual)
        let x = differs(current.x, visual.x) ? frame.x : nil
        let y = differs(current.y, visual.y) ? frame.y : nil
        let width = differs(current.width, visual.width) ? frame.width : nil
        let height = differs(current.height, visual.height) ? frame.height : nil
        guard x != nil || y != nil || width != nil || height != nil else { return nil }
        return try PBIRLayoutPatch.setPosition(in: json, x: x, y: y, width: width, height: height)
    }
}

/// `visual.json` có `visual.query.queryState` là đối tượng (D2 chỉ sửa visual đã có cấu hình trường).
private func hasQueryState(_ json: Data) -> Bool {
    guard let value = try? JSONValue.parse(json) else { return false }
    if case .object = value["visual"]?["query"]?["queryState"] ?? .null { return true }
    return false
}
