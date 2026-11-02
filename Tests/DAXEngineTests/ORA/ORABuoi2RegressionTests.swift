// Hồi quy cho các hành vi sửa theo golden và quan sát Power BI buổi 2 (docs/phase-b-evidence/BUOI2.md).
// Chạy trên MiniBank nên không cần fixture Nhom6.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct ORABuoi2RegressionTests {
    private let engine = ftEngine(MiniBank.makeSource())

    private func one(_ query: String) async throws -> Value {
        let rows = try await engine.execute(query).tables[0].rows
        try #require(rows.count == 1 && rows[0].count == 1, "cần đúng một ô, nhận \(rows)")
        return rows[0][0]
    }

    private func column(_ query: String) async throws -> [Value] {
        try await engine.execute(query).tables[0].rows.map { $0[0] }
    }

    /// G5-month, [Complaints MA3]: hai đối số CALCULATE trên cùng một cột phải giao nhau, không ghi đè nhau.
    @Test func calculateHaiBoLocCungCotGiaoNhau() async throws {
        let n = try await one("""
        EVALUATE ROW ( "n", CALCULATE ( COUNTROWS ( Dim_Date ), Dim_Date[year] >= 2024, Dim_Date[year] <= 2024 ) )
        """)
        #expect(n == .integer(366), "chỉ năm 2024; ghi đè sẽ cho 731")
        // Vẫn ghi đè bộ lọc NGOÀI trên cùng cột.
        let outer = try await one("""
        EVALUATE ROW ( "n", CALCULATE ( CALCULATE ( COUNTROWS ( Dim_Date ), Dim_Date[year] >= 2023, Dim_Date[year] <= 2023 ),
                                        Dim_Date[year] = 2024 ) )
        """)
        #expect(outer == .integer(365))
    }

    /// T2-time-edges: trọn tháng cho trọn tháng đích; ngày lẻ dịch từng ngày và kẹp, không mở rộng tới cuối tháng.
    @Test func dichNgayTronThangVaNgayLe() async throws {
        func dates(_ inner: String) -> String {
            "FILTER ( VALUES ( Dim_Date[full_date] ), \(inner) )"
        }
        let feb2023 = dates("Dim_Date[full_date] >= DATE ( 2023, 2, 1 ) && Dim_Date[full_date] <= DATE ( 2023, 2, 28 )")
        #expect(try await one("EVALUATE ROW ( \"n\", COUNTROWS ( DATEADD ( \(feb2023), 1, YEAR ) ) )") == .integer(29))
        let feb2024 = dates("Dim_Date[full_date] >= DATE ( 2024, 2, 1 ) && Dim_Date[full_date] <= DATE ( 2024, 2, 29 )")
        #expect(try await one("EVALUATE ROW ( \"n\", COUNTROWS ( SAMEPERIODLASTYEAR ( \(feb2024) ) ) )") == .integer(28))
        // 28/02/2023 +1 năm = 28/02/2024 (45350), một ngày.
        let d28 = dates("Dim_Date[full_date] = DATE ( 2023, 2, 28 )")
        #expect(try await column("EVALUATE DATEADD ( \(d28), 1, YEAR )") == [.dateTime(45350)])
        // 30/04/2024 −1 tháng = 30/03/2024 (45381), không thêm 31/03.
        let d30 = dates("Dim_Date[full_date] = DATE ( 2024, 4, 30 )")
        #expect(try await column("EVALUATE DATEADD ( \(d30), -1, MONTH )") == [.dateTime(45381)])
        // T5 (buổi 3): khoảng lẻ nhiều ngày kết thúc ở cuối tháng thì mở rộng: 15–28/02/2023 +1 năm = 15–29/02/2024.
        let mid = dates("Dim_Date[full_date] >= DATE ( 2023, 2, 15 ) && Dim_Date[full_date] <= DATE ( 2023, 2, 28 )")
        #expect(try await one("EVALUATE ROW ( \"n\", COUNTROWS ( DATEADD ( \(mid), 1, YEAR ) ) )") == .integer(15))
        // 01/03–30/04/2024 −1 tháng = 01/02–31/03/2024: 29 + 31 = 60 ngày.
        let marApr = dates("Dim_Date[full_date] >= DATE ( 2024, 3, 1 ) && Dim_Date[full_date] <= DATE ( 2024, 4, 30 )")
        #expect(try await one("EVALUATE ROW ( \"n\", COUNTROWS ( DATEADD ( \(marApr), -1, MONTH ) ) )") == .integer(60))
    }

    /// G6f1/G6f2 bản lỗi: T[m] với measure m thuộc bảng khác bị Power BI từ chối.
    @Test func measureSaiBangBaoLoi() async {
        await ftExpectDAXError(engine, "EVALUATE ROW ( \"x\", 'Dim_Date'[Trans Amount] )",
                               kind: .unknownName, contains: "thuộc bảng")
    }

    /// O18a, O18b: [Value] của bảng hằng, và BLANK sắp như 0.
    @Test func bangHangVaBlankKhiSapXep() async throws {
        let sorted = try await engine.execute("""
        EVALUATE ADDCOLUMNS ( { 1, BLANK (), -1 }, "k", [Value] )
        ORDER BY [Value]
        """).tables[0].rows
        #expect(sorted == [[.integer(-1), .integer(-1)], [.blank, .blank], [.integer(1), .integer(1)]])
        #expect(try await column("EVALUATE TOPN ( 1, { 1, BLANK (), -1 }, [Value], ASC )") == [.integer(-1)])
        // O19 (buổi 3): BLANK đứng ngay trước 0.
        let withZero = try await column("EVALUATE { 1, 0, BLANK (), -1 } ORDER BY [Value]")
        #expect(withZero == [.integer(-1), .blank, .integer(0), .integer(1)])
    }

    /// O15: "General Date" nửa đêm chỉ in ngày; O17: so chuỗi với số báo lỗi.
    @Test func formatGeneralDateVaSoSanhChuoiSo() async throws {
        #expect(try await one("EVALUATE ROW ( \"c\", FORMAT ( DATE ( 2018, 12, 31 ), \"General Date\" ) )")
                == .string("12/31/2018"))
        #expect(try await one("EVALUATE ROW ( \"c\", FORMAT ( 43465.6691666667, \"General Date\" ) )")
                == .string("12/31/2018 4:03:36 PM"))
        await ftExpectDAXError(engine, "EVALUATE ROW ( \"x\", IF ( \"12\" > 12, 1, 0 ) )",
                               kind: .typeMismatch, contains: "Text with values of type Integer")
    }
}
