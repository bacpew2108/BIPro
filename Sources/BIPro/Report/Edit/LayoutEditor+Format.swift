import Foundation
import PBIXKit

/// Trạng thái một thẻ định dạng của một visual, cho giao diện (`specs/006-d4-format-pane/data-model.md`).
struct FormatCardState: Equatable {
    let card: FormatCard
    /// Khoá có trong file.
    let isPresent: Bool
    /// Có mục chung để sửa (hoặc chưa có khoá nên thêm được). `false`: khoá chỉ có mục theo trường hoặc điểm dữ liệu.
    let isEditable: Bool
    /// Giá trị hiện có của các thuộc tính trong mục chung (thuộc tính vắng mặt không có khoá).
    let values: [String: FormatValue]
}

struct FormatState: Equatable {
    let visualID: String
    let type: String
    let objects: [FormatCardState]
    let container: [FormatCardState]
    /// Chỗ không sửa được: khoá hoặc thuộc tính ngoài danh mục, mục theo trường (R4, R6).
    let readOnly: [FormatReadOnlyItem]
    /// Lý do không sửa được cả visual (nhóm, báo cáo cũ), nil nếu sửa được.
    let blocker: String?
}

extension LayoutEditor {
    // MARK: Điều kiện

    /// Lý do visual này chưa sửa định dạng được, hoặc nil nếu sửa được (chế độ Xem và chọn nhiều visual do `DocumentState` lo).
    func formatEditingBlocker(for id: String) -> String? {
        guard let pageID = currentPageID, visual(id) != nil else { return "Chọn một visual để sửa định dạng." }
        if isLegacy { return Self.legacyMessage }
        if isLockedByGroup(id) { return "Visual nằm trong nhóm, chưa sửa định dạng được." }
        guard baseJSON(of: id, page: pageID) != nil else {
            return "Không đọc được visual.json của visual này (báo cáo định dạng cũ chưa sửa được)."
        }
        return nil
    }

    // MARK: Đọc

    private func scopeJSON(of visual: ReportVisual, _ scope: FormatScope) -> JSONValue? { visual.raw["visual"]?[scope.key] }

    func formatState(of id: String) -> FormatState? {
        guard let visual = visual(id) else { return nil }
        func states(_ scope: FormatScope) -> [FormatCardState] {
            let json = scopeJSON(of: visual, scope)
            return FormatCatalog.cards(for: visual.type, scope: scope).map { card in
                let entries = json?[card.objectKey]?.array ?? []
                let editable = entries.first(where: FormatCatalog.isEditable)
                var values: [String: FormatValue] = [:]
                for property in card.properties {
                    if let value = FormatValue.read(editable?["properties"]?[property.key], kind: property.kind) { values[property.key] = value }
                }
                return FormatCardState(card: card, isPresent: !entries.isEmpty, isEditable: entries.isEmpty || editable != nil, values: values)
            }
        }
        let readOnly = FormatScope.allCases.flatMap { FormatCatalog.readOnlyItems(in: scopeJSON(of: visual, $0), type: visual.type, scope: $0) }
        return FormatState(visualID: id, type: visual.type, objects: states(.objects), container: states(.container),
                           readOnly: readOnly, blocker: formatEditingBlocker(for: id))
    }

    // MARK: Ghi

    /// Đặt `property` của khoá `object` trong phạm vi `scope` của visual `id`. Trả lý do từ chối (cũng ghi ở `fieldRefusal`) hoặc nil.
    /// Giá trị bằng giá trị hiện có thì không tạo bước. Nhiều lần đặt liên tiếp cùng thuộc tính gộp thành một bước.
    @discardableResult
    func setFormat(_ value: FormatValue, scope: FormatScope, object: String, property: String, visual id: String) -> String? {
        resetMessages()
        func refuse(_ message: String) -> String { noteFieldRefusal(message); return message }
        guard let pageID = currentPageID else { return refuse("Chưa mở trang nào.") }
        if let blocker = formatEditingBlocker(for: id) { return refuse(blocker) }
        guard let visual = visual(id) else { return refuse("Không tìm thấy visual.") }
        guard let card = FormatCatalog.cards(for: visual.type, scope: scope).first(where: { $0.objectKey == object }),
              let spec = card.properties.first(where: { $0.key == property }) else {
            return refuse("Thuộc tính này chưa quan sát ở Power BI Desktop nên chưa sửa được.")
        }
        if let reason = value.validate(kind: spec.kind) { return refuse(reason) }
        let entries = scopeJSON(of: visual, scope)?[object]?.array ?? []
        let editable = entries.first(where: FormatCatalog.isEditable)
        if !entries.isEmpty, editable == nil { return refuse("Thẻ này có định dạng riêng theo trường hoặc điểm dữ liệu, chưa sửa được.") }
        let existing = editable?["properties"]?[property]
        if existing == nil, !spec.addable { return refuse("Thuộc tính này chỉ sửa được khi file đã có giá trị.") }
        var tail: NumberTail?
        if case .number(_, let existingTail)? = FormatValue.read(existing, kind: spec.kind) { tail = existingTail }
        let json: String
        do { json = try value.json(kind: spec.kind, keepingTail: tail) } catch { return refuse("\(error)") }
        if let existing, let new = try? JSONValue.parse(json), existing == new { return nil }
        let edit = FormatEdit(scope: scope, object: object, action: .set(property: property, value: json), selectorDefault: card.usesDefaultSelector)
        let key = FormatTarget(visualID: id, scope: scope, object: object, property: property).coalesceKey
        return applyFormat(edit, visual: id, page: pageID, coalesce: key)
    }

