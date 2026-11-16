// Phase F, T063: "Làm mới nguồn" trong Query Editor. Truy vấn đọc từ file có bước khoá (bảng nền = dữ liệu đã lưu); làm mới chạy M thật của các
// bước đó (Csv.Document, Excel.Workbook…) để đọc lại tệp nguồn. Tệp mất/đổi chỗ thì giữ dữ liệu cũ và báo lý do; dữ liệu đổi thì
// truy vấn thành "chưa áp dụng" để Close & Apply thay bảng.
import ColumnStore
import Foundation
import MEngine
import Testing
@testable import BIPro

@Suite("Phase F: làm mới nguồn", .serialized)
@MainActor
struct RefreshSourceTests {
    private func csvQuery(path: String) -> String {
        """
        let
            Source = Csv.Document(File.Contents("\(path)"),[Delimiter=",", Columns=2, Encoding=65001, QuoteStyle=QuoteStyle.None]),
            #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
            #"Changed Type" = Table.TransformColumnTypes(#"Promoted Headers",{{"ID", Int64.Type}, {"Name", type text}})
        in
            #"Changed Type"
        """
    }

    /// Bảng lưu trong file lúc "nạp": 2 dòng.
    private func savedTable() throws -> TableData {
        try TableData(columns: [
            TableColumn(name: "ID", data: ColumnBuilder.integers([1, 2])),
            TableColumn(name: "Name", data: ColumnBuilder.strings(["An", "Binh"])),
        ])
    }

    private func editor(path: String) throws -> (QueryEditorState, UUID) {
        let editor = QueryEditorState()
        let query = QueryEditorState.model(name: "People", source: csvQuery(path: path), tableName: "People", locked: true)
        editor.addQuery(query, base: try savedTable())
        return (editor, query.id)
    }

    private func tempFile(_ name: String, _ text: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bipro-refresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func refreshReadsTheSourceFileAgain() async throws {
        let url = try tempFile("people.csv", "ID,Name\n1,An\n2,Binh\n3,Chi\n")
        let (editor, id) = try editor(path: url.path)
        #expect(editor.hasPendingChanges == false)
        #expect(editor.queries[0].isModified == false)

        #expect(await editor.refreshSource(of: id) == nil)
        await editor.refresh()
        #expect(editor.errorMessage == nil)
        #expect(editor.preview?.rowCount == 3)   // 3 dòng: tệp có thêm "Chi"
        #expect(editor.preview?.value(row: 2, column: 1) == .string("Chi"))
        #expect(editor.queries[0].dataChanged)
        #expect(editor.queries[0].isModified)    // Close & Apply sẽ thay bảng
        #expect(editor.hasPendingChanges)
    }

    @Test func refreshWithUnchangedFileChangesNothing() async throws {
        let url = try tempFile("people.csv", "ID,Name\n1,An\n2,Binh\n")
        let (editor, id) = try editor(path: url.path)
        #expect(await editor.refreshSource(of: id) == nil)
        #expect(editor.queries[0].dataChanged == false)
        #expect(editor.hasPendingChanges == false)
    }

    @Test func missingSourceKeepsSavedDataAndSaysWhy() async throws {
        let path = "C:\\Users\\bacpew\\f6\\khong-co.csv"
        let (editor, id) = try editor(path: path)
        let reason = try #require(await editor.refreshSource(of: id))
        #expect(reason.contains(path))
        #expect(reason.contains("Không tìm thấy tệp nguồn"))
        #expect(reason.contains("giữ nguyên"))
        await editor.refresh()
        #expect(editor.preview?.rowCount == 2)    // vẫn xem trước bằng dữ liệu đã lưu
        #expect(editor.queries[0].dataChanged == false)
        #expect(editor.hasPendingChanges == false)
    }

    @Test func movedSourceCanBeFixedInTheAdvancedEditorAndRefreshed() async throws {
        let url = try tempFile("moved.csv", "ID,Name\n7,Zed\n")
        let (editor, id) = try editor(path: "C:\\nowhere\\people.csv")
        #expect(await editor.refreshSource(of: id) != nil)
        // Người dùng đổi đường dẫn trong Advanced Editor (đổi bước khoá bị từ chối: tạo truy vấn mới từ văn bản M).
        let fixed = QueryEditorState.model(name: "People", source: csvQuery(path: url.path), tableName: "People", locked: true)
        var query = editor.queries[0]
        query.steps = fixed.steps
        editor.queries[0] = query
        #expect(await editor.refreshSource(of: id) == nil)
        await editor.refresh()
        #expect(editor.preview?.rowCount == 1)
        #expect(editor.preview?.value(row: 0, column: 1) == .string("Zed"))
    }

    @Test func excelWorkbookNavigationReadsTheSheet() async throws {
        guard let xlsx = FFixtures.sample("sales_2026.xlsx") else { return }
        let source = """
        let
            Source = Excel.Workbook(File.Contents("\(xlsx.path)"), null, true),
            Sales_Sheet = Source{[Item="Sales",Kind="Sheet"]}[Data],
            #"Promoted Headers" = Table.PromoteHeaders(Sales_Sheet, [PromoteAllScalars=true])
        in
            #"Promoted Headers"
        """
        let editor = QueryEditorState()
        let query = QueryEditorState.model(name: "Sales", source: source, tableName: "Sales", locked: true)
        editor.addQuery(query, base: try savedTable())
        #expect(await editor.refreshSource(of: query.id) == nil)
        await editor.refresh()
        #expect(editor.errorMessage == nil)
        #expect(editor.preview?.columns.map(\.name).prefix(3) == ["OrderID", "OrderDate", "Region"])
        #expect(editor.queries[0].dataChanged)   // khác bảng 2 dòng ban đầu
    }

    @Test func hiddenQueryWithoutLockedStepsEvaluatesTheSourceDirectly() async throws {
        let url = try tempFile("direct.csv", "ID,Name\n5,Eo\n")
        let editor = QueryEditorState()
        let query = QueryEditorState.model(name: "Direct", source: csvQuery(path: url.path), tableName: nil, locked: false)
        editor.addQuery(query, base: nil)
        await editor.refresh()
        #expect(editor.errorMessage == nil)
        #expect(editor.preview?.rowCount == 1)
        #expect(await editor.refreshSource(of: query.id) == nil)   // không có bước khoá: không có gì để làm mới
    }
}
