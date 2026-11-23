import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — PaneParity (US5, T054)")
@MainActor
struct PaneParityTests {
    @Test func filtersCollapsedByDefaultAndPanesUseDesktopMetrics() throws {
        let blank = try NewDocument.blank()
        let state = DocumentState(workspace: try Workspace(data: blank), fileName: "Panes.pbix")
        #expect(state.filtersCollapsed == true)
        #expect(state.visualizationsCollapsed == false)
        #expect(state.dataCollapsed == false)
        #expect(UIMetrics.collapsedPane == 31)
        #expect(UIMetrics.pane == 181)
        #expect(state.paneWidth(for: .visualizations) == UIMetrics.pane)
        #expect(state.paneWidth(for: .data) == UIMetrics.pane)

        // Kéo giãn pane được đến 320 pt
        state.setPaneWidth(320, for: .data)
        #expect(state.paneWidth(for: .data) == 320)
        state.setPaneWidth(500, for: .data)
        #expect(state.paneWidth(for: .data) == 320)

        // Thu gọn Visualizations và Data thành dải dọc rồi mở lại được
        state.visualizationsCollapsed = true
        state.dataCollapsed = true
        #expect(state.visualizationsCollapsed == true)
        #expect(state.dataCollapsed == true)
        state.visualizationsCollapsed = false
        state.dataCollapsed = false
        #expect(state.visualizationsCollapsed == false)
        #expect(state.dataCollapsed == false)
    }

    @Test func visualizationsPaneHasThreeIconTabsAndSixColumnDesktopGallery() async throws {
        // 3 tab biểu tượng: Build, Format, Analytics
        #expect(DocumentState.VisualizationsTab.allCases == [.build, .format, .analytics])

        // Lưới 6 cột theo `contracts/visual-gallery.md` (39 ô, 7 hàng)
        let slots = VisualizationsPane.desktopGallery
        #expect(VisualizationsPane.galleryColumnCount == 6)
        #expect(slots.count == 39)

        let expectedOrder: [(type: String?, en: String)] = [
            // Hàng 1
            ("barChart", "Stacked bar chart"),
            ("columnChart", "Stacked column chart"),
            ("clusteredBarChart", "Clustered bar chart"),
            ("clusteredColumnChart", "Clustered column chart"),
            ("hundredPercentStackedBarChart", "100% stacked bar chart"),
            ("hundredPercentStackedColumnChart", "100% stacked column chart"),
            // Hàng 2
            ("lineChart", "Line chart"),
            ("areaChart", "Area chart"),
            ("stackedAreaChart", "Stacked area chart"),
            ("lineStackedColumnComboChart", "Line and stacked column chart"),
            ("lineClusteredColumnComboChart", "Line and clustered column chart"),
            ("ribbonChart", "Ribbon chart"),
            // Hàng 3
            ("waterfallChart", "Waterfall chart"),
            ("funnel", "Funnel"),
            ("scatterChart", "Scatter chart"),
            ("pieChart", "Pie chart"),
            ("donutChart", "Donut chart"),
            ("treemap", "Treemap"),
            // Hàng 4
            ("map", "Map"),
            ("filledMap", "Filled map"),
            (nil, "Azure map"),
            ("gauge", "Gauge"),
            ("cardVisual", "Card"),
            ("multiRowCard", "Multi-row card"),
            // Hàng 5
            ("kpi", "KPI"),
            ("slicer", "Slicer"),
            ("tableEx", "Table"),
            ("pivotTable", "Matrix"),
            (nil, "R script visual"),
            (nil, "Python script visual"),
            // Hàng 6
            (nil, "Key influencers"),
            (nil, "Decomposition tree"),
            (nil, "Q&A"),
            (nil, "Smart narrative"),
            (nil, "Paginated report"),
            (nil, "Power Apps for Power BI"),
            // Hàng 7
            (nil, "Power Automate for Power BI"),
            (nil, "ArcGIS Maps for Power BI"),
            (nil, "Get more visuals"),
        ]

        for (index, expected) in expectedOrder.enumerated() {
            let slot = slots[index]
            #expect(slot.type == expected.type, "Ô \(index + 1) sai loại: \(String(describing: slot.type)) != \(String(describing: expected.type))")
            #expect(slot.title.en == expected.en, "Ô \(index + 1) sai nhãn EN: \(slot.title.en) != \(expected.en)")
            if expected.type == nil {
                #expect(slot.isSupported == false)
                #expect(!slot.disabledTooltip.vi.isEmpty)
                #expect(!slot.disabledTooltip.en.isEmpty)
            } else {
                #expect(slot.isSupported == true)
            }
        }

        // Bấm ô có loại BI Pro gọi đúng insertVisual(type)
        let blank = try NewDocument.blank()
        let state = DocumentState(workspace: try Workspace(data: blank), fileName: "GalleryInsert.pbix")
        state.mode = .report
        state.editMode = true
        let initialCount = state.page?.visuals.count ?? 0
        VisualizationsPane.handleGalleryTap(slots[3], state: state) // clusteredColumnChart
        #expect(state.page?.visuals.count == initialCount + 1)
        #expect(state.visual?.type == "clusteredColumnChart")

        // Bấm ô unsupported không thêm visual mới
        let beforeUnsupported = state.page?.visuals.count ?? 0
        state.visualID = nil
        VisualizationsPane.handleGalleryTap(slots[20], state: state) // Azure map (nil)
        #expect(state.page?.visuals.count == beforeUnsupported)
    }

    @Test func formatPaneHasSearchAndVisualGeneralTabsAndDataPaneShowsSemanticModelTree() async throws {
        // FormatPane chỉ còn 2 tab Visual / General (Analytics chuyển sang tab biểu tượng thứ 3 ở VisualizationsPane)
        #expect(FormatPane.Tab.allCases == [.objects, .container])

        // DataPane hiện tab Tables/Model ở Model, DAX và TMDL view
        #expect(DataPane.showsModelTabs(mode: .report, purpose: .report) == false)
        #expect(DataPane.showsModelTabs(mode: .table, purpose: .table) == false)
        #expect(DataPane.showsModelTabs(mode: .model, purpose: .table) == true)
        #expect(DataPane.showsModelTabs(mode: .daxQuery, purpose: .query) == true)
        #expect(DataPane.showsModelTabs(mode: .tmdl, purpose: .query) == true)

        // Cây Semantic model có đủ 9 nhóm kèm số lượng từ metadata
        let state = try await ParityRenderTests.makeSampleState()
        let groupsEN = ModelTreeView.groupSummaries(metadata: state.workspace.metadata, language: .en)
        #expect(groupsEN.map(\.name) == [
            "Calculation groups",
            "Cultures",
            "Expressions",
            "Functions",
            "Measures",
            "Perspectives",
            "Relationships",
            "Roles",
            "Tables",
        ])
        #expect(groupsEN.last?.count == 1) // 1 bảng "Sales"

        // Không còn chân trạng thái riêng của pane Filters / Visualizations / Data
        #expect(FiltersPane.showsFooter == false)
        #expect(VisualizationsPane.showsFooter == false)
        #expect(DataPane.showsFooter == false)
    }
}
}
