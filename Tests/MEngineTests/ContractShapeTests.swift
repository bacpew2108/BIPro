// Phase F, T005: hình dạng hợp đồng MEngine. Seam: contracts/m-engine.md. Thân hàm còn là khung.
import Testing
import ColumnStore
@testable import MEngine

@Suite struct MEngineContractShapeTests {
    @Test func unsupportedErrorNamesTheFunctionAndLine() {
        let error = MError.unsupported("Table.Fuzzy", line: 4)
        #expect(error.reason == "Expression.Unsupported")
        #expect(error.message.contains("Table.Fuzzy") && error.message.contains("4"))
    }

    @Test func valuesHoldTablesAndErrorsAsData() throws {
        let table = try TableData(columns: [TableColumn(name: "A", data: ColumnBuilder.integers([1]))])
        let record = MValue.record([MField(name: "t", value: .table(table)), MField(name: "e", value: .error(MError(reason: "r", message: "m")))])
        guard case .record(let fields) = record, case .table(let t) = fields[0].value, case .error = fields[1].value else {
            Issue.record("sai hình dạng"); return
        }
        #expect(t.rowCount == 1)
    }
}
