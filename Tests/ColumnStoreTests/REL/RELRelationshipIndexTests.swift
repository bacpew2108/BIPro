// Kiểm tra chỉ mục many→one (REL, đợt 1b): ánh xạ FK, blank row ảo, hai đường đi ngược và cache.
// Đường posting và đường quét phải cho cùng kết quả, và cùng bằng đáp án brute force.
import Dispatch
import Foundation
import Testing
@testable import ColumnStore
@testable import DAXTestSupport

@Suite struct RELRelationshipIndexTests {

    private func relationship(_ name: String) throws -> RelationshipSchema {
        try #require(MiniBank.schema.relationships.first { $0.name == name }, "thiếu quan hệ \(name)")
    }

    /// Đáp án brute force cho một → nhiều: mọi dòng bên nhiều có FK trong `oneSet`, và blank ảo nếu blank bên một có trong `oneSet`.
    private func bruteManyRows(_ index: RelationshipIndex, _ oneSet: RowSet) -> [UInt32] {
        var out: [UInt32] = []
        for i in 0..<index.manyRowCount where oneSet.contains(Int(index.fkToPK[i])) {
            out.append(UInt32(i))
        }
        if oneSet.contains(index.oneRowCount) {
            out.append(UInt32(index.manyRowCount))
        }
        return out
    }

    /// Đáp án brute force cho nhiều → một: dòng bên một được tham chiếu, blank nếu có dòng trỏ tới nó.
    private func bruteOneRows(_ index: RelationshipIndex, _ manySet: RowSet) -> [UInt32] {
        var hits = Set<Int>()
        for m in manySet.rows {
            let i = Int(m)
            hits.insert(i < index.manyRowCount ? Int(index.fkToPK[i]) : index.oneRowCount)
        }
        return hits.sorted().map { UInt32($0) }
    }

    /// Sinh tập con giả ngẫu nhiên, xác định (LCG cố định) để kết quả tái lập.
    private func randomSet(universe: Int, seed: inout UInt64, density: UInt64) -> RowSet {
        var picked: [UInt32] = []
        for r in 0..<universe {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            if (seed >> 33) % density == 0 { picked.append(UInt32(r)) }
        }
        return RowSet(universe: universe, sortedRows: picked)
    }

    // MARK: - Ánh xạ FK

    @Test func fkToPKMapsEachFactRowToItsDimensionRow() throws {
        let store = MiniBank.makeStore()
        let index = try store.relationshipIndex(try relationship("Trans_Account"))
        #expect(index.manyRowCount == 40)
        #expect(index.oneRowCount == 5)
        // Khoá tài khoản 1..5 nằm ở dòng 0..4. FK 99 không khớp, nên trỏ tới blank row (chỉ số 5).
        for i in 0..<40 {
            let expected = MiniBankRaw.accountKey.firstIndex(of: MiniBankRaw.transAccountKey[i]) ?? 5
            #expect(Int(index.fkToPK[i]) == expected, "dòng \(i)")
        }
        #expect(index.fkToPK[32] == 5, "trans_key 33 có FK 99")
        #expect(index.hasUnmatched)
    }

    @Test func unmatchedFlagIsFalseWhenEveryKeyMatches() throws {
        let store = MiniBank.makeStore()
        #expect(try store.relationshipIndex(try relationship("Trans_Date")).hasUnmatched == false)
        #expect(try store.relationshipIndex(try relationship("Complaint_Client")).hasUnmatched == false)
        // FK -1 của Dim_Account khớp dòng khoá -1 của Dim_Client, nên không có dòng không khớp.
        #expect(try store.relationshipIndex(try relationship("Account_Client")).hasUnmatched == false)
    }

    // MARK: - Một → nhiều

