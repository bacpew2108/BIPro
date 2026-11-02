// Chia 0, ±∞ và NaN (architecture.md §5.5): `/` không báo lỗi; DIVIDE trả alt khi mẫu bằng 0 hoặc BLANK.
import Testing
@testable import DAXEngine

@Suite struct VALDivideTests {

    @Test func chiKhacKhongTheoIEEE() throws {
        #expect(xapXiSo(try Value.arithmetic(.divide, .integer(5), .integer(0)), .infinity))
        #expect(xapXiSo(try Value.arithmetic(.divide, .integer(-5), .integer(0)), -.infinity))
        #expect(xapXiSo(try Value.arithmetic(.divide, .integer(0), .integer(0)), .nan))
        #expect(xapXiSo(try Value.arithmetic(.divide, .double(2.5), .double(0)), .infinity))
    }

    @Test func mauCoInfVaNanKhongBaoLoi() throws {
        #expect(xapXiSo(try Value.arithmetic(.divide, .integer(5), .double(.infinity)), 0))
        #expect(xapXiSo(try Value.arithmetic(.divide, .integer(5), .double(-.infinity)), 0))
        #expect(xapXiSo(try Value.arithmetic(.divide, .double(.infinity), .double(.infinity)), .nan))
        #expect(xapXiSo(try Value.arithmetic(.divide, .double(.nan), .integer(2)), .nan))
        #expect(xapXiSo(try Value.arithmetic(.divide, .integer(2), .double(.nan)), .nan))
    }

    @Test func divideTraAltKhiMauLaZeroHoacBlank() throws {
        #expect(try Value.divide(.integer(10), .integer(0)) == .blank)
        #expect(try Value.divide(.integer(10), .integer(0), alternate: .integer(-1)) == .integer(-1))
        #expect(try Value.divide(.integer(10), .double(-0.0), alternate: .string("n/a")) == .string("n/a"))
        #expect(try Value.divide(.integer(10), .blank, alternate: .integer(0)) == .integer(0))
    }

    @Test func divideBinhThuongVaInf() throws {
        #expect(xapXiSo(try Value.divide(.integer(10), .integer(4)), 2.5))
        // Mẫu là ±∞ hoặc NaN thì không bằng 0, nên không dùng alt.
        #expect(xapXiSo(try Value.divide(.integer(5), .double(.infinity), alternate: .integer(9)), 0))
        #expect(xapXiSo(try Value.divide(.integer(5), .double(.nan), alternate: .integer(9)), .nan))
    }

    @Test func divideVoiChuoiKhongEpDuocBaoLoi() {
        #expect(loiDAX { try Value.divide(.integer(1), .string("abc")) }?.kind == .typeMismatch)
    }
}
