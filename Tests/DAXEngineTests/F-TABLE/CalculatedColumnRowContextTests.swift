// Phase F, T081: cột tính toán trên MiniBank (không cần file): EARLIER, EARLIEST, RELATEDTABLE, RELATED hai bước. Đáp án đếm thẳng
// từ dữ liệu lưu của store bằng Swift (không qua DAX); cột `Fact_Trans[client_region]` so với giá trị lưu sẵn do Python tính.
import ColumnStore
import DAXTestSupport
import Testing
@testable import DAXEngine

struct CalculatedColumnRowContextTests {
    private let engine = DAXEngine(store: MiniBank.makeStore(), catalog: Catalog(schema: MiniBank.schema))

    private func stored(_ id: ColumnID) throws -> [Value] {
        let data = try engine.store.column(id)
        return (0..<(try engine.store.rowCount(id.table))).map { Value(stored: data.value(at: $0)) }
    }

    private func number(_ v: Value) -> Double? {
        switch v {
        case .integer(let i): Double(i)
        case .currency(let c): Double(c) / 10_000
        case .double(let d): d
        default: nil
        }
    }

    @Test func earlierXepHangTheoSoTien() throws {
        let amounts = try stored(MiniBank.Columns.FactTrans.amount).map { number($0)! }
        let computed = try engine.calculatedColumn(
            table: "Fact_Trans",
            expression: "COUNTROWS(FILTER(Fact_Trans, Fact_Trans[amount] > EARLIER(Fact_Trans[amount]))) + 1")
        let expected = amounts.map { a in Value.integer(Int64(amounts.filter { $0 > a }.count + 1)) }
        #expect(computed == expected)
        // EARLIEST cùng kết quả khi chỉ có hai cấp.
        let earliest = try engine.calculatedColumn(
            table: "Fact_Trans",
            expression: "COUNTROWS(FILTER(Fact_Trans, Fact_Trans[amount] > EARLIEST(Fact_Trans[amount]))) + 1")
        #expect(earliest == expected)
    }

    @Test func earlierKhongCoKhungNgoaiBaoLoi() {
        #expect(throws: DAXError.self) {
            _ = try engine.calculatedColumn(table: "Fact_Trans", expression: "EARLIER(Fact_Trans[amount])")
        }
    }

    @Test func relatedTableDemGiaoDichMoiTaiKhoan() throws {
        let transAccount = try stored(MiniBank.Columns.FactTrans.accountKey)
        let accounts = try stored(MiniBank.Columns.DimAccount.accountKey)
        let computed = try engine.calculatedColumn(table: "Dim_Account", expression: "COUNTROWS(RELATEDTABLE(Fact_Trans))")
        let expected = accounts.map { key -> Value in
            let n = transAccount.filter { $0 == key }.count
            return n == 0 ? .blank : .integer(Int64(n))
        }
        #expect(computed == expected)
    }

    @Test func relatedHaiBuocKhopCotLuuSan() throws {
        let computed = try engine.calculatedColumn(table: "Fact_Trans", expression: "RELATED(Dim_Client[client_region])")
        let expected = try stored(MiniBank.Columns.FactTrans.clientRegion)
        #expect(computed == expected)
    }
}
