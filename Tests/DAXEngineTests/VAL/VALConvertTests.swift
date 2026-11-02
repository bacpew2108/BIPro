// Ép kiểu, số học, so sánh, logic và nối chuỗi (architecture.md §5.5). Ca [SUY ĐOÁN] chờ oracle.
import Testing
@testable import DAXEngine

@Suite struct VALConvertTests {

    // MARK: - Số học theo kiểu

    @Test func nguyenVoiNguyenRaNguyen() throws {
        #expect(try Value.arithmetic(.add, .integer(2), .integer(3)) == .integer(5))
        #expect(try Value.arithmetic(.subtract, .integer(7), .integer(10)) == .integer(-3))
        #expect(try Value.arithmetic(.multiply, .integer(2), .integer(3)) == .integer(6))
    }

    @Test func chiLuonRaSoThuc() throws {
        // `/` luôn ra số thực, kể cả khi chia hết.
        #expect(try Value.arithmetic(.divide, .integer(6), .integer(3)) == .double(2))
        #expect(xapXiSo(try Value.arithmetic(.divide, .integer(1), .integer(4)), 0.25))
    }

    @Test func coSoThucThiRaSoThuc() throws {
        #expect(try Value.arithmetic(.add, .integer(1), .double(1.5)) == .double(2.5))
        #expect(try Value.arithmetic(.multiply, .double(1.5), .integer(2)) == .double(3))
    }

    @Test func currencyVoiNguyenRaCurrency() throws {
        // 1.5 là 15000 (×10⁴). Cộng 2 là 35000; nhân 2 là 30000.
        #expect(try Value.arithmetic(.add, .currency(15_000), .integer(2)) == .currency(35_000))
        #expect(try Value.arithmetic(.multiply, .currency(15_000), .integer(2)) == .currency(30_000))
        #expect(try Value.arithmetic(.add, .integer(2), .currency(15_000)) == .currency(35_000))
    }

    @Test func currencyVoiCurrencyRaCurrency() throws {
        // [SUY ĐOÁN] currency × currency: 1.5 × 2.0 = 3.0.
        #expect(try Value.arithmetic(.add, .currency(15_000), .currency(22_500)) == .currency(37_500))
        #expect(try Value.arithmetic(.multiply, .currency(15_000), .currency(20_000)) == .currency(30_000))
    }

    @Test func currencyVoiSoThucRaSoThuc() throws {
        // currency với số thực ra số thực; currency chia ra số thực.
        #expect(xapXiSo(try Value.arithmetic(.add, .currency(15_000), .double(0.25)), 1.75))
        #expect(xapXiSo(try Value.arithmetic(.divide, .currency(15_000), .integer(2)), 0.75))
    }

    @Test func booleanLaSoTrongPhepTinh() throws {
        // [SUY ĐOÁN] TRUE + 1 = 2.
        #expect(try Value.arithmetic(.add, .boolean(true), .integer(1)) == .integer(2))
    }

    @Test func ngayCongSoRaNgay() throws {
        // [SUY ĐOÁN] Ngày ± số ngày là ngày; ngày − ngày là số.
        #expect(try Value.arithmetic(.add, .dateTime(ngay2023_03_15), .integer(1)) == .dateTime(45_001))
        #expect(try Value.arithmetic(.subtract, .dateTime(45_001), .dateTime(45_000)) == .double(1))
    }

    @Test func chuoiEpSangSoTrongPhepTinh() throws {
        #expect(try Value.arithmetic(.add, .string("1"), .integer(1)) == .integer(2))
        #expect(try Value.arithmetic(.add, .string("1.5"), .integer(1)) == .double(2.5))
        #expect(try Value.arithmetic(.multiply, .string(" 3 "), .integer(2)) == .integer(6))
        #expect(xapXiSo(try Value.arithmetic(.add, .string("1e2"), .integer(0)), 100))
    }

    @Test func chuoiKhongEpDuocBaoTypeMismatch() {
        let loi = [
            loiDAX { try Value.arithmetic(.add, .string("abc"), .integer(1)) },
            loiDAX { try Value.arithmetic(.multiply, .integer(2), .string("")) },
            loiDAX { try Value.arithmetic(.add, .string("NaN"), .integer(1)) },
            loiDAX { try Value.arithmetic(.divide, .string("12abc"), .integer(1)) },
        ]
        for e in loi {
            #expect(e?.kind == .typeMismatch)
        }
    }

