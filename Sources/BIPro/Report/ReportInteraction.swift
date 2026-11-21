// Gói G (Phase C, lead): nối trạng thái lọc/tương tác với truy vấn và renderer.
//
// - Giữ một `FilterState` cho mỗi trang (slicer, điểm đang chọn…). Mỗi visual dữ liệu lắng nghe trạng thái trang của mình:
//   đổi trạng thái thì dựng lại truy vấn rồi nạp lại (cache theo văn bản DAX nên visual không đổi bộ lọc thì trả về ngay).
// - Dựng `VisualQuerySpec` từ visual (bộ đọc Q), ghép bộ lọc tĩnh (visual, trang, báo cáo) với slicer và lọc chéo bằng
//   `FilterTranslator.assemble` (gói I), chạy qua `VisualDataLoader`, đưa `DataView` cho renderer.
import DAXEngine
import Foundation
import Observation
import PBIXKit

/// Kết quả nạp của một visual: spec (để biết cột nhóm), DataView và truy vấn đã chạy.
struct LiveVisualData: Sendable {
    let spec: VisualQuerySpec
    let view: DataView
    let query: String
    let elapsed: Duration
}

@MainActor
@Observable
final class ReportInteraction {
    let workspace: Workspace
    /// Trang của báo cáo đang sửa (D5: thêm, xoá, đổi tên). `DocumentState` đặt; không đặt thì là trang của file.
    @ObservationIgnored var pagesProvider: (() -> [ReportPage])?
    /// Bookmark của file mà thao tác xoá trang đã gỡ trong phiên (ẩn khỏi danh sách).
    @ObservationIgnored var removedBookmarksProvider: (() -> Set<String>)?
    /// `page.json` của trang tạo trong phiên (nhân bản): để đọc bộ lọc cấp trang của chúng.
    @ObservationIgnored var pageJSONProvider: ((String) -> Data?)?
    var pages: [ReportPage] { pagesProvider?() ?? workspace.report.pages }
    var visiblePages: [ReportPage] { pages.filter { !$0.isHidden } }
    /// Trạng thái lọc theo trang (khoá = id trang).
    var states: [String: FilterState] = [:]
    /// Phiên bản mô hình hiệu lực (Phase E): đổi thì mọi visual nạp lại vì measure, quan hệ hoặc cột có thể đã đổi.
    var modelVersion = 0
    /// Dữ liệu đã nạp gần nhất của từng visual (dùng cho Xuất CSV tức thì và tóm tắt VoiceOver — Phase G).
    var loadedDataViews: [String: DataView] = [:]

    /// Mô hình hiệu lực đổi (Phase E): bỏ bộ đọc spec và bộ nạp đã dựng trên mô hình cũ (kèm bộ nhớ đệm kết quả) và báo visual nạp lại.
    func modelDidChange() {
        servicesTask?.cancel()
        servicesTask = nil
        servicesGeneration += 1
        loadedDataViews = [:]
        modelVersion += 1
    }

    /// Cấp drill hiện tại của từng visual (0 = cấp gốc), khoá = id visual.
    var drillDepth: [String: Int] = [:]
    /// Slicer hierarchy: giá trị cấp gốc đang mở nút do người dùng đặt (ghi đè `expansionStates` trong file).
    var slicerExpansion: [String: [Value]] = [:]
    /// Matrix: các nút cột đang mở (đường giá trị từ cấp gốc) do người dùng đặt, khoá = id visual.
    var matrixExpansion: [String: [[Value]]] = [:]
    /// Matrix: các nút hàng đang mở (đường giá trị từ cấp gốc, Wave 3A / VM-V11B), khoá = id visual.
    var matrixRowExpansion: [String: [[Value]]] = [:]

