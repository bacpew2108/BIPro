// Quy tắc BLANK trong architecture.md §5.5: số học, logic, so sánh, nối chuỗi, ISBLANK, DIVIDE.
// Ca đánh dấu [SUY ĐOÁN] chưa có oracle; xem docs/PHASE_B_PLAN.md §5.3 và O1/O2.
import Testing
@testable import DAXEngine

@Suite struct VALBlankTests {

    @Test func blankCongTruVoiSo() throws {
        // BLANK + 5 = 5; BLANK − 5 = −5; 5 − BLANK = 5; 5 + BLANK = 5.
        #expect(try Value.arithmetic(.add, .blank, .integer(5)) == .integer(5))
        #expect(try Value.arithmetic(.add, .integer(5), .blank) == .integer(5))
        #expect(try Value.arithmetic(.subtract, .blank, .integer(5)) == .integer(-5))
        #expect(try Value.arithmetic(.subtract, .integer(5), .blank) == .integer(5))
        #expect(try Value.arithmetic(.add, .blank, .double(1.5)) == .double(1.5))
    }

    @Test func blankNhanVaChiaSoLaBlank() throws {
        // BLANK × 5 = BLANK; BLANK / 5 = BLANK; 5 × BLANK = BLANK.
        #expect(try Value.arithmetic(.multiply, .blank, .integer(5)) == .blank)
        #expect(try Value.arithmetic(.multiply, .integer(5), .blank) == .blank)
        #expect(try Value.arithmetic(.divide, .blank, .integer(5)) == .blank)
    }

    @Test func soChiaBlankLaVoCung() throws {
        // 5 / BLANK = +∞; 0 / BLANK = NaN; BLANK / BLANK = BLANK.
        #expect(xapXiSo(try Value.arithmetic(.divide, .integer(5), .blank), .infinity))
        #expect(xapXiSo(try Value.arithmetic(.divide, .integer(-5), .blank), -.infinity))
        #expect(xapXiSo(try Value.arithmetic(.divide, .integer(0), .blank), .nan))
        #expect(try Value.arithmetic(.divide, .blank, .blank) == .blank)
    }

    @Test func blankVoiBlankTrongCongTru() throws {
        // [SUY ĐOÁN] BLANK + BLANK = BLANK; chưa có oracle.
        #expect(try Value.arithmetic(.add, .blank, .blank) == .blank)
        #expect(try Value.arithmetic(.subtract, .blank, .blank) == .blank)
    }

    @Test func blankDaoDau() throws {
        // [SUY ĐOÁN] -BLANK = BLANK, giống phép nhân với -1.
        #expect(try Value.unary(.negate, .blank) == .blank)
    }

    @Test func blankLogicAndOr() throws {
        // BLANK && TRUE = FALSE; BLANK || TRUE = TRUE; NOT BLANK = TRUE.
        #expect(try Value.logical(.and, .blank, .boolean(true)) == .boolean(false))
        #expect(try Value.logical(.or, .blank, .boolean(true)) == .boolean(true))
        #expect(try Value.logical(.and, .blank, .boolean(false)) == .boolean(false))
        #expect(try Value.logical(.or, .blank, .boolean(false)) == .boolean(false))
        #expect(try Value.unary(.not, .blank) == .boolean(true))
    }

    @Test func blankSoSanhVoiSo() throws {
        // BLANK = 0 là TRUE; BLANK <> 0 là FALSE; BLANK < 1 là TRUE.
        #expect(try Value.compare(.equal, .blank, .integer(0)) == .boolean(true))
        #expect(try Value.compare(.equal, .integer(0), .blank) == .boolean(true))
        #expect(try Value.compare(.notEqual, .blank, .integer(0)) == .boolean(false))
        #expect(try Value.compare(.less, .blank, .integer(1)) == .boolean(true))
        #expect(try Value.compare(.equal, .blank, .double(0)) == .boolean(true))
    }

    @Test func blankSoSanhVoiChuoi() throws {
        // BLANK = "" là TRUE; BLANK = "a" là FALSE; BLANK < "a" là TRUE.
        #expect(try Value.compare(.equal, .blank, .string("")) == .boolean(true))
        #expect(try Value.compare(.equal, .blank, .string("a")) == .boolean(false))
        #expect(try Value.compare(.less, .blank, .string("a")) == .boolean(true))
    }

    @Test func blankSoSanhVoiBoolean() throws {
        // BLANK coi như FALSE khi vế kia là boolean.
        #expect(try Value.compare(.equal, .blank, .boolean(false)) == .boolean(true))
        #expect(try Value.compare(.equal, .blank, .boolean(true)) == .boolean(false))
    }

    @Test func blankSoSanhVoiBlank() throws {
        #expect(try Value.compare(.equal, .blank, .blank) == .boolean(true))
        #expect(try Value.compare(.notEqual, .blank, .blank) == .boolean(false))
    }

    @Test func toanTuStrictEqualKhongEpBlank() throws {
        // [SUY ĐOÁN] Toán tử == không ép BLANK: BLANK == 0 là FALSE, BLANK == "" là FALSE.
        #expect(try Value.compare(.strictEqual, .blank, .integer(0)) == .boolean(false))
        #expect(try Value.compare(.strictEqual, .blank, .string("")) == .boolean(false))
        #expect(try Value.compare(.strictEqual, .blank, .blank) == .boolean(true))
    }

    @Test func blankVoiNoiChuoi() {
        // & biến BLANK thành "".
        #expect(Value.concatenate(.blank, .string("x")) == .string("x"))
        #expect(Value.concatenate(.string("x"), .blank) == .string("x"))
        #expect(Value.concatenate(.blank, .blank) == .string(""))
        #expect(Value.concatenate(.blank, .integer(5)) == .string("5"))
    }

    @Test func isBlankPhanBietBlankVoiZeroVaChuoiRong() {
        // ISBLANK(0) là FALSE; chỉ BLANK thật mới là BLANK.
        #expect(Value.blank.isBlank)
        #expect(!Value.integer(0).isBlank)
        #expect(!Value.double(0).isBlank)
        #expect(!Value.string("").isBlank)
        #expect(!Value.boolean(false).isBlank)
    }

    @Test func blankQuaDivide() throws {
        // DIVIDE(BLANK, 5) = BLANK (theo `/`); DIVIDE(10, BLANK) trả alt mặc định BLANK.
        #expect(try Value.divide(.blank, .integer(5)) == .blank)
        #expect(try Value.divide(.integer(10), .blank) == .blank)
        #expect(try Value.divide(.integer(10), .blank, alternate: .integer(0)) == .integer(0))
    }

    @Test func blankQuaNhiTuCoBangKhong() throws {
        // BLANK coi như 0 trong so sánh với số: BLANK = 0 TRUE đã kiểm; bảng dưới kiểm các cặp còn lại.
        let cases: [(BinaryOp, Value, Value, Bool)] = [
            (.greaterEqual, .blank, .integer(0), true),
            (.lessEqual, .blank, .integer(0), true),
            (.greater, .blank, .integer(-1), true),
            (.less, .integer(-1), .blank, true),
        ]
        for (op, a, b, want) in cases {
            #expect(try Value.compare(op, a, b) == .boolean(want), "\(op.rawValue) \(a) \(b)")
        }
    }
}
