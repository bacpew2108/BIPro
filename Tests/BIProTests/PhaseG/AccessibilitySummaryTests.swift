import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("PhaseG — VoiceOver AccessibilitySummary")
struct AccessibilitySummaryTests {
    private func makeVisual(type: String, title: String? = nil, fields: [ReportField] = []) -> ReportVisual {
        var container: [String: JSONValue] = [:]
        if let title {
            container["title"] = .array([.object(["properties": .object(["text": .object(["expr": .object(["Literal": .object(["Value": .string("'\(title)'")])])])])])])
        }
        return ReportVisual(
            id: "v1", type: type, x: 0, y: 0, z: 0, width: 300, height: 200,
            isHidden: false, objects: ObjectProperties(.object([:])),
            containerObjects: ObjectProperties(.object(container)), fields: fields, raw: .object([:])
        )
    }

    @Test("Sinh nhãn và giá trị không rỗng cho Card, Biểu đồ, Matrix, Slicer ở cả vi và en")
    func describesAllVisualKindsBilingually() {
        let m = FieldInfo(queryRef: "F.Rev", displayName: "Doanh thu", role: "Values", formatString: "#,0", isMeasure: true)
        let cardVisual = makeVisual(type: "card", title: "Tổng doanh thu")
        let cardData = DataView.single(SingleValueData(measure: m, cell: DataCell(.integer(1500), formatString: "#,0")))

        let viCard = VisualAccessibilitySummary.describe(visual: cardVisual, data: cardData, language: .vi)
        let enCard = VisualAccessibilitySummary.describe(visual: cardVisual, data: cardData, language: .en)
        #expect(viCard.label == "Thẻ số liệu: Tổng doanh thu")
        #expect(enCard.label == "Card: Tổng doanh thu")
        #expect(!viCard.value.isEmpty)
        #expect(!enCard.hint.isEmpty)

        let cat = FieldInfo(queryRef: "D.Year", displayName: "Year", role: "Category", formatString: nil, isMeasure: false)
        let chartVisual = makeVisual(type: "clusteredColumnChart")
        let chartData = DataView.categorical(CategoricalData(
            categoryLevels: [cat],
            categories: [CategoryKey(values: [.integer(2024)]), CategoryKey(values: [.integer(2025)])],
            seriesField: nil, series: [], measures: [m],
            values: [[[DataCell(.integer(10)), DataCell(.integer(20))]]], highlights: nil, isReduced: false
        ))
        let viChart = VisualAccessibilitySummary.describe(visual: chartVisual, data: chartData, language: .vi)
        let enChart = VisualAccessibilitySummary.describe(visual: chartVisual, data: chartData, language: .en)
        #expect(viChart.label == "Biểu đồ cột")
        #expect(viChart.value == "2 danh mục, 1 chuỗi")
        #expect(enChart.label == "Column chart")
        #expect(enChart.value == "2 categories, 1 series")

        let slicerVisual = makeVisual(type: "slicer")
        let slicerData = DataView.slicer(SlicerData(levels: [cat], roots: [SlicerNode(.integer(2024))]))
        #expect(VisualAccessibilitySummary.describe(visual: slicerVisual, data: slicerData, slicerSelectedCount: 0, language: .vi).value == "Tất cả")
        #expect(VisualAccessibilitySummary.describe(visual: slicerVisual, data: slicerData, slicerSelectedCount: 2, language: .en).value == "2 selected")
    }

    @Test("AccessibilityAnnouncer an toàn khi gọi trong môi trường test không có NSApp")
    @MainActor
    func announcerSafeAndCallsHook() {
        var received: [String] = []
        AccessibilityAnnouncer.testHook = { received.append($0) }
        defer { AccessibilityAnnouncer.testHook = nil }

        AccessibilityAnnouncer.announce("Đã chuyển sang trang D1")
        AccessibilityAnnouncer.announce("")
        #expect(received == ["Đã chuyển sang trang D1"])
    }
}
