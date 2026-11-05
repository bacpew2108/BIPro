// Gói E3 (Phase C đợt 3): RowSet.union(disjointLists:) thay cho "nối rồi sắp lại" khi lọc theo nhiều mã.
import Testing
@testable import ColumnStore

@Suite struct RowSetUnionTests {
    private func reference(_ lists: [[UInt32]], extra: [UInt32], universe: Int) -> RowSet {
        RowSet(universe: universe, sortedRows: (lists.flatMap { $0 } + extra).sorted())
    }

    @Test func trungVoiNoiRoiSapLai() {
        let universe = 1000
        let cases: [([[UInt32]], [UInt32])] = [
            ([[1, 5, 900], [2, 3, 4]], []),
            ([[0, 10, 20], [5, 15], [7]], [999]),
            ([[]], [999]),
            ([], []),
            ([Array(stride(from: 0, to: 999, by: 3).map(UInt32.init)), Array(stride(from: 1, to: 999, by: 3).map(UInt32.init))], [999]),
        ]
        for (lists, extra) in cases {
            let got = RowSet.union(universe: universe, disjointLists: lists.map { $0[...] }, extra: extra)
            let want = reference(lists, extra: extra, universe: universe)
            #expect(got == want, "lists \(lists.count) extra \(extra)")
            #expect(got.count == want.count)
            #expect(got.rows == want.rows)
        }
    }

    @Test func dongBlankAoKhongDem2Lan() {
        let got = RowSet.union(universe: 10, disjointLists: [[1, 2][...]], extra: [9, 9])
        #expect(got.rows == [1, 2, 9])
        #expect(got.count == 3)
    }
}
