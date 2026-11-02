// Kiểm tra blank row (FK 99), USERELATIONSHIP, bộ lọc theo bảng (chiếu) và VALUES/HASONEVALUE trên MiniBank.
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

/// Tổng cột amount (currency nhân 10^4) của các dòng Fact_Trans thấy được.
private func tongAmount(_ rows: RowSet, _ store: ColumnStore) throws -> Int64 {
    let data = try store.column(MiniBank.Columns.FactTrans.amount)
    var tong: Int64 = 0
    rows.forEach { row in
        if case .currency(let v) = data.value(at: row) { tong += v }
    }
    return tong
}

private let cotThanhPho = MiniBank.Columns.DimAccount.branchCity
private let cotTheTu = MiniBank.Columns.DimAccount.cardType
private let cotNgayKhoa = MiniBank.Columns.DimDate.dateKey

@Suite struct FCBlankRelTests {

    private let store = MiniBank.makeStore()

    // MARK: Blank row (FK 99)

    @Test func blankRowKhongLocThiCoMatDong() throws {
        // Dim_Account có 5 dòng thật và 1 blank row ảo vì FK 99 không khớp.
        let tai = try FilterContext().visibleRows(in: store, table: MiniBank.Tables.dimAccount, overrides: [])
        #expect(tai.count == FCExpected.dimAccountVisibleNoFilter)
        #expect(tai.contains(5), "blank row ảo có chỉ số rowCount = 5")
    }

    @Test func locBlankChiGiuBlankRow() throws {
        // Lọc thành phố = BLANK: chỉ blank row của Dim_Account, và chỉ giao dịch FK 99 đi vào đó.
        let ctx = FilterContext().applying([
            .filter(FilterItem(column: cotThanhPho, values: [.blank]), keep: false),
        ])
        let tai = try ctx.visibleRows(in: store, table: MiniBank.Tables.dimAccount, overrides: [])
        #expect(tai.count == FCExpected.dimAccountVisibleBlankCity)
        #expect(tai.contains(5))

        let giaoDich = try ctx.visibleRows(in: store, table: MiniBank.Tables.factTrans, overrides: [])
        #expect(giaoDich.count == FCExpected.blankCityTrans)
        #expect(try tongAmount(giaoDich, store) == Int64(FCExpected.blankCityTransSum))
    }

    @Test func valuesGomBlankCuaBlankRow() throws {
        // VALUES(thành phố) không lọc: ba thành phố và BLANK của blank row.
        let gia = try FilterContext().visibleValues(of: cotThanhPho, in: store)
        #expect(gia.count == FCExpected.valuesBranchCityNoFilterCount)
        #expect(gia.contains(.blank))
        #expect(Set(gia).isSuperset(of: [.string("Hà Nội"), .string("Đà Nẵng"), .string("TP. Hồ Chí Minh")]))
    }

    @Test func hasOneValueDocTuVaiTroNgu() throws {
        // Thành phố Hà Nội chỉ có tài khoản 1 và 4, đều là thẻ Debit.
        let ctx = FilterContext().applying([
            .filter(FilterItem(column: cotThanhPho, values: [.string("Hà Nội")]), keep: false),
        ])
        #expect(try ctx.hasOneValue(cotTheTu, in: store))
        #expect(try ctx.visibleValues(of: cotTheTu, in: store) == [.string("Debit")])
        #expect(!(try FilterContext().hasOneValue(cotTheTu, in: store)))
    }

    // MARK: USERELATIONSHIP

    @Test func userRelationshipDoiQuanHeHoatDong() throws {
        // Fact_Complaint có quan hệ hoạt động tới Dim_Date qua received_date, và inactive qua sent_date.
        let ctx = FilterContext().applying([
            .filter(FilterItem(column: cotNgayKhoa, values: [.integer(20230315)]), keep: false),
        ])
        let mac = MiniBank.Tables.factComplaint
        let nhan = try ctx.visibleRows(in: store, table: mac, overrides: [])
        #expect(nhan.count == FCExpected.complaintActiveReceivedMatch)

        // USERELATIONSHIP(sent_date) bật quan hệ inactive và tắt quan hệ received_date cùng cặp bảng.
        let gui = ctx.applying([.useRelationship(RelationshipID(raw: 4))])
        let ketQua = try gui.visibleRows(in: store, table: mac, overrides: [])
        #expect(ketQua.count == FCExpected.complaintSentWithUserRelationship)
    }

    // MARK: Bộ lọc theo bảng và chiếu

    @Test func boLocBangLocDongFact() throws {
        // Bộ lọc bảng là các giao dịch của năm 2024 (vị trí 20..39). Chỉ fact bị lọc, Dim_Date thì không.
        let nam2024 = RowSet(universe: 41, sortedRows: (20...39).map { UInt32($0) })
        let ctx = FilterContext().applying(rows: RowsFilter(table: MiniBank.Tables.factTrans, rows: nam2024), keep: false)
        #expect(try ctx.visibleRows(in: store, table: MiniBank.Tables.factTrans, overrides: []).count
            == FCExpected.rowsFilterFact2024Trans)
        #expect(try ctx.visibleRows(in: store, table: MiniBank.Tables.dimDate, overrides: []).count
            == FCExpected.rowsFilterFact2024DimDate, "quan hệ một chiều: lọc fact không lọc ngược dim")
    }

    @Test func boLocBangDimAccountTheoViTri() throws {
        // Bộ lọc bảng Dim_Account {vị trí 0, 3} = tài khoản 1 và 4.
        let hai = RowSet(universe: 6, sortedRows: [0, 3])
        let ctx = FilterContext().applying(rows: RowsFilter(table: MiniBank.Tables.dimAccount, rows: hai), keep: false)
        #expect(try ctx.visibleRows(in: store, table: MiniBank.Tables.factTrans, overrides: []).count
            == FCExpected.rowsFilterAccount14Trans)
    }

    @Test func chieuBoLocBangLamRongDong() throws {
        // Bộ lọc bảng chỉ có tài khoản 1. Chiếu bỏ account_key và client_key, còn (Hà Nội, Debit).
        // Hai dòng Dim_Account khớp: tài khoản 1 và 4. Fact theo đó thấy giao dịch của cả hai.
        let mot = RowSet(universe: 6, sortedRows: [0])
        let ctx = FilterContext()
            .applying(rows: RowsFilter(table: MiniBank.Tables.dimAccount, rows: mot), keep: false)
            .removingColumns([MiniBank.Columns.DimAccount.accountKey, MiniBank.Columns.DimAccount.clientKey])
        #expect(try ctx.visibleRows(in: store, table: MiniBank.Tables.dimAccount, overrides: []).count
            == FCExpected.rowsFilterProjectedDimAccountRows)
        #expect(try ctx.visibleRows(in: store, table: MiniBank.Tables.factTrans, overrides: []).count
            == FCExpected.rowsFilterProjectedFactTrans)
    }
}
