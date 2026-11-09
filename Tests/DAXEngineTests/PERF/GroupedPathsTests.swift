// GroupedPathsTests.swift
// E3-cấu-trúc: các đường nhanh mới của engine phải cho cùng kết quả với cách tính trực tiếp:
// - tổ hợp phân biệt theo mã của SUMMARIZECOLUMNS (`distinctEncodedTuples`) so với băm giá trị từng dòng;
// - `FilterContext.values(of:among:)` (mảng cờ + thứ tự dictionary) so với sắp theo `sortRank`.

import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct GroupedPathsTests {
    private typealias Col = MiniBank.Columns

    private let store = MiniBank.makeStore()

    /// Các tập dòng thử: tất cả, một nửa, thưa, rỗng, kèm dòng BLANK ảo (chỉ số = số dòng).
    private func rowSets(for table: TableID) throws -> [(String, RowSet)] {
        let n = try store.rowCount(table)
        let universe = n + 1
        return [
            ("tất cả", RowSet.all(rowCount: n)),
            ("chẵn", RowSet(universe: universe, sortedRows: stride(from: 0, to: n, by: 2).map { UInt32($0) })),
            ("thưa", RowSet(universe: universe, sortedRows: n > 3 ? [1, UInt32(n - 1)] : [])),
            ("rỗng", RowSet.none(universe: universe)),
            ("có dòng BLANK ảo", RowSet(universe: universe, sortedRows: [0, UInt32(n)])),
        ]
    }

    private func brute(_ datas: [ColumnData], _ rows: RowSet, rowCount: Int) -> Set<[Value]> {
        var out = Set<[Value]>()
        rows.forEach { row in
            out.insert(datas.map { row >= rowCount ? .blank : Value(stored: $0.value(at: row)) })
        }
        return out
    }

    @Test func toHopPhanBietTheoMaGiongBamGiaTri() throws {
        let combos: [[ColumnID]] = [
            [Col.DimDate.year],
            [Col.DimDate.month],
            [Col.DimDate.year, Col.DimDate.month],
            [Col.DimDate.year, Col.DimDate.month, Col.DimDate.yearMonth],
            [Col.FactTrans.accountKey],
            [Col.FactTrans.accountKey, Col.FactTrans.clientRegion],
            [Col.DimClient.clientRegion],
            [Col.DimAccount.branchCity, Col.DimAccount.cardType],
        ]
        var fastCount = 0
        for columns in combos {
            let table = columns[0].table
            let n = try store.rowCount(table)
            let datas = try columns.map { try store.column($0) }
            for (name, rows) in try rowSets(for: table) {
                let expected = brute(datas, rows, rowCount: n)
                guard let fast = try SummarizeColumns.distinctEncodedTuples(datas: datas, rows: rows, rowCount: n) else {
                    continue
                }
                fastCount += 1
                #expect(Set(fast) == expected, "\(columns) @ \(name)")
                #expect(fast.count == expected.count, "\(columns) @ \(name): có tổ hợp trùng")
            }
        }
        #expect(fastCount > 10, "đường nhanh phải chạy cho phần lớn tổ hợp")
    }

    @Test func cotKhongMaHoaThiKhongCoDuongNhanh() throws {
        // Cột dense không mã hoá: không có đường nhanh, người gọi dùng đường băm.
        let data = try store.column(Col.FactTrans.amount)
        if !data.isEncoded {
            let rows = RowSet.all(rowCount: try store.rowCount(Col.FactTrans.amount.table))
            #expect(try SummarizeColumns.distinctEncodedTuples(datas: [data], rows: rows, rowCount: data.rowCount) == nil)
        }
    }

    @Test func giaTriPhanBietGiongSapTheoHang() throws {
        let columns: [ColumnID] = [Col.DimDate.year, Col.DimDate.month, Col.DimDate.yearMonth, Col.FactTrans.accountKey,
                                   Col.FactTrans.balanceAfter, Col.DimClient.clientRegion, Col.DimAccount.branchCity]
        var checked = 0
        for column in columns {
            let index = try store.index(column)
            guard index.column.isEncoded else { continue }
            for (name, rows) in try rowSets(for: column.table) {
                // Cách trực tiếp: mã có mặt, sắp theo sortRank.
                var codes = Set<Int>()
                rows.forEach { codes.insert(index.column.code(atRow: $0) ?? 0) }
                let ordered = codes.sorted { (index.sortRank(ofCode: $0) ?? 0) < (index.sortRank(ofCode: $1) ?? 0) }
                let expected: [Value] = ordered.compactMap { code in
                    code == 0 ? .blank : index.column.dictionaryValue(code: code).map { Value(stored: $0) }
                }
                let actual = try FilterContext.empty.bound(to: MiniBank.schema)
                    .values(of: column, among: rows, store: store)
                #expect(actual == expected, "\(column) @ \(name)")
                checked += 1
            }
        }
        #expect(checked > 10)
    }
}
