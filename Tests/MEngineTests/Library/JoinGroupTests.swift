// Tests cho JoinGroupLibrary (Phase F, T068). Ngữ nghĩa chưa đối chiếu golden Desktop (T067): các test này khoá hành vi theo tài liệu M.
import Testing
import ColumnStore
@testable import MEngine

@Suite struct JoinGroupTests {
    private func eval(_ source: String) async throws -> MValue {
        try await MEvaluator(environment: MEnvironment()).evaluate(source: source, upTo: nil, rowLimit: nil)
    }

    private func table(_ source: String) async throws -> TableData {
        guard case .table(let t) = try await eval(source) else { throw MError.expression("kết quả không phải bảng") }
        return t
    }

    private func rows(_ t: TableData) -> [[String]] {
        (0..<t.rowCount).map { r in (0..<t.columns.count).map { c in "\(t.value(row: r, column: c))" } }
    }

    private let customers = #"#table({"ID","Name"}, {{1,"An"},{2,"Binh"},{3,"Chi"},{null,"Zed"}})"#
    private let orders = #"#table({"OID","Cust","Amt"}, {{10,1,5.0},{11,1,7.0},{12,3,2.0},{13,9,4.0},{14,null,1.0}})"#

    private func join(_ kind: String) async throws -> TableData {
        try await table("Table.Join(\(customers), \"ID\", \(orders), \"Cust\", \(kind))")
    }

    @Test func innerJoinMatchesNullKeysAndKeepsLeftOrder() async throws {
        let t = try await join("JoinKind.Inner")
        #expect(t.columns.map(\.name) == ["ID", "Name", "OID", "Cust", "Amt"])
        #expect(t.rowCount == 4) // An×2, Chi×1, Zed×(null=null)
        #expect(t.value(row: 0, column: 2) == .double(10))
        #expect(t.value(row: 1, column: 2) == .double(11))
        #expect(t.value(row: 2, column: 1) == .string("Chi"))
        #expect(t.value(row: 3, column: 1) == .string("Zed"))
        #expect(t.value(row: 3, column: 2) == .double(14))
    }

    @Test func leftOuterKeepsUnmatchedLeftRows() async throws {
        let t = try await join("JoinKind.LeftOuter")
        #expect(t.rowCount == 5) // thêm Binh không khớp, xếp cuối như Desktop
        #expect(t.value(row: 4, column: 1) == .string("Binh"))
        #expect(t.value(row: 4, column: 2) == .blank)
    }

    @Test func rightOuterAddsUnmatchedRightRows() async throws {
        let t = try await join("JoinKind.RightOuter")
        #expect(t.rowCount == 5) // 4 khớp + dòng OID 13
        #expect(t.value(row: 4, column: 2) == .double(13))
        #expect(t.value(row: 4, column: 1) == .blank)
    }

    @Test func fullOuterHasBothSides() async throws {
        let t = try await join("JoinKind.FullOuter")
        #expect(t.rowCount == 6) // 4 khớp + Binh + OID 13
    }

    @Test func antiJoins() async throws {
        let left = try await join("JoinKind.LeftAnti")
        #expect(rows(left).map { $0[1] } == ["string(\"Binh\")"])
        #expect(left.columns.count == 5)
        let right = try await join("JoinKind.RightAnti")
        #expect(right.rowCount == 1)
        #expect(right.value(row: 0, column: 2) == .double(13))
    }

