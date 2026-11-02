// Kiểm tra RowSet dạng bitset và dạng thưa (CS, đợt 1a).
// Dữ liệu ngẫu nhiên dùng seed cố định, nên mỗi lần chạy cho cùng kết quả. Đáp án là mảng tăng dần tính bằng Set.
import Testing
@testable import ColumnStore

/// Bộ sinh số giả ngẫu nhiên có seed (SplitMix64). Không dùng `SystemRandomNumberGenerator` để test lặp lại được.
struct CSSeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Tập con ngẫu nhiên của 0..<universe với mật độ cho trước, đã sắp tăng dần.
private func randomRows(universe: Int, density: Double, rng: inout CSSeededGenerator) -> [UInt32] {
    var out: [UInt32] = []
    for i in 0..<universe {
        let u = Double(rng.next() >> 11) / Double(1 << 53)
        if u < density { out.append(UInt32(i)) }
    }
    return out
}

@Suite struct CSRowSetTests {

    @Test func denseAndSparseMatchReferenceOnRandomSets() {
        var rng = CSSeededGenerator(seed: 20_260_101)
        let universes = [1, 2, 31, 32, 33, 63, 64, 65, 127, 128, 129, 1000, 4097]
        let densities = [0.0, 0.005, 0.02, 0.03, 0.05, 0.3, 0.5, 0.97, 1.0]
        for universe in universes {
            for density in densities {
                let a = randomRows(universe: universe, density: density, rng: &rng)
                let b = randomRows(universe: universe, density: 0.4, rng: &rng)
                let setA = Set(a.map(Int.init)), setB = Set(b.map(Int.init))
                let rsA = RowSet(universe: universe, sortedRows: a)
                let rsB = RowSet(universe: universe, sortedRows: b)
                let label = "universe \(universe), mật độ \(density)"

                #expect(rsA.rows == a, "rows phải khớp đầu vào: \(label)")
                #expect(rsA.count == a.count, "count: \(label)")
                for row in 0..<(universe + 2) {
                    #expect(rsA.contains(row) == setA.contains(row), "contains(\(row)): \(label)")
                }
                let expectedAnd = setA.intersection(setB).sorted().map(UInt32.init)
                let expectedOr = setA.union(setB).sorted().map(UInt32.init)
                #expect(rsA.intersection(rsB).rows == expectedAnd, "giao: \(label)")
                #expect(rsB.intersection(rsA).rows == expectedAnd, "giao đảo: \(label)")
                #expect(rsA.union(rsB).rows == expectedOr, "hợp: \(label)")
                #expect(rsB.union(rsA).rows == expectedOr, "hợp đảo: \(label)")
                #expect(rsA.intersection(rsB).count == expectedAnd.count, "count giao: \(label)")
                #expect(rsA.union(rsB).count == expectedOr.count, "count hợp: \(label)")

                var visited: [UInt32] = []
                rsA.forEach { visited.append(UInt32($0)) }
                #expect(visited == a, "forEach: \(label)")
            }
        }
    }

    @Test func representationFollowsDensityThreshold() {
        // Ngưỡng: thưa khi số phần tử × 32 ≤ universe.
        let universe = 3200
        let sparse = RowSet(universe: universe, sortedRows: (0..<100).map { UInt32($0 * 32) })
        #expect(sparse.count == 100)
        #expect(!sparse.usesBitset, "100 × 32 ≤ 3200 phải là thưa")
        let dense = RowSet(universe: universe, sortedRows: (0..<101).map { UInt32($0 * 31) })
        #expect(dense.usesBitset, "101 × 32 > 3200 phải là bitset")
        #expect(RowSet.none(universe: universe).count == 0)
        #expect(!RowSet.none(universe: universe).usesBitset)
    }

    @Test func allRowsUsesBitsetAndExcludesVirtualBlankRow() {
        for rowCount in [0, 1, 63, 64, 65, 127, 128, 1000] {
            let all = RowSet.all(rowCount: rowCount)
            #expect(all.universe == rowCount + 1)
            #expect(all.count == rowCount)
            #expect(all.rows == (0..<rowCount).map { UInt32($0) }, "all(\(rowCount)) rows")
            #expect(!all.contains(rowCount), "blank row ảo không thuộc all(\(rowCount))")
            if rowCount >= 64 {
                #expect(all.usesBitset, "all(\(rowCount)) đặc nên dùng bitset")
            }
        }
    }

    @Test func equalSetsFromDifferentPathsAreEqualAndHashEqual() {
        // Cùng universe 301, cùng 300 dòng, đi qua hai đường dựng khác nhau (all và sortedRows).
        let viaAll = RowSet.all(rowCount: 300)
        let viaSorted = RowSet(universe: 301, sortedRows: (0..<300).map { UInt32($0) })
        #expect(viaSorted == viaAll)
        #expect(viaSorted.hashValue == viaAll.hashValue)

        let other = RowSet(universe: 301, sortedRows: (0..<299).map { UInt32($0) })
        #expect(viaSorted != other)
    }

    @Test func intersectionAndUnionWithEmptyAndFull() {
        let universe = 70
        let full = RowSet.all(rowCount: 69)
        let empty = RowSet.none(universe: universe)
        #expect(full.intersection(empty).count == 0)
        #expect(full.union(empty).rows == full.rows)
        #expect(full.intersection(full).rows == full.rows)
    }

    @Test func containsOutsideUniverseIsFalse() {
        let set = RowSet(universe: 10, sortedRows: [0, 9])
        #expect(!set.contains(-1))
        #expect(!set.contains(10))
        #expect(set.contains(9))
    }
}
