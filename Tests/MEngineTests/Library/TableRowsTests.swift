// Tests for TableRowsLibrary.
import Testing
import ColumnStore
@testable import MEngine

@Suite struct TableRowsTests {
    private func eval(_ source: String) async throws -> MValue {
        try await MEvaluator(environment: MEnvironment()).evaluate(source: source, upTo: nil, rowLimit: nil)
    }

    @Test func selectRowsFiltersCorrectly() async throws {
        let m = """
        let
            Source = #table({"Name", "Qty"}, {{"A", 1}, {"B", 2}, {"C", 3}}),
            Filtered = Table.SelectRows(Source, each [Qty] >= 2)
        in
            Filtered
        """
        guard case .table(let t) = try await eval(m) else { Issue.record("phải là bảng"); return }
        #expect(t.rowCount == 2)
        #expect(t.value(row: 0, column: 0) == .string("B"))
        #expect(t.value(row: 1, column: 0) == .string("C"))
    }

    @Test func selectRowsNonLogicalThrows() async throws {
        let m = """
        let
            Source = #table({"Qty"}, {{1}, {2}}),
            Filtered = Table.SelectRows(Source, each [Qty])
        in
            Filtered
        """
        await #expect(throws: MError.self) {
            try await eval(m)
        }
    }

    @Test func sortAscendingAndDescending() async throws {
        let m = """
        let
            Source = #table({"ID", "Val"}, {{1, 30}, {2, 10}, {3, 20}}),
            SortedAsc = Table.Sort(Source, {{"Val", Order.Ascending}}),
            SortedDesc = Table.Sort(Source, {{"Val", Order.Descending}})
        in
            [Asc = SortedAsc, Desc = SortedDesc]
        """
        guard case .record(let fields) = try await eval(m),
              case .table(let asc) = fields.first(where: { $0.name == "Asc" })?.value,
              case .table(let desc) = fields.first(where: { $0.name == "Desc" })?.value else {
            Issue.record("phải là bản ghi chứa bảng"); return
        }
        #expect(asc.value(row: 0, column: 1) == .double(10))
        #expect(asc.value(row: 1, column: 1) == .double(20))
        #expect(asc.value(row: 2, column: 1) == .double(30))

        #expect(desc.value(row: 0, column: 1) == .double(30))
        #expect(desc.value(row: 1, column: 1) == .double(20))
        #expect(desc.value(row: 2, column: 1) == .double(10))
    }

    @Test func firstNAndSkip() async throws {
        let m = """
        let
            Source = #table({"N"}, {{1}, {2}, {3}, {4}, {5}}),
            First2 = Table.FirstN(Source, 2),
            Skip2 = Table.Skip(Source, 2),
            FirstOver = Table.FirstN(Source, 10),
            SkipAll = Table.Skip(Source, 10)
        in
            [F2 = First2, S2 = Skip2, FO = FirstOver, SA = SkipAll]
        """
        guard case .record(let f) = try await eval(m),
              case .table(let f2) = f.first(where: { $0.name == "F2" })?.value,
              case .table(let s2) = f.first(where: { $0.name == "S2" })?.value,
              case .table(let fo) = f.first(where: { $0.name == "FO" })?.value,
              case .table(let sa) = f.first(where: { $0.name == "SA" })?.value else {
            Issue.record("phải là record"); return
        }
        #expect(f2.rowCount == 2)
        #expect(f2.value(row: 0, column: 0) == .double(1))
        #expect(f2.value(row: 1, column: 0) == .double(2))

        #expect(s2.rowCount == 3)
        #expect(s2.value(row: 0, column: 0) == .double(3))

        #expect(fo.rowCount == 5)
        #expect(sa.rowCount == 0)
    }

    @Test func lastNRemoveFirstNRemoveLastNRange() async throws {
        let m = """
        let
            Source = #table({"N"}, {{1}, {2}, {3}, {4}, {5}}),
            Last2 = Table.LastN(Source, 2),
            RemFirst1 = Table.RemoveFirstN(Source, 1),
            RemLast2 = Table.RemoveLastN(Source, 2),
            SubRange = Table.Range(Source, 1, 3)
        in
            [L2 = Last2, RF = RemFirst1, RL = RemLast2, Rng = SubRange]
        """
        guard case .record(let f) = try await eval(m),
              case .table(let l2) = f.first(where: { $0.name == "L2" })?.value,
              case .table(let rf) = f.first(where: { $0.name == "RF" })?.value,
              case .table(let rl) = f.first(where: { $0.name == "RL" })?.value,
              case .table(let rng) = f.first(where: { $0.name == "Rng" })?.value else {
            Issue.record("phải là record"); return
        }
        #expect(l2.rowCount == 2)
        #expect(l2.value(row: 0, column: 0) == .double(4))
        #expect(l2.value(row: 1, column: 0) == .double(5))

        #expect(rf.rowCount == 4)
        #expect(rf.value(row: 0, column: 0) == .double(2))

        #expect(rl.rowCount == 3)
        #expect(rl.value(row: 2, column: 0) == .double(3))

        #expect(rng.rowCount == 3)
        #expect(rng.value(row: 0, column: 0) == .double(2))
        #expect(rng.value(row: 2, column: 0) == .double(4))
    }

    @Test func distinctKeepsFirstAppearanceAndOrder() async throws {
        let m = """
        let
            Source = #table({"K", "V"}, {{"A", 1}, {"B", 2}, {"A", 3}, {"C", 4}, {"B", 5}}),
            Unique = Table.Distinct(Source, {"K"})
        in
            Unique
        """
        guard case .table(let t) = try await eval(m) else { Issue.record("phải là bảng"); return }
        #expect(t.rowCount == 3)
        #expect(t.value(row: 0, column: 0) == .string("A"))
        #expect(t.value(row: 0, column: 1) == .double(1)) // Giữ dòng đầu (V=1, không phải 3)
        #expect(t.value(row: 1, column: 0) == .string("B"))
        #expect(t.value(row: 1, column: 1) == .double(2))
        #expect(t.value(row: 2, column: 0) == .string("C"))
        #expect(t.value(row: 2, column: 1) == .double(4))
    }

    @Test func replaceValue() async throws {
        let m = """
        let
            Source = #table({"Region"}, {{"North East"}, {"North West"}, {"South"}}),
            Replaced = Table.ReplaceValue(Source, "North", "Bac", Replacer.ReplaceText, {"Region"})
        in
            Replaced
        """
        guard case .table(let t) = try await eval(m) else { Issue.record("phải là bảng"); return }
        #expect(t.rowCount == 3)
        #expect(t.value(row: 0, column: 0) == .string("Bac East"))
        #expect(t.value(row: 1, column: 0) == .string("Bac West"))
        #expect(t.value(row: 2, column: 0) == .string("South"))
    }

    @Test func fillDownAndFillUp() async throws {
        let m = """
        let
            Source = #table({"V"}, {{"A"}, {null}, {null}, {"B"}, {null}}),
            Down = Table.FillDown(Source, {"V"}),
            Up = Table.FillUp(Source, {"V"})
        in
            [D = Down, U = Up]
        """
        guard case .record(let f) = try await eval(m),
              case .table(let down) = f.first(where: { $0.name == "D" })?.value,
              case .table(let up) = f.first(where: { $0.name == "U" })?.value else {
            Issue.record("phải là record"); return
        }
        #expect(down.value(row: 0, column: 0) == .string("A"))
        #expect(down.value(row: 1, column: 0) == .string("A"))
        #expect(down.value(row: 2, column: 0) == .string("A"))
        #expect(down.value(row: 3, column: 0) == .string("B"))
        #expect(down.value(row: 4, column: 0) == .string("B"))

        #expect(up.value(row: 0, column: 0) == .string("A"))
        #expect(up.value(row: 1, column: 0) == .string("B"))
        #expect(up.value(row: 2, column: 0) == .string("B"))
        #expect(up.value(row: 3, column: 0) == .string("B"))
        #expect(up.value(row: 4, column: 0) == .blank)
    }

    @Test func reverseRows() async throws {
        let m = """
        let
            Source = #table({"N"}, {{1}, {2}, {3}}),
            Reversed = Table.ReverseRows(Source)
        in
            Reversed
        """
        guard case .table(let t) = try await eval(m) else { Issue.record("phải là bảng"); return }
        #expect(t.rowCount == 3)
        #expect(t.value(row: 0, column: 0) == .double(3))
        #expect(t.value(row: 1, column: 0) == .double(2))
        #expect(t.value(row: 2, column: 0) == .double(1))
    }

    @Test func replaceErrorsAndFilterErrors() async throws {
        // Dựng bảng có ô lỗi
        let col = TableColumn(name: "Qty", data: ColumnBuilder.integers([1, nil, 3]))
        let table = try TableData(columns: [col], errorMask: [0: [1: "Lỗi"]])
        let env = MEnvironment(bindings: ["T": .table(table)])

        let res = try await MEvaluator(environment: env).evaluate(
            source: "Table.ReplaceErrorValues(T, {{\"Qty\", 0}})"
        )
        guard case .table(let replaced) = res else { Issue.record("phải là table"); return }
        #expect(replaced.errorMask.isEmpty)
        #expect(replaced.value(row: 0, column: 0) == .integer(1))
        #expect(replaced.value(row: 1, column: 0) == .integer(0))
        #expect(replaced.value(row: 2, column: 0) == .integer(3))

        let resRem = try await MEvaluator(environment: env).evaluate(
            source: "Table.RemoveRowsWithErrors(T)"
        )
        guard case .table(let withoutErrors) = resRem else { Issue.record("phải là table"); return }
        #expect(withoutErrors.rowCount == 2)
        #expect(withoutErrors.value(row: 0, column: 0) == .integer(1))
        #expect(withoutErrors.value(row: 1, column: 0) == .integer(3))

        let resSel = try await MEvaluator(environment: env).evaluate(
            source: "Table.SelectRowsWithErrors(T)"
        )
        guard case .table(let onlyErrors) = resSel else { Issue.record("phải là table"); return }
        #expect(onlyErrors.rowCount == 1)
        #expect(onlyErrors.error(row: 0, column: 0) == "Lỗi")
    }
}
