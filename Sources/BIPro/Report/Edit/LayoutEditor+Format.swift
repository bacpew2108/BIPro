import Foundation
import PBIXKit

/// Một chuỗi của visual trong thẻ có định dạng theo chuỗi (VM-D8 mục 6).
struct FormatSeriesState: Equatable {
    /// `queryRef` của measure, ghi vào `selector.metadata`.
    let queryRef: String
    let title: String
    /// Giá trị hiện có ở mục riêng của chuỗi.
    let values: [String: FormatValue]
    /// Lý do chưa sửa được chuỗi này (đang tô màu theo công thức hoặc điểm dữ liệu), nil nếu sửa được.
    let blocker: String?
}

/// Trạng thái một thẻ định dạng của một visual, cho giao diện (`specs/006-d4-format-pane/data-model.md`).
struct FormatCardState: Equatable {
    let card: FormatCard
    /// Khoá có trong file.
    let isPresent: Bool
    /// Có mục chung để sửa (hoặc chưa có khoá nên thêm được). `false`: khoá chỉ có mục theo trường hoặc điểm dữ liệu.
    let isEditable: Bool
    /// Giá trị hiện có của các thuộc tính trong mục chung (thuộc tính vắng mặt không có khoá).
    let values: [String: FormatValue]
    /// Các chuỗi đặt được định dạng riêng (thẻ có `seriesProperties`); rỗng khi thẻ không có, hoặc visual có trường ở ô Chú giải.
    var series: [FormatSeriesState] = []
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

    /// Các chuỗi của visual. Không có trường ở ô Chú giải: measure ở ô `Y` rồi `Y2`, theo thứ tự trong ô (khoá là `queryRef`,
    /// ghi `selector.metadata`). Có trường ở ô Chú giải: các giá trị của cột đó đang hiện trên biểu đồ (`legendValuesProvider`,
    /// theo thứ tự dữ liệu) rồi các giá trị mà `entries` đã có mục riêng nhưng không còn trong dữ liệu (khoá `data:<literal>`;
    /// giá trị chưa có mục thì Desktop tạo mục mới, VM-D9 mục 2).
    func formatSeries(of visual: ReportVisual, entries: [JSONValue]) -> [(queryRef: String, title: String)] {
        if let legend = colourColumn(of: visual) {
            var seen = Set<String>()
            let live = legendValuesProvider(visual.id).map { (FormatCatalog.legendPrefix + $0, FormatCatalog.legendTitle($0)) }
            let existing = entries.compactMap { entry -> (String, String)? in
                guard let value = FormatCatalog.legendValue(of: entry), value.entity == legend.entity, value.property == legend.property else { return nil }
                return (FormatCatalog.legendPrefix + value.literal, FormatCatalog.legendTitle(value.literal))
            }
            return (live + existing).filter { seen.insert($0.0).inserted }
        }
        var seen = Set<String>()
        return FormatCatalog.seriesRoles.sorted().flatMap { role in
            visual.fields.filter { $0.role == role && ($0.kind == .measure || $0.kind == .aggregation) }
        }
        .filter { seen.insert($0.queryRef).inserted }
        .map { ($0.queryRef, $0.displayName ?? $0.property) }
    }

    /// Cột mà màu chia theo giá trị: trường ở ô Chú giải; hoặc, ở cột nhóm không có Chú giải và chỉ một measure, cột `Category`
    /// duy nhất (Desktop: "Apply settings to" > "Categories", mỗi điểm dữ liệu một mục `dataPoint`, VM-D10). Loại khác chưa quan sát.
    func colourColumn(of visual: ReportVisual) -> ReportField? {
        if let legend = visual.fields.first(where: { $0.role == FormatCatalog.legendRole }) { return legend }
        guard visual.type == "clusteredColumnChart" else { return nil }
        let measures = visual.fields.filter { FormatCatalog.seriesRoles.contains($0.role) && ($0.kind == .measure || $0.kind == .aggregation) }
        let categories = visual.fields.filter { $0.role == "Category" }
        guard measures.count == 1, categories.count == 1, categories[0].kind == .column else { return nil }
        return categories[0]
    }

    private static let seriesBlocker = "Chuỗi này đang tô màu theo công thức hoặc theo điểm dữ liệu, chưa sửa được."

    /// Chuỗi `ref` có mục không phải mục riêng thuần (selector có thêm `data`): không ghi đè.
    private func seriesBlocker(_ ref: String, in entries: [JSONValue]) -> String? {
        entries.contains { $0["selector"]?["metadata"]?.string == ref && FormatCatalog.seriesRef(of: $0) == nil } ? Self.seriesBlocker : nil
    }

