// Kiểm tra ALLSELECTED và shadow filter context trên MiniBank (FC, đợt 2), architecture.md §4.5.
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

private func soGiaoDich(_ ctx: FilterContext, _ store: ColumnStore) throws -> Int {
    try ctx.visibleRows(in: store, table: MiniBank.Tables.factTrans, overrides: []).count
}

private let cotNam = MiniBank.Columns.DimDate.year
private let cotThanhPho = MiniBank.Columns.DimAccount.branchCity
private let cotTheTu = MiniBank.Columns.DimAccount.cardType

@Suite struct FCShadowTests {

    private let store = MiniBank.makeStore()

    @Test func allSelectedKhoiPhucLocCuaShadow() throws {
        // Slicer chọn Debit và Credit. Bên trong iterator, ngữ cảnh dòng đặt thẻ là No Card.
        // ALLSELECTED(thẻ) trả lại lọc Debit và Credit của shadow gần nhất.
        let slicer = FilterContext().applying([
            .filter(FilterItem(column: cotTheTu, values: [.string("Debit"), .string("Credit")]), keep: false),
        ])
        let trong = slicer.pushingShadow().applying([
            .filter(FilterItem(column: cotTheTu, values: [.string("No Card")]), keep: false),
        ])
        #expect(try soGiaoDich(trong, store) == FCExpected.noCardTrans)

        let chon = trong.applying([.allSelected(columns: [cotTheTu])])
        #expect(chon.values(for: cotTheTu) == [.string("Debit"), .string("Credit")])
        #expect(try soGiaoDich(chon, store) == FCExpected.allSelectedCardTrans)
    }

    @Test func allSelectedKhongCoBoLoc() throws {
        // Không có shadow nào lọc thành phố thì ALLSELECTED(thành phố) trả mọi giá trị.
        let ctx = FilterContext().applying([
            .filter(FilterItem(column: cotThanhPho, values: [.string("Đà Nẵng")]), keep: false),
        ])
        let ketQua = ctx.applying([.allSelected(columns: [cotThanhPho])])
        #expect(ketQua.values(for: cotThanhPho) == nil)
        #expect(try soGiaoDich(ketQua, store) == FCExpected.allSelectedNoShadowTrans)
    }

    @Test func allSelectedKhongThamSoLayMoiCot() throws {
        // ALLSELECTED(): năm 2024 từ shadow được khôi phục, thành phố Đà Nẵng của ngữ cảnh bị bỏ.
        let shadow = FilterContext().applying([
            .filter(FilterItem(column: cotNam, values: [.integer(2024)]), keep: false),
        ])
        let trong = shadow.pushingShadow().applying([
            .filter(FilterItem(column: cotThanhPho, values: [.string("Đà Nẵng")]), keep: false),
        ])
        let ketQua = trong.applying([.allSelected(columns: nil)])
        #expect(ketQua.values(for: cotNam) == [.integer(2024)])
        #expect(ketQua.values(for: cotThanhPho) == nil)
        #expect(try soGiaoDich(ketQua, store) == FCExpected.allSelectedAllYear2024Trans)
    }

    @Test func shadowDoiVanTayVaPopKhoiPhucNgu() {
        let ctx = FilterContext().applying([
            .filter(FilterItem(column: cotNam, values: [.integer(2024)]), keep: false),
        ])
        let co = ctx.pushingShadow()
        #expect(ctx.fingerprint != co.fingerprint, "shadow là một phần của khoá cache")
        #expect(co.shadows.frames.count == 1)
        #expect(co.poppingShadow() == ctx.poppingShadow(), "pop trả về ngữ cảnh không còn shadow")
        #expect(co.poppingShadow().shadows.isEmpty)
    }
}
