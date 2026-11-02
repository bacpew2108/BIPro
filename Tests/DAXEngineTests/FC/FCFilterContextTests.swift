// Kiểm tra FilterContext trên MiniBank (FC, đợt 2): ghi đè, KEEPFILTERS, chiếu, expanded table, ISFILTERED.
// Đáp án nằm ở FCExpected.swift, sinh bằng Python stdlib (fc_oracle.py), không tính bằng Swift.
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

/// Số dòng Fact_Trans thấy được trong ngữ cảnh.
private func soGiaoDich(_ ctx: FilterContext, _ store: ColumnStore) throws -> Int {
    try ctx.visibleRows(in: store, table: MiniBank.Tables.factTrans, overrides: []).count
}

private let cotNam = MiniBank.Columns.DimDate.year
private let cotThanhPho = MiniBank.Columns.DimAccount.branchCity
private let cotTheTu = MiniBank.Columns.DimAccount.cardType
private let cotVungClient = MiniBank.Columns.DimClient.clientRegion

@Suite struct FCFilterContextTests {

    private let store = MiniBank.makeStore()

    // MARK: Ghi đè và KEEPFILTERS

    @Test func ghiDeLenBoLocCungCot() throws {
        // CALCULATE không KEEPFILTERS: lọc năm 2024 thay lọc năm 2023 trên cùng cột.
        let nam2023 = FilterContext().applying(FilterItem(column: cotNam, values: [.integer(2023)]), keep: false)
        let nam2024 = nam2023.applying(FilterItem(column: cotNam, values: [.integer(2024)]), keep: false)
        #expect(nam2024.values(for: cotNam) == [.integer(2024)], "chỉ còn một mục cho cột năm")
        #expect(try soGiaoDich(nam2024, store) == FCExpected.overwriteYear2024Trans)
    }

    @Test func ghiDeThanhPhoKhongGiuLocCu() throws {
        let hcm = FilterContext()
            .applying([.filter(FilterItem(column: cotThanhPho, values: [.string("Hà Nội"), .string("Đà Nẵng")]), keep: false)])
            .applying([.filter(FilterItem(column: cotThanhPho, values: [.string("TP. Hồ Chí Minh")]), keep: false)])
        #expect(hcm.values(for: cotThanhPho) == [.string("TP. Hồ Chí Minh")])
        #expect(try soGiaoDich(hcm, store) == FCExpected.overwriteHcmTrans)
    }

    @Test func keepFiltersGiaoGiaTri() throws {
        // KEEPFILTERS: {Hà Nội, Đà Nẵng} giao {Hà Nội, TP. Hồ Chí Minh} = {Hà Nội}.
        let base = FilterContext().applying([
            .filter(FilterItem(column: cotThanhPho, values: [.string("Hà Nội"), .string("Đà Nẵng")]), keep: false),
        ])
        let giao = base.applying([
            .filter(FilterItem(column: cotThanhPho, values: [.string("Hà Nội"), .string("TP. Hồ Chí Minh")]), keep: true),
        ])
        #expect(giao.values(for: cotThanhPho) == [.string("Hà Nội")])
        #expect(try soGiaoDich(giao, store) == FCExpected.keepIntersectHanoiTrans)
    }

    @Test func keepFiltersTrenCotChuaCoBoLoc() throws {
        // KEEPFILTERS khi chưa có bộ lọc trên cột thì chỉ là thêm mới.
        let ctx = FilterContext().applying([
            .filter(FilterItem(column: cotThanhPho, values: [.string("Đà Nẵng")]), keep: true),
        ])
        #expect(ctx.values(for: cotThanhPho) == [.string("Đà Nẵng")])
    }

    // MARK: Chiếu và expanded table

