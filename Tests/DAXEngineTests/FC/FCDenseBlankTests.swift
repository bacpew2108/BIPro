// Ngữ cảnh lọc trên model nhỏ có cột dense (FC, đợt 3): BLANK của NaN, BLANK ảo của quan hệ, và khoá chiếu
// của bộ lọc bảng có cột dense còn giữ. Đáp án tính tay theo dữ liệu ở FCDenseSupport.swift.
import Testing
import ColumnStore
import DAXEngine

private let D = FCDenseModel.tDim
private let F = FCDenseModel.tFact

/// Số dòng thấy được của một bảng trong ngữ cảnh.
private func soDong(_ ctx: FilterContext, _ store: ColumnStore, _ table: TableID) throws -> Int {
    try ctx.visibleRows(in: store, table: table, overrides: []).count
}

@Suite struct FCDenseBlankTests {

    private let store = FCDenseModel.makeStore()

    private func locX(_ values: [Value]) -> FilterContext {
        FilterContext().applying([.filter(FilterItem(column: FCDenseModel.colX, values: values), keep: false)])
    }

    @Test func locGiaTriDoubleTrenCotDense() throws {
        // x = 2.0 khớp D dòng 0 và 2. Fact có fk 1 và 3 khớp hai dòng này: F dòng 0 và 2.
        let ctx = locX([.double(2.0)])
        let rowsD = try ctx.visibleRows(in: store, table: D, overrides: [])
        #expect(rowsD.rows == [0, 2])
        #expect(try soDong(ctx, store, F) == 2, "F dòng 0 (fk 1) và 2 (fk 3)")
    }

    @Test func blankCuaNaNKhopDongBlank() throws {
        // x = BLANK khớp dòng 3 của D (NaN) và blank row ảo (chỉ số 4, mọi cột là BLANK).
        // Fact dòng 4 (fk 4) khớp dòng 3. Fact dòng 3 (fk 9) không khớp, nên vào blank row ảo và được giữ.
        let ctx = locX([.blank])
        #expect(try ctx.visibleRows(in: store, table: D, overrides: []).rows == [3, 4])
        #expect(try soDong(ctx, store, F) == 2)
    }

    @Test func gopNhieuGiaTriGomBlank() throws {
        // x IN {2.0, BLANK}: D dòng 0, 2, 3 và blank row ảo (4). Fact dòng 0 (fk 1), 2 (fk 3), 3 (fk 9 vào blank ảo), 4 (fk 4).
        let ctx = locX([.double(2.0), .blank])
        #expect(try ctx.visibleRows(in: store, table: D, overrides: []).rows == [0, 2, 3, 4])
        #expect(try soDong(ctx, store, F) == 4)
    }

    @Test func giaoHaiDieuKienCungBangRong() throws {
        // g = a (dòng 0, 2) và x = BLANK (dòng 3): giao rỗng, cả D và F đều rỗng.
        let ctx = FilterContext().applying([
            .filter(FilterItem(column: FCDenseModel.colG, values: [.string("a")]), keep: false),
            .filter(FilterItem(column: FCDenseModel.colX, values: [.blank]), keep: false),
        ])
        #expect(try soDong(ctx, store, D) == 0)
        #expect(try soDong(ctx, store, F) == 0)
    }

    @Test func blankRowAoCuaFactKhiLocBlankDense() throws {
        // v = BLANK chỉ khớp F dòng 3 (fk 9 không khớp D): F còn 1 dòng, và blank row ảo của D thấy được.
        let ctx = FilterContext().applying([.filter(FilterItem(column: FCDenseModel.colV, values: [.blank]), keep: false)])
        #expect(try soDong(ctx, store, F) == 1)
        #expect(try ctx.visibleRows(in: store, table: D, overrides: []).contains(4), "blank row ảo của D (chỉ số 4)")
    }

    @Test func valuesTrenCotDenseGiuBlank() throws {
        // g = b: D dòng 1 (x = 5.0) và dòng 3 (x = NaN). VALUES(x) là 5.0 và BLANK theo thứ tự dòng.
        let ctx = FilterContext().applying([.filter(FilterItem(column: FCDenseModel.colG, values: [.string("b")]),
                                                    keep: false)])
        let values = try ctx.visibleValues(of: FCDenseModel.colX, in: store)
        #expect(values == [.double(5.0), .blank])
    }

    @Test func valuesTrenCotDenseSauLocGiaTri() throws {
        let ctx = FilterContext().applying([.filter(FilterItem(column: FCDenseModel.colG, values: [.string("a")]),
                                                    keep: false)])
        #expect(try ctx.visibleValues(of: FCDenseModel.colX, in: store) == [.double(2.0)])
        #expect(try ctx.hasOneValue(FCDenseModel.colX, in: store))
    }

    @Test func chieuBoLocBangGiuCotDenseTrongKhoa() throws {
        // Bộ lọc bảng D chọn dòng 1 (g = b, x = 5.0). Bỏ cột khoá k rồi so theo (g, x): chỉ dòng 1 khớp.
        // Nếu khoá bỏ qua cột dense thì dòng 3 (g = b, x = NaN) cũng bị kéo vào.
        let base = FilterContext().applying(rows: RowsFilter(table: D, rows: RowSet(universe: 5, sortedRows: [1])),
                                            keep: false)
        let chieu = base.removingColumns([FCDenseModel.colK])
        #expect(try chieu.visibleRows(in: store, table: D, overrides: []).rows == [1])
    }

    @Test func chieuBoLocBangKhongBoCotDenseVanDung() throws {
        // Bộ lọc bảng chọn dòng 0 (g = a, x = 2.0). Bỏ cột g: khoá (k, x) chỉ khớp dòng 0.
        let base = FilterContext().applying(rows: RowsFilter(table: D, rows: RowSet(universe: 5, sortedRows: [0])),
                                            keep: false)
        let chieu = base.removingColumns([FCDenseModel.colG])
        #expect(try chieu.visibleRows(in: store, table: D, overrides: []).rows == [0])
    }
}