    /// Ẩn/hiện visual do Selection pane và bookmark đặt (gói P).
    var visibility = VisibilityState()
    /// Bộ lọc Basic người dùng sửa ở Filters pane (gói P). Áp cho mọi visual nên đổi là mọi visual nạp lại (có cache theo văn bản).
    var userFilters: [UserFilterKey: UserFilter] = [:]
    /// Thẻ bộ lọc trong file mà người dùng đã bỏ (không áp nữa).
    var removedFilters: Set<UserFilterKey> = []

    /// Bookmark thêm hoặc cập nhật trong phiên, bookmark trong file đã xoá hoặc đổi tên (xem `UserBookmark.swift`).
    var userBookmarks: [UserBookmark] = []
    var deletedBookmarkIDs: Set<String> = []
    var renamedBookmarks: [String: String] = [:]

    /// Nối với bộ sửa tài liệu (D6): `DocumentState` đặt. Có thì sửa bộ lọc và bookmark đi vào lớp tài liệu (chỉ ở chế độ Sửa);
    /// không có (test, nơi khác) thì như trước: chỉ lớp phiên.
    @ObservationIgnored var editing: ReportEditing?

    /// Thay đổi cấp tài liệu hiện có (rỗng khi không nối).
    var documentEdits: ReportEdits { editing?.edits() ?? ReportEdits() }
    /// Bộ lọc người dùng hiệu lực: lớp tài liệu rồi lớp phiên (áp bookmark, trạng thái xem đè lên).
    var effectiveUserFilters: [UserFilterKey: UserFilter] { ReportEdits.effectiveFilters(edits: documentEdits, session: userFilters) }
    var effectiveRemovedFilters: Set<UserFilterKey> { ReportEdits.effectiveRemovals(edits: documentEdits, session: removedFilters) }

    @ObservationIgnored private var servicesTask: Task<(VisualQuerySpecReader, VisualDataLoader), Error>?
    /// Tăng khi mô hình đổi: kết quả dựng bộ nạp của phiên bản cũ bị bỏ và dựng lại.
    @ObservationIgnored private var servicesGeneration = 0
    @ObservationIgnored private var topoMap: TopoMap?

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    /// Có mô hình để chạy truy vấn hay không.
    var isAvailable: Bool { workspace.metadata != nil && workspace.abf != nil }

    // MARK: - Trạng thái

    func state(for page: ReportPage) -> FilterState {
        states[page.id] ?? FilterState(slicerOrder: page.visuals.filter { Self.slicerTypes.contains($0.type) }.map(\.id))
    }

    func update(page: ReportPage, _ change: (inout FilterState) -> Void) {
        var state = state(for: page)
        change(&state)
        states[page.id] = state
    }

    func setSlicer(page: ReportPage, visualID: String, columns: [QueryColumn], selection: SlicerSelection) {
        update(page: page) { $0.setSlicer(visualID: visualID, columns: columns, selection: selection) }
    }

    func select(page: ReportPage, visual: ReportVisual, spec: VisualQuerySpec, point: DataPointID?, additive: Bool) {
        guard InteractionRules.canSelect(visualType: visual.type) else { return }
        let columns = (spec.primary + spec.secondary).map { CrossColumn(queryRef: $0.field.queryRef, column: $0.column) }
        update(page: page) {
            $0.selection.select(point, additive: additive,
                                from: InteractionTarget(visualID: visual.id, visualType: visual.type), columns: columns)
        }
    }

    /// Bấm ra ngoài mọi visual: bỏ lựa chọn điểm dữ liệu (lọc chéo, tô sáng) của trang, như Power BI.
    func clearSelection(page: ReportPage) {
        guard !state(for: page).selection.points.isEmpty else { return }
        update(page: page) { $0.selection.select(nil, additive: false, from: InteractionTarget(visualID: "", visualType: ""), columns: []) }
    }

    // MARK: - Ẩn/hiện và bookmark (gói P)

    func isHidden(_ visual: ReportVisual) -> Bool { visibility.isHidden(visual) }

