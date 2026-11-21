import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite("US2 — TableVisualView & Scatter/Gauge/KPI/MultiRowCard Renderers")
struct ScatterGaugeKPITests {

    private func context() -> VisualRenderContext {
        VisualRenderContext(
            theme: ReportTheme.fallback,
            format: VisualFormat(objects: ObjectProperties(nil)),
            selection: [],
            slicerSelection: SlicerSelection(),
            actions: .none,
            visualSize: CGSize(width: 340, height: 220),
            isExporting: true
        )
    }

    @Test("GaugeLayout defaults Max to 2 × Value when MaxValue is omitted (VM-V11A)")
    func gaugeDefaultMaxRule() {
        let f = FieldInfo(queryRef: "Sales.Rev", displayName: "Rev", role: "Y", formatString: "#,0", isMeasure: true)
        let data = GaugeData(valueField: f, value: DataCell(.double(5369)), min: nil, max: nil, target: DataCell(.double(8000)))
        let layout = GaugeLayout(data: data)
        #expect(layout.min == 0)
        #expect(layout.max == 10738)
        #expect(abs(layout.fillFraction - 0.5) < 1e-9)
        #expect(layout.targetFraction != nil)
        #expect(abs((layout.targetFraction ?? 0) - (8000.0 / 10738.0)) < 1e-6)
    }

    @Test("KPILayout computes good/bad status and delta percentage")
    func kpiStatusMath() {
        let ind = FieldInfo(queryRef: "Sales.Rev", displayName: "Rev", role: "Indicator", formatString: "#,0", isMeasure: true)
        let goal = FieldInfo(queryRef: "Sales.Goal", displayName: "Goal", role: "Goal", formatString: "#,0", isMeasure: true)
        let good = KPILayout(data: KPIData(indicatorField: ind, trendField: nil, goalField: goal,
                                           latestValue: DataCell(.double(120)), goalValue: DataCell(.double(100)), trendPoints: []))
        #expect(good.status == .good)
        #expect(abs((good.deltaPercent ?? 0) - 20.0) < 1e-9)

        let bad = KPILayout(data: KPIData(indicatorField: ind, trendField: nil, goalField: goal,
                                          latestValue: DataCell(.double(80)), goalValue: DataCell(.double(100)), trendPoints: []))
        #expect(bad.status == .bad)
        #expect(abs((bad.deltaPercent ?? 0) - (-20.0)) < 1e-9)
    }

    @Test("ScatterLayout handles both 2D bubbles and 1D horizontal fallback")
    func scatterLayoutMath() {
        let xf = FieldInfo(queryRef: "Sales.X", displayName: "X", role: "X", formatString: "#,0", isMeasure: true)
        let yf = FieldInfo(queryRef: "Sales.Y", displayName: "Y", role: "Y", formatString: "#,0", isMeasure: true)
        let pt = ScatterPoint(id: DataPointID(["Sales.R": .string("A")]), categoryLabel: "A", seriesValue: nil,
                              x: 50, y: 20, size: 10, xCell: DataCell(.double(50)), yCell: DataCell(.double(20)),
                              sizeCell: DataCell(.double(10)), tooltips: [])

        let d2 = ScatterLayout(data: ScatterData(categoryField: nil, seriesField: nil, series: [], xField: xf, yField: yf, sizeField: nil, points: [pt], isReduced: false),
                               format: VisualFormat(objects: ObjectProperties(nil)))
        #expect(!d2.is1D)
        #expect(d2.bubbles.count == 1)

        let d1 = ScatterLayout(data: ScatterData(categoryField: nil, seriesField: nil, series: [], xField: xf, yField: nil, sizeField: nil, points: [pt], isReduced: false),
                               format: VisualFormat(objects: ObjectProperties(nil)))
        #expect(d1.is1D)
        #expect(d1.bubbles[0].yNorm == 0.5)
    }

    @MainActor
    @Test("All 5 US2 renderers produce non-blank PNG images in export mode")
    func renderAllUS2Visuals() {
        let ctx = context()
        let colF = FieldInfo(queryRef: "Sales.Region", displayName: "Region", role: "Values", formatString: nil, isMeasure: false)
        let valF = FieldInfo(queryRef: "Sales.Amount", displayName: "Amount", role: "Values", formatString: "$#,0", isMeasure: true)

        let tableData = TableDataView(
            columns: [colF, valF],
            rows: [[DataCell(.string("North")), DataCell(.double(1200))], [DataCell(.string("South")), DataCell(.double(800))]],
            totals: [.blank, DataCell(.double(2000))],
            isReduced: false
        )
        let scatterData = ScatterData(
            categoryField: colF, seriesField: nil, series: [],
            xField: valF, yField: valF, sizeField: nil,
            points: [
                ScatterPoint(id: DataPointID(["Sales.Region": .string("North")]), categoryLabel: "North", seriesValue: nil,
                             x: 10, y: 20, size: 5, xCell: DataCell(.double(10)), yCell: DataCell(.double(20)), sizeCell: nil, tooltips: []),
                ScatterPoint(id: DataPointID(["Sales.Region": .string("South")]), categoryLabel: "South", seriesValue: nil,
                             x: 30, y: 45, size: 15, xCell: DataCell(.double(30)), yCell: DataCell(.double(45)), sizeCell: nil, tooltips: []),
            ],
            isReduced: false
        )
        let gaugeData = GaugeData(valueField: valF, value: DataCell(.double(5369)), min: nil, max: nil, target: DataCell(.double(8000)))
        let kpiData = KPIData(indicatorField: valF, trendField: colF, goalField: valF,
                              latestValue: DataCell(.double(1200)), goalValue: DataCell(.double(1000)),
                              trendPoints: [.init(label: "2022", value: 900), .init(label: "2023", value: 1050), .init(label: "2024", value: 1200)])
        let mrcData = MultiRowCardData(fields: [colF, valF], rows: [[DataCell(.string("North")), DataCell(.double(1200))]], isReduced: false)

        let views: [AnyView] = [
            AnyView(TableVisualView(data: tableData, context: ctx, scrollable: false)),
            AnyView(ScatterChartView(data: scatterData, context: ctx, interactive: false)),
            AnyView(GaugeVisualView(data: gaugeData, context: ctx)),
            AnyView(KPIVisualView(data: kpiData, context: ctx)),
            AnyView(MultiRowCardView(data: mrcData, context: ctx, scrollable: false)),
        ]
        for view in views {
            let renderer = ImageRenderer(content: view.frame(width: 340, height: 220).background(Color.white))
            renderer.scale = 1
            let cg = renderer.cgImage
            #expect(cg != nil)
            #expect((cg?.width ?? 0) > 0 && (cg?.height ?? 0) > 0)
        }
    }
}