    @Test func joinKeysAreCaseSensitiveAndTypeStrict() async throws {
        let t = try await table(#"""
        Table.Join(#table({"K"}, {{"a"},{"A"}}), "K", #table({"K2","V"}, {{"a",1},{"1",2}}), "K2", JoinKind.Inner)
        """#)
        #expect(t.rowCount == 1)
        let mixed = try await table(#"""
        Table.Join(#table({"K"}, {{1}}), "K", #table({"K2"}, {{"1"}}), "K2", JoinKind.Inner)
        """#)
        #expect(mixed.rowCount == 0)
    }

    @Test func joinOnIntegerAndDoubleKeysCompareByValue() async throws {
        let t = try await table(#"""
        Table.Join(#table({"K"}, {{1}}), "K", #table({"K2"}, {{1.0}}), "K2")
        """#)
        #expect(t.rowCount == 1)
    }

    @Test func compositeKeys() async throws {
        let t = try await table(#"""
        Table.Join(#table({"A","B"}, {{1,"x"},{1,"y"}}), {"A","B"}, #table({"C","D","V"}, {{1,"y",9}}), {"C","D"})
        """#)
        #expect(t.rowCount == 1)
        #expect(t.value(row: 0, column: 1) == .string("y"))
    }

    @Test func joinRejectsDuplicateColumnNamesAndMissingKeys() async throws {
        await #expect(throws: MError.self) { try await eval(#"Table.Join(#table({"K"},{{1}}), "K", #table({"K"},{{1}}), "K")"#) }
        await #expect(throws: MError.self) { try await eval(#"Table.Join(#table({"K"},{{1}}), "Nope", #table({"J"},{{1}}), "J")"#) }
    }

    @Test func nestedJoinThenExpand() async throws {
        let t = try await table("""
        let
            Nested = Table.NestedJoin(\(customers), "ID", \(orders), "Cust", "Orders", JoinKind.LeftOuter),
            Expanded = Table.ExpandTableColumn(Nested, "Orders", {"OID", "Amt"}, {"Orders.OID", "Orders.Amt"})
        in Expanded
        """)
        #expect(t.columns.map(\.name) == ["ID", "Name", "Orders.OID", "Orders.Amt"])
        #expect(t.rowCount == 5)
        #expect(t.value(row: 0, column: 2) == .double(10))
        #expect(t.value(row: 2, column: 1) == .string("Binh"))
        #expect(t.value(row: 2, column: 2) == .blank)
    }

    @Test func nestedJoinDefaultsToLeftOuterAndKeepsOneRowPerLeftRow() async throws {
        let t = try await table("Table.NestedJoin(\(customers), \"ID\", \(orders), \"Cust\", \"Orders\")")
        #expect(t.rowCount == 4)
        #expect(t.nested[2]?.map(\.rowCount) == [2, 0, 1, 1])
    }

    @Test func expandNeedsNestedColumn() async throws {
        await #expect(throws: MError.self) {
            try await eval(#"Table.ExpandTableColumn(#table({"A"},{{1}}), "A", {"x"})"#)
        }
    }

    @Test func combineUnionsColumnsInFirstSeenOrder() async throws {
        let t = try await table(#"""
        Table.Combine({#table({"A","B"}, {{1,"x"}}), #table({"B","C"}, {{"y",true}}), #table({"A"}, {{3}})})
        """#)
        #expect(t.columns.map(\.name) == ["A", "B", "C"])
        #expect(t.rowCount == 3)
        #expect(t.value(row: 1, column: 0) == .blank)
        #expect(t.value(row: 1, column: 2) == .boolean(true))
        #expect(t.value(row: 2, column: 1) == .blank)
        #expect(t.value(row: 2, column: 0) == .double(3))
    }

    @Test func combineWithColumnsListAndMixedTypes() async throws {
        let only = try await table(#"""
        Table.Combine({#table({"A","B"}, {{1,"x"}}), #table({"A","B"}, {{2,"y"}})}, {"B"})
        """#)
        #expect(only.columns.map(\.name) == ["B"])
        await #expect(throws: MError.self) {
            try await eval(#"Table.Combine({#table({"A"},{{1}}), #table({"A"},{{"x"}})})"#)
        }
    }

    private let sales = #"#table({"Region","Prod","Qty"}, {{"N","a",1},{"S","a",2},{"N","b",3},{"N","a",4},{"S","b",null}})"#

    @Test func groupGlobalByFirstAppearance() async throws {
        let t = try await table("""
        Table.Group(\(sales), {"Region"}, {{"Total", each List.Sum([Qty]), type nullable number}, {"Rows", each Table.RowCount(_), Int64.Type}})
        """)
        #expect(t.columns.map(\.name) == ["Region", "Total", "Rows"])
        #expect(rows(t) == [["string(\"N\")", "double(8.0)", "integer(3)"], ["string(\"S\")", "double(2.0)", "integer(2)"]])
    }

    @Test func groupLocalSplitsOnlyConsecutiveRuns() async throws {
        let t = try await table("""
        Table.Group(\(sales), {"Region"}, {{"Rows", each Table.RowCount(_), Int64.Type}}, GroupKind.Local)
        """)
        #expect(t.rowCount == 4) // N, S, N, S
    }

    @Test func groupByMultipleKeysAndNullKey() async throws {
        let t = try await table("""
        Table.Group(#table({"K","V"}, {{null,1},{null,2},{"x",3}}), {"K"}, {{"S", each List.Sum([V]), type number}})
        """)
        #expect(t.rowCount == 2)
        #expect(t.value(row: 0, column: 0) == .blank)
        #expect(t.value(row: 0, column: 1) == .double(3))
    }

    @Test func pivotWithAggregation() async throws {
        let t = try await table("""
        Table.Pivot(\(sales), {"a","b"}, "Prod", "Qty", List.Sum)
        """)
        #expect(t.columns.map(\.name) == ["Region", "a", "b"])
        #expect(t.rowCount == 2)
        #expect(t.value(row: 0, column: 1) == .double(5))
        #expect(t.value(row: 0, column: 2) == .double(3))
        #expect(t.value(row: 1, column: 1) == .double(2))
    }

    @Test func unpivotOtherColumnsDropsNulls() async throws {
        let t = try await table(#"""
        Table.UnpivotOtherColumns(#table({"Id","Q1","Q2"}, {{1,10,20},{2,null,5}}), {"Id"}, "Attribute", "Value")
        """#)
        #expect(t.columns.map(\.name) == ["Id", "Attribute", "Value"])
        #expect(rows(t).count == 3)
        #expect(t.value(row: 2, column: 1) == .string("Q2"))
        #expect(t.value(row: 2, column: 2) == .double(5))
    }

    @Test func unpivotSelectedColumns() async throws {
        let t = try await table(#"""
        Table.Unpivot(#table({"Id","A","B"}, {{1,1,2}}), {"A","B"}, "K", "V")
        """#)
        #expect(t.columns.map(\.name) == ["Id", "K", "V"])
        #expect(t.rowCount == 2)
    }
}
