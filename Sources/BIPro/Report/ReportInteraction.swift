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
    /// Trạng thái lọc theo trang (khoá = id trang).
    private(set) var states: [String: FilterState] = [:]

    /// Cấp drill hiện tại của từng visual (0 = cấp gốc), khoá = id visual.
    private(set) var drillDepth: [String: Int] = [:]

    @ObservationIgnored private var servicesTask: Task<(VisualQuerySpecReader, VisualDataLoader), Error>?
    @ObservationIgnored private var topoMap: TopoMap?

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    /// Có mô hình để chạy truy vấn hay không.
    var isAvailable: Bool { workspace.metadata != nil && workspace.abf != nil }

    // MARK: - Trạng thái

    func state(for page: ReportPage) -> FilterState {
        states[page.id] ?? FilterState(slicerOrder: page.visuals.filter { $0.type == "slicer" }.map(\.id))
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
        workspace.drillthroughPages.compactMap { entry in
            guard entry.page.id != page.id else { return nil }
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

    /// Nạp dữ liệu của visual theo trạng thái lọc hiện tại của trang. Ném `DAXError` (kể cả `.cancelled`).
    func load(page: ReportPage, visual: ReportVisual, state: FilterState) async throws -> LiveVisualData {
        let (reader, loader) = try await services()
        var spec = try reader.spec(for: visual, filters: [])
        let statics = staticFilters(page: page, visual: visual)
        let assembled = FilterTranslator.assemble(
            for: InteractionTarget(visualID: visual.id, visualType: visual.type), staticFilters: statics, state: state)
        VisualQuerySpecReader.applyDrill(&spec, depth: depth(of: visual))
        spec.filters = assembled.filters
        spec.highlight = assembled.highlight
        let loaded = try await loader.load(spec)
        return LiveVisualData(spec: spec, view: loaded.view, query: loaded.query, elapsed: loaded.elapsed)
    }

    private func staticFilters(page: ReportPage, visual: ReportVisual) -> [StaticFilter] {
        let visualList = workspace.visualFilters[visual.id] ?? []
        let pageList = workspace.pageFilters[page.id] ?? []
        return visualList.compactMap { VisualQuerySpecReader.staticFilter($0, scope: .visual) }
            + pageList.compactMap { VisualQuerySpecReader.staticFilter($0, scope: .page) }
            + workspace.reportFilters.compactMap { VisualQuerySpecReader.staticFilter($0, scope: .report) }
    }

    /// Bộ đọc spec và bộ nạp dữ liệu, dựng một lần ngoài main thread (nạp lược đồ, tạo engine) rồi dùng chung.
    private func services() async throws -> (VisualQuerySpecReader, VisualDataLoader) {
        if let servicesTask { return try await servicesTask.value }
        let workspace = workspace
        let task = Task.detached { () throws -> (VisualQuerySpecReader, VisualDataLoader) in
            guard let metadata = workspace.metadata else {
                throw DAXError(.runtime, workspace.modelError ?? "File không có mô hình dữ liệu")
            }
            return (VisualQuerySpecReader(metadata: metadata), VisualDataLoader(engine: try workspace.daxEngine()))
        }
        servicesTask = task
        return try await task.value
    }
}
