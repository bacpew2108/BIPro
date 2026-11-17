// Đợt tồn đọng sau Phase F, US1 (T010): phép gộp ngầm. Golden: `f10-desktop.pbix` Desktop lưu ở VM-F10 (ngoài git, thiếu thì bỏ qua)
// và văn bản Performance Analyzer `docs/phase-f2-evidence/vm-f10/golden-queries.json` (visualId → truy vấn). Truy vấn so sau khi
// chuẩn hoá khoảng trắng như golden Phase C.
import DAXTestSupport
import Foundation
import PBIXKit
import Testing
@testable import BIPro

private struct F10Report: @unchecked Sendable {
    let metadata: ModelMetadata
    let report: ReportDefinition
}

private let f10: Result<F10Report, Error> = Result {
    let pbix = try PBIXFile(url: try #require(F2Fixtures.desktop("vm-f10", "f10-desktop.pbix")))
    let (abf, _) = try pbix.loadDataModel()
    return F10Report(metadata: try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb")), report: try pbix.loadReport())
}

private func goldenQueries() throws -> [String: String] {
    let url = F2Fixtures.root.appendingPathComponent("docs/phase-f2-evidence/vm-f10/golden-queries.json")
    return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
}

@Suite(.enabled(if: F2Fixtures.desktop("vm-f10", "f10-desktop.pbix") != nil))
struct ImplicitAggregationGoldenTests {
    /// Biểu đồ cột không trục (6 phép gộp), biểu đồ cột theo Region (Sum, Variance, Median), card cột chữ (First = MIN).
    /// Card phân cấp ngày (`a0e188ab…`) thuộc US2 (bảng ngày cục bộ, T034).
    @Test(arguments: ["32c278f0a20143906d5e", "7bcc23338e8023ea1450", "34ba2c516a0e180025a6"])
    func vanBanGiongPerformanceAnalyzer(_ visualID: String) throws {
        let model = try f10.get()
        let visual = try #require(model.report.pages.flatMap(\.visuals).first { $0.id == visualID })
        let spec = try VisualQuerySpecReader(metadata: model.metadata).spec(for: visual, filters: [])
        let ours = DAXQueryBuilder.normalized(DAXQueryBuilder.build(spec))
        let theirs = DAXQueryBuilder.normalized(try #require(try goldenQueries()[visualID]))
        #expect(ours == theirs, "\(visualID)\n--- Power BI\n\(theirs)\n--- BI Pro\n\(ours)")
    }

    @Test func truongGopCoNhanTiengVietVaDinhDang() throws {
        let model = try f10.get()
        let visual = try #require(model.report.pages.flatMap(\.visuals).first { $0.id == "32c278f0a20143906d5e" })
        let spec = try VisualQuerySpecReader(metadata: model.metadata).spec(for: visual, filters: [])
        #expect(spec.measures.map(\.field.displayName) == ["Trung bình của Amount", "Số lượng (riêng biệt) của CustomerID",
                                                          "Số lượng của OrderID", "Lớn nhất của Price",
                                                          "Độ lệch chuẩn của ProductID", "Nhỏ nhất của Qty"])
        #expect(spec.measures.map(\.aggregation) == [.average, .countDistinct, .count, .max, .standardDeviation, .min])
        let card = try #require(model.report.pages.flatMap(\.visuals).first { $0.id == "34ba2c516a0e180025a6" })
        let cardSpec = try VisualQuerySpecReader(metadata: model.metadata).spec(for: card, filters: [])
        #expect(cardSpec.measures.map(\.field.displayName) == ["Đầu tiên của Region"])
    }
}

/// Gate T016: Desktop mở `bipro-f10.pbix` do BI Pro ghi (bản chép ở `vm-f10/`, ngoài git) và Performance Analyzer của Desktop sinh truy
/// vấn `gate-queries.json`; văn bản BI Pro sinh cho cùng visual phải trùng.
@Suite(.enabled(if: F2Fixtures.desktop("vm-f10", "bipro-f10.pbix") != nil))
struct ImplicitAggregationGateTests {
    @Test func truyVanBIProTrungDesktopTrenFileBIProGhi() throws {
        let pbix = try PBIXFile(url: try #require(F2Fixtures.desktop("vm-f10", "bipro-f10.pbix")))
        let (abf, _) = try pbix.loadDataModel()
        let reader = VisualQuerySpecReader(metadata: try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb")))
        let visuals = try pbix.loadReport().pages.flatMap(\.visuals)
        let url = F2Fixtures.root.appendingPathComponent("docs/phase-f2-evidence/vm-f10/gate-queries.json")
        let golden = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        #expect(golden.count == 3)
        for (id, theirs) in golden {
            let visual = try #require(visuals.first { $0.id == id })
            let ours = DAXQueryBuilder.normalized(DAXQueryBuilder.build(try reader.spec(for: visual, filters: [])))
            #expect(ours == DAXQueryBuilder.normalized(theirs), Comment(rawValue: id))
        }
    }
}

@Suite struct ImplicitAggregationUnitTests {
    @Test func maPBIRVaHamDAXTheoVMF10() {
        #expect(AggregateFunction.allCases.map(\.rawValue) == Array(0...8))
        #expect(AggregateFunction.allCases.map(\.daxFunction)
                == ["SUM", "AVERAGE", "DISTINCTCOUNT", "MIN", "MAX", "COUNTA", "MEDIAN", "STDEV.P", "VAR.P"])
        #expect(AggregateFunction.allCases.map(\.resultPrefix)
                == ["Sum", "Average", "DistinctCount", "Min", "Max", "Count", "Median", "StandardDeviation", "Variance"])
    }

    @Test func truongGopSinhCalculateHam() {
        let field = FieldInfo(queryRef: "Sum(Sales.Amount)", displayName: "Tổng của Amount", role: "Y", formatString: nil, isMeasure: true)
        var spec = VisualQuerySpec(visualID: "v", visualType: "clusteredColumnChart")
        spec.shape = .chart
        spec.primary = [GroupField(field: FieldInfo(queryRef: "Sales.Region", displayName: "Region", role: "Category", formatString: nil,
                                                    isMeasure: false),
                                   column: QueryColumn(table: "Sales", column: "Region"), sortBy: nil)]
        spec.measures = [QueryMeasure(field: field, table: "Sales", measure: "Amount", resultName: "SumAmount", ignore: false,
                                      purpose: .value, aggregation: .sum)]
        #expect(DAXQueryBuilder.build(spec).contains("\"SumAmount\", CALCULATE(SUM('Sales'[Amount]))"))
    }
}