    @Test func chieuBoLocCot() throws {
        // Lọc Đà Nẵng và năm 2024, rồi REMOVEFILTERS(năm): chỉ còn lọc thành phố.
        let ctx = FilterContext().applying([
            .filter(FilterItem(column: cotThanhPho, values: [.string("Đà Nẵng")]), keep: false),
            .filter(FilterItem(column: cotNam, values: [.integer(2024)]), keep: false),
        ])
        #expect(try soGiaoDich(ctx, store) == FCExpected.filteredDanangYear2024Trans)
        let boNam = ctx.applying([.removeColumns([cotNam])])
        #expect(boNam.values(for: cotNam) == nil)
        #expect(boNam.values(for: cotThanhPho) == [.string("Đà Nẵng")])
        #expect(try soGiaoDich(boNam, store) == FCExpected.projectRemoveYearDanangTrans)
    }

    @Test func expandedTableBoLocLanQuaBang() throws {
        // Lọc thành phố Hà Nội, năm 2024, vùng Miền Bắc (Dim_Client phía một của Dim_Account).
        let goc = FilterContext.empty.bound(to: MiniBank.schema)
        let ctx = goc.applying([
            .filter(FilterItem(column: cotThanhPho, values: [.string("Hà Nội")]), keep: false),
            .filter(FilterItem(column: cotNam, values: [.integer(2024)]), keep: false),
            .filter(FilterItem(column: cotVungClient, values: [.string("Miền Bắc")]), keep: false),
        ])
        #expect(try soGiaoDich(ctx, store) == FCExpected.expandedBeforeRemoveTrans)

        // REMOVEFILTERS(Dim_Account) xoá cả lọc trên Dim_Client, nhưng không xoá lọc năm (Dim_Date không thuộc expanded).
        let boAccount = ctx.applying([.removeExpandedTable(MiniBank.Tables.dimAccount)])
        #expect(boAccount.values(for: cotThanhPho) == nil)
        #expect(boAccount.values(for: cotVungClient) == nil)
        #expect(boAccount.values(for: cotNam) == [.integer(2024)])
        #expect(try soGiaoDich(boAccount, store) == FCExpected.expandedAfterRemoveAccountTrans)

        // REMOVEFILTERS(Fact_Trans) xoá mọi bộ lọc trên các bảng mà Fact_Trans mở rộng tới.
        let boFact = ctx.applying([.removeExpandedTable(MiniBank.Tables.factTrans)])
        #expect(boFact.items.isEmpty)
        #expect(try soGiaoDich(boFact, store) == FCExpected.expandedAfterRemoveFactTrans)
    }

    @Test func removeAllGiuGhiDeQuanHe() throws {
        let ctx = FilterContext().applying([
            .filter(FilterItem(column: cotNam, values: [.integer(2024)]), keep: false),
            .useRelationship(RelationshipID(raw: 4)),
        ])
        let trong = ctx.removingAll()
        #expect(trong.items.isEmpty)
        #expect(trong.relationshipOverrides == ctx.relationshipOverrides, "REMOVEFILTERS() không xoá USERELATIONSHIP")
    }

    // MARK: ISFILTERED và vân tay

    @Test func isFilteredDocTuNguCanh() {
        let ctx = FilterContext().applying([
            .filter(FilterItem(column: cotThanhPho, values: [.string("Hà Nội")]), keep: false),
        ])
        #expect(ctx.isFiltered(cotThanhPho))
        #expect(!ctx.isFiltered(cotTheTu), "cột khác cùng bảng không bị lọc trực tiếp")
        #expect(ctx.isFiltered(table: MiniBank.Tables.dimAccount))
        #expect(!ctx.isFiltered(table: MiniBank.Tables.dimDate))
        #expect(!ctx.removingColumns([cotThanhPho]).isFiltered(table: MiniBank.Tables.dimAccount))
    }

    @Test func vanTayPhanBietNguCanh() {
        let a = FilterContext().applying([
            .filter(FilterItem(column: cotThanhPho, values: [.string("Hà Nội")]), keep: false),
        ])
        let b = FilterContext().applying([
            .filter(FilterItem(column: cotThanhPho, values: [.string("Hà Nội")]), keep: false),
        ])
        let c = a.applying([.filter(FilterItem(column: cotNam, values: [.integer(2024)]), keep: false)])
        #expect(a == b && a.fingerprint == b.fingerprint, "cùng nội dung thì cùng khoá cache")
        #expect(a != c && a.fingerprint != c.fingerprint, "khác bộ lọc thì khác khoá cache")
    }
}