    /// Mục chung thêm được vào cuối mảng khi mảng chỉ có mục theo chuỗi (VM-D8 mục 6); cạnh mục kiểu khác thì chưa quan sát.
    private func acceptsCommonEntry(_ card: FormatCard, _ entries: [JSONValue]) -> Bool {
        if entries.isEmpty || entries.contains(where: FormatCatalog.isEditable) { return true }
        // Cạnh mục theo giá trị Chú giải thì mục chung chưa quan sát.
        return !card.seriesProperties.isEmpty && entries.allSatisfy { FormatCatalog.seriesRef(of: $0).map { !$0.hasPrefix(FormatCatalog.legendPrefix) } ?? false }
    }

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
                var state = FormatCardState(card: card, isPresent: !entries.isEmpty, isEditable: acceptsCommonEntry(card, entries), values: values)
                guard !card.seriesProperties.isEmpty else { return state }
                state.series = formatSeries(of: visual, entries: entries).map { series in
                    let own = entries.first { FormatCatalog.seriesRef(of: $0) == series.queryRef }
                    var values: [String: FormatValue] = [:]
                    for property in card.seriesProperties {
                        if let value = FormatValue.read(own?["properties"]?[property.key], kind: property.kind) { values[property.key] = value }
                    }
                    return FormatSeriesState(queryRef: series.queryRef, title: series.title, values: values,
                                             blocker: seriesBlocker(series.queryRef, in: entries))
                }
                return state
            }
        }
        let readOnly = FormatScope.allCases.flatMap { FormatCatalog.readOnlyItems(in: scopeJSON(of: visual, $0), type: visual.type, scope: $0) }
        return FormatState(visualID: id, type: visual.type, objects: states(.objects), container: states(.container),
                           readOnly: readOnly, blocker: formatEditingBlocker(for: id))
    }

    // MARK: Ghi

    /// Đặt `property` của khoá `object` trong phạm vi `scope` của visual `id`. Trả lý do từ chối (cũng ghi ở `fieldRefusal`) hoặc nil.
    /// Giá trị bằng giá trị hiện có thì không tạo bước. Nhiều lần đặt liên tiếp cùng thuộc tính gộp thành một bước.
    /// `series`: `queryRef` của chuỗi khi đặt định dạng riêng của một chuỗi (màu cột, thanh, đường); nil là mục chung.
    @discardableResult
    func setFormat(_ value: FormatValue, scope: FormatScope, object: String, property: String, visual id: String, series: String? = nil) -> String? {
        resetMessages()
        func refuse(_ message: String) -> String { noteFieldRefusal(message); return message }
        guard let pageID = currentPageID else { return refuse("Chưa mở trang nào.") }
        if let blocker = formatEditingBlocker(for: id) { return refuse(blocker) }
        guard let visual = visual(id) else { return refuse("Không tìm thấy visual.") }
        guard let card = FormatCatalog.cards(for: visual.type, scope: scope).first(where: { $0.objectKey == object }) else {
            return refuse("Thuộc tính này chưa quan sát ở Power BI Desktop nên chưa sửa được.")
        }
        let entries = scopeJSON(of: visual, scope)?[object]?.array ?? []
        let spec: FormatProperty, target: JSONValue?
        if let series {
            guard let found = card.seriesProperties.first(where: { $0.key == property }) else {
                return refuse("Thuộc tính này chưa quan sát theo từng chuỗi ở Power BI Desktop nên chưa sửa được.")
            }
            if let reason = seriesRefusal(series, visual: visual, entries: entries) { return refuse(reason) }
            spec = found
            target = entries.first { FormatCatalog.seriesRef(of: $0) == series }
        } else {
            guard let found = card.properties.first(where: { $0.key == property }) else {
                if card.seriesProperties.contains(where: { $0.key == property }) {
                    return refuse("Chọn một chuỗi để đổi thuộc tính này (Power BI Desktop cũng khoá khi chọn Tất cả).")
                }
                return refuse("Thuộc tính này chưa quan sát ở Power BI Desktop nên chưa sửa được.")
            }
            if !acceptsCommonEntry(card, entries) { return refuse("Thẻ này có định dạng riêng theo trường hoặc điểm dữ liệu, chưa sửa được.") }
            spec = found
            target = entries.first(where: FormatCatalog.isEditable)
        }
        if let reason = value.validate(kind: spec.kind) { return refuse(reason) }
        let existing = target?["properties"]?[property]
        if existing == nil, !spec.addable { return refuse("Thuộc tính này chỉ sửa được khi file đã có giá trị.") }
        var tail: NumberTail?
        if case .number(_, let existingTail)? = FormatValue.read(existing, kind: spec.kind) { tail = existingTail }
        let json: String
        do { json = try value.json(kind: spec.kind, keepingTail: tail) } catch { return refuse("\(error)") }
        if let existing, let new = try? JSONValue.parse(json), existing == new { return nil }
        var legendColumn: FormatEdit.LegendColumn?
        if series?.hasPrefix(FormatCatalog.legendPrefix) == true, let legend = colourColumn(of: visual) {
            legendColumn = .init(entity: legend.entity, property: legend.property)
        }
        let edit = FormatEdit(scope: scope, object: object, action: .set(property: property, value: json),
                              selectorDefault: card.usesDefaultSelector, selectorMetadata: series, legendColumn: legendColumn)
        let key = FormatTarget(visualID: id, scope: scope, object: object, property: property, series: series).coalesceKey
        return applyFormat(edit, visual: id, page: pageID, coalesce: key)
    }

    /// Lý do không đặt được định dạng riêng cho chuỗi `series` của `visual`, hoặc nil.
    private func seriesRefusal(_ series: String, visual: ReportVisual, entries: [JSONValue]) -> String? {
        let list = formatSeries(of: visual, entries: entries)
        if !list.contains(where: { $0.queryRef == series }) {
            if colourColumn(of: visual) != nil {
                return "Màu theo giá trị (Chú giải hoặc danh mục): giá trị này không có trong dữ liệu đang hiện."
            }
            return "Chuỗi này không có trong visual."
        }
        return seriesBlocker(series, in: entries)
    }

    /// Đặt lại về mặc định: cả thẻ (`property` nil, bỏ cả khoá) hoặc một thuộc tính. Khoá hoặc thuộc tính không có trong file
    /// thì không làm gì (không tạo bước). `series`: đặt lại một thuộc tính ở mục riêng của chuỗi đó (cần `property`).
    @discardableResult
    func resetFormat(scope: FormatScope, object: String, property: String? = nil, visual id: String, series: String? = nil) -> String? {
        resetMessages()
        func refuse(_ message: String) -> String { noteFieldRefusal(message); return message }
        guard let pageID = currentPageID else { return refuse("Chưa mở trang nào.") }
        if let blocker = formatEditingBlocker(for: id) { return refuse(blocker) }
        guard let visual = visual(id) else { return refuse("Không tìm thấy visual.") }
        guard let card = FormatCatalog.cards(for: visual.type, scope: scope).first(where: { $0.objectKey == object }) else {
            return refuse("Thẻ này chưa quan sát ở Power BI Desktop nên chưa sửa được.")
        }
        let entries = scopeJSON(of: visual, scope)?[object]?.array ?? []
        guard !entries.isEmpty else { return nil }
        let editable = entries.first(where: FormatCatalog.isEditable)
        if let series {
            guard let property, card.seriesProperties.contains(where: { $0.key == property }) else {
                return refuse("Thuộc tính này chưa quan sát theo từng chuỗi ở Power BI Desktop nên chưa sửa được.")
            }
            guard entries.first(where: { FormatCatalog.seriesRef(of: $0) == series })?["properties"]?[property] != nil else { return nil }
            let edit = FormatEdit(scope: scope, object: object, action: .removeProperty(property), selectorMetadata: series)
            return applyFormat(edit, visual: id, page: pageID, coalesce: nil)
        }
        if let property {
            guard editable?["properties"]?[property] != nil else { return nil }
            return applyFormat(FormatEdit(scope: scope, object: object, action: .removeProperty(property)), visual: id, page: pageID, coalesce: nil)
        }
        let hasSeriesEntries = !card.seriesProperties.isEmpty && entries.contains { FormatCatalog.seriesRef(of: $0) != nil }
        if hasSeriesEntries {
            // Đặt lại cả thẻ ở "Tất cả" chỉ bỏ phần chung; màu riêng của từng chuỗi nằm lại (đặt lại ở từng chuỗi).
            if entries.contains(where: { !FormatCatalog.isEditable($0) && FormatCatalog.seriesRef(of: $0) == nil }) {
                return refuse("Thẻ này có định dạng riêng theo trường hoặc điểm dữ liệu, chưa đặt lại được.")
            }
            let keys = editable?["properties"]?.object.keys.sorted() ?? []
            guard !keys.isEmpty else { return nil }
            return applyFormats(keys.map { FormatEdit(scope: scope, object: object, action: .removeProperty($0)) }, visual: id, page: pageID, coalesce: nil)
        }
        if entries.contains(where: { !FormatCatalog.isEditable($0) }) {
            return refuse("Thẻ này có định dạng riêng theo trường hoặc điểm dữ liệu, chưa đặt lại được.")
        }
        return applyFormat(FormatEdit(scope: scope, object: object, action: .removeObject), visual: id, page: pageID, coalesce: nil)
    }

    /// Dựng `visual.json` mới, cập nhật `raw`, `objects`, `containerObjects` từ chính chuỗi byte đó (cái vẽ chính là cái sẽ lưu)
    /// và ghi một bước hoàn tác.
    private func applyFormat(_ edit: FormatEdit, visual id: String, page pageID: String, coalesce key: String?) -> String? {
        applyFormats([edit], visual: id, page: pageID, coalesce: key)
    }

    /// Như `applyFormat` cho một nhóm lệnh làm cùng một bước hoàn tác.
    private func applyFormats(_ edits: [FormatEdit], visual id: String, page pageID: String, coalesce key: String?) -> String? {
        func refuse(_ message: String) -> String { noteFieldRefusal(message); return message }
        let isNew = edited[pageID]?.added[id] != nil
        var formats = edited[pageID]?.formats[id] ?? []
        let bytes: Data, raw: JSONValue
        do {
            if isNew {
                guard let current = edited[pageID]?.added[id] else { return refuse("Không tìm thấy visual.") }
                bytes = try PBIRFormatPatch.apply(edits, to: current)
            } else {
                for edit in edits { formats = FormatEdit.merging(formats, adding: edit) }
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