    func toggleHidden(_ visual: ReportVisual) { visibility.toggle(visual) }

    /// Áp bookmark theo id. Trả id trang cần chuyển tới (nếu bookmark đổi trang).
    func applyBookmark(id: String) -> String? {
        guard let bookmark = workspace.bookmarks.first(where: { $0.id == id }) else { return nil }
        return apply(bookmark)
    }

    /// Áp một bookmark (tách riêng để test với bookmark dựng tay).
    @discardableResult
    func apply(_ bookmark: ReportBookmark) -> String? {
        // [SUY ĐOÁN] Bookmark không `suppressData` khôi phục bộ lọc và slicer đã lưu (VM-TODO-C2.md, mục B1).
        if !bookmark.suppressData, let data = bookmark.data { applyBookmarkData(data) }
        return visibility.apply(bookmark)
    }

    /// Đặt lại bộ lọc người dùng sửa ở các phạm vi bookmark có ghi, rồi áp bộ lọc và lựa chọn slicer của bookmark.
    private func applyBookmarkData(_ data: BookmarkData) {
        let scopes = Set([""] + Array(data.pageFilters.keys) + Array(data.visualFilters.keys))
        userFilters = userFilters.filter { !scopes.contains($0.key.scope) }
        removedFilters = removedFilters.filter { !scopes.contains($0.scope) }

        func put(_ filters: [ReportFilter], level: ReportFilter.Level, scope: String, existing: [ReportFilter]) {
            for filter in filters {
                guard let user = UserFilter.from(filter) else { continue }
                let known = existing.contains { $0.id == filter.id }
                // Bộ lọc trong file mà bookmark đặt về "Tất cả" vẫn phải ghi đè bộ lọc của file.
                guard known || user.isActive else { continue }
                let id = known ? filter.id : "added-\(user.column.table).\(user.column.column)"
                userFilters[UserFilterKey(level: level, scope: scope, filterID: id)] = user
            }
        }
        put(data.reportFilters, level: .report, scope: "", existing: workspace.reportFilters)
        for (pageID, list) in data.pageFilters {
            put(list, level: .page, scope: pageID, existing: workspace.pageFilters[pageID] ?? [])
        }
        for (visualID, list) in data.visualFilters {
            put(list, level: .visual, scope: visualID, existing: workspace.visualFilters[visualID] ?? [])
        }

        // Slicer của các trang có trong bookmark: lấy lựa chọn đã lưu, không có thì bỏ chọn.
        for pageID in data.pageFilters.keys {
            guard let page = pages.first(where: { $0.id == pageID }) else { continue }
            for visual in page.visuals where Self.slicerTypes.contains(visual.type) && data.visualFilters[visual.id] != nil {
                let columns = slicerColumns(of: visual)
                guard !columns.isEmpty else { continue }
                let paths = data.slicerFilters[visual.id].map(Self.slicerPaths) ?? []
                setSlicer(page: page, visualID: visual.id, columns: columns, selection: SlicerSelection(paths))
            }
        }
    }

    /// Cột của slicer: cột trực tiếp, hoặc cột của từng cấp hierarchy (slicer Năm › Quý), theo thứ tự trường.
    private func slicerColumns(of visual: ReportVisual) -> [QueryColumn] {
        visual.fields.compactMap { field -> QueryColumn? in
            switch field.kind {
            case .column: return QueryColumn(table: field.entity, column: field.property)
            case .hierarchyLevel:
                return workspace.levelColumn(field)
            default: return nil
            }
        }
    }

    private static let slicerTypes: Set<String> = ["slicer", "advancedSlicerVisual", "listSlicer", "textSlicer"]

