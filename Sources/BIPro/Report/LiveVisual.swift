// Gói G (Phase C, lead): visual dữ liệu chạy số thật.
//
// `LiveVisualView` nạp DataView của visual qua `ReportInteraction` rồi chọn renderer theo loại visual. Trong lúc nạp, hoặc khi
// visual chưa có renderer (bảng, multi-row card…), hiện bản giữ chỗ cũ (`DataPlaceholders`), nên canvas không bao giờ trống.
import DAXEngine
import PBIXKit
import SwiftUI

struct LiveVisualView: View {
    let workspace: Workspace
    let page: ReportPage
    let visual: ReportVisual
    let interaction: ReportInteraction
    let navigate: (String) -> Void

    private enum Phase {
        case loading
        case failed(String)
        case loaded(LiveVisualData)
    }

    @State private var phase: Phase = .loading
    /// Chế độ drill: bấm vào điểm là drill down (thay cho lọc chéo), như nút mũi tên xuống của Power BI.
    @State private var drillMode = false
    @State private var menu: MenuTarget?
    @State private var hover: MenuTarget?

    private struct MenuTarget: Equatable { var point: DataPointID?; var location: CGPoint }
    private struct LoadKey: Hashable { var visualType: String; var query: JSONValue?; var state: FilterState; var depth: Int; var expansion: [Value]; var matrixExpansion: [[Value]]; var userFilters: [UserFilterKey: UserFilter]; var removed: Set<UserFilterKey> }

    var body: some View {
        let state = interaction.state(for: page)
        let key = LoadKey(visualType: visual.type, query: visual.raw["visual"]?["query"], state: state, depth: interaction.depth(of: visual), expansion: interaction.slicerExpansion[visual.id] ?? [], matrixExpansion: interaction.matrixExpansion[visual.id] ?? [], userFilters: interaction.effectiveUserFilters.filter { ["", page.id, visual.id].contains($0.key.scope) },
                         removed: interaction.effectiveRemovedFilters.filter { ["", page.id, visual.id].contains($0.scope) })
        ZStack {
            content(state: state)
        }
        .task(id: key) { await load(state) }
    }

    @ViewBuilder
    private func content(state: FilterState) -> some View {
        switch phase {
        case .loading:
            placeholder
        case .failed(let message):
            placeholder.overlay(alignment: .bottomLeading) {
                Text(message).font(.system(size: 10)).foregroundStyle(.red).lineLimit(2).padding(4)
            }
        case .loaded(let data):
            rendered(data, state: state)
        }
    }

    /// Visual có cấu hình trường nhưng chưa còn trường nào để vẽ (vừa bỏ hết trường ở Build pane).
    private var needsFields: Bool {
        (visual.raw["visual"]?["query"]?["queryState"] != nil || !WellRules.rules(for: visual).isEmpty)
            && !visual.fields.contains { $0.role != "Tooltips" }
    }

    @ViewBuilder
    private var placeholder: some View {
        if needsFields {
            ZStack {
                Rectangle().fill(Color.white)
                Text("Thêm trường để vẽ").font(.system(size: 12)).foregroundStyle(DS.Palette.tertiaryLabel)
            }
        } else {
            typedPlaceholder
        }
    }

    @ViewBuilder
    private var typedPlaceholder: some View {
        switch visual.type {
        case "card", "cardVisual", "multiRowCard", "kpi":
            CardPlaceholder(visual: visual, theme: workspace.theme)
        case "slicer", "advancedSlicerVisual", "listSlicer", "textSlicer":
            SlicerPlaceholder(visual: visual, theme: workspace.theme)
        case "tableEx", "pivotTable", "matrix", "table":
            TablePlaceholder(visual: visual, theme: workspace.theme)
        default:
            ChartPlaceholder(visual: visual, theme: workspace.theme)
        }
    }

    // MARK: - Renderer