    @Test func traBoChuoiDaoDauVaTran() throws {
        // Tràn Int64 thì ra số thực, không trap.
        #expect(xapXiSo(try Value.arithmetic(.add, .integer(Int64.max), .integer(1)), 9_223_372_036_854_775_808))
        #expect(xapXiSo(try Value.arithmetic(.multiply, .integer(Int64.max), .integer(2)), 1.8446744073709552e19))
    }

    @Test func dauTruMotNgoi() throws {
        #expect(try Value.unary(.negate, .integer(5)) == .integer(-5))
        #expect(try Value.unary(.negate, .double(1.5)) == .double(-1.5))
        #expect(try Value.unary(.negate, .currency(15_000)) == .currency(-15_000))
        #expect(try Value.unary(.negate, .string("2")) == .integer(-2))
        #expect(try Value.unary(.plus, .string("2.5")) == .double(2.5))
    }

    // MARK: - So sánh

    @Test func soSanhSoVoiSo() throws {
        #expect(try Value.compare(.equal, .integer(1), .double(1.0)) == .boolean(true))
        #expect(try Value.compare(.greater, .integer(2), .double(1.5)) == .boolean(true))
        #expect(try Value.compare(.notEqual, .integer(1), .integer(2)) == .boolean(true))
        #expect(try Value.compare(.lessEqual, .integer(2), .integer(2)) == .boolean(true))
        #expect(try Value.compare(.greaterEqual, .integer(3), .integer(4)) == .boolean(false))
    }

    @Test func soSanhCurrencyVoiNguyenVaSoThuc() throws {
        #expect(try Value.compare(.equal, .currency(20_000), .integer(2)) == .boolean(true))
        #expect(try Value.compare(.less, .currency(15_000), .double(1.6)) == .boolean(true))
    }

    @Test func soNguyenSoSanhChinhXac() throws {
        // Hai số nguyên lớn khác nhau 1 đơn vị không được coi là bằng nhau do làm tròn Double.
        #expect(try Value.compare(.equal, .integer(9_007_199_254_740_993), .integer(9_007_199_254_740_992)) == .boolean(false))
    }

    @Test func soSanhChuoiKhongPhanBietHoaThuong() throws {
        // [SUY ĐOÁN] Chuỗi so theo không phân biệt hoa thường; chưa đối chiếu collation.
        #expect(try Value.compare(.equal, .string("abc"), .string("ABC")) == .boolean(true))
        #expect(try Value.compare(.less, .string("a"), .string("B")) == .boolean(true))
        #expect(try Value.compare(.notEqual, .string("Apple"), .string("apple")) == .boolean(false))
        #expect(try Value.compare(.greater, .string("b"), .string("A")) == .boolean(true))
    }

    @Test func chuoiVoiSoBaoLoi() {
        // Thông điệp lấy từ đặc tả: "DAX comparison operations do not support comparing values of type Text with values of type Integer".
        let loi = loiDAX { try Value.compare(.equal, .string("1"), .integer(1)) }
        #expect(loi?.kind == .typeMismatch)
        #expect(loi?.message == "DAX comparison operations do not support comparing values of type Text with values of type Integer")
        let nguoc = loiDAX { try Value.compare(.less, .integer(1), .string("2")) }
        #expect(nguoc?.kind == .typeMismatch)
        #expect(nguoc?.message == "DAX comparison operations do not support comparing values of type Integer with values of type Text")
        #expect(loiDAX { try Value.compare(.equal, .boolean(true), .string("TRUE")) }?.kind == .typeMismatch)
    }

    @Test func ngaySoSanhNhuSo() throws {
        // Ngày được coi như số serial.
        #expect(try Value.compare(.greater, .dateTime(45_000), .integer(44_999)) == .boolean(true))
        #expect(try Value.compare(.equal, .dateTime(45_000), .integer(45_000)) == .boolean(true))
    }

    @Test func booleanSoSanh() throws {
        #expect(try Value.compare(.greater, .boolean(true), .boolean(false)) == .boolean(true))
        #expect(try Value.compare(.equal, .boolean(true), .boolean(true)) == .boolean(true))
        // [SUY ĐOÁN] TRUE = 1 là TRUE khi so với số.
        #expect(try Value.compare(.equal, .boolean(true), .integer(1)) == .boolean(true))
    }

