// VM-D16: xuất ảnh PNG của vùng, vùng 100%, ruy-băng, thác nước (có Breakdown) và phễu bằng số liệu của hình Desktop,
// vào `build/d-out/D16/` để xem bằng mắt (không so điểm ảnh).
import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite struct NewChartsImageTests {
    @MainActor
    private func png(_ view: some View, size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(Color.white))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func field(_ ref: String, _ name: String, role: String, measure: Bool = false, format: String? = nil) -> FieldInfo {
        FieldInfo(queryRef: ref, displayName: name, role: role, formatString: format, isMeasure: measure)
    }

    /// Total_Credit_Inflow theo năm (6) và vùng (4), số của hình Desktop.
    private var yearRegion: CategoricalData {
        let years = ["2013", "2014", "2015", "2016", "2017", "2018"]
        let regions = ["Midwest", "Northeast", "South", "West"]
        let inflow: [[Double]] = [[14, 62, 25, 20], [27, 150, 55, 43], [40, 212, 80, 64], [62, 320, 122, 102], [82, 458, 178, 145], [88, 510, 200, 163]]
        let rows: [[DataCell]] = regions.indices.map { r in years.indices.map { DataCell(.double(inflow[$0][r] * 1e6), formatString: "\\$#,0") } }
        return CategoricalData(categoryLevels: [field("Dim_Date.year", "year", role: "Category")], categories: years.map { CategoryKey(values: [.string($0)]) },
                               seriesField: field("Dim_Client.region", "client_region", role: "Series"), series: regions.map { .string($0) },
                               measures: [field("Fact.Inflow", "Total_Credit_Inflow", role: "Y", measure: true, format: "\\$#,0")],
                               values: [rows], highlights: nil, isReduced: false)
    }

    private var theme: ReportTheme {
        var theme = ReportTheme.fallback
        theme.dataColors = ["#1F7A8C", "#14213D", "#E07A5F", "#8C98A6", "#F2CC8F", "#81B29A", "#3D5A80", "#B5452F"]
        theme.good = "#2E7D32"; theme.bad = "#C0392B"
        return theme
    }

    @Test @MainActor func xuatAnhCacLoaiMoi() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("build/d-out/D16", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let context = VisualRenderContext(theme: theme)
        let size = CGSize(width: 616, height: 380)
        var outputs: [(String, Data?)] = []
        outputs.append(("area", png(CartesianChartView(data: yearRegion, kind: .area, context: context), size: size)))
        outputs.append(("stackedArea", png(CartesianChartView(data: yearRegion, kind: .stackedArea, context: context), size: size)))
        outputs.append(("hundredPercentArea", png(CartesianChartView(data: yearRegion, kind: .hundredPercentStackedArea, context: context), size: size)))
        outputs.append(("ribbon", png(RibbonChartView(data: yearRegion, context: context), size: size)))

        // Thác nước có Breakdown: vùng × giới tính.
        let regions = ["Northeast", "South", "West", "Midwest"]
        let waterfall = CategoricalData(categoryLevels: [field("Dim_Client.region", "client_region", role: "Category")],
                                        categories: regions.map { CategoryKey(values: [.string($0)]) },
                                        seriesField: field("Dim_Client.sex", "sex", role: "Breakdown"), series: [.string("Female"), .string("Male")],
                                        measures: [field("Fact.Inflow", "Total_Credit_Inflow", role: "Y", measure: true, format: "\\$#,0")],
                                        values: [[[0.82, 0.33, 0.27, 0.15].map { DataCell(.double($0 * 1e9), formatString: "\\$#,0") },
                                                  [0.90, 0.33, 0.27, 0.16].map { DataCell(.double($0 * 1e9), formatString: "\\$#,0") }]],
                                        highlights: nil, isReduced: false)
        outputs.append(("waterfall", png(WaterfallChartView(data: waterfall, context: context), size: size)))

        let years = ["2018", "2017", "2016", "2015", "2014", "2013"]
        let funnel = CategoricalData(categoryLevels: [field("Dim_Date.year", "year", role: "Category")], categories: years.map { CategoryKey(values: [.string($0)]) },
                                     seriesField: nil, series: [], measures: [field("Fact.Inflow", "Total_Credit_Inflow", role: "Y", measure: true, format: "\\$#,0")],
                                     values: [[[961, 865, 607, 396, 279, 120].map { DataCell(.double($0 * 1e6), formatString: "\\$#,0") }]],
                                     highlights: nil, isReduced: false)
        outputs.append(("funnel", png(FunnelChartView(data: funnel, context: context), size: size)))
        for (name, data) in outputs {
            let bytes = try #require(data, Comment(rawValue: name))
            #expect(bytes.count > 4000, Comment(rawValue: "\(name): ảnh không trống"))
            try bytes.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }
}