    /// Các đường chọn (một giá trị cho mỗi cấp) trong `Where[0].Condition.In.Values` của lựa chọn slicer.
    nonisolated static func slicerPaths(_ filter: JSONValue) -> Set<[Value]> {
        let values = filter["Where"]?[0]?["Condition"]?["In"]?["Values"]?.array ?? []
        var out: Set<[Value]> = []
        for tuple in values {
            let path = tuple.array.compactMap { UserFilter.value(of: $0) }
            if !path.isEmpty, path.count == tuple.array.count { out.insert(path) }
        }
        return out
    }

    // MARK: - Bộ lọc người dùng sửa (gói P)

    /// Đặt bộ lọc Basic cho một thẻ. `nil` hoặc không có giá trị nào = bỏ bộ lọc do người dùng đặt, quay về bản trong file.
    func setUserFilter(_ filter: UserFilter?, for key: UserFilterKey) {
        if let editing {
            guard editing.blocker() == nil else { return }
            userFilters[key] = nil
            removedFilters.remove(key)
            if let filter { editing.setFilter(filter, key) } else { editing.resetFilter(key) }
            return
        }
        userFilters[key] = filter
    }

    struct MeasureRef: Hashable, Sendable { var table: String; var name: String }

    /// Measure của model, để chọn trong Top N. Bỏ measure ẩn và measure phụ của định dạng động.
    func measureRefs() -> [MeasureRef] {
        (workspace.metadata?.measures ?? []).filter { !$0.isHidden && !$0.name.hasPrefix("_") }
            .map { MeasureRef(table: $0.tableName, name: $0.name) }
            .sorted { ($0.name, $0.table) < ($1.name, $1.table) }
    }

    private func dataType(of column: QueryColumn) -> ModelMetadata.DataType? {
        workspace.metadata?.columns.first { $0.tableName == column.table && $0.name == column.column }?.dataType
    }

    func isNumeric(_ column: QueryColumn) -> Bool { dataType(of: column)?.isNumeric ?? false }
    func isDate(_ column: QueryColumn) -> Bool { dataType(of: column) == .dateTime }

    /// Cột của các bảng người dùng (không ẩn), theo bảng, để chọn khi thêm thẻ bộ lọc.
    func filterableColumns() -> [(table: String, columns: [String])] {
        guard let metadata = workspace.metadata else { return [] }
        let tables = metadata.tables.filter { $0.isUserTable && !$0.isHidden }.map(\.name).sorted()
        return tables.map { table in
            (table, metadata.columns.filter { $0.tableName == table && !$0.isHidden && $0.kind == .data || $0.tableName == table && !$0.isHidden && $0.kind == .calculated }
                .map(\.name).sorted())
        }.filter { !$0.columns.isEmpty }
    }

    /// Thêm thẻ bộ lọc cho một cột ở cấp và phạm vi đã cho (chưa lọc gì cho tới khi người dùng chọn).
    func addFilter(column: QueryColumn, level: ReportFilter.Level, scope: String) {
        let key = UserFilterKey(level: level, scope: scope, filterID: "added-\(column.table).\(column.column)")
        if let editing {
            guard editing.blocker() == nil else { return }
            removedFilters.remove(key)
            userFilters[key] = nil
            if effectiveUserFilters[key] == nil { editing.setFilter(UserFilter(column: column), key) }
            return
        }
        removedFilters.remove(key)
        if userFilters[key] == nil { userFilters[key] = UserFilter(column: column) }
    }

    /// Bỏ thẻ: thẻ thêm tay thì xoá hẳn, thẻ trong file thì ẩn đi và không áp nữa.
    func removeFilter(_ key: UserFilterKey) {
        if let editing {
            guard editing.blocker() == nil else { return }
            let column = effectiveUserFilters[key]?.column
            userFilters[key] = nil
            removedFilters.remove(key)
            editing.removeFilter(key, column)
            return
        }
        userFilters[key] = nil
        if !key.filterID.hasPrefix("added-") { removedFilters.insert(key) }
    }

