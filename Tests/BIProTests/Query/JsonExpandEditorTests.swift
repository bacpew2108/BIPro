// Phase F, T088: mở rộng cột bản ghi và danh sách trong Query Editor (JSON). Seam: `QueryEditorState` (xem trước, loại cột mở rộng được,
// lệnh `.expandRecord`/`.expandList`). Dữ liệu là văn bản JSON nhỏ trong test, số mong đợi viết tay.
import ColumnStore
import Foundation
import MEngine
import Testing
@testable import BIPro

@Suite("Phase F: mở rộng cột JSON trong Query Editor", .serialized)
@MainActor
struct JsonExpandEditorTests {
    private let json = #"[{"Id":1,"Tags":["a","b"],"Who":{"Name":"An","Age":30}},{"Id":2,"Tags":[],"Who":{"Name":"Bình"}}]"#

    private func editor() async -> QueryEditorState {
        let editor = QueryEditorState()
        let text = StepFactory.quote(json)
        let steps = [
            QueryStep(name: "Source", expression: "Json.Document(\(text))", kind: StepKind.custom),
            QueryStep(name: "Converted to Table", expression: "Table.FromList(Source, Splitter.SplitByNothing(), null, null, ExtraValues.Error)", kind: StepKind.custom),
            QueryStep(name: "Expanded Column1", expression: #"Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"Id", "Tags", "Who"}, {"Id", "Tags", "Who"})"#, kind: StepKind.custom),
        ]
        editor.addQuery(QueryModel(name: "Q", steps: steps, enableLoad: true), base: nil)
        editor.selectQuery(editor.queries[0].id)
        await editor.refresh()
        return editor
    }

    @Test func nhanRaCotBanGhiVaDanhSach() async throws {
        let editor = await editor()
        #expect(editor.errorMessage == nil)
        #expect(editor.nestedColumnNames == ["Tags", "Who"])
        #expect(editor.expandableKind(of: "Tags") == .list)
        #expect(editor.expandableKind(of: "Who") == .record)
        #expect(editor.expandableKind(of: "Id") == nil)
        #expect(editor.nestedColumns(of: "Who")?.map(\.name) == ["Name", "Age"])
        #expect(editor.preview?.value(row: 0, column: 2) == .string("Record"))
    }

    @Test func moBanGhiCoTienToVaDanhSachThanhDong() async throws {
        let editor = await editor()
        var model = ExpandColumnModel(sourceColumn: "Who", allColumns: ["Name", "Age"])
        model.kind = .record
        let command = try #require(model.command())
        #expect(command == .expandRecord(column: "Who", fields: ["Name", "Age"], prefixed: true))
        #expect(editor.perform(command) == .applied)
        #expect(editor.selectedQuery?.steps.last?.expression == #"Table.ExpandRecordColumn(#"Expanded Column1", "Who", {"Name", "Age"}, {"Who.Name", "Who.Age"})"#)
        #expect(editor.perform(.expandList(column: "Tags")) == .applied)
        #expect(editor.selectedQuery?.steps.last?.name == "Expanded Tags")
        await editor.refresh()
        let table = try #require(editor.preview)
        #expect(table.columns.map(\.name) == ["Id", "Tags", "Who.Name", "Who.Age"])
        #expect(table.rowCount == 3)   // đơn 1 hai thẻ, đơn 2 danh sách rỗng → một dòng null
        #expect((0..<3).map { table.value(row: $0, column: 1) } == [.string("a"), .string("b"), .blank])
        #expect((0..<3).map { table.value(row: $0, column: 2) } == [.string("An"), .string("An"), .string("Bình")])
        #expect((0..<3).map { table.value(row: $0, column: 3) } == [.double(30), .double(30), .blank])
    }
}