    /// Đặt lại về mặc định: cả thẻ (`property` nil, bỏ cả khoá) hoặc một thuộc tính. Khoá hoặc thuộc tính không có trong file
    /// thì không làm gì (không tạo bước).
    @discardableResult
    func resetFormat(scope: FormatScope, object: String, property: String? = nil, visual id: String) -> String? {
        resetMessages()
        func refuse(_ message: String) -> String { noteFieldRefusal(message); return message }
        guard let pageID = currentPageID else { return refuse("Chưa mở trang nào.") }
        if let blocker = formatEditingBlocker(for: id) { return refuse(blocker) }
        guard let visual = visual(id) else { return refuse("Không tìm thấy visual.") }
        guard FormatCatalog.cards(for: visual.type, scope: scope).contains(where: { $0.objectKey == object }) else {
            return refuse("Thẻ này chưa quan sát ở Power BI Desktop nên chưa sửa được.")
        }
        let entries = scopeJSON(of: visual, scope)?[object]?.array ?? []
        guard !entries.isEmpty else { return nil }
        let editable = entries.first(where: FormatCatalog.isEditable)
        if let property {
            guard editable?["properties"]?[property] != nil else { return nil }
            return applyFormat(FormatEdit(scope: scope, object: object, action: .removeProperty(property)), visual: id, page: pageID, coalesce: nil)
        }
        if editable == nil || entries.count > 1 && entries.contains(where: { !FormatCatalog.isEditable($0) }) {
            return refuse("Thẻ này có định dạng riêng theo trường hoặc điểm dữ liệu, chưa đặt lại được.")
        }
        return applyFormat(FormatEdit(scope: scope, object: object, action: .removeObject), visual: id, page: pageID, coalesce: nil)
    }

    /// Dựng `visual.json` mới, cập nhật `raw`, `objects`, `containerObjects` từ chính chuỗi byte đó (cái vẽ chính là cái sẽ lưu)
    /// và ghi một bước hoàn tác.
    private func applyFormat(_ edit: FormatEdit, visual id: String, page pageID: String, coalesce key: String?) -> String? {
        func refuse(_ message: String) -> String { noteFieldRefusal(message); return message }
        let isNew = edited[pageID]?.added[id] != nil
        var formats = edited[pageID]?.formats[id] ?? []
        let bytes: Data, raw: JSONValue
        do {
            if isNew {
                guard let current = edited[pageID]?.added[id] else { return refuse("Không tìm thấy visual.") }
                bytes = try PBIRFormatPatch.apply([edit], to: current)
            } else {
                formats = FormatEdit.merging(formats, adding: edit)
                guard let source = jsonBeforeFormats(of: id, page: pageID) else { return refuse("Không đọc được visual.json của visual này.") }
                bytes = try PBIRFormatPatch.apply(formats, to: source)
            }
            raw = try JSONValue.parse(bytes)
        } catch {
            return refuse("Không ghi được định dạng: \(error)")
        }
        commit(pageID: pageID, coalesceIDs: key.map { [$0] }) { page in
            guard let index = page.visuals.firstIndex(where: { $0.id == id }) else { return }
            page.visuals[index].raw = raw
            page.visuals[index].objects = ObjectProperties(raw["visual"]?["objects"])
            page.visuals[index].containerObjects = ObjectProperties(raw["visual"]?["visualContainerObjects"])
            if isNew { page.added[id] = bytes } else { page.formats[id] = formats }
        }
        return nil
    }
}