    /// Chuỗi định dạng của cột trong model (nil nếu không có), để hiện giá trị trong Filters pane như trên visual.
    func formatString(of column: QueryColumn) -> String? {
        workspace.metadata?.columns.first { $0.tableName == column.table && $0.name == column.column }?.formatString
    }

    /// Bộ lọc thấy được của một thẻ sau khi áp phần người dùng sửa, để Filters pane hiện lại đúng trạng thái.
    func effective(_ filter: ReportFilter, key: UserFilterKey) -> UserFilter? {
        effectiveUserFilters[key] ?? UserFilter.from(filter)
    }

    /// Giá trị phân biệt của một cột, xếp tăng dần, để Filters pane liệt kê. Ném `DAXError`.
    func distinctValues(of column: QueryColumn, limit: Int = 1000) async throws -> [Value] {
        let (_, loader) = try await services()
        return try await loader.distinctValues(of: column, limit: limit)
    }

    // MARK: - Mở nút

    /// Mở nút cấp gốc `path[0]` của slicer hierarchy (nạp lại để lấy các cấp con). Đóng nút chỉ ẩn phía giao diện.
    /// Matrix: bấm +/− trên tiêu đề cột cấp gốc thì mở hoặc đóng nút đó.
    func expandSlicer(visual: ReportVisual, spec: VisualQuerySpec, path: [Value]) {
        if spec.shape == .matrix { return expandMatrix(visual: visual, spec: spec, path: path) }
        guard path.count == 1, spec.drillLevels.count >= 2 else { return }
        var current = slicerExpansion[visual.id] ?? spec.expanded
        if !current.contains(path[0]) { current.append(path[0]) }
        slicerExpansion[visual.id] = current
    }

    /// Matrix: bấm + mở nút `path` (xuống một cấp), bấm − đóng nút đó cùng mọi nút con đang mở. Mở được tới cấp áp chót.
    func expandMatrix(visual: ReportVisual, spec: VisualQuerySpec, path: [Value]) {
        guard !path.isEmpty, path.count < spec.drillLevels.count else { return }
        var current = matrixExpansion[visual.id] ?? spec.expandedPaths
        if current.contains(path) {
            current.removeAll { $0.count >= path.count && Array($0.prefix(path.count)) == path }
        } else {
            current.append(path)
        }
        matrixExpansion[visual.id] = current
    }

    /// Matrix phân cấp hàng (Wave 3A): bấm + mở nút hàng `path`, bấm − đóng nút đó cùng mọi nút con đang mở.
    func expandMatrixRow(visual: ReportVisual, spec: VisualQuerySpec, path: [Value]) {
        guard !path.isEmpty, path.count < spec.rowDrillLevels.count else { return }
        var current = matrixRowExpansion[visual.id] ?? spec.rowExpandedPaths
        if current.contains(path) {
            current.removeAll { $0.count >= path.count && Array($0.prefix(path.count)) == path }
        } else {
            current.append(path)
        }
        matrixRowExpansion[visual.id] = current
    }

    // MARK: - Drill

    func depth(of visual: ReportVisual) -> Int { drillDepth[visual.id] ?? 0 }

    /// Drill down vào một điểm: sang cấp kế, các cấp trên thành bộ lọc drill (C1.md §2.2: `year IN {2016}`).
    func drillDown(page: ReportPage, visual: ReportVisual, spec: VisualQuerySpec, point: DataPointID) {
        let d = depth(of: visual)
        guard d + 1 < spec.drillLevels.count else { return }
        let level = spec.drillLevels[d]
        guard let value = point.values[level.field.queryRef] else { return }
        update(page: page) { $0.drillFilters[visual.id, default: []].append(ColumnValues(column: level.column, values: [value])) }
        drillDepth[visual.id] = d + 1
    }

    func drillUp(page: ReportPage, visual: ReportVisual) {
        let d = depth(of: visual)
        guard d > 0 else { return }
        update(page: page) {
            if var list = $0.drillFilters[visual.id], !list.isEmpty {
                list.removeLast()
                $0.drillFilters[visual.id] = list.isEmpty ? nil : list
            }
        }
        drillDepth[visual.id] = d - 1
    }