    @ViewBuilder
    private func rendered(_ data: LiveVisualData, state: FilterState) -> some View {
        let context = renderContext(data, state: state)
        ZStack(alignment: .topLeading) {
            renderedBody(data.view, context: context)
            if data.spec.drillLevels.count > 1 { drillControls(data.spec) }
            if menu == nil, let hover, let point = hover.point, case .categorical(let categorical) = data.view {
                let rows = VisualTooltip.rows(for: point, in: categorical)
                if !rows.isEmpty {
                    // Gần mép phải hoặc dưới thì tooltip lật sang trái hoặc lên trên để không bị cắt, như Power BI.
                    GeometryReader { geo in
                        let left = hover.location.x > geo.size.width * 0.6
                        let up = hover.location.y > geo.size.height * 0.7
                        VisualTooltipView(rows: rows, pointerOnRight: left)
                            .fixedSize()
                            .alignmentGuide(.leading) { d in left ? d.width : 0 }
                            .alignmentGuide(.top) { d in up ? d.height : 0 }
                            .offset(x: hover.location.x + (left ? -12 : 12), y: hover.location.y + (up ? -12 : 12))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .allowsHitTesting(false)
                }
            }
            if let menu { contextMenu(menu, spec: data.spec) }
        }
    }

    @ViewBuilder
    private func renderedBody(_ view: DataView, context: VisualRenderContext) -> some View {
        switch view {
        case .empty(let reason):
            placeholder.overlay(alignment: .bottomLeading) {
                Text(reason).font(.system(size: 10)).foregroundStyle(.secondary).padding(4)
            }
        case .single(let single):
            CardVisualView(data: single, context: context)
        case .slicer(let slicer):
            DropdownSlicerView(data: slicer, title: nil, context: context)
        case .matrix(let matrix):
            MatrixVisualView(data: matrix, context: context)
        case .categorical(let categorical):
            categoricalView(categorical, context: context)
        }
    }

    @ViewBuilder
    private func categoricalView(_ data: CategoricalData, context: VisualRenderContext) -> some View {
        switch visual.type {
        case "donutChart", "pieChart":
            DonutChartView(data: data, context: context)
        case "treemap":
            TreemapView(data: data, context: context)
        case "waterfallChart":
            WaterfallChartView(data: data, context: context)
        case "funnel":
            FunnelChartView(data: data, context: context)
        case "ribbonChart":
            RibbonChartView(data: data, context: context)
        case "shapeMap":
            if let map = interaction.shapeMap() {
                ShapeMapView(data: data, map: map, context: context)
            } else {
                placeholder
            }
        default:
            if let kind = CartesianKind(visualType: visual.type) {
                CartesianChartView(data: data, kind: kind, context: context)
            } else {
                placeholder
            }
        }
    }

    private func renderContext(_ data: LiveVisualData, state: FilterState) -> VisualRenderContext {
        let page = page, visual = visual, interaction = interaction
        let spec = data.spec
        var actions = VisualActions()
        let drillMode = drillMode
        actions.select = { point, additive in
            MainActor.assumeIsolated {
                menu = nil
                if drillMode, let point {
                    interaction.drillDown(page: page, visual: visual, spec: spec, point: point)
                } else {
                    interaction.select(page: page, visual: visual, spec: spec, point: point, additive: additive)
                }
            }
        }
        actions.hover = { point, location in
            MainActor.assumeIsolated { hover = point.map { MenuTarget(point: $0, location: location) } }
        }
        actions.contextMenu = { point, location in
            MainActor.assumeIsolated { menu = MenuTarget(point: point, location: location) }
        }
        actions.drill = { request in
            MainActor.assumeIsolated {
                switch request {
                case .down(let point): interaction.drillDown(page: page, visual: visual, spec: spec, point: point)
                case .up: interaction.drillUp(page: page, visual: visual)
                case .nextLevel, .expandAll: interaction.nextLevel(visual: visual, spec: spec)
                case .toggle(_, let path): interaction.expandSlicer(visual: visual, spec: spec, path: path)
                }
            }
        }
        actions.slicerChanged = { selection in
            MainActor.assumeIsolated {
                interaction.setSlicer(page: page, visualID: visual.id, columns: spec.primary.map(\.column), selection: selection)
            }
        }
        return VisualRenderContext(
            theme: workspace.theme,
            format: VisualFormat(objects: visual.objects),
            selection: state.selection.points(forVisual: visual.id),
            slicerSelection: state.slicers[visual.id]?.selection ?? SlicerSelection(),
            actions: actions)
    }

    // MARK: - Drill và menu chuột phải

    /// Ba nút ở góc trên phải: lên một cấp, chế độ drill (bấm điểm để xuống), xuống một cấp cho cả trục.
    private func drillControls(_ spec: VisualQuerySpec) -> some View {
        let depth = interaction.depth(of: visual)
        func button(_ symbol: String, _ help: String, on: Bool = false, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 4).fill(on ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35).help(help)
        }
        return HStack(spacing: 3) {
            button("arrow.up.left", "Lên một cấp", enabled: depth > 0) { interaction.drillUp(page: page, visual: visual) }
            button("arrow.down", "Chế độ drill: bấm điểm để xuống cấp", on: drillMode, enabled: depth + 1 < spec.drillLevels.count) { drillMode.toggle() }
            button("arrow.down.to.line", "Xuống một cấp cho cả trục", enabled: depth + 1 < spec.drillLevels.count) { interaction.nextLevel(visual: visual, spec: spec) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(2)
    }

    private func contextMenu(_ target: MenuTarget, spec: VisualQuerySpec) -> some View {
        let depth = interaction.depth(of: visual)
        let through = target.point.map { interaction.drillthroughTargets(from: page, point: $0) } ?? []
        return ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { menu = nil }
            VStack(alignment: .leading, spacing: 0) {
                if spec.drillLevels.count > 1 {
                    if let point = target.point, depth + 1 < spec.drillLevels.count {
                        menuItem("Drill down") { interaction.drillDown(page: page, visual: visual, spec: spec, point: point) }
                    }
                    if depth > 0 { menuItem("Drill up") { interaction.drillUp(page: page, visual: visual) } }
                }
                ForEach(Array(through.enumerated()), id: \.offset) { _, entry in
                    menuItem("Drillthrough › \(entry.page.displayName)") {
                        interaction.applyDrillthrough(to: entry.page, values: entry.values)
                        navigate(entry.page.id)
                    }
                }
                if target.point != nil, InteractionRules.canSelect(visualType: visual.type) {
                    menuItem("Bỏ chọn") { interaction.select(page: page, visual: visual, spec: spec, point: nil, additive: false) }
                }
            }
            .padding(4)
            .frame(width: 200, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white).shadow(color: .black.opacity(0.25), radius: 6, y: 2))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.12)))
            .offset(x: target.location.x, y: target.location.y)
        }
    }

    private func menuItem(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button {
            menu = nil
            action()
        } label: {
            Text(title).font(.system(size: 12)).foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nạp

    private func load(_ state: FilterState) async {
        guard interaction.isAvailable else { return }
        if needsFields { phase = .loading; return }
        do {
            let data = try await interaction.load(page: page, visual: visual, state: state)
            phase = .loaded(data)
        } catch is CancellationError {
            return
        } catch let error as DAXError where error.kind == .cancelled {
            return
        } catch let error as VisualQuerySpecReader.ReadError {
            // Không phải visual dữ liệu (không có queryState): giữ bản giữ chỗ, không báo lỗi.
            _ = error
            phase = .loading
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
