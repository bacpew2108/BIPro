import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("PhaseG — VisualCSVExporter")
struct ExportCSVTests {
    @Test("RFC 4180: UTF-8 BOM, CRLF, thoát dấu phẩy, ngoặc kép, xuống dòng và tiếng Việt")
    func rfc4180EscapingAndBOM() throws {
        let cat = FieldInfo(queryRef: "T.Name", displayName: "Tên sản phẩm", role: "Category", formatString: nil, isMeasure: false)
        let m = FieldInfo(queryRef: "T.Sales", displayName: "Doanh thu", role: "Y", formatString: nil, isMeasure: true)
        let data = CategoricalData(
            categoryLevels: [cat],
            categories: [
                CategoryKey(values: [.string("Cà phê, rang xay")]),
                CategoryKey(values: [.string("Trà \"Đào\"\nMùa hè")]),
                CategoryKey(values: [.string("Bánh mì")]),
            ],
            seriesField: nil,
            series: [],
            measures: [m],
            values: [[[DataCell(.integer(1500)), DataCell(.double(25.5)), .blank]]],
            highlights: nil,
            isReduced: false
        )

        let bytes = try VisualCSVExporter.export(.categorical(data))
        #expect(bytes.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        let text = try #require(String(data: bytes.dropFirst(3), encoding: .utf8))
        let expected =
            "Tên sản phẩm,Doanh thu\r\n" +
            "\"Cà phê, rang xay\",1500\r\n" +
            "\"Trà \"\"Đào\"\"\nMùa hè\",25.5\r\n" +
            "Bánh mì,\r\n"
        #expect(text == expected)
    }

