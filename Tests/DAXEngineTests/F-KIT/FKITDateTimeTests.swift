// Hàm ngày giờ (F-KIT, đợt 2): DATE, YEAR, MONTH, DAY, QUARTER, HOUR, DATEDIFF.
// Serial OLE (ngày 0 là 1899-12-30) tính bằng Python 3 datetime, độc lập với Swift:
// 2019-01-01 = 43466; 2024-02-29 = 45351; 2023-03-01 = 44986; 2023-12-01 = 45261; 2025-02-15 = 45703;
// 1918-01-01 = 6576; 2024-01-01 = 45292; 2024-01-02 = 45293; 2024-01-15 = 45306; 2024-01-16 = 45307;
// 2024-01-31 = 45322; 2024-03-14 = 45365; 2024-03-15 = 45366; 2024-07-14 = 45487;
// 2019-12-31 = 43830; 2020-12-30 = 44195; 2020-12-31 = 44196; 2024-04-01 = 45383; 2024-06-30 = 45473;
// 2024-07-01 = 45474; 2024-12-31 = 45657; 1899-12-31 = 1.
import Testing
import ColumnStore
@testable import DAXEngine

@Suite struct FKITDateTimeTests {

    @Test func dateTranBienThang() {
        // DATE(2018, 13, 1) là 2019-01-01 (tháng 13 tràn sang năm).
        #expect(fkChay("DATE", [fkLit(.integer(2018)), fkLit(.integer(13)), fkLit(.integer(1))]) == .success(.dateTime(43466)))
        // Tháng 0 là tháng 12 năm trước: DATE(2024, 0, 1) = 2023-12-01.
        #expect(fkChay("DATE", [fkLit(.integer(2024)), fkLit(.integer(0)), fkLit(.integer(1))]) == .success(.dateTime(45261)))
        // Tháng 14 của 2024 là tháng 2 của 2025: DATE(2024, 14, 15) = 2025-02-15.
        #expect(fkChay("DATE", [fkLit(.integer(2024)), fkLit(.integer(14)), fkLit(.integer(15))]) == .success(.dateTime(45703)))
    }

    @Test func dateTranBienNgay() {
        // Ngày 0 là ngày cuối tháng trước: DATE(2024, 3, 0) = 2024-02-29.
        #expect(fkChay("DATE", [fkLit(.integer(2024)), fkLit(.integer(3)), fkLit(.integer(0))]) == .success(.dateTime(45351)))
        // 29/02/2023 không tồn tại, tràn thành 01/03/2023.
        #expect(fkChay("DATE", [fkLit(.integer(2023)), fkLit(.integer(2)), fkLit(.integer(29))]) == .success(.dateTime(44986)))
        // Ngày 32 của tháng 1 là 01/02/2024.
        #expect(fkChay("DATE", [fkLit(.integer(2024)), fkLit(.integer(1)), fkLit(.integer(32))]) == .success(.dateTime(45323)))
    }

    @Test func dateNamTu0Den1899CongThem1900() {
        // DATE(18, 1, 1) = 1918-01-01 (năm 18 thành 1918).
        #expect(fkChay("DATE", [fkLit(.integer(18)), fkLit(.integer(1)), fkLit(.integer(1))]) == .success(.dateTime(6576)))
    }

    @Test func yearMonthDayQuarterTaiNgay29Thang2() {
        // 2024-02-29 là ngày biên của năm nhuận.
        let ngay = fkLit(.dateTime(45351))
        #expect(fkChay("YEAR", [ngay]) == .success(.integer(2024)))
        #expect(fkChay("MONTH", [ngay]) == .success(.integer(2)))
        #expect(fkChay("DAY", [ngay]) == .success(.integer(29)))
        #expect(fkChay("QUARTER", [ngay]) == .success(.integer(1)))
    }

    @Test func quarterBienCacQuy() {
        // Ranh giới quý: 01/04 là quý 2, 30/06 là quý 2, 01/07 là quý 3, 31/12 là quý 4.
        #expect(fkChay("QUARTER", [fkLit(.dateTime(45383))]) == .success(.integer(2)))
        #expect(fkChay("QUARTER", [fkLit(.dateTime(45473))]) == .success(.integer(2)))
        #expect(fkChay("QUARTER", [fkLit(.dateTime(45474))]) == .success(.integer(3)))
        #expect(fkChay("QUARTER", [fkLit(.dateTime(45657))]) == .success(.integer(4)))
        #expect(fkChay("YEAR", [fkLit(.dateTime(45657))]) == .success(.integer(2024)))
        #expect(fkChay("DAY", [fkLit(.dateTime(45657))]) == .success(.integer(31)))
    }

    @Test func serialSoMotLaNgayCuoiCua1899() {
        // Serial 1 là 1899-12-31 (serial 0 là 1899-12-30).
        #expect(fkChay("YEAR", [fkLit(.dateTime(1))]) == .success(.integer(1899)))
        #expect(fkChay("MONTH", [fkLit(.dateTime(1))]) == .success(.integer(12)))
        #expect(fkChay("DAY", [fkLit(.dateTime(1))]) == .success(.integer(31)))
    }

