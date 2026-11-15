// Tests for TableColumnsLibrary.
import Testing
import ColumnStore
@testable import MEngine

@Suite struct TableColumnsTests {
    private func eval(_ source: String) async throws -> MValue {
        try await MEvaluator(environment: MEnvironment()).evaluate(source: source, upTo: nil, rowLimit: nil)
    }

    @Test func promoteHeaders() async throws {
        let m = """
        let
            Source = #table({"C1", "C2"}, {{"Name", "Age"}, {"Alice", "30"}, {"Bob", "25"}}),
            Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars = true])
        in
            Promoted
        """
        guard case .table(let t) = try await eval(m) else { Issue.record("phải là bảng"); return }
        #expect(t.columns.map(\.name) == ["Name", "Age"])
        #expect(t.rowCount == 2)
        #expect(t.value(row: 0, column: 0) == .string("Alice"))
        #expect(t.value(row: 0, column: 1) == .string("30"))
    }

    @Test func transformColumnTypesWithConversionError() async throws {
        let m = """
        let
            Source = #table({"Val"}, {{"South"}, {"North"}, {"5"}, {null}}),
            Transformed = Table.TransformColumnTypes(Source, {{"Val", Int64.Type}})
        in
            Transformed
        """
        guard case .table(let t) = try await eval(m) else { Issue.record("phải là bảng"); return }
        #expect(t.columns[0].data.type == .integer)
        #expect(t.rowCount == 4)
        // Ô "South" và "North" bị lỗi vào errorMask
        #expect(t.error(row: 0, column: 0)?.contains("DataFormat.Error") == true)
        #expect(t.error(row: 0, column: 0)?.contains("We couldn't convert to Number.") == true)
        #expect(t.error(row: 1, column: 0)?.contains("DataFormat.Error") == true)
        // Ô "5" chuyển thành số nguyên 5, không lỗi
        #expect(t.error(row: 2, column: 0) == nil)
        #expect(t.value(row: 2, column: 0) == .integer(5))
        // Ô null giữ nguyên null
        #expect(t.error(row: 3, column: 0) == nil)
        #expect(t.value(row: 3, column: 0) == .blank)
    }

    @Test func renameAndRemoveColumns() async throws {
        let m = """
        let
            Source = #table({"A", "B", "C"}, {{1, 2, 3}}),
            Renamed = Table.RenameColumns(Source, {{"A", "A_New"}}),
            Removed = Table.RemoveColumns(Renamed, {"B"})
        in
            Removed
        """
        guard case .table(let t) = try await eval(m) else { Issue.record("phải là bảng"); return }
        #expect(t.columns.map(\.name) == ["A_New", "C"])
        #expect(t.rowCount == 1)
        #expect(t.value(row: 0, column: 0) == .double(1))
        #expect(t.value(row: 0, column: 1) == .double(3))
    }

    @Test func selectReorderDuplicateColumns() async throws {
        let m = """
        let
            Source = #table({"A", "B", "C"}, {{1, 2, 3}}),
            Selected = Table.SelectColumns(Source, {"C", "A"}),
            Reordered = Table.ReorderColumns(Source, {"B", "C", "A"}),
            Duplicated = Table.DuplicateColumn(Source, "A", "A_Copy")
        in
            [Sel = Selected, Reo = Reordered, Dup = Duplicated]
        """
        guard case .record(let f) = try await eval(m),
              case .table(let sel) = f.first(where: { $0.name == "Sel" })?.value,
              case .table(let reo) = f.first(where: { $0.name == "Reo" })?.value,
              case .table(let dup) = f.first(where: { $0.name == "Dup" })?.value else {
            Issue.record("phải là record"); return
        }
        #expect(sel.columns.map(\.name) == ["C", "A"])
        #expect(reo.columns.map(\.name) == ["B", "C", "A"])
        #expect(dup.columns.map(\.name) == ["A", "B", "C", "A_Copy"])
        #expect(dup.value(row: 0, column: 3) == .double(1))
    }