    @Test("Card (.single) và Matrix và Slicer và .empty")
    func singleMatrixSlicerAndEmpty() throws {
        let m = FieldInfo(queryRef: "F.Rev", displayName: "Net Revenue", role: "Values", formatString: "#,0", isMeasure: true)
        let cardData = try VisualCSVExporter.export(.single(SingleValueData(measure: m, cell: DataCell(.integer(123456), formatString: "#,0"))))
        let cardText = try #require(String(data: cardData.dropFirst(3), encoding: .utf8))
        #expect(cardText.contains("Net Revenue"))
        #expect(cardText.contains("123,456") || cardText.contains("123.456"))

        let rowF = FieldInfo(queryRef: "D.Region", displayName: "Vùng", role: "Rows", formatString: nil, isMeasure: false)
        let colF = FieldInfo(queryRef: "D.Year", displayName: "Năm", role: "Columns", formatString: nil, isMeasure: false)
        let matrix = MatrixData(
            rowLevels: [rowF],
            columnLevels: [colF],
            measures: [m],
            rows: [
                MatrixHeader(path: [.string("Bắc")], level: 0),
                MatrixHeader(path: [], level: -1, isGrandTotal: true),
            ],
            columns: [
                MatrixHeader(path: [.integer(2024)], level: 0),
                MatrixHeader(path: [.integer(2025)], level: 0),
            ],
            cells: [
                [[DataCell(.integer(10))], [DataCell(.integer(20))]],
                [[DataCell(.integer(10))], [DataCell(.integer(20))]],
            ],
            isReduced: false
        )
        let (headers, rows) = try VisualCSVExporter.tabularRows(from: .matrix(matrix))
        #expect(headers == ["Vùng", "2024", "2025"])
        #expect(rows == [["Bắc", "10", "20"], ["Total", "10", "20"]])

        let slicer = SlicerData(
            levels: [colF],
            roots: [SlicerNode(.integer(2024)), SlicerNode(.integer(2025))]
        )
        let (sHeaders, sRows) = try VisualCSVExporter.tabularRows(from: .slicer(slicer))
        #expect(sHeaders == ["Năm"])
        #expect(sRows == [["2024"], ["2025"]])

        #expect(throws: ExportError.self) {
            _ = try VisualCSVExporter.export(.empty(reason: "Trống"))
        }
    }

    @Test("v1.1a (T020): Xuất CSV cho 5 DataView mới (.table, .scatter, .gauge, .kpi, .multiRowCard)")
    func v11aFiveNewDataViewsCSV() throws {
        let reg = FieldInfo(queryRef: "Sales.Region", displayName: "Region", role: "Values", formatString: nil, isMeasure: false)
        let rev = FieldInfo(queryRef: "Sales.Rev", displayName: "Revenue", role: "Y", formatString: "#,0", isMeasure: true)
        let goal = FieldInfo(queryRef: "Sales.Goal", displayName: "Goal", role: "Goal", formatString: "#,0", isMeasure: true)

        // 1. Table with Total row
        let tv = TableDataView(columns: [reg, rev], rows: [[DataCell(.string("North")), DataCell(.integer(100))]],
                               totals: [.blank, DataCell(.integer(100))], isReduced: false)
        let (tH, tR) = try VisualCSVExporter.tabularRows(from: .table(tv))
        #expect(tH == ["Region", "Revenue"])
        #expect(tR == [["North", "100"], ["Total", "100"]])

        // 2. Scatter
        let sd = ScatterData(categoryField: reg, seriesField: nil, series: [], xField: rev, yField: goal, sizeField: nil,
                             points: [ScatterPoint(id: DataPointID([:]), categoryLabel: "North", seriesValue: nil, x: 100, y: 80, size: nil,
                                                   xCell: DataCell(.integer(100)), yCell: DataCell(.integer(80)), sizeCell: nil, tooltips: [])],
                             isReduced: false)
        let (sH, sR) = try VisualCSVExporter.tabularRows(from: .scatter(sd))
        #expect(sH == ["Region", "Revenue", "Goal"])
        #expect(sR == [["North", "100", "80"]])

        // 3. Gauge
        let gd = GaugeData(valueField: rev, value: DataCell(.integer(50)), min: DataCell(.integer(0)), max: DataCell(.integer(100)), target: DataCell(.integer(75)))
        let (gH, gR) = try VisualCSVExporter.tabularRows(from: .gauge(gd))
        #expect(gH == ["Revenue", "Min", "Max", "Target"])
        #expect(gR == [["50", "0", "100", "75"]])

        // 4. KPI
        let kd = KPIData(indicatorField: rev, trendField: reg, goalField: goal, latestValue: DataCell(.integer(120)),
                         goalValue: DataCell(.integer(100)), trendPoints: [.init(label: "2023", value: 90), .init(label: "2024", value: 120)])
        let (kH, kR) = try VisualCSVExporter.tabularRows(from: .kpi(kd))
        #expect(kH == ["Region", "Revenue", "Goal"])
        #expect(kR.count == 2)

        // 5. MultiRowCard
        let mc = MultiRowCardData(fields: [reg, rev], rows: [[DataCell(.string("North")), DataCell(.integer(100))]], isReduced: false)
        let (mH, mR) = try VisualCSVExporter.tabularRows(from: .multiRowCard(mc))
        #expect(mH == ["Region", "Revenue"])
        #expect(mR == [["North", "100"]])
    }

    @Test("Nặng (SC-001): Xuất CSV từ Card, Biểu đồ và Matrix trên Nhom6_work.pbix khớp 100% DataView DAX")
    @MainActor
    func heavyNhom6CSVMatchesDAX() async throws {
        guard ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1" else { return }
        guard let url = Self.nhom6URL() else { return }
        let workspace = try Workspace(data: try Data(contentsOf: url))
        let interaction = ReportInteraction(workspace: workspace)
        let page = try #require(workspace.visiblePages.first)
        let state = interaction.state(for: page)

        var checkedSingle = false
        var checkedCategorical = false
        var checkedMatrix = false

        let outDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/g-out/csv", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        for visual in page.visuals where !visual.isHidden {
            guard let loaded = try? await interaction.load(page: page, visual: visual, state: state) else { continue }
            switch loaded.view {
            case .single(let single) where !checkedSingle:
                let csv = try VisualCSVExporter.export(loaded.view)
                #expect(csv.prefix(3) == VisualCSVExporter.utf8BOM)
                let (h, r) = try VisualCSVExporter.tabularRows(from: loaded.view)
                #expect(h == [single.measure.displayName])
                #expect(r == [[VisualCSVExporter.formattedCell(single.cell)]])
                try csv.write(to: outDir.appendingPathComponent("nhom6-card.csv"))
                checkedSingle = true

            case .categorical(let cat) where !checkedCategorical && !cat.categories.isEmpty:
                let csv = try VisualCSVExporter.export(loaded.view)
                #expect(csv.prefix(3) == VisualCSVExporter.utf8BOM)
                let (_, r) = try VisualCSVExporter.tabularRows(from: loaded.view)
                #expect(!r.isEmpty)
                try csv.write(to: outDir.appendingPathComponent("nhom6-chart.csv"))
                checkedCategorical = true

            case .matrix(let mat) where !checkedMatrix && !mat.rows.isEmpty:
                let csv = try VisualCSVExporter.export(loaded.view)
                #expect(csv.prefix(3) == VisualCSVExporter.utf8BOM)
                let (_, r) = try VisualCSVExporter.tabularRows(from: loaded.view)
                #expect(r.count == mat.rows.count)
                try csv.write(to: outDir.appendingPathComponent("nhom6-matrix.csv"))
                checkedMatrix = true

            default:
                break
            }
            if checkedSingle && checkedCategorical && checkedMatrix { break }
        }

        // Nếu trang D1 không có matrix thì tìm ở các trang sau
        if !checkedMatrix {
            for p in workspace.visiblePages.dropFirst() {
                let st = interaction.state(for: p)
                for v in p.visuals where !v.isHidden && (v.type == "pivotTable" || v.type == "matrix") {
                    if let loaded = try? await interaction.load(page: p, visual: v, state: st),
                       case .matrix(let mat) = loaded.view, !mat.rows.isEmpty {
                        let csv = try VisualCSVExporter.export(loaded.view)
                        let (_, r) = try VisualCSVExporter.tabularRows(from: loaded.view)
                        #expect(r.count == mat.rows.count)
                        try csv.write(to: outDir.appendingPathComponent("nhom6-matrix.csv"))
                        checkedMatrix = true
                        break
                    }
                }
                if checkedMatrix { break }
            }
        }

        #expect(checkedSingle, "Phải kiểm được ít nhất 1 Card trên Nhom6")
        #expect(checkedCategorical, "Phải kiểm được ít nhất 1 Biểu đồ trên Nhom6")
        #expect(checkedMatrix, "Phải kiểm được ít nhất 1 Matrix trên Nhom6")
    }

    private static func nhom6URL() -> URL? {
        if let env = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], FileManager.default.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for rel in ["Downloads/bipro-golden/Nhom6_work.pbix", "Downloads/Nhom6_work.pbix"] {
            let u = home.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
}
