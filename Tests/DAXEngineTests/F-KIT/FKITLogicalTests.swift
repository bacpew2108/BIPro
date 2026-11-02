// Hàm logic và BLANK (F-KIT, đợt 2): IF, SWITCH, AND, OR, NOT, TRUE, FALSE, BLANK, COALESCE, ISBLANK.
// Đáp án tính tay theo architecture.md §5.5. Đánh giá lười kiểm bằng nhật ký của FKDanhGia.
import Testing
import ColumnStore
@testable import DAXEngine

@Suite struct FKITLogicalTests {

    @Test func blankVaISBLANKTheoSec55() {
        #expect(fkChay("BLANK", []) == .success(.blank))
        #expect(fkChay("ISBLANK", [fkLit(.blank)]) == .success(.boolean(true)))
        // ISBLANK(0) là FALSE; chuỗi rỗng không phải BLANK khi dùng ISBLANK.
        #expect(fkChay("ISBLANK", [fkLit(.integer(0))]) == .success(.boolean(false)))
        #expect(fkChay("ISBLANK", [fkLit(.string(""))]) == .success(.boolean(false)))
        #expect(fkChay("ISBLANK", [fkLit(.boolean(false))]) == .success(.boolean(false)))
    }

    @Test func blankLaFalseTrongAndOrNot() {
        // BLANK && TRUE là FALSE; BLANK || TRUE là TRUE.
        #expect(fkChay("AND", [fkLit(.blank), fkLit(.boolean(true))]) == .success(.boolean(false)))
        #expect(fkChay("OR", [fkLit(.blank), fkLit(.boolean(true))]) == .success(.boolean(true)))
        // NOT(BLANK) là TRUE vì BLANK là FALSE.
        #expect(fkChay("NOT", [fkLit(.blank)]) == .success(.boolean(true)))
        #expect(fkChay("OR", [fkLit(.integer(0)), fkLit(.blank)]) == .success(.boolean(false)))
    }

    @Test func andOrNotVoiSoVaChuoi() {
        #expect(fkChay("AND", [fkLit(.integer(1)), fkLit(.integer(2))]) == .success(.boolean(true)))
        #expect(fkChay("AND", [fkLit(.integer(1)), fkLit(.integer(0))]) == .success(.boolean(false)))
        // Chuỗi "TRUE" được ép thành logic (không phân biệt hoa thường).
        #expect(fkChay("NOT", [fkLit(.string("true"))]) == .success(.boolean(false)))
        #expect(fkChay("NOT", [fkLit(.integer(0))]) == .success(.boolean(true)))
        #expect(fkLoi(fkChay("AND", [fkLit(.string("abc")), fkLit(.boolean(true))])) == .typeMismatch)
    }

    @Test func trueVaFalse() {
        #expect(fkChay("TRUE", []) == .success(.boolean(true)))
        #expect(fkChay("FALSE", []) == .success(.boolean(false)))
    }

    @Test func ifChiDanhGiaNhanhDuocChonKhiTrue() {
        let nhat = FKNhatKy()
        let ketQua = fkChay("IF", [fkLit(.boolean(true)), fkLit(.string("DUNG")), fkLit(.string("SAI"))], nhatKy: nhat)
        #expect(ketQua == .success(.string("DUNG")))
        // Nhánh SAI không được đánh giá: nhật ký chỉ có điều kiện và nhánh DUNG.
        #expect(nhat.giaTri == [.boolean(true), .string("DUNG")])
    }

    @Test func ifChiDanhGiaNhanhDuocChonKhiFalse() {
        let nhat = FKNhatKy()
        let ketQua = fkChay("IF", [fkLit(.boolean(false)), fkLit(.string("DUNG")), fkLit(.string("SAI"))], nhatKy: nhat)
        #expect(ketQua == .success(.string("SAI")))
        #expect(nhat.giaTri == [.boolean(false), .string("SAI")])
    }

