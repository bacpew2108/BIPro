// Kiểm tra bảng ảo TableValue (FC, đợt 2): lineage, DISTINCT, SUMMARIZE, ADDCOLUMNS, CROSSJOIN, context transition.
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

@Suite struct FCTableValueTests {

    private let store = MiniBank.makeStore()

    /// Các giá trị một cột của bảng nguồn, theo thứ tự dòng.
    private func cacGiaTri(_ column: ColumnID, rows: Int) throws -> [Value] {
        let data = try store.column(column)
        return (0..<rows).map { Value(stored: data.value(at: $0)) }
    }

    @Test func summarizeGiuLineageVaDistinct() throws {
        // SUMMARIZE(Fact_Trans, account_key): 40 dòng, 6 khoá phân biệt (gồm 99).
        let khoa = MiniBank.Columns.FactTrans.accountKey
        let bang = TableValue(columns: ["account_key"],
                              rows: try cacGiaTri(khoa, rows: 40).map { [$0] },
                              lineage: [khoa])
        let tomTat = bang.summarized(groupBy: [0])
        #expect(tomTat.rows.count == FCExpected.summarizeAccountKeysCount)
        #expect(tomTat.lineage == [khoa], "cột nhóm giữ lineage")
        #expect(tomTat.lineageIndex(of: khoa) == 0)
    }

    @Test func rowFilterItemsLaContextTransition() throws {
        // Context transition của bảng ảo: mỗi cột có lineage thành một bộ lọc theo giá trị dòng.
        let khoa = MiniBank.Columns.DimAccount.accountKey
        let tenTP = MiniBank.Columns.DimAccount.branchCity
        let bang = TableValue(columns: ["account_key", "ten", "ghi_chu"],
                              rows: [[.integer(1), .string("Hà Nội"), .string("a")]],
                              lineage: [khoa, tenTP, nil])
        let muc = bang.rowFilterItems(row: 0)
        #expect(muc == [
            FilterItem(column: khoa, values: [.integer(1)]),
            FilterItem(column: tenTP, values: [.string("Hà Nội")]),
        ], "cột không có lineage bị bỏ qua")
        #expect(bang.rowFilterItems(row: 5).isEmpty, "dòng ngoài phạm vi trả rỗng")
    }

    @Test func crossJoinNoiLineageVaDem() throws {
        // CROSSJOIN(thành phố của Dim_Account, thành phố của Dim_District): 3 x 3 = 9 dòng.
        let tp = MiniBank.Columns.DimAccount.branchCity
        let quan = MiniBank.Columns.DimDistrict.city
        let a = TableValue(columns: ["branch_city"],
                           rows: try cacGiaTri(tp, rows: 5).map { [$0] }, lineage: [tp]).distinct()
        let b = TableValue(columns: ["city"],
                           rows: try cacGiaTri(quan, rows: 3).map { [$0] }, lineage: [quan]).distinct()
        let tich = a.crossJoined(with: b)
        #expect(tich.rows.count == FCExpected.crossJoinCitiesDistrictCount)
        #expect(tich.lineage == [tp, quan])
    }

    @Test func addingColumnKhongCoLineageMoi() {
        let khoa = MiniBank.Columns.DimAccount.accountKey
        let bang = TableValue(columns: ["account_key"], rows: [[.integer(1)], [.integer(2)]], lineage: [khoa])
        let co = bang.addingColumn(name: "@c", lineage: nil, values: [.integer(10), .integer(20)])
        #expect(co.columns == ["account_key", "@c"])
        #expect(co.lineage == [khoa, nil])
        #expect(co.rows == [[.integer(1), .integer(10)], [.integer(2), .integer(20)]])
    }

    @Test func valuesDungBangMotCotCoLineage() {
        let tp = MiniBank.Columns.DimAccount.branchCity
        let bang = TableValue.values(of: tp, name: "branch_city",
                                     values: [.string("Hà Nội"), .string("Hà Nội"), .blank])
        #expect(bang.rows.count == 2, "VALUES bỏ giá trị trùng")
        #expect(bang.lineage == [tp])
    }
}