    @Test func nanKhongSoSanhDuoc() throws {
        // NaN không bằng chính nó; <> với NaN là TRUE.
        #expect(try Value.compare(.equal, .double(.nan), .double(.nan)) == .boolean(false))
        #expect(try Value.compare(.notEqual, .double(.nan), .double(.nan)) == .boolean(true))
        #expect(try Value.compare(.less, .double(.nan), .integer(1)) == .boolean(false))
        #expect(try Value.compare(.greater, .double(.nan), .integer(1)) == .boolean(false))
    }

    @Test func strictEqualSoSanhTheoNhom() throws {
        // [SUY ĐOÁN] == không báo lỗi khi khác nhóm kiểu; trả FALSE.
        #expect(try Value.compare(.strictEqual, .integer(1), .double(1.0)) == .boolean(true))
        #expect(try Value.compare(.strictEqual, .string("1"), .integer(1)) == .boolean(false))
    }

    // MARK: - Logic

    @Test func logicEpSoVaChuoi() throws {
        // [SUY ĐOÁN] Số khác 0 là TRUE; chuỗi "TRUE"/"FALSE" không phân biệt hoa thường được chấp nhận.
        #expect(try Value.logical(.and, .boolean(true), .integer(0)) == .boolean(false))
        #expect(try Value.logical(.or, .integer(1), .boolean(false)) == .boolean(true))
        #expect(try Value.logical(.and, .string("true"), .boolean(true)) == .boolean(true))
        #expect(try Value.unary(.not, .integer(0)) == .boolean(true))
        #expect(try Value.unary(.not, .string("FALSE")) == .boolean(true))
    }

    @Test func logicKhongEpDuocBaoLoi() {
        #expect(loiDAX { try Value.logical(.and, .string("abc"), .boolean(true)) }?.kind == .typeMismatch)
    }

    // MARK: - Nối chuỗi

    @Test func noiChuoiVoiSo() {
        #expect(Value.concatenate(.double(1.5), .string("x")) == .string("1.5x"))
        #expect(Value.concatenate(.double(2.0), .string("")) == .string("2"))
        #expect(Value.concatenate(.integer(42), .string("")) == .string("42"))
        #expect(Value.concatenate(.currency(15_000), .string("")) == .string("1.5"))
        #expect(Value.concatenate(.currency(-15_000), .string("")) == .string("-1.5"))
        #expect(Value.concatenate(.boolean(true), .string("")) == .string("TRUE"))
    }

    @Test func noiChuoiSoThucKhongKyHieuMu() {
        // [SUY ĐOÁN] 15 chữ số có nghĩa và không ký hiệu mũ.
        #expect(Value.concatenate(.double(0.1 + 0.2), .string("")) == .string("0.3"))
        #expect(Value.concatenate(.double(1e20), .string("")) == .string("100000000000000000000"))
        #expect(Value.concatenate(.double(-0.0000125), .string("")) == .string("-0.0000125"))
        #expect(Value.concatenate(.double(.infinity), .string("")) == .string("∞"))
        #expect(Value.concatenate(.double(.nan), .string("")) == .string("NaN"))
    }

    @Test func noiChuoiVoiNgay() {
        // [SUY ĐOÁN, chờ O2] Định dạng en-US "M/d/yyyy h:mm:ss AM", giờ UTC.
        #expect(Value.concatenate(.dateTime(45_000), .string("")) == .string("3/15/2023 12:00:00 AM"))
        #expect(Value.concatenate(.dateTime(45_000.5), .string("")) == .string("3/15/2023 12:00:00 PM"))
    }

    // MARK: - Ép kiểu tường minh

    @Test func asDoubleVaAsText() throws {
        #expect(try Value.blank.asDouble() == 0)
        #expect(try Value.string("2.5").asDouble() == 2.5)
        #expect(try Value.boolean(true).asDouble() == 1)
        #expect(loiDAX { _ = try Value.string("abc").asDouble(); return .blank }?.kind == .typeMismatch)
        #expect(Value.blank.asText() == "")
        #expect(Value.integer(-7).asText() == "-7")
    }
}