    /// "Show next level": xuống một cấp cho cả trục, không lọc.
    func nextLevel(visual: ReportVisual, spec: VisualQuerySpec) {
        let d = depth(of: visual)
        if d + 1 < spec.drillLevels.count { drillDepth[visual.id] = d + 1 }
    }

    // MARK: - Drillthrough

    /// Trang drillthrough mà điểm này dùng được: điểm có giá trị cho ít nhất một cột tham số của trang.
    func drillthroughTargets(from page: ReportPage, point: DataPointID) -> [(page: ReportPage, values: [ColumnValues])] {
        let alive = Set(pages.map(\.id))
        return workspace.drillthroughPages.compactMap { entry in
            guard entry.page.id != page.id, alive.contains(entry.page.id) else { return nil }
            let values = entry.columns.compactMap { column -> ColumnValues? in
                point.values["\(column.table).\(column.column)"].map { ColumnValues(column: column, values: [$0]) }
            }
            return values.isEmpty ? nil : (entry.page, values)
        }
    }

    /// Đặt tham số drillthrough cho trang đích (bộ lọc `TREATAS` đứng đầu, C1.md §2.2). Người gọi chuyển trang.
    func applyDrillthrough(to target: ReportPage, values: [ColumnValues]) {
        update(page: target) { $0.drillthrough = values }
    }

    // MARK: - Nạp dữ liệu

    /// Bản đồ TopoJSON nhúng trong file (shape map). nil nếu file không có.
    func shapeMap() -> TopoMap? {
        if let topoMap { return topoMap }
        guard let data = workspace.pbix.resource(named: "usa.states.topo.json"),
              let map = try? TopoJSON.decode(data) else { return nil }
        topoMap = map
        return map
    }

    /// Giá trị chữ của cột màu của từng visual đã nạp (literal `'…'`, theo thứ tự hiện): cột ở ô Chú giải, hoặc khi không có
    /// Chú giải thì cột Category duy nhất (màu theo điểm dữ liệu, VM-D10). Dùng cho thẻ định dạng.
    private(set) var legendValues: [String: [String]] = [:]

    private func recordLegendValues(of id: String, in view: DataView) {
        var values: [Value] = []
        if case .categorical(let data) = view {
            if data.seriesField != nil { values = data.series }
            else if data.categoryLevels.count == 1 { values = data.categories.compactMap { $0.values.first } }
        }
        let literals = values.compactMap { value -> String? in
            guard case .string(let text) = value else { return nil }
            return "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
        }
        if literals.isEmpty { if legendValues[id] != nil { legendValues[id] = nil }; return }
        if legendValues[id] != literals { legendValues[id] = literals }
    }