    @Test func addColumnAndAddIndexColumn() async throws {
        let m = """
        let
            Source = #table({"Qty"}, {{10}, {20}}),
            WithCustom = Table.AddColumn(Source, "DoubleQty", each [Qty] * 2),
            WithIndex = Table.AddIndexColumn(WithCustom, "Index", 0, 1, Int64.Type)
        in
            WithIndex
        """
        guard case .table(let t) = try await eval(m) else { Issue.record("phải là bảng"); return }
        #expect(t.columns.map(\.name) == ["Qty", "DoubleQty", "Index"])
        #expect(t.rowCount == 2)
        #expect(t.value(row: 0, column: 1) == .double(20))
        #expect(t.value(row: 1, column: 1) == .double(40))
        #expect(t.value(row: 0, column: 2) == .integer(0))
        #expect(t.value(row: 1, column: 2) == .integer(1))
    }

    @Test func splitColumn() async throws {
        let m = """
        let
            Source = #table({"ID", "Vung"}, {{1, "North East"}, {2, "Bac"}}),
            Split = Table.SplitColumn(Source, "Vung", Splitter.SplitTextByDelimiter(" ", QuoteStyle.Csv), {"Vung.1", "Vung.2"})
        in
            Split
        """
        guard case .table(let t) = try await eval(m) else { Issue.record("phải là bảng"); return }
        #expect(t.columns.map(\.name) == ["ID", "Vung.1", "Vung.2"])
        #expect(t.rowCount == 2)
        #expect(t.value(row: 0, column: 1) == .string("North"))
        #expect(t.value(row: 0, column: 2) == .string("East"))
        #expect(t.value(row: 1, column: 1) == .string("Bac"))
        #expect(t.value(row: 1, column: 2) == .blank) // thiếu phần 2 -> null
    }

    @Test func combineColumns() async throws {
        let m = """
        let
            Source = #table({"A", "B"}, {{"Hello", "World"}, {"Swift", "Language"}}),
            Combined = Table.CombineColumns(Source, {"A", "B"}, Combiner.CombineTextByDelimiter(" "), "Greeting")
        in
            Combined
        """
        guard case .table(let t) = try await eval(m) else { Issue.record("phải là bảng"); return }
        #expect(t.columns.map(\.name) == ["Greeting"])
        #expect(t.rowCount == 2)
        #expect(t.value(row: 0, column: 0) == .string("Hello World"))
        #expect(t.value(row: 1, column: 0) == .string("Swift Language"))
    }

    @Test func transformColumns() async throws {
        let m = """
        let
            Source = #table({"Product"}, {{"áo thun"}, {"quần jean"}}),
            Upper = Table.TransformColumns(Source, {{"Product", Text.Upper, type text}})
        in
            Upper
        """
        guard case .table(let t) = try await eval(m) else { Issue.record("phải là bảng"); return }
        #expect(t.rowCount == 2)
        #expect(t.value(row: 0, column: 0) == .string("ÁO THUN"))
        #expect(t.value(row: 1, column: 0) == .string("QUẦN JEAN"))
    }

    @Test func metadataFunctions() async throws {
        let m = """
        let
            Source = #table({"A", "B", "C"}, {{1, 2, 3}, {4, 5, 6}}),
            Names = Table.ColumnNames(Source),
            Rows = Table.RowCount(Source),
            Cols = Table.ColumnCount(Source)
        in
            [N = Names, R = Rows, C = Cols]
        """
        guard case .record(let f) = try await eval(m),
              case .list(let names) = f.first(where: { $0.name == "N" })?.value,
              case .number(let rows) = f.first(where: { $0.name == "R" })?.value,
              case .number(let cols) = f.first(where: { $0.name == "C" })?.value else {
            Issue.record("phải là record"); return
        }
        #expect(names == [.text("A"), .text("B"), .text("C")])
        #expect(rows == 2)
        #expect(cols == 3)
    }
}
