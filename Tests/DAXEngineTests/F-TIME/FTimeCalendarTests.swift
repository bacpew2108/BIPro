// Lịch của DATEADD và SAMEPERIODLASTYEAR (F-TIME, đợt 3): cuối tháng, 29/02, khoảng qua năm, bảng ngày trên MiniBank.
// Đáp án là serial OLE do Python stdlib tính (scratchpad/ftime3/oracle_ftime.py). Các ca đánh dấu [SUY ĐOÁN] trong
// TimeIntel.swift được ghi rõ ở từng ca.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FTimeCalendarTests {

    /// Một ca: serial nguồn, số khoảng, khoảng, serial kỳ vọng, ghi chú (ngày đọc được cho người xem).
    private struct Ca {
        let nguon: Double
        let n: Int
        let khoang: String
        let ketQua: Double
        let ghiChu: String
    }

    /// Đáp án từ Python. Serial 2023-02-28 là 44985; 2024-02-28 là 45350; 2024-02-29 là 45351.
    private let cacCa: [Ca] = [
        Ca(nguon: 45349, n: -1, khoang: "YEAR", ketQua: 44984, ghiChu: "27/02/2024 -1 năm = 27/02/2023"),
        Ca(nguon: 45350, n: -1, khoang: "YEAR", ketQua: 44985, ghiChu: "28/02/2024 -1 năm = 28/02/2023"),
        Ca(nguon: 45351, n: -1, khoang: "YEAR", ketQua: 44985, ghiChu: "29/02/2024 -1 năm = 28/02/2023 (năm không nhuận)"),
        Ca(nguon: 45322, n: -1, khoang: "YEAR", ketQua: 44957, ghiChu: "31/01/2024 -1 năm = 31/01/2023 (cuối tháng)"),
        Ca(nguon: 45322, n: 1, khoang: "MONTH", ketQua: 45351, ghiChu: "31/01/2024 +1 tháng = 29/02/2024 (cuối tháng)"),
        Ca(nguon: 45321, n: 1, khoang: "MONTH", ketQua: 45351, ghiChu: "30/01/2024 +1 tháng = 29/02/2024 (kẹp về cuối tháng, [SUY ĐOÁN])"),
        Ca(nguon: 45382, n: -1, khoang: "QUARTER", ketQua: 45291, ghiChu: "31/03/2024 -1 quý = 31/12/2023 (cuối tháng)"),
        Ca(nguon: 45352, n: -1, khoang: "DAY", ketQua: 45351, ghiChu: "01/03/2024 -1 ngày = 29/02/2024"),
        Ca(nguon: 45292, n: -1, khoang: "MONTH", ketQua: 45261, ghiChu: "01/01/2024 -1 tháng = 01/12/2023 (qua năm)"),
        Ca(nguon: 45351, n: 1, khoang: "YEAR", ketQua: 45716, ghiChu: "29/02/2024 +1 năm = 28/02/2025"),
        Ca(nguon: 44985, n: 1, khoang: "YEAR", ketQua: 45350, ghiChu: "28/02/2023 +1 năm = 28/02/2024 (ngày lẻ không mở rộng; golden T2)"),
        Ca(nguon: 45651, n: -1, khoang: "YEAR", ketQua: 45285, ghiChu: "25/12/2024 -1 năm = 25/12/2023"),
    ]

    @Test func dichTungNgayTheoQuyTacLich() throws {
        for ca in cacCa {
            let ketQua = try TimeIntelligenceFunctions.shiftSerial(ca.nguon, count: ca.n, unit: ca.khoang)
            #expect(ketQua == ca.ketQua, "\(ca.ghiChu): nhận \(ketQua)")
        }
    }

    @Test func giuPhanGioTrongNgay() throws {
        // 29/02/2024 12:00 (serial .5) -1 năm = 28/02/2023 12:00.
        let ketQua = try TimeIntelligenceFunctions.shiftSerial(45351.5, count: -1, unit: "YEAR")
        #expect(ketQua == 44985.5)
        let ngay = try TimeIntelligenceFunctions.shiftSerial(45351.25, count: 1, unit: "DAY")
        #expect(ngay == 45352.25)
    }

    @Test func ngoaiPhamViBaoLoi() {
        // Serial 1 là 31/12/1899. Lùi một năm thì ra 1898, ngoài 1900–9999, nên báo lỗi chứ không trả số.
        #expect(throws: DAXError.self) {
            _ = try TimeIntelligenceFunctions.shiftSerial(1, count: -1, unit: "YEAR")
        }
    }

    @Test func sameperiodlastyearBangDateaddMotNam() async throws {
        let engine = ftEngine(MiniBank.makeSource())
        let voi = "EVALUATE SAMEPERIODLASTYEAR ( FILTER ( VALUES ( Dim_Date[full_date] ), Dim_Date[full_date] = DATE ( 2024, 2, 29 ) ) )"
        let dateadd = "EVALUATE DATEADD ( FILTER ( VALUES ( Dim_Date[full_date] ), Dim_Date[full_date] = DATE ( 2024, 2, 29 ) ), -1, YEAR )"
        let a = try await engine.execute(voi).tables[0].rows
        let b = try await engine.execute(dateadd).tables[0].rows
        #expect(a == b)
        #expect(a == [[.dateTime(44985)]], "29/02/2024 phải thành 28/02/2023")
    }

    @Test func ngayTrongNamHaiNghinBonDungKhoa() async throws {
        // Mọi ngày năm 2024 (366 ngày) dịch -1 năm: 365 ngày phân biệt, 28/02/2023 xuất hiện đúng một lần.
        let engine = ftEngine(MiniBank.makeSource())
        let query = """
        EVALUATE SAMEPERIODLASTYEAR (
            FILTER ( VALUES ( Dim_Date[full_date] ), Dim_Date[full_date] >= DATE ( 2024, 1, 1 ) && Dim_Date[full_date] <= DATE ( 2024, 12, 31 ) )
        )
        """
        let rows = try await engine.execute(query).tables[0].rows
        var serials: [Double] = []
        for row in rows {
            guard case .dateTime(let d) = row[0] else {
                Issue.record("kỳ vọng ngày, nhận \(row[0])")
                return
            }
            serials.append(d)
        }
        #expect(serials.count == 365, "số ngày: \(serials.count)")
        #expect(Set(serials).count == 365, "có ngày trùng lặp")
        // Tổng serial 365 ngày của năm 2023 (Python: 16464785).
        #expect(serials.reduce(0, +) == 16_464_785, "tổng serial khác đáp án Python")
        #expect(serials.filter { $0 == 44985 }.count == 1)
    }

    @Test func toanBoDimDateDichRaHaiNamTruoc() async throws {
        // 731 ngày của Dim_Date: 2023 dịch thành 365 ngày của 2022, 2024 dịch thành 365 ngày của 2023.
        // Hai tập không giao nhau nên có 730 ngày phân biệt. 28/02/2024 và 29/02/2024 cùng về 28/02/2023.
        let engine = ftEngine(MiniBank.makeSource())
        let rows = try await engine.execute(
            "EVALUATE SAMEPERIODLASTYEAR ( VALUES ( Dim_Date[full_date] ) )").tables[0].rows
        #expect(rows.count == 730, "số dòng: \(rows.count)")
        #expect(Set(rows).count == 730, "có dòng trùng lặp")
    }
}