    /// Nạp dữ liệu của visual theo trạng thái lọc hiện tại của trang. Ném `DAXError` (kể cả `.cancelled`).
    func load(page: ReportPage, visual: ReportVisual, state: FilterState) async throws -> LiveVisualData {
        let (reader, loader) = try await services()
        var spec = try reader.spec(for: visual, filters: [])
        let statics = staticFilters(page: page, visual: visual)
        var effectiveState = state
        if !page.visualInteractions.isEmpty {
            let pageOverrides = page.visualInteractions.map { item -> InteractionOverride in
                let effect: InteractionEffect = switch item.type {
                case .dataFilter: .filter
                case .highlightFilter: .highlight
                case .noFilter: .none
                }
                return InteractionOverride(sourceID: item.source, targetID: item.target, effect: effect)
            }
            effectiveState.overrides = pageOverrides + state.overrides
        }
        let assembled = FilterTranslator.assemble(
            for: InteractionTarget(visualID: visual.id, visualType: visual.type), staticFilters: statics, state: effectiveState)
        VisualQuerySpecReader.applyDrill(&spec, depth: depth(of: visual))
        if let expanded = slicerExpansion[visual.id] { spec.expanded = expanded }
        if let paths = matrixExpansion[visual.id] { spec.expandedPaths = paths }
        if let rowPaths = matrixRowExpansion[visual.id] { spec.rowExpandedPaths = rowPaths }
        spec.filters = assembled.filters
        spec.valueFilters = valueFilters(for: visual)
        spec.highlight = assembled.highlight
        let loaded = try await loader.load(spec)
        var finalView = loaded.view
        if case .slicer(var slicerData) = finalView, let col = spec.primary.first?.column {
            let colIsDate = isDate(col)
            let colIsNumeric = isNumeric(col)
            slicerData.isDateColumn = colIsDate
            let mode = visual.objects.string("data", "mode")
            if visual.type == "slicer", mode == "Between" || (mode == nil && (colIsNumeric || colIsDate)) {
                slicerData.domainRange = try? await loader.columnRange(of: col, filters: spec.filters)
            }
            finalView = .slicer(slicerData)
        }
        recordLegendValues(of: visual.id, in: finalView)
        loadedDataViews[visual.id] = finalView
        return LiveVisualData(spec: spec, view: finalView, query: loaded.query, elapsed: loaded.elapsed)
    }

    /// Bộ lọc theo measure của visual (Power BI: `__ValueFilterDM0`, xem `DAXQueryBuilder`).
    func valueFilters(for visual: ReportVisual) -> [ValueFilter] {
        Self.valueFilters(visual: visualFilters(of: visual), visualID: visual.id, user: effectiveUserFilters, removed: effectiveRemovedFilters)
    }

    /// Thẻ measure của một visual thành bộ lọc dòng kết quả: thẻ người dùng sửa, và thẻ trong file chưa bị sửa hay bỏ.
    nonisolated static func valueFilters(visual: [ReportFilter], visualID: String, user: [UserFilterKey: UserFilter],
                                         removed: Set<UserFilterKey> = []) -> [ValueFilter] {
        var entries = user.filter { $0.key.level == .visual && $0.key.scope == visualID && $0.value.isMeasure }
            .map { (id: $0.key.filterID, filter: $0.value) }
        for filter in visual {
            let key = UserFilterKey(level: .visual, scope: visualID, filterID: filter.id)
            if removed.contains(key) || user[key] != nil { continue }
            if let read = UserFilter.from(filter), read.isMeasure { entries.append((filter.id, read)) }
        }
        return entries.sorted { $0.id < $1.id }.compactMap { entry in
            guard let rule = entry.filter.rule, rule.predicate(expression: "[x]") != nil else { return nil }
            return ValueFilter(table: entry.filter.column.table, measure: entry.filter.column.column, rule: rule)
        }
    }

    /// Bộ lọc cấp visual của một visual: của file (theo mã visual), hoặc đọc từ `filterConfig` của chính visual khi mã là mới
    /// trong phiên (bản sao visual hoặc trang nhân bản, D1 và D5) để bản sao vẽ cùng dữ liệu với bản gốc.
    func visualFilters(of visual: ReportVisual) -> [ReportFilter] {
        if let list = workspace.visualFilters[visual.id] { return list }
        return PBIXFile.filters(visual.raw["filterConfig"]?["filters"], level: .visual)
    }

    /// Bộ lọc cấp trang: của file (theo mã trang), hoặc đọc từ `filterConfig` của `page.json` khi trang tạo trong phiên (bản nhân bản).
    func pageFilters(of pageID: String) -> [ReportFilter] {
        if let list = workspace.pageFilters[pageID] { return list }
        guard let json = pageJSONProvider?(pageID), let value = try? JSONValue.parse(json) else { return [] }
        return PBIXFile.filters(value["filterConfig"]?["filters"], level: .page)
    }