    @Test func yearCuaBlankLa1899() {
        // [SUY ĐOÁN] BLANK là serial 0 (1899-12-30). Chưa có oracle.
        #expect(fkChay("YEAR", [fkLit(.blank)]) == .success(.integer(1899)))
    }

    @Test func hourLayGioTrongNgay() {
        // 2024-02-29 13:45 là serial 45351,572916…; 2024-01-01 12:00 là 45292,5.
        #expect(fkChay("HOUR", [fkLit(.dateTime(45351.572916666664))]) == .success(.integer(13)))
        #expect(fkChay("HOUR", [fkLit(.dateTime(45292.5))]) == .success(.integer(12)))
        #expect(fkChay("HOUR", [fkLit(.dateTime(45292))]) == .success(.integer(0)))
    }

    @Test func datediffDonViMonth() {
        // Tháng đủ: 15/01 tới 14/03 là 1 tháng (chưa đủ tháng thứ hai); 15/01 tới 15/03 là 2 tháng.
        let d0115 = fkLit(.dateTime(45306))
        #expect(fkChay("DATEDIFF", [d0115, fkLit(.dateTime(45365)), .keyword("MONTH")]) == .success(.integer(1)))
        #expect(fkChay("DATEDIFF", [d0115, fkLit(.dateTime(45366)), .keyword("MONTH")]) == .success(.integer(2)))
        // Đảo chiều thì số âm, cắt về 0.
        #expect(fkChay("DATEDIFF", [fkLit(.dateTime(45365)), d0115, .keyword("MONTH")]) == .success(.integer(-1)))
        // [SUY ĐOÁN] 31/01 tới 29/02 chưa đủ một tháng vì 29 < 31.
        #expect(fkChay("DATEDIFF", [fkLit(.dateTime(45322)), fkLit(.dateTime(45351)), .keyword("MONTH")]) == .success(.integer(0)))
    }

    @Test func datediffQuarterVaYear() {
        // 15/01 tới 14/07: 5 tháng đủ, tức 1 quý.
        #expect(fkChay("DATEDIFF", [fkLit(.dateTime(45306)), fkLit(.dateTime(45487)), .keyword("QUARTER")]) == .success(.integer(1)))
        // 31/12/2019 tới 30/12/2020: 11 tháng đủ, tức 0 năm; tới 31/12/2020 thì 1 năm.
        #expect(fkChay("DATEDIFF", [fkLit(.dateTime(43830)), fkLit(.dateTime(44195)), .keyword("YEAR")]) == .success(.integer(0)))
        #expect(fkChay("DATEDIFF", [fkLit(.dateTime(43830)), fkLit(.dateTime(44196)), .keyword("YEAR")]) == .success(.integer(1)))
    }

    @Test func datediffDonViTheoNgayGio() {
        // 01/01 tới 15/01: 14 ngày, tức DAY là 14 và WEEK là 2.
        #expect(fkChay("DATEDIFF", [fkLit(.dateTime(45292)), fkLit(.dateTime(45306)), .keyword("DAY")]) == .success(.integer(14)))
        #expect(fkChay("DATEDIFF", [fkLit(.dateTime(45292)), fkLit(.dateTime(45306)), .keyword("WEEK")]) == .success(.integer(2)))
        // 1 phút là 60 giây; 1 giờ là 60 phút.
        let mot = fkLit(.dateTime(45292 + 1.0 / 1440))
        #expect(fkChay("DATEDIFF", [fkLit(.dateTime(45292)), mot, .keyword("SECOND")]) == .success(.integer(60)))
        #expect(fkChay("DATEDIFF", [fkLit(.dateTime(45292)), fkLit(.dateTime(45292 + 1.0 / 24)), .keyword("MINUTE")]) == .success(.integer(60)))
        // 01/01 00:00 tới 01/01 12:00 là 12 giờ; ngày chưa đủ 1 nên DAY là 0.
        #expect(fkChay("DATEDIFF", [fkLit(.dateTime(45292)), fkLit(.dateTime(45292.5)), .keyword("HOUR")]) == .success(.integer(12)))
        #expect(fkChay("DATEDIFF", [fkLit(.dateTime(45292.5)), fkLit(.dateTime(45293.458333333336)), .keyword("DAY")]) == .success(.integer(0)))
    }

    @Test func datediffDonViLaVaThieu() {
        #expect(fkLoi(fkChay("DATEDIFF", [fkLit(.dateTime(45292)), fkLit(.dateTime(45306)), .keyword("FORTNIGHT")])) == .typeMismatch)
        #expect(fkLoi(fkChay("DATEDIFF", [fkLit(.dateTime(45292)), fkLit(.dateTime(45306)), nil])) == .typeMismatch)
    }
}
