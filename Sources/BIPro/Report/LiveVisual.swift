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

    private enum Phase {
        case loading
        case failed(String)
        case loaded(LiveVisualData)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        let state = interaction.state(for: page)
        ZStack {
            content(state: state)
        }
        .task(id: state) { await load(state) }
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

    @ViewBuilder
    private var placeholder: some View {
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
        switch data.view {
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
        actions.select = { point, additive in
            MainActor.assumeIsolated {
                interaction.select(page: page, visual: visual, spec: spec, point: point, additive: additive)
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

    // MARK: - Nạp

    private func load(_ state: FilterState) async {
        guard interaction.isAvailable else { return }
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
