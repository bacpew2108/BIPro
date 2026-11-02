// Gói Q: bộ sinh truy vấn visual phải ra ĐÚNG văn bản Power BI (sau khi chuẩn hoá khoảng trắng).
// Golden: truy vấn Performance Analyzer thật ở trạng thái mặc định (buổi C1 và buổi 2 của Phase B).
// Chạy khi có ~/Downloads/Nhom6_Dashboard.pbix (chỉ đọc metadata và report, không đọc dữ liệu cột).
import DAXTestSupport
import Foundation
import PBIXKit
import Testing
@testable import BIPro

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Tên file golden → (trang, tiền tố id visual).
private let goldenVisuals: [(file: String, page: String, visual: String)] = [
    ("pa/D1-slicer-nam", "d1_giaodich", "f4c48650"), ("pa/D1-slicer-vung", "d1_giaodich", "c0076ed4"),
    ("pa/D1-slicer-loaigd", "d1_giaodich", "83b98895"), ("pa/D1-slicer-loaithe", "d1_giaodich", "b3cf5dc6"),
    ("pa/D1-slicer-nhomtuoi", "d1_giaodich", "f264fab9"), ("pa/D1-card-tienvao", "d1_giaodich", "7362dc48"),
    ("pa/D1-card-tienvao-delta", "d1_giaodich", "ea0f95d9"), ("pa/D1-line-thang", "d1_giaodich", "c3662592"),
    ("pa/D1-donut", "d1_giaodich", "b1106ee1"), ("pa/D1-matrix-gio-thu", "d1_giaodich", "2132ddc1"),
    ("pa/D1-combo-dongtien", "d1_giaodich", "bd7c2a2d"), ("pa/D1-combo-thauchi", "d1_giaodich", "69ca295f"),
    ("pa/D1-matrix-nhomtuoi", "d1_giaodich", "70eec8cd"), ("pa/D1-line-thangtrongnam", "d1_giaodich", "52888e84"),
    ("pa/D2-slicer-1", "d2_khoanvay", "a9bb9c5a"), ("pa/D2-slicer-2", "d2_khoanvay", "2f47bf6f"),
    ("pa/D2-slicer-3", "d2_khoanvay", "d24727b1"), ("pa/D2-slicer-4", "d2_khoanvay", "344274ff"),
    ("pa/D2-slicer-5", "d2_khoanvay", "36f4eb2f"), ("pa/D2-slicer-6", "d2_khoanvay", "5df11828"),
    ("pa/D2-card-giaingan", "d2_khoanvay", "f7e03ae5"), ("pa/D2-card-giaingan-delta", "d2_khoanvay", "4aaa27cf"),
    ("pa/D2-combo-thoigian", "d2_khoanvay", "a1d6568d"), ("pa/D2-donut", "d2_khoanvay", "b87e0317"),
    ("pa/D2-100pct", "d2_khoanvay", "fefd7eb8"), ("pa/D2-shapemap", "d2_khoanvay", "4353768e"),
    ("pa/D2-bar-nhomtuoi", "d2_khoanvay", "7d84e6ad"), ("pa/D2-combo-nhomkh", "d2_khoanvay", "dbe28e74"),
    ("pa/D3-slicer-1", "d3_cskh", "c6bad7af"), ("pa/D3-slicer-2", "d3_cskh", "c39cd1a5"),
    ("pa/D3-slicer-3", "d3_cskh", "9261e4a0"), ("pa/D3-slicer-4", "d3_cskh", "f4f933fc"),
    ("pa/D3-slicer-5", "d3_cskh", "63132cdf"), ("pa/D3-slicer-6", "d3_cskh", "edf505fc"),
    ("pa/D3-card-khachhang", "d3_cskh", "595dca09"), ("pa/D3-card-khachhang-sub", "d3_cskh", "2de88bf0"),
    ("pa/D3-combo-kenh", "d3_cskh", "5c5c251a"), ("pa/D3-combo-pareto", "d3_cskh", "aabc04ac"),
    ("pa/D3-bar-sanpham", "d3_cskh", "c1ed9ef5"), ("pa/D3-combo-phanhoi", "d3_cskh", "e32431bc"),
    ("pa/D3-treemap", "d3_cskh", "312cad44"), ("pa/D3-bar-nhomkh", "d3_cskh", "1106a6e5"),
    ("PA-D4-1", "d4_chinhanh", "a165a2a3"), ("PA-D4-2", "d4_chinhanh", "002f3167"),
]

/// Khuôn chưa làm, có lý do (không tính là lỗi của bộ sinh).
private let knownGaps: [String: String] = [
    "pa/D1-slicer-nam": "slicer hierarchy đang mở nút 2011 (expansionStates → ROLLUPADDISSUBTOTAL + NONVISUAL), chưa làm",
]

