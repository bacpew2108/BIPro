// Phase F (T050): kiểm trợ giúp golden và hằng số thư viện chuẩn.
import Testing
import ColumnStore
@testable import MEngine

@Suite struct GoldenFixturesTests {
    @Test func hangSoThuVienChuan() async throws {
        let e = MEvaluator(environment: MEnvironment())
        #expect(try await e.evaluate(source: "Order.Ascending") == .number(0))
        #expect(try await e.evaluate(source: "Order.Descending") == .number(1))
        #expect(try await e.evaluate(source: "QuoteStyle.None") == .number(0))
        #expect(try await e.evaluate(source: "QuoteStyle.Csv") == .number(1))
    }

    @Test func goldenTsvDocDuoc() throws {
        let t = try GoldenFixtures.tsv("chuoi-1-pivot-6-dong.tsv")
        #expect(t.header == ["Product", "Count"])
        #expect(t.rows.count == 6)
        #expect(try GoldenFixtures.tsv("chuoi-2-98-dong.tsv").rows.count == 98)
    }

    @Test func salesPromotedCo500Dong() async throws {
        guard let table = try await GoldenFixtures.salesPromoted() else { return }
        #expect(table.rowCount == 500)
        #expect(table.columns.map(\.name) == ["OrderID", "OrderDate", "Region", "CustomerID", "Product", "Qty", "Price", "Amount"])
    }
}
