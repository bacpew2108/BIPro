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

        // v1.1a (T021): Các loại visual mới song ngữ vi/en
        #expect(VisualAccessibilitySummary.visualTypeName("pieChart", language: .vi) == "Biểu đồ tròn")
        #expect(VisualAccessibilitySummary.visualTypeName("pieChart", language: .en) == "Pie chart")
        #expect(VisualAccessibilitySummary.visualTypeName("scatterChart", language: .vi) == "Biểu đồ phân tán")
        #expect(VisualAccessibilitySummary.visualTypeName("gauge", language: .en) == "Gauge")
        #expect(VisualAccessibilitySummary.visualTypeName("kpi", language: .en) == "KPI")
        #expect(VisualAccessibilitySummary.visualTypeName("multiRowCard", language: .vi) == "Thẻ nhiều hàng")
        #expect(VisualAccessibilitySummary.visualTypeName("map", language: .en) == "Map")
        #expect(VisualAccessibilitySummary.visualTypeName("filledMap", language: .vi) == "Bản đồ")

        let gaugeData = DataView.gauge(GaugeData(valueField: m, value: DataCell(.integer(500)), min: nil, max: nil, target: nil))
        #expect(VisualAccessibilitySummary.describe(visual: makeVisual(type: "gauge"), data: gaugeData, language: .en).value == "500")
        let tableData = DataView.table(TableDataView(columns: [cat, m], rows: [[DataCell(.integer(2024)), DataCell(.integer(10))]], totals: nil, isReduced: false))
        #expect(VisualAccessibilitySummary.describe(visual: makeVisual(type: "tableEx"), data: tableData, language: .en).value == "1 rows, 2 columns")
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

    @Test("DataTreeAccessibility sinh nhãn và trạng thái chuẩn cho đủ 6 loại nút ở vi và en")
    func dataTreeAccessibilityLabelsAndValues() {
        #expect(DataTreeAccessibility.label(kind: .table, name: "Sales", language: .vi) == "Bảng: Sales")
        #expect(DataTreeAccessibility.label(kind: .table, name: "Sales", language: .en) == "Table: Sales")
        #expect(DataTreeAccessibility.label(kind: .folder, name: "KPIs", language: .en) == "Folder: KPIs")
        #expect(DataTreeAccessibility.label(kind: .column, name: "OrderDate", language: .vi) == "Cột: OrderDate")
        #expect(DataTreeAccessibility.label(kind: .column, name: "OrderDate", language: .en) == "Column: OrderDate")
        #expect(DataTreeAccessibility.label(kind: .measure, name: "Revenue", language: .en) == "Measure: Revenue")
        #expect(DataTreeAccessibility.label(kind: .hierarchy, name: "Date Hierarchy", language: .vi) == "Phân cấp: Date Hierarchy")
        #expect(DataTreeAccessibility.label(kind: .hierarchyLevel, name: "Year", language: .en) == "Level: Year")

        #expect(DataTreeAccessibility.value(isHidden: true, isSelected: true, isChecked: true, language: .vi) == "Đang dùng, Đang chọn, Đang ẩn")
        #expect(DataTreeAccessibility.value(isHidden: true, isSelected: false, isChecked: true, language: .en) == "In visual, Hidden")
        #expect(DataTreeAccessibility.value(isHidden: false, isSelected: false, isChecked: false, language: .en).isEmpty)
    }
}