private struct Nhom6Report: @unchecked Sendable {
    let metadata: ModelMetadata
    let report: ReportDefinition
    let filters: (report: [ReportFilter], pages: [String: [ReportFilter]], visuals: [String: [ReportFilter]])
}

private let nhom6: Result<Nhom6Report, Error> = Result {
    let pbix = try PBIXFile(url: DAXFixtures.nhom6)
    let (abf, _) = try pbix.loadDataModel()
    let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    let report = try pbix.loadReport()
    return Nhom6Report(metadata: metadata, report: report, filters: pbix.loadFilters(report: report))
}

private func goldenText(_ file: String) throws -> String {
    let url = file.hasPrefix("PA-")
        ? repo.appendingPathComponent("docs/phase-b-evidence/observe2/\(file).dax")
        : repo.appendingPathComponent("docs/phase-c-evidence/observe-c1/\(file).dax")
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite(.enabled(if: DAXFixtures.exists(DAXFixtures.nhom6)))
struct DAXQueryBuilderGoldenTests {
    @Test(arguments: goldenVisuals.map(\.file))
    func vanBanGiongPowerBI(_ file: String) throws {
        let model = try nhom6.get()
        let entry = try #require(goldenVisuals.first { $0.file == file })
        let page = try #require(model.report.pages.first { $0.id == entry.page })
        let visual = try #require(page.visuals.first { $0.id.hasPrefix(entry.visual) })
        let filters = (model.filters.visuals[visual.id] ?? []) + (model.filters.pages[page.id] ?? []) + model.filters.report
        let spec = try VisualQuerySpecReader(metadata: model.metadata).spec(for: visual, filters: filters)
        let ours = DAXQueryBuilder.normalized(DAXQueryBuilder.build(spec))
        let theirs = DAXQueryBuilder.normalized(try goldenText(file))
        if let gap = knownGaps[file] {
            withKnownIssue(Comment(rawValue: gap)) { #expect(ours == theirs) }
            return
        }
        #expect(ours == theirs, "\(file)\n--- Power BI\n\(theirs)\n--- BI Pro\n\(ours)\n--- lệch từ: \(firstDifference(ours, theirs))")
    }
}

@Suite(.enabled(if: DAXFixtures.exists(DAXFixtures.nhom6)))
struct DAXQueryBuilderCoverageTests {
    /// Đếm độc lập số visual khớp, để chắc test tham số hoá không bỏ sót ca nào.
    @Test func soVisualKhop() throws {
        let model = try nhom6.get()
        let reader = VisualQuerySpecReader(metadata: model.metadata)
        var matched: [String] = []
        for entry in goldenVisuals {
            guard let page = model.report.pages.first(where: { $0.id == entry.page }),
                  let visual = page.visuals.first(where: { $0.id.hasPrefix(entry.visual) }) else { continue }
            let filters = (model.filters.visuals[visual.id] ?? []) + (model.filters.pages[page.id] ?? []) + model.filters.report
            guard let spec = try? reader.spec(for: visual, filters: filters) else { continue }
            if DAXQueryBuilder.normalized(DAXQueryBuilder.build(spec)) == DAXQueryBuilder.normalized(try goldenText(entry.file)) {
                matched.append(entry.file)
            }
        }
        #expect(goldenVisuals.count == 44)
        #expect(matched.count == goldenVisuals.count - knownGaps.count, "khớp \(matched.count)/\(goldenVisuals.count)")
    }
}

private func firstDifference(_ a: String, _ b: String) -> String {
    let i = zip(a, b).prefix { $0 == $1 }.count
    return "ký tự \(i): …\(a.dropFirst(max(0, i - 30)).prefix(70))… / …\(b.dropFirst(max(0, i - 30)).prefix(70))…"
}

@Suite struct DAXQueryBuilderUnitTests {
    @Test func chuanHoaBoKhoangTrangVaDongDau() {
        let a = "// DAX Query\nDEFINE\n\tVAR x = \n\t\tTOPN(\n\t\t\t1,\n\t\t\tT\n\t\t)\n"
        #expect(DAXQueryBuilder.normalized(a) == "DEFINE VAR x = TOPN(1, T)")
        #expect(DAXQueryBuilder.normalized("IN {2016,\r\n\t\t\t\t2017}") == "IN {2016, 2017}")
    }

    @Test func tachDoiSoCapNgoai() {
        #expect(DAXQueryBuilder.topLevelArguments("KEEPFILTERS(VALUES('T'[c])), NOT('T'[c] IN {1, 2})")
                == ["KEEPFILTERS(VALUES('T'[c]))", "NOT('T'[c] IN {1, 2})"])
        #expect(DAXQueryBuilder.topLevelArguments("\"a, b\", 1") == ["\"a, b\"", "1"])
    }
}