    func staticFilters(page: ReportPage, visual: ReportVisual) -> [StaticFilter] {
        Self.mergeStatics(
            visual: visualFilters(of: visual), visualID: visual.id,
            page: pageFilters(of: page.id), pageID: page.id,
            report: workspace.reportFilters, user: effectiveUserFilters, removed: effectiveRemovedFilters)
    }

    /// Bộ lọc tĩnh sau khi áp phần người dùng sửa: thẻ trong file mà người dùng sửa thì thay vị từ (giữ vị trí), thẻ ngầm
    /// (field của visual chưa có bộ lọc trong file) thì thêm vào cuối nhóm cấp của nó.
    nonisolated static func mergeStatics(visual: [ReportFilter], visualID: String, page: [ReportFilter], pageID: String,
                                         report: [ReportFilter], user: [UserFilterKey: UserFilter],
                                         removed: Set<UserFilterKey> = []) -> [StaticFilter] {
        func group(_ list: [ReportFilter], level: ReportFilter.Level, scopeID: String, scope: FilterScope) -> [StaticFilter] {
            var out: [StaticFilter] = []
            var used = Set<String>()
            for filter in list {
                let key = UserFilterKey(level: level, scope: scopeID, filterID: filter.id)
                if removed.contains(key) { continue }
                if let edit = user[key] {
                    used.insert(filter.id)
                    if edit.isMeasure { continue } // bộ lọc theo measure đi đường `valueFilters`, không phải bảng lọc cột
                    if let predicate = edit.predicate { out.append(StaticFilter(column: edit.column, predicate: predicate, scope: scope)) }
                } else if let sf = VisualQuerySpecReader.staticFilter(filter, scope: scope) {
                    out.append(sf)
                }
            }
            let extras = user.filter { $0.key.level == level && $0.key.scope == scopeID && !used.contains($0.key.filterID) }
                .sorted { $0.key.filterID < $1.key.filterID }
            for (_, edit) in extras where !edit.isMeasure {
                if let predicate = edit.predicate { out.append(StaticFilter(column: edit.column, predicate: predicate, scope: scope)) }
            }
            return out
        }
        return group(visual, level: .visual, scopeID: visualID, scope: .visual)
            + group(page, level: .page, scopeID: pageID, scope: .page)
            + group(report, level: .report, scopeID: "", scope: .report)
    }

    /// Bộ đọc spec và bộ nạp dữ liệu, dựng một lần ngoài main thread (nạp lược đồ, tạo engine) rồi dùng chung.
    private func services() async throws -> (VisualQuerySpecReader, VisualDataLoader) {
        if let servicesTask {
            let generation = servicesGeneration
            let result = try await servicesTask.value
            if generation == servicesGeneration { return result }
            return try await services()
        }
        let generation = servicesGeneration
        let workspace = workspace
        let task = Task.detached { () throws -> (VisualQuerySpecReader, VisualDataLoader) in
            guard let metadata = workspace.metadata else {
                throw DAXError(.runtime, workspace.modelError ?? "File không có mô hình dữ liệu")
            }
            return (VisualQuerySpecReader(metadata: metadata), VisualDataLoader(engine: try workspace.daxEngine()))
        }
        servicesTask = task
        let result = try await task.value
        if generation != servicesGeneration { return try await services() }
        return result
    }
}

/// Cầu nối từ `ReportInteraction` tới bộ sửa tài liệu (D6): chặn khi không sửa được (Xem, báo cáo cũ), đặt, bỏ, đặt lại thẻ lọc.
struct ReportEditing {
    /// Lý do chưa sửa được; nil khi sửa được.
    var blocker: () -> String?
    var edits: () -> ReportEdits
    var setFilter: (UserFilter, UserFilterKey) -> Void
    var removeFilter: (UserFilterKey, QueryColumn?) -> Void
    var resetFilter: (UserFilterKey) -> Void
}
