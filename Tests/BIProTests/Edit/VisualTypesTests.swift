import PBIXKit
import Testing
@testable import BIPro

@Suite struct VisualTypesTests {
    @Test func supportedTypesAreTheObservedOnesPlusTheTextbox() {
        #expect(Set(VisualTypes.supported) == [
            "card", "cardVisual", "multiRowCard", "kpi", "gauge",
            "slicer", "advancedSlicerVisual", "listSlicer", "textSlicer",
            "clusteredBarChart", "barChart", "stackedBarChart", "hundredPercentStackedBarChart",
            "clusteredColumnChart", "columnChart", "hundredPercentStackedColumnChart",
            "lineChart", "lineClusteredColumnComboChart", "lineStackedColumnComboChart",
            "areaChart", "stackedAreaChart", "hundredPercentStackedAreaChart", "ribbonChart", "waterfallChart", "funnel",
            "scatterChart", "donutChart", "pieChart", "treemap",
            "pivotTable", "tableEx", "shapeMap", "map", "filledMap",
            "textbox", "shape", "actionButton", "pageNavigator", "bookmarkNavigator", "image",
        ])
        #expect(VisualTypes.supported.count == 40)
    }

    @Test func everySupportedTypeHasAnObservedWellAndAMatchingDefaultSize() throws {
        let nonDataElements: Set<String> = ["textbox", "shape", "actionButton", "pageNavigator", "bookmarkNavigator", "image"]
        for type in VisualTypes.supported {
            let info = try #require(VisualTypes.info(for: type), Comment(rawValue: type))
            let size = try #require(PBIRNewVisual.defaultSize(for: type), Comment(rawValue: type))
            #expect(info.defaultSize.width == size.width && info.defaultSize.height == size.height, Comment(rawValue: type))
            #expect(info.isSupported && VisualTypes.isSupported(type))
            if !nonDataElements.contains(type) {
                let visual = ReportVisual(id: "aaaaaaaaaaaaaaaaaaa1", type: type)
                #expect(WellRules.rules(for: visual).contains { $0.status == .observed }, Comment(rawValue: "\(type) cần ít nhất một ô đã quan sát"))
            }
        }
    }

    @Test func everyOtherGalleryTypeHasAReasonToRefuse() {
        for entry in VisualCatalog.gallery where !VisualTypes.isSupported(entry.type) {
            let reason = VisualTypes.refusal(for: entry.type)
            #expect(!reason.isEmpty, Comment(rawValue: entry.type))
            #expect(VisualTypes.info(for: entry.type) == nil, Comment(rawValue: entry.type))
        }
        #expect(VisualTypes.isSupported("barChart") && VisualTypes.isSupported("stackedBarChart"))
        #expect(VisualTypes.isSupported("clusteredColumnChart") && VisualTypes.isSupported("columnChart"))
        #expect(VisualTypes.isSupported("image") && VisualTypes.isSupported("scatterChart"))
        #expect(!VisualTypes.refusal(for: "unknownType").isEmpty)
    }

    @Test func familiesGroupTheTypesThatShareWells() {
        #expect(VisualTypes.info(for: "lineChart")?.family == .xy && VisualTypes.info(for: "clusteredBarChart")?.family == .xy)
        #expect(VisualTypes.info(for: "lineClusteredColumnComboChart")?.family == .xy)
        #expect(VisualTypes.info(for: "donutChart")?.family == .circular && VisualTypes.info(for: "treemap")?.family == .circular)
        #expect(VisualTypes.info(for: "card")?.family == .value && VisualTypes.info(for: "slicer")?.family == .slicer)
        #expect(VisualTypes.info(for: "textbox")?.family == .text)
        #expect(VisualTypes.info(for: "pivotTable")?.family == .matrix && VisualTypes.info(for: "shapeMap")?.family == .map)
    }
}
