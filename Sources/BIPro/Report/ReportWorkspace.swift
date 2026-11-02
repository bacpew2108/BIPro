import PBIXKit
import SwiftUI

struct ReportWorkspace: View {
    @Bindable var state: DocumentState
    @State private var currentScale: Double = 1
    @State private var filtersCollapsed = false
    @State private var visualsCollapsed = false
    @State private var dataCollapsed = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let page = state.page {
                    ReportPageView(workspace: state.workspace, page: page, selectedVisual: $state.visualID,
                                   zoom: state.zoom, onScale: { currentScale = $0 },
                                   navigate: { state.pageID = $0; state.visualID = nil })
                        .id(page.id)
                } else {
                    ContentUnavailableView("Báo cáo không có trang", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.Palette.backdrop)
                }
                PageTabs(state: state, scale: currentScale)
            }
            panes
        }
    }

    @ViewBuilder private var panes: some View {
        if state.showSelection {
            SelectionPane(state: state) { state.showSelection = false }
                .frame(width: 220).hairline(.leading)
        }
        if state.showBookmarks {
            BookmarksPane(state: state) { state.showBookmarks = false }
                .frame(width: 200).hairline(.leading)
        }
        if state.showFilters {
            pane(collapsed: $filtersCollapsed, title: "Bộ lọc", symbol: "line.3.horizontal.decrease", width: 230) {
                FiltersPane(state: state) { filtersCollapsed = true }
            }
        }
        if state.showVisualizations {
            pane(collapsed: $visualsCollapsed, title: "Trực quan hóa", symbol: "chart.bar.xaxis", width: 250) {
                VisualizationsPane(state: state) { visualsCollapsed = true }
            }
        }
        if state.showData {
            pane(collapsed: $dataCollapsed, title: "Dữ liệu", symbol: "cylinder.split.1x2", width: 250) {
                DataPane(state: state, purpose: .report) { dataCollapsed = true }
            }
        }
    }

    @ViewBuilder private func pane<Content: View>(collapsed: Binding<Bool>, title: String, symbol: String, width: CGFloat,
                                                  @ViewBuilder content: () -> Content) -> some View {
        Group {
            if collapsed.wrappedValue {
                CollapsedPaneStrip(title: title, symbol: symbol) { collapsed.wrappedValue = false }
            } else {
                content().frame(width: width)
            }
        }
        .hairline(.leading)
    }
}

/// Bottom bar: page tabs (hidden pages marked), page counter, zoom.
struct PageTabs: View {
    @Bindable var state: DocumentState
    let scale: Double

    var body: some View {
        let pages = state.workspace.report.pages
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(pages) { page in
                        let selected = state.pageID == page.id
                        Button {
                            state.pageID = page.id
                            state.visualID = nil
                        } label: {
                            HStack(spacing: 4) {
                                if page.isHidden { Image(systemName: "eye.slash").font(.system(size: 10)) }
                                Text(page.displayName).font(.system(size: 12, weight: selected ? .semibold : .regular))
                            }
                            .foregroundStyle(selected ? DS.Palette.label : DS.Palette.secondaryLabel)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(selected ? Color.white : .clear)
                                .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 1, y: 0.5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(page.isHidden ? "Trang ẩn khi xem báo cáo" : page.displayName)
                    }
                    Button {} label: { Image(systemName: "plus") }
                        .buttonStyle(GhostIconButtonStyle())
                        .disabled(true)
                        .help("Thêm trang: Phase D")
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 8)
            if let index = pages.firstIndex(where: { $0.id == state.pageID }) {
                Text("Trang \(index + 1) / \(pages.count)").font(DS.Typeface.label).foregroundStyle(DS.Palette.secondaryLabel)
            }
            ZoomControl(percent: Int((scale * 100).rounded()),
                        zoomOut: { state.zoom = max(0.25, (state.zoom ?? scale) - 0.1) },
                        zoomIn: { state.zoom = min(4, (state.zoom ?? scale) + 0.1) },
                        fit: { state.zoom = nil })
                .padding(.trailing, 8)
        }
        .frame(height: DS.Metrics.pageTabs)
        .background(DS.Palette.chrome)
        .hairline(.top)
    }
}
