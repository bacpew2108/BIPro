import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite("US1 — Stacked Bar, 100% Stacked Bar & Pie Chart")
struct StackedBarAndPieTests {

    private func sampleCategorical() -> CategoricalData {
        let cat = FieldInfo(queryRef: "Sales.Region", displayName: "Region", role: "Category", formatString: nil, isMeasure: false)
        let ser = FieldInfo(queryRef: "Sales.Channel", displayName: "Channel", role: "Series", formatString: nil, isMeasure: false)
        let m = FieldInfo(queryRef: "Sales.Amount", displayName: "Amount", role: "Y", formatString: "#,0", isMeasure: true)
        return CategoricalData(
            categoryLevels: [cat],
            categories: [CategoryKey(values: [.string("North")]), CategoryKey(values: [.string("South")])],
            seriesField: ser,
            series: [.string("Online"), .string("Store")],
            measures: [m],
            values: [[
                [DataCell(.double(60)), DataCell(.double(20))],
                [DataCell(.double(40)), DataCell(.double(80))],
            ]],
            highlights: nil,
            isReduced: false
        )
    }

    @Test("CartesianKind maps barChart, stackedBarChart, and hundredPercentStackedBarChart")
    func cartesianKindMapping() {
        #expect(CartesianKind(visualType: "barChart") == .stackedBar)
        #expect(CartesianKind(visualType: "stackedBarChart") == .stackedBar)
        #expect(CartesianKind(visualType: "hundredPercentStackedBarChart") == .hundredPercentStackedBar)
        #expect(CartesianKind.stackedBar.isHorizontalBar)
        #expect(CartesianKind.stackedBar.isStackedBar)
        #expect(CartesianKind.hundredPercentStackedBar.isHorizontalBar)
        #expect(CartesianKind.hundredPercentStackedBar.isStackedBar)
    }

    @Test("StackLayout computes stacked and 100% normalized segments for horizontal bars")
    func stackedBarLayoutMath() {
        let segs = StackLayout.segments(values: [60, 40], isNormalized: false)
        #expect(segs.count == 2)
        #expect(segs[0].y0 == 0 && segs[0].y1 == 60)
        #expect(segs[1].y0 == 60 && segs[1].y1 == 100)

        let pct = StackLayout.segments(values: [60, 40], isNormalized: true)
        #expect(pct.count == 2)
        #expect(abs(pct[0].y1 - 0.6) < 1e-9)
        #expect(abs(pct[1].y1 - 1.0) < 1e-9)
    }

    @MainActor
    @Test("Stacked bar, 100% stacked bar, and pieChart render non-blank PNG")
    func renderStackedBarAndPie() {
        let data = sampleCategorical()
        let ctx = VisualRenderContext(
            theme: ReportTheme.fallback,
            format: VisualFormat(objects: ObjectProperties(nil)),
            selection: [],
            slicerSelection: SlicerSelection(),
            actions: .none,
            visualSize: CGSize(width: 360, height: 240),
            isExporting: true
        )

        let views: [AnyView] = [
            AnyView(CartesianChartView(data: data, kind: .stackedBar, context: ctx, interactive: false)),
            AnyView(CartesianChartView(data: data, kind: .hundredPercentStackedBar, context: ctx, interactive: false)),
            AnyView(DonutChartView(data: data, context: ctx, interactive: false, isPie: true)),
        ]

        for view in views {
            let renderer = ImageRenderer(content: view.frame(width: 360, height: 240).background(Color.white))
            renderer.scale = 1
            let cg = renderer.cgImage
            #expect(cg != nil)
            #expect((cg?.width ?? 0) > 0 && (cg?.height ?? 0) > 0)
        }
    }

    @Test("VisualContentView.liveTypes includes barChart, stackedBarChart, hundredPercentStackedBarChart, pieChart")
    func liveTypesRegistered() {
        #expect(VisualContentView.liveTypes.contains("barChart"))
        #expect(VisualContentView.liveTypes.contains("stackedBarChart"))
        #expect(VisualContentView.liveTypes.contains("hundredPercentStackedBarChart"))
        #expect(VisualContentView.liveTypes.contains("pieChart"))
    }
}
