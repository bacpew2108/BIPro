// Phase F, T092: ô bảng lồng tính trễ (`MDeferred`) cho bảng điều hướng của nguồn cơ sở dữ liệu (`PostgreSQL.Database`):
// `Source{[Schema=…,Item=…]}[Data]` chỉ đọc bảng được chọn, không đọc mọi bảng của cơ sở dữ liệu.
import ColumnStore
import Foundation
import Synchronization
import Testing
@testable import MEngine

@Suite struct DeferredCellTests {
    @Test func onlyTheNavigatedCellIsComputed() async throws {
        let calls = Mutex<[String]>([])
        func cell(_ name: String) -> MDeferred {
            MDeferred(tag: name) {
                calls.withLock { $0.append(name) }
                return .table(try MTables.build(names: ["x"], types: [nil], columns: [[.number(Double(name.count))]]))
            }
        }
        let nav = try TableData(
            columns: [TableColumn(name: "Item", data: ColumnBuilder.strings(["a", "bb", "ccc"])),
                      TableColumn(name: "Data", data: ColumnBuilder.strings(["Table", "Table", "Table"]))],
            structured: [1: [0: cell("a"), 1: cell("bb"), 2: cell("ccc")]])
        let env = MEnvironment(bindings: ["Nav": .table(nav)])
        let result = try await MEvaluator(environment: env).evaluate(source: "Nav{[Item=\"bb\"]}[Data]", upTo: nil, rowLimit: nil)
        guard case .table(let t) = result else { Issue.record("không phải bảng: \(result)"); return }
        guard case .number(2) = MTables.cell(t, row: 0, column: 0) else { Issue.record("sai ô: \(MTables.cell(t, row: 0, column: 0))"); return }
        #expect(calls.withLock { $0 } == ["bb"])
    }

    @Test func failureSurfacesAsErrorOnAccess() async throws {
        let failing = MDeferred(tag: Optional<String>.none) { throw MError(reason: "DataSource.Error", message: "hỏng") }
        let nav = try TableData(columns: [TableColumn(name: "Data", data: ColumnBuilder.strings(["Table"]))], structured: [0: [0: failing]])
        let env = MEnvironment(bindings: ["Nav": .table(nav)])
        await #expect(throws: MError.self) {
            _ = try await MEvaluator(environment: env).evaluate(source: "Nav{0}[Data]", upTo: nil, rowLimit: nil)
        }
    }
}
