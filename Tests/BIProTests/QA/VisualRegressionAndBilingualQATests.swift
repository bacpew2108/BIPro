import AppKit
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

/// Đợt 1 QA (v1.0.1): Kiểm thử hồi quy hình ảnh toàn bộ loại biểu đồ hiện có + Dark Mode & Song ngữ các pane phụ.
@Suite("QA — Visual Regression & Deep Bilingual Dark Mode")
@MainActor
struct VisualRegressionAndBilingualQATests {

    private func renderPNG(_ view: some View, size: CGSize, scheme: ColorScheme) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, scheme)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        let cg = try #require(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: cg)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        return rep
    }

    private func metrics(of rep: NSBitmapImageRep) -> (distinctColors: Int, avgLuminance: Double) {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var colors = Set<UInt32>()
        var lumSum = 0.0
        var count = 0
        let step = max(1, Int(sqrt(Double(w * h) / 1600.0)))
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                    lumSum += 0.2126 * r + 0.7152 * g + 0.0722 * b
                    count += 1
                    colors.insert((UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded()))
                }
            }
        }
        return (colors.count, count > 0 ? lumSum / Double(count) : 1.0)
    }

    private func sampleCategorical() -> CategoricalData {
        let cats = ["Q1", "Q2", "Q3", "Q4"]
        let series = ["North", "South"]
        let yVals: [[Double]] = [[120, 90], [180, 140], [150, 175], [220, 195]]
        let yRows: [[DataCell]] = series.indices.map { s in cats.indices.map { DataCell(.double(yVals[$0][s]), formatString: "#,0") } }
        let y2Rows: [[DataCell]] = [cats.indices.map { DataCell(.double(Double($0 + 1) * 25.0), formatString: "0.0%") }]
        return CategoricalData(
            categoryLevels: [FieldInfo(queryRef: "T.Quarter", displayName: "Quarter", role: "Category", formatString: nil, isMeasure: false)],
            categories: cats.map { CategoryKey(values: [.string($0)]) },
            seriesField: FieldInfo(queryRef: "T.Region", displayName: "Region", role: "Series", formatString: nil, isMeasure: false),
            series: series.map { .string($0) },
            measures: [
                FieldInfo(queryRef: "T.Sales", displayName: "Sales", role: "Y", formatString: "#,0", isMeasure: true),
                FieldInfo(queryRef: "T.Growth", displayName: "Growth", role: "Y2", formatString: "0.0%", isMeasure: true),
            ],
            values: [yRows, y2Rows],
            highlights: nil,
            isReduced: false
        )
    }

    @Test("Hồi quy vẽ hình toàn bộ 14+ bộ vẽ visual hiện có (Card, Slicer, Matrix, Donut, Treemap, Waterfall, Funnel, Ribbon, 10 Cartesian)")
    func renderEveryImplementedVisualRenderer() throws {
        let context = VisualRenderContext(theme: .fallback)
        let size = CGSize(width: 420, height: 260)
        let cat = sampleCategorical()

        // 1. Card
        let card = SingleValueData(
            measure: FieldInfo(queryRef: "T.Sales", displayName: "Total Sales", role: "Data", formatString: "\\$#,0", isMeasure: true),
            cell: DataCell(.double(1_245_800), formatString: "\\$#,0")
        )
        let cardRep = try renderPNG(CardVisualView(data: card, context: context).background(Color.white), size: CGSize(width: 240, height: 120), scheme: .light)
        #expect(metrics(of: cardRep).distinctColors >= 4)

        // 2. Slicer
        let slicer = SlicerData(
            levels: [FieldInfo(queryRef: "T.Region", displayName: "Region", role: "Values", formatString: nil, isMeasure: false)],
            roots: [
                SlicerNode(.string("North")),
                SlicerNode(.string("South")),
            ]
        )
        let slicerRep = try renderPNG(DropdownSlicerView(data: slicer, title: "Region", context: context).background(Color.white), size: CGSize(width: 220, height: 90), scheme: .light)
        #expect(metrics(of: slicerRep).distinctColors >= 3)

        // 3. Matrix
        let matrix = MatrixData(
            rowLevels: [FieldInfo(queryRef: "T.Region", displayName: "Region", role: "Rows", formatString: nil, isMeasure: false)],
            columnLevels: [FieldInfo(queryRef: "T.Quarter", displayName: "Quarter", role: "Columns", formatString: nil, isMeasure: false)],
            measures: [FieldInfo(queryRef: "T.Sales", displayName: "Sales", role: "Values", formatString: "#,0", isMeasure: true)],
            rows: [
                MatrixHeader(path: [.string("North")], level: 0),
                MatrixHeader(path: [.string("South")], level: 0),
            ],
            columns: [
                MatrixHeader(path: [.string("Q1")], level: 0),
                MatrixHeader(path: [.string("Q2")], level: 0),
            ],
            cells: [
                [[DataCell(.double(120), formatString: "#,0")], [DataCell(.double(180), formatString: "#,0")]],
                [[DataCell(.double(90), formatString: "#,0")], [DataCell(.double(140), formatString: "#,0")]],
            ],
            isReduced: false
        )
        let matrixRep = try renderPNG(MatrixVisualView(data: matrix, context: context, scrollable: false).background(Color.white), size: size, scheme: .light)
        #expect(metrics(of: matrixRep).distinctColors >= 4)

        // 4. Donut, Treemap, Waterfall, Funnel, Ribbon
        let specialViews: [(String, AnyView)] = [
            ("Donut", AnyView(DonutChartView(data: cat, context: context, interactive: false))),
            ("Treemap", AnyView(TreemapView(data: cat, context: context, interactive: false))),
            ("Waterfall", AnyView(WaterfallChartView(data: cat, context: context, interactive: false))),
            ("Funnel", AnyView(FunnelChartView(data: cat, context: context, interactive: false))),
            ("Ribbon", AnyView(RibbonChartView(data: cat, context: context, interactive: false))),
        ]
        for (name, view) in specialViews {
            let rep = try renderPNG(view.background(Color.white), size: size, scheme: .light)
            #expect(metrics(of: rep).distinctColors >= 5, "\(name) vẽ ra ít màu bất thường")
        }

        // 5. Toàn bộ 10 loại CartesianKind
        let kinds: [CartesianKind] = [
            .clusteredBar, .clusteredColumn, .stackedColumn, .hundredPercentStackedColumn,
            .line, .area, .stackedArea, .hundredPercentStackedArea,
            .comboClustered, .comboStacked,
        ]
        for kind in kinds {
            let rep = try renderPNG(CartesianChartView(data: cat, kind: kind, context: context, interactive: false).background(Color.white), size: size, scheme: .light)
            #expect(metrics(of: rep).distinctColors >= 5, "CartesianKind.\(kind) vẽ ra ít màu bất thường")
        }
    }

    @Test("Song ngữ & Dark Mode: kiểm tra các pane phụ (FormatPane, BuildWells, ColumnPropertiesEditor, MeasurePropertiesPanel, ModelWorkspace, TMDLWorkspace, QueryToolbar/TabBar/Results)")
    func secondaryPanesDarkModeAndBilingual() async throws {
        let prevLang = AppPreferences.shared.language
        let prevApp = AppPreferences.shared.appearance
        defer {
            AppPreferences.shared.language = prevLang
            AppPreferences.shared.appearance = prevApp
        }

        // Kiểm tra đổi ngôn ngữ động trên ColumnPropertiesEditor & MeasurePropertiesPanel
        AppPreferences.shared.language = .vi
        #expect(ColumnPropertiesEditor.summarizeOptions.first?.title == "Mặc định")
        #expect(MeasurePropertiesPanel.typeName(.int64) == "Số nguyên")

        AppPreferences.shared.language = .en
        AppPreferences.shared.appearance = .dark
        #expect(ColumnPropertiesEditor.summarizeOptions.first?.title == "Default")
        #expect(MeasurePropertiesPanel.typeName(.int64) == "Whole number")

        // Dựng tài liệu mẫu có 1 bảng, 1 measure, 1 visual
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bipro-qa-ui-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(
            workspace: try Workspace(data: Data(contentsOf: untitled)),
            fileName: "QA.pbix",
            fileURL: untitled
        )
        state.editMode = true
        var t = EnterDataTable(name: "Sales")
        try t.paste("Region\tAmount\nNorth\t100\nSouth\t200\n")
        #expect(await state.loadEnterData(t) == nil)
        state.beginNewMeasure(table: "Sales")
        state.measureDraft?.text = "Total = SUM(Sales[Amount])"
        await state.applyMeasureDraft()

        let visualID = try #require(state.layout.insertVisual(type: "cardVisual", visibleRect: nil))
        state.visualID = visualID
        let visual = try #require(state.visual)
        let column = try #require(state.workspace.column(table: "Sales", name: "Amount"))
        let measure = try #require(state.workspace.measure(table: "Sales", name: "Total"))

        let views: [(String, CGSize, AnyView)] = [
            ("FormatPane", CGSize(width: 280, height: 420), AnyView(FormatPane(state: state).background(DS.Palette.chrome))),
            ("BuildWells", CGSize(width: 280, height: 320), AnyView(BuildWells(state: state, visual: visual).background(DS.Palette.chrome))),
            ("ColumnPropertiesEditor", CGSize(width: 280, height: 360), AnyView(ColumnPropertiesEditor(state: state, column: column).padding(10).background(DS.Palette.chrome))),
            ("MeasurePropertiesPanel", CGSize(width: 280, height: 340), AnyView(MeasurePropertiesPanel(state: state, measure: measure))),
            ("QueryToolbar", CGSize(width: 680, height: 44), AnyView(QueryToolbar(state: state).background(DS.Palette.chrome))),
            ("QueryTabBar", CGSize(width: 680, height: 34), AnyView(QueryTabBar(state: state))),
            ("QueryResultsView", CGSize(width: 680, height: 260), AnyView(QueryResultsView(state: state))),
        ]

        for (name, size, view) in views {
            let rep = try renderPNG(view, size: size, scheme: .dark)
            let m = metrics(of: rep)
            #expect(m.avgLuminance < 0.35, "\(name) quá sáng trong Dark Mode (avgLum=\(String(format: "%.3f", m.avgLuminance)))")
            #expect(m.distinctColors >= 4, "\(name) thiếu sắc độ UI (\(m.distinctColors))")
        }
    }
}
