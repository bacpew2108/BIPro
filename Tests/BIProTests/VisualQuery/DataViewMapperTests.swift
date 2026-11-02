// Gói Q: DataViewMapper đọc đúng các bảng kết quả theo khuôn Power BI.
// Dữ liệu vào là kết quả THẬT của Power BI (observe-c1/results/*.tsv), đổi sang ResultTable.
import DAXEngine
import DAXTestSupport
import Foundation
import PBIXKit
import Testing
@testable import BIPro

private let resultsDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("docs/phase-c-evidence/observe-c1/results")

/// File Copy của Power BI → các ResultTable (tách theo dòng `#RESULT n`). Ô: rỗng → BLANK, true/false → boolean,
/// số nguyên → integer, số thực → double, còn lại là chuỗi.
func powerBIResult(_ name: String) throws -> QueryResult {
    let text = try String(contentsOf: resultsDir.appendingPathComponent("\(name).tsv"), encoding: .utf8)
        .replacingOccurrences(of: "\r", with: "")
    var tables: [ResultTable] = []
    var lines: [String] = []
    func flush() {
        guard let header = lines.first else { return }
        let rows = lines.dropFirst().filter { !$0.isEmpty }.map { line in
            line.components(separatedBy: "\t").map { cell -> Value in
                if cell.isEmpty { return .blank }
                if cell == "true" || cell == "false" { return .boolean(cell == "true") }
                if let i = Int64(cell) { return .integer(i) }
                if let d = Double(cell) { return .double(d) }
                return .string(cell)
            }
        }
        tables.append(ResultTable(columns: header.components(separatedBy: "\t"), rows: rows))
        lines = []
    }
    for line in text.components(separatedBy: "\n") {
        if line.hasPrefix("#RESULT") { flush(); continue }
        lines.append(line)
    }
    flush()
    return QueryResult(tables: tables, elapsedNanoseconds: 0)
}

private struct Model: @unchecked Sendable {
    let reader: VisualQuerySpecReader
    let report: ReportDefinition
    let filters: (report: [ReportFilter], pages: [String: [ReportFilter]], visuals: [String: [ReportFilter]])

    func spec(page: String, visual prefix: String) throws -> VisualQuerySpec {
        let p = try #require(report.pages.first { $0.id == page })
        let v = try #require(p.visuals.first { $0.id.hasPrefix(prefix) })
        return try reader.spec(for: v, filters: (filters.visuals[v.id] ?? []) + (filters.pages[p.id] ?? []) + filters.report)
    }
}

private let model: Result<Model, Error> = Result {
    let pbix = try PBIXFile(url: DAXFixtures.nhom6)
    let (abf, _) = try pbix.loadDataModel()
    let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    let report = try pbix.loadReport()
    return Model(reader: VisualQuerySpecReader(metadata: metadata), report: report, filters: pbix.loadFilters(report: report))
}

@Suite(.enabled(if: DAXFixtures.exists(DAXFixtures.nhom6)))
struct DataViewMapperTests {
    @Test func barCoSeriesTheoGioiTinh() throws {
        let spec = try model.get().spec(page: "d3_cskh", visual: "1106a6e5")
        guard case .categorical(let d) = DataViewMapper.map(try powerBIResult("D3-bar-nhomkh"), spec: spec) else {
            Issue.record("không phải categorical"); return
        }
        #expect(d.series == [.string("Female"), .string("Male")])
        #expect(d.categories.first == CategoryKey(values: [.string("<25")]))
        #expect(d.measures.map(\.role) == ["Y", "Tooltips"])
        // Dòng đầu: <25, Female (ColumnIndex 0) = 4488.70…; dòng hai: <25, Male = 4450.42…
        #expect(d.cell(measure: 0, series: 0, category: 0).value == .double(4488.700564971752))
        #expect(d.cell(measure: 0, series: 1, category: 0).value == .double(4450.42492917847))
        #expect(d.cell(measure: 1, series: 1, category: 0).value == .integer(1571))
    }

    @Test func donutBoDongTong() throws {
        let spec = try model.get().spec(page: "d2_khoanvay", visual: "b87e0317")
        guard case .categorical(let d) = DataViewMapper.map(try powerBIResult("D2-donut"), spec: spec) else {
            Issue.record("không phải categorical"); return
        }
        #expect(d.categories.map(\.values) == [[.string("Car")], [.string("Debt_Consolidation")], [.string("Home")], [.string("Home_Improvement")]])
        #expect(d.cell(measure: 0, series: 0, category: 2).value == .integer(97_894_260))
        #expect(d.measures.map(\.role) == ["Y", "Tooltips", "Tooltips"])
    }

    @Test func matrixGioThuCoMauVaIcon() throws {
        let spec = try model.get().spec(page: "d1_giaodich", visual: "2132ddc1")
        guard case .matrix(let m) = DataViewMapper.map(try powerBIResult("D1-matrix-gio-thu"), spec: spec) else {
            Issue.record("không phải matrix"); return
        }
        #expect(m.columns.map(\.path) == ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].map { [.string($0)] })
        #expect(m.measures.count == 1)
        #expect(m.rows.allSatisfy { !$0.isGrandTotal })
        #expect(m.cells.count == m.rows.count)
        // Có ít nhất một ô mang màu chữ và một ô mang icon SVG lấy từ measure.
        let all = m.cells.flatMap { $0.flatMap { $0 } }
        #expect(all.contains { $0.fontColor?.hasPrefix("#") == true })
        #expect(all.contains { $0.icon?.hasPrefix("data:image/svg+xml") == true })
    }

    @Test func comboKhongSeriesMotBang() throws {
        let spec = try model.get().spec(page: "d1_giaodich", visual: "69ca295f")
        guard case .categorical(let d) = DataViewMapper.map(try powerBIResult("D1-combo-thauchi"), spec: spec) else {
            Issue.record("không phải categorical"); return
        }
        #expect(d.categories.count == 72)
        #expect(d.measures.map(\.role) == ["Y", "Y2", "Tooltips", "Tooltips", "Tooltips"])
        // Overdraft Rate có định dạng động: ô mang chuỗi định dạng của dòng.
        #expect(d.cell(measure: 2, series: 0, category: 0).formatString != nil)
        // Màu cột từ `Neg Trans Alert Color` gắn vào measure đích của selector.
        let colored = d.values.flatMap { $0.flatMap { $0 } }.contains { $0.fillColor != nil }
        #expect(colored)
    }
}