    @Test func ifThieuNhanhSaiTraBlank() {
        let nhat = FKNhatKy()
        #expect(fkChay("IF", [fkLit(.boolean(false)), fkLit(.integer(1))], nhatKy: nhat) == .success(.blank))
        #expect(nhat.giaTri == [.boolean(false)])
    }

    @Test func ifDieuKienBlankVaSoKhacKhong() {
        // BLANK là FALSE trong điều kiện; số khác 0 là TRUE. [SUY ĐOÁN: số thành logic chưa có oracle.]
        #expect(fkChay("IF", [fkLit(.blank), fkLit(.integer(1)), fkLit(.integer(2))]) == .success(.integer(2)))
        #expect(fkChay("IF", [fkLit(.integer(3)), fkLit(.string("x")), fkLit(.string("y"))]) == .success(.string("x")))
    }

    @Test func switchChonCapKhopVaKhongDanhGiaPhanSau() {
        let nhat = FKNhatKy()
        // Thứ tự đánh giá: expr, value1 (không khớp), value2 (khớp), result2. "khác" không được đánh giá.
        let ketQua = fkChay("SWITCH", [fkLit(.integer(2)),
                                       fkLit(.integer(1)), fkLit(.string("một")),
                                       fkLit(.integer(2)), fkLit(.string("hai")),
                                       fkLit(.string("khác"))], nhatKy: nhat)
        #expect(ketQua == .success(.string("hai")))
        #expect(nhat.giaTri == [.integer(2), .integer(1), .integer(2), .string("hai")])
    }

    @Test func switchKhongKhopThiDungElse() {
        let nhat = FKNhatKy()
        let ketQua = fkChay("SWITCH", [fkLit(.integer(5)),
                                       fkLit(.integer(1)), fkLit(.string("một")),
                                       fkLit(.integer(2)), fkLit(.string("hai")),
                                       fkLit(.string("khác"))], nhatKy: nhat)
        #expect(ketQua == .success(.string("khác")))
        #expect(nhat.giaTri == [.integer(5), .integer(1), .integer(2), .string("khác")])
    }

    @Test func switchKhongKhopVaKhongElseTraBlank() {
        #expect(fkChay("SWITCH", [fkLit(.integer(5)),
                                  fkLit(.integer(1)), fkLit(.string("một")),
                                  fkLit(.integer(2)), fkLit(.string("hai"))]) == .success(.blank))
    }

    @Test func switchKhopDauTienThiKhongDanhGiaCapSau() {
        let nhat = FKNhatKy()
        let ketQua = fkChay("SWITCH", [fkLit(.integer(1)),
                                       fkLit(.integer(1)), fkLit(.string("một")),
                                       fkLit(.integer(1)), fkLit(.string("một lần nữa"))], nhatKy: nhat)
        #expect(ketQua == .success(.string("một")))
        #expect(nhat.giaTri == [.integer(1), .integer(1), .string("một")])
    }

    @Test func switchBlankKhopVoiKhong() {
        // BLANK = 0 là TRUE (§5.5), nên SWITCH(BLANK, 0, "không") ra "không".
        #expect(fkChay("SWITCH", [fkLit(.blank), fkLit(.integer(0)), fkLit(.string("không"))]) == .success(.string("không")))
    }

    @Test func coalesceLayGiaTriKhongBlankDauTien() {
        let nhat = FKNhatKy()
        let ketQua = fkChay("COALESCE", [fkLit(.blank), fkLit(.blank), fkLit(.integer(3)), fkLit(.integer(4))],
                            nhatKy: nhat)
        #expect(ketQua == .success(.integer(3)))
        // Đối số thứ tư không được đánh giá.
        #expect(nhat.giaTri == [.blank, .blank, .integer(3)])
    }

    @Test func coalesceTatCaBlankVaChuoiRong() {
        #expect(fkChay("COALESCE", [fkLit(.blank)]) == .success(.blank))
        // Chuỗi rỗng không phải BLANK nên được giữ lại.
        #expect(fkChay("COALESCE", [fkLit(.string("")), fkLit(.integer(1))]) == .success(.string("")))
    }
}
