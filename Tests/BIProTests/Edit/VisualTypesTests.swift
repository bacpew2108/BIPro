import PBIXKit
import Testing
@testable import BIPro

@Suite struct VisualTypesTests {
    @Test func supportedTypesAreTheObservedOnesPlusTheTextbox() {
        #expect(Set(VisualTypes.supported) == ["card", "slicer", "clusteredBarChart", "hundredPercentStackedColumnChart", "lineChart",
                                               "lineClusteredColumnComboChart", "lineStackedColumnComboChart", "donutChart", "treemap",
                                               "pivotTable", "shapeMap", "textbox", "clusteredColumnChart", "columnChart"])
        #expect(VisualTypes.supported.count == 14)
    }

    @Test func everySupportedTypeHasAnObservedWellAndAMatchingDefaultSize() throws {
        for type in VisualTypes.supported {
            let info = try #require(VisualTypes.info(for: type), Comment(rawValue: type))
            let size = try #require(PBIRNewVisual.defaultSize(for: type), Comment(rawValue: type))
            #expect(info.defaultSize.width == size.width && info.defaultSize.height == size.height, Comment(rawValue: type))
            #expect(info.isSupported && VisualTypes.isSupported(type))
            if type != "textbox" {
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
        #expect(VisualTypes.refusal(for: "stackedBarChart").contains("VM-D3"))
        #expect(VisualTypes.isSupported("clusteredColumnChart") && VisualTypes.isSupported("columnChart"))
        #expect(VisualTypes.refusal(for: "image").contains("tài nguyên"))
        #expect(VisualTypes.refusal(for: "scatterChart").contains("chưa vẽ"))
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