    /// Posting, quét và tự chọn cho cùng kết quả, và bằng brute force, trên nhiều tập bên một ngẫu nhiên.
    @Test func manyRowsAgreeAcrossStrategiesAndBruteForce() throws {
        let store = MiniBank.makeStore()
        for name in ["Trans_Account", "Trans_Date", "Complaint_ReceivedDate", "Complaint_Client"] {
            let index = try store.relationshipIndex(try relationship(name))
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15 ^ UInt64(index.schema.id.raw)
            for density in [UInt64(2), 3, 5] {
                for _ in 0..<20 {
                    let oneSet = randomSet(universe: index.oneRowCount + 1, seed: &seed, density: density)
                    let brute = bruteManyRows(index, oneSet)
                    #expect(index.manyRows(from: oneSet, strategy: .postings).rows == brute, "\(name) posting")
                    #expect(index.manyRows(from: oneSet, strategy: .scan).rows == brute, "\(name) quét")
                    #expect(index.manyRows(from: oneSet).rows == brute, "\(name) tự chọn")
                }
            }
        }
    }

    /// Blank row bên một có trong tập thì kéo theo dòng FK 99 (chỉ số 32), và blank ảo bên nhiều.
    @Test func blankOneRowPullsUnmatchedFactRows() throws {
        let store = MiniBank.makeStore()
        let index = try store.relationshipIndex(try relationship("Trans_Account"))
        let blankOnly = RowSet(universe: 6, sortedRows: [5])
        #expect(index.manyRows(from: blankOnly, strategy: .postings).rows == [32, 40])
        #expect(index.manyRows(from: blankOnly, strategy: .scan).rows == [32, 40])
    }

    // MARK: - Nhiều → một

    @Test func oneRowsAgreeWithBruteForce() throws {
        let store = MiniBank.makeStore()
        for name in ["Trans_Account", "Trans_Date", "Complaint_Client", "Account_Client"] {
            let index = try store.relationshipIndex(try relationship(name))
            var seed: UInt64 = 0x0123_4567_89AB_CDEF ^ UInt64(index.schema.id.raw)
            for density in [UInt64(2), 3, 7] {
                for _ in 0..<20 {
                    let manySet = randomSet(universe: index.manyRowCount + 1, seed: &seed, density: density)
                    #expect(index.oneRows(from: manySet).rows == bruteOneRows(index, manySet), "\(name)")
                }
            }
        }
    }

    // MARK: - Cache theo store

    /// 32 luồng cùng xin chỉ mục thì mọi luồng nhận cùng một ánh xạ.
    @Test func concurrentIndexRequestsShareOneBuild() throws {
        let store = MiniBank.makeStore()
        let rel = try relationship("Trans_Account")
        let maps = RELResultBox<[Int32]>()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            if let index = try? store.relationshipIndex(rel) {
                maps.append(index.fkToPK)
            }
        }
        #expect(maps.all.count == 32)
        #expect(Set(maps.all).count == 1)
    }

    /// Cache gắn với store đang sống. Store mới (kể cả khi địa chỉ được tái sử dụng) không dùng chỉ mục cũ.
    @Test func newStoreDoesNotReuseIndexOfDeadStore() throws {
        let rel = try relationship("Trans_Account")
        do {
            let first = MiniBank.makeStore()
            #expect(try first.relationshipIndex(rel).hasUnmatched)
        }
        // Nguồn khác: không còn dòng không khớp, vì FK 99 được thay bằng khoá 1.
        var keys = MiniBankRaw.transAccountKey
        keys[32] = 1
        let base = MiniBank.makeSource()
        let accountColumn = ColumnBuilder.integers(keys.map { Optional($0) })
        var columns: [ColumnID: ColumnData] = [:]
        for table in MiniBank.schema.tables {
            for column in table.columns {
                if column.id == MiniBank.Columns.FactTrans.accountKey {
                    columns[column.id] = accountColumn
                } else if let data = try? base.loadColumn(column.id) {
                    columns[column.id] = data
                }
            }
        }
        var rowCounts: [TableID: Int] = [:]
        for table in MiniBank.schema.tables {
            rowCounts[table.id] = try base.rowCount(table.id)
        }
        let second = ColumnStore(source: InMemoryColumnSource(schema: MiniBank.schema, rowCounts: rowCounts,
                                                              columns: columns))
        #expect(try second.relationshipIndex(rel).hasUnmatched == false)
    }
}
