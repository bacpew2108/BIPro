// Kiểm tra contract của ColumnStore ở đợt 0 (lead). Test thật của CS nằm ở file có tiền tố riêng.
import Testing
@testable import ColumnStore

@Suite struct ColumnContractSmokeTests {
    @Test func rowSetIntersectionAndUnion() {
        let a = RowSet(universe: 10, sortedRows: [1, 3, 5, 7])
        let b = RowSet(universe: 10, sortedRows: [3, 4, 5])
        #expect(a.intersection(b).rows == [3, 5])
        #expect(a.union(b).rows == [1, 3, 4, 5, 7])
        #expect(a.contains(5) && !a.contains(4))
    }

    @Test func allRowsExcludesVirtualBlankRow() {
        let all = RowSet.all(rowCount: 3)
        #expect(all.rows == [0, 1, 2])
        #expect(all.universe == 4)
    }

    @Test func builderKeepsBlankAndEmptyStringApart() {
        let column = ColumnBuilder.strings(["a", nil, "", "a"])
        #expect(column.value(at: 0) == .string("a"))
        #expect(column.value(at: 1) == .blank)
        #expect(column.value(at: 2) == .string(""))
        #expect(column.value(at: 3) == .string("a"))
        #expect(column.value(at: 4) == .blank, "dòng ngoài phạm vi (blank row ảo) phải là BLANK")
    }

    @Test func denseNaNIsBlank() {
        let column = ColumnData(type: .double, rowCount: 2, payload: .dense(.doubles([1.5, .nan])))
        #expect(column.value(at: 0) == .double(1.5))
        #expect(column.value(at: 1) == .blank)
    }

    @Test func columnStoreLoadsLazilyOnce() throws {
        let schema = ModelSchema(culture: "en-US", tables: [], relationships: [])
        let id = ColumnID(table: TableID(raw: 1), index: 7)
        let source = InMemoryColumnSource(
            schema: schema,
            rowCounts: [TableID(raw: 1): 2],
            columns: [id: ColumnBuilder.integers([10, nil])])
        let store = ColumnStore(source: source)
        #expect(try store.column(id).value(at: 0) == .integer(10))
        #expect(try store.rowCount(TableID(raw: 1)) == 2)
    }
}
