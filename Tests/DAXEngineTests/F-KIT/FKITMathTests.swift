// Hàm toán (F-KIT, đợt 2): ABS, INT, MOD, DIVIDE, ROUND, FLOOR.
// Đáp án MOD, INT, ROUND, FLOOR lấy từ Python 3 (phép % của Python cùng dấu với số chia, như DAX).
import Testing
import ColumnStore
@testable import DAXEngine

@Suite struct FKITMathTests {

    @Test func absGiuKieuSo() {
        #expect(fkChay("ABS", [fkLit(.integer(-5))]) == .success(.integer(5)))
        #expect(fkChay("ABS", [fkLit(.double(-2.5))]) == .success(.double(2.5)))
        #expect(fkChay("ABS", [fkLit(.currency(-15_000))]) == .success(.currency(15_000)))
        #expect(fkChay("ABS", [fkLit(.blank)]) == .success(.blank))
    }

    @Test func intLamTronXuongKeCaSoAm() {
        // INT làm tròn xuống: INT(-4,5) = -5, INT(4,7) = 4.
        #expect(fkChay("INT", [fkLit(.double(4.7))]) == .success(.integer(4)))
        #expect(fkChay("INT", [fkLit(.double(-4.5))]) == .success(.integer(-5)))
        #expect(fkChay("INT", [fkLit(.double(-0.5))]) == .success(.integer(-1)))
        #expect(fkChay("INT", [fkLit(.integer(-4))]) == .success(.integer(-4)))
        // Currency -1,5 (đơn vị 10⁻⁴ nên -15000) làm tròn xuống thành -2.
        #expect(fkChay("INT", [fkLit(.currency(-15_000))]) == .success(.integer(-2)))
        #expect(fkChay("INT", [fkLit(.blank)]) == .success(.blank))
    }

    @Test func modCoDauTheoSoChia() {
        // Python: -3 % 2 = 1; 3 % -2 = -1; -4 % 2 = 0; 5,5 % 2 = 1,5; -5,5 % 2 = 0,5; -10 % -3 = -1; -7 % 3 = 2.
        #expect(fkChay("MOD", [fkLit(.integer(-3)), fkLit(.integer(2))]) == .success(.integer(1)))
        #expect(fkChay("MOD", [fkLit(.integer(3)), fkLit(.integer(-2))]) == .success(.integer(-1)))
        #expect(fkChay("MOD", [fkLit(.integer(-4)), fkLit(.integer(2))]) == .success(.integer(0)))
        #expect(fkChay("MOD", [fkLit(.integer(-10)), fkLit(.integer(-3))]) == .success(.integer(-1)))
        #expect(fkChay("MOD", [fkLit(.integer(-7)), fkLit(.integer(3))]) == .success(.integer(2)))
        #expect(fkKhopSo(fkChay("MOD", [fkLit(.double(5.5)), fkLit(.integer(2))]), 1.5))
        #expect(fkKhopSo(fkChay("MOD", [fkLit(.double(-5.5)), fkLit(.integer(2))]), 0.5))
    }

    @Test func modLoiVaBlank() {
        #expect(fkLoi(fkChay("MOD", [fkLit(.integer(5)), fkLit(.integer(0))])) == .runtime)
        #expect(fkLoi(fkChay("MOD", [fkLit(.double(5.5)), fkLit(.double(0))])) == .runtime)
        #expect(fkChay("MOD", [fkLit(.blank), fkLit(.integer(3))]) == .success(.blank))
    }

    @Test func divideVoiAltVaBlank() {
        #expect(fkKhopSo(fkChay("DIVIDE", [fkLit(.integer(10)), fkLit(.integer(4))]), 2.5))
        // Mẫu bằng 0 thì trả alt; alt bỏ trống thì BLANK.
        #expect(fkChay("DIVIDE", [fkLit(.integer(10)), fkLit(.integer(0))]) == .success(.blank))
        #expect(fkChay("DIVIDE", [fkLit(.integer(10)), fkLit(.integer(0)), fkLit(.integer(-1))]) == .success(.integer(-1)))
        #expect(fkChay("DIVIDE", [fkLit(.integer(10)), fkLit(.integer(0)), fkLit(.blank)]) == .success(.blank))
        // Mẫu BLANK thì trả alt.
        #expect(fkChay("DIVIDE", [fkLit(.integer(10)), fkLit(.blank), fkLit(.integer(99))]) == .success(.integer(99)))
        #expect(fkChay("DIVIDE", [fkLit(.integer(0)), fkLit(.integer(0)), fkLit(.string("n/a"))]) == .success(.string("n/a")))
        // Tử BLANK thì ra BLANK (BLANK / x = BLANK).
        #expect(fkChay("DIVIDE", [fkLit(.blank), fkLit(.integer(5))]) == .success(.blank))
    }

    @Test func roundLamTronNuaXa() {
        // Python (làm tròn nửa xa số 0): 2,5 → 3; -2,5 → -3; 2,675 → 2,68; 1234,5678 → 1234,57; 0,125 → 0,13.
        #expect(fkKhopSo(fkChay("ROUND", [fkLit(.double(2.5)), fkLit(.integer(0))]), 3))
        #expect(fkKhopSo(fkChay("ROUND", [fkLit(.double(-2.5)), fkLit(.integer(0))]), -3))
        #expect(fkKhopSo(fkChay("ROUND", [fkLit(.double(2.675)), fkLit(.integer(2))]), 2.68))
        #expect(fkKhopSo(fkChay("ROUND", [fkLit(.double(1234.5678)), fkLit(.integer(2))]), 1234.57))
        #expect(fkKhopSo(fkChay("ROUND", [fkLit(.double(0.125)), fkLit(.integer(2))]), 0.13))
        // Số chữ số âm làm tròn tới hàng trăm: 1234,5678 → 1200.
        #expect(fkKhopSo(fkChay("ROUND", [fkLit(.double(1234.5678)), fkLit(.integer(-2))]), 1200))
        // Số nguyên với số chữ số không âm vẫn là số nguyên.
        #expect(fkChay("ROUND", [fkLit(.integer(7)), fkLit(.integer(0))]) == .success(.integer(7)))
        #expect(fkChay("ROUND", [fkLit(.blank), fkLit(.integer(2))]) == .success(.blank))
    }

    @Test func floorLamTronVeKhong() {
        #expect(fkKhopSo(fkChay("FLOOR", [fkLit(.double(3.7)), fkLit(.integer(1))]), 3))
        // FLOOR làm tròn về phía 0: FLOOR(-2,5; 2) = -2.
        #expect(fkKhopSo(fkChay("FLOOR", [fkLit(.double(-2.5)), fkLit(.integer(2))]), -2))
        // 0,3 / 0,1 cho 2,9999… trong nhị phân; sau khi đưa về 15 chữ số thì ra 3 và kết quả là 0,3.
        #expect(fkKhopSo(fkChay("FLOOR", [fkLit(.double(0.3)), fkLit(.double(0.1))]), 0.3))
        #expect(fkChay("FLOOR", [fkLit(.integer(7)), fkLit(.integer(2))]) == .success(.integer(6)))
        #expect(fkChay("FLOOR", [fkLit(.integer(5))]) == .success(.integer(5)))
        #expect(fkKhopSo(fkChay("FLOOR", [fkLit(.double(-0.5))]), 0))
        #expect(fkLoi(fkChay("FLOOR", [fkLit(.integer(5)), fkLit(.integer(-1))])) == .runtime)
        #expect(fkChay("FLOOR", [fkLit(.blank)]) == .success(.blank))
    }
}
