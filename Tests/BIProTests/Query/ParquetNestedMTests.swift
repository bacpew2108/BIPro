// specs/011, US6 (T042/T045): M `Parquet.Document` trên tệp lồng cho ô bản ghi/danh sách; mở rộng như Power Query.
import ColumnStore
import Connectors
import Foundation
import MEngine
import Testing
@testable import BIPro

@Suite struct ParquetNestedMTests {
    @Test(.enabled(if: F2Fixtures.sample("nested.parquet") != nil))
    func moRongBanGhiVaDanhSach() async throws {
        let path = try #require(F2Fixtures.sample("nested.parquet")).path
        let m = """
        let
            Source = Parquet.Document(File.Contents(\(StepFactory.quote(path))), [Compression=null, LegacyColumnNameEncoding=false, MaxDepth=null]),
            S = Table.ExpandRecordColumn(Source, "s", {"a", "b"}, {"s.a", "s.b"}),
            L = Table.ExpandListColumn(S, "l")
        in
            L
        """
        let env = MEnvironment(bindings: SourceFunctions.bindings(credentials: CredentialVault(service: "BI Pro test \(UUID().uuidString)")))
        guard case .table(let t) = try await MEvaluator(environment: env).evaluate(source: m, upTo: nil, rowLimit: nil) else {
            Issue.record("không ra bảng"); return
        }
        let names = t.columns.map(\.name)
        #expect(Array(names.prefix(4)) == ["id", "s.a", "s.b", "l"])
        // l: [1,2,3], [] (1 dòng null), null, [null,5], [7], [8,9] → 3 + 1 + 1 + 2 + 1 + 2 = 10 dòng.
        #expect(t.rowCount == 10)
        let l = try #require(t.columns.firstIndex { $0.name == "l" })
        #expect((0..<t.rowCount).map { t.value(row: $0, column: l) }.compactMap { if case .double(let v) = $0 { Int(v) } else if case .integer(let v) = $0 { Int(v) } else { nil } }
                    == [1, 2, 3, 5, 7, 8, 9])
        let sa = try #require(t.columns.firstIndex { $0.name == "s.b" })
        #expect(t.value(row: 0, column: sa) == .string("một"))
    }
}
