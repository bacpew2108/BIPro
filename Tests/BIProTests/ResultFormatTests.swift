// Kiểm định dạng kết quả của DAX Query View (UI1) với bằng chứng thật từ Power BI Desktop (buổi 1):
// - Copy (O2): so từng byte với docs/phase-b-evidence/observe/O1-copy.tsv do người dùng copy từ Power BI.
// - Lưới (O1): so với ảnh O1-grid.png (giá trị đọc từ ảnh).
import Foundation
import Testing
import DAXEngine
@testable import BIPro

@Suite struct ResultFormatTests {
    /// Cùng các giá trị như truy vấn observe/O1-format.dax, theo kiểu engine trả về.
    private static let o1Table: ResultTable = {
        let dt: Double = 43_465 + (16.0 * 3600 + 3 * 60 + 36) / 86_400
        return ResultTable(
            columns: ["[int]", "[dbl]", "[big]", "[neg]", "[cur]", "[date]", "[dt]", "[bool]", "[blank]", "[empty]",
                      "[vn]", "[inf]", "[nan]"],
            rows: [[.integer(1), .double(1.0 / 3), .double(6257793560.3), .double(-0.000001), .currency(12_346),
                    .dateTime(43_465), .dateTime(dt), .boolean(true), .blank, .string(""),
                    .string("Không có số liệu ▲"), .double(.infinity), .double(.nan)]])
    }()

    private static let evidence = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/phase-b-evidence/observe")

    @Test func copyGiongHetFileCopyCuaPowerBI() throws {
        let expected = try Data(contentsOf: Self.evidence.appendingPathComponent("O1-copy.tsv"))
        let actual = Data(ResultFormat.tsv(Self.o1Table).utf8)
        #expect(actual == expected, "\(String(decoding: actual, as: UTF8.self))")
    }

    @Test func hienThiTheoLuoiPowerBI() {
        let row = Self.o1Table.rows[0]
        #expect(row.map(ResultFormat.display) == [
            "1", "0.33", "6257793560.3", "0", "1.23", "12/31/2018 12:00:00 AM", "12/31/2018 4:03:36 PM", "True",
            "", "", "Không có số liệu ▲", "Infinity", "NaN",
        ])
    }

    @Test func soThucDayDuKhongKyHieuMu() {
        #expect(ResultFormat.fullDouble(1e20) == "100000000000000000000")
        #expect(ResultFormat.fullDouble(1.5e-7) == "0.00000015")
        #expect(ResultFormat.fullDouble(-2.5) == "-2.5")
        #expect(ResultFormat.fullDouble(3) == "3")
        #expect(ResultFormat.fullDouble(0.1 + 0.2) == "0.30000000000000004")
    }

    @Test func csvBocNhayKhiCan() {
        let table = ResultTable(columns: ["[a]", "[b]"], rows: [[.string("x,y"), .string("say \"hi\"")]])
        #expect(ResultFormat.csv(table) == "[a],[b]\r\n\"x,y\",\"say \"\"hi\"\"\"\r\n")
    }

    @Test func thuTuSapXepDuocApKhiCopy() {
        let table = ResultTable(columns: ["[n]"], rows: [[.integer(1)], [.integer(2)], [.integer(3)]])
        #expect(ResultFormat.tsv(table, order: [2, 0, 1]) == "[n]\r\n3\r\n1\r\n2")
    }

    @Test func loiCoViTriTheoDangPowerBI() {
        let error = DAXError(.unknownName, "Column 'yearx' in table 'Dim_Date' cannot be found",
                             range: SourceRange(start: 10, end: 15, line: 4, column: 2))
        #expect(QueryResultsView.errorText(error) == "Query (4, 2) Column 'yearx' in table 'Dim_Date' cannot be found")
        #expect(QueryResultsView.errorText(DAXError(.runtime, "x")) == "x")
    }
}
