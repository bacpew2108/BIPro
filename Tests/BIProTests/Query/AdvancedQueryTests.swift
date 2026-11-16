// Phase F, T069/T073: biến đổi nâng cao trong Query Editor: Merge → mở rộng, Append, Group By nhiều phép, truy vấn tham chiếu truy vấn
// khác (đổi truy vấn nguồn thì truy vấn dùng nó tính lại), vòng tham chiếu báo lỗi. Dữ liệu dựng bằng `#table`, số mong đợi viết tay.
// Ngữ nghĩa join/group chưa đối chiếu golden Desktop (T067 chưa chạy).
import ColumnStore
import Foundation
import MEngine
import Testing
@testable import BIPro

@Suite("Phase F: biến đổi nâng cao", .serialized)
@MainActor
struct AdvancedQueryTests {
    private func query(_ name: String, _ expression: String) -> QueryModel {
        QueryModel(name: name, steps: [QueryStep(name: "Source", expression: expression, kind: StepKind.custom)], enableLoad: true)
    }

    private func makeEditor() -> QueryEditorState {
        let editor = QueryEditorState()
        editor.addQuery(query("Customers", #"#table({"ID","Name"}, {{1,"An"},{2,"Binh"},{3,"Chi"}})"#), base: nil)
        editor.addQuery(query("Orders", #"#table({"Cust","Amt","Region"}, {{1,5.0,"N"},{1,7.0,"S"},{3,2.0,"N"},{9,4.0,"N"}})"#), base: nil)
        return editor
    }

    private func select(_ editor: QueryEditorState, _ name: String) {
        editor.selectQuery(editor.queries.first { $0.name == name }!.id)
    }

    private func settle(_ editor: QueryEditorState) async {
        await editor.refresh()
    }

    @Test func mergeThenExpand() async throws {
        let editor = makeEditor()
        select(editor, "Customers")
        #expect(editor.perform(.merge(otherQuery: "Orders", leftKeys: ["ID"], rightKeys: ["Cust"], kind: .leftOuter, newColumn: "Orders")) == .applied)
        #expect(editor.selectedQuery?.steps.last?.name == "Merged Queries")
        await settle(editor)
        #expect(editor.errorMessage == nil)
        #expect(editor.preview?.columns.map(\.name) == ["ID", "Name", "Orders"])
        #expect(editor.preview?.rowCount == 3)

        #expect(editor.perform(.expandColumn(column: "Orders", names: ["Amt", "Region"], prefixed: true)) == .applied)
        #expect(editor.selectedQuery?.steps.last?.name == "Expanded Orders")
        await settle(editor)
        let table = try #require(editor.preview)
        #expect(table.columns.map(\.name) == ["ID", "Name", "Orders.Amt", "Orders.Region"])
        #expect(table.rowCount == 4) // An×2, Binh (trống), Chi
        #expect(table.value(row: 1, column: 2) == .double(7))
        #expect(table.value(row: 2, column: 1) == .string("Binh"))
        #expect(table.value(row: 2, column: 2) == .blank)
    }

    @Test func mergeInnerKeepsOnlyMatches() async throws {
        let editor = makeEditor()
        select(editor, "Customers")
        editor.perform(.merge(otherQuery: "Orders", leftKeys: ["ID"], rightKeys: ["Cust"], kind: .inner, newColumn: "O"))
        editor.perform(.expandColumn(column: "O", names: ["Amt"], prefixed: false))
        await settle(editor)
        #expect(editor.preview?.rowCount == 3)
        #expect(editor.preview?.columns.map(\.name) == ["ID", "Name", "Amt"])
    }

    @Test func appendTwoQueries() async throws {
        let editor = makeEditor()
        editor.addQuery(query("More", #"#table({"ID","Name"}, {{7,"Zed"}})"#), base: nil)
        select(editor, "Customers")
        #expect(editor.perform(.append(queries: ["More"])) == .applied)
        await settle(editor)
        #expect(editor.errorMessage == nil)
        #expect(editor.preview?.rowCount == 4)
        #expect(editor.preview?.value(row: 3, column: 1) == .string("Zed"))
    }

    /// Desktop: Append chọn chính truy vấn hiện tại → `Table.Combine({prev, prev})` (nối với bước liền trước, không tạo vòng).
    @Test func appendCurrentQueryUsesPreviousStep() async throws {
        let editor = makeEditor()
        select(editor, "Customers")
        #expect(editor.perform(.append(queries: ["Customers"])) == .applied)
        #expect(editor.selectedQuery?.steps.last?.expression == "Table.Combine({Source, Source})")
        await settle(editor)
        #expect(editor.errorMessage == nil)
        #expect(editor.preview?.rowCount == 6)
        #expect(editor.dependencyGraph.cycle == nil)
    }

    @Test func groupByWithSeveralAggregates() async throws {
        let editor = makeEditor()
        select(editor, "Orders")
        let aggregates = [GroupAggregate(name: "Total", operation: .sum, column: "Amt"),
                          GroupAggregate(name: "Rows", operation: .countRows),
                          GroupAggregate(name: "Max", operation: .max, column: "Amt")]
        #expect(editor.perform(.groupBy(keys: ["Region"], aggregates: aggregates)) == .applied)
        await settle(editor)
        #expect(editor.errorMessage == nil)
        let table = try #require(editor.preview)
        #expect(table.columns.map(\.name) == ["Region", "Total", "Rows", "Max"])
        #expect(table.rowCount == 2)
        #expect(table.value(row: 0, column: 0) == .string("N"))
        #expect(table.value(row: 0, column: 1) == .double(11))
        #expect(table.value(row: 0, column: 2) == .integer(3))
        #expect(table.value(row: 0, column: 3) == .double(5))
    }

    @Test func groupByCountUnpivotAndPivotCommandsRun() async throws {
        let editor = makeEditor()
        select(editor, "Orders")
        #expect(editor.perform(.groupByCount(keys: ["Region"], newColumn: "Count")) == .applied)
        await settle(editor)
        #expect(editor.errorMessage == nil)
        #expect(editor.preview?.rowCount == 2)
        #expect(editor.preview?.value(row: 0, column: 1) == .integer(3))

        select(editor, "Customers")
        #expect(editor.perform(.unpivotOtherColumns(keep: ["ID"])) == .applied)
        await settle(editor)
        #expect(editor.errorMessage == nil)
        #expect(editor.preview?.columns.map(\.name) == ["ID", "Attribute", "Value"])
        #expect(editor.preview?.rowCount == 3)

        #expect(editor.perform(.pivot(attributeColumn: "Attribute", valueColumn: "Value")) == .applied)
        await settle(editor)
        #expect(editor.errorMessage == nil)
        #expect(editor.preview?.columns.map(\.name) == ["ID", "Name"])
    }

    @Test func formulaSyntaxCheck() {
        let editor = QueryEditorState()
        #expect(editor.formulaError("[Qty] * 2") == nil)
        #expect(editor.formulaError("  ") != nil)
        #expect(editor.formulaError("[Qty] *")?.contains("Dòng 1") == true)
    }

    @Test func customColumnFormula() async throws {
        let editor = makeEditor()
        select(editor, "Orders")
        #expect(editor.perform(.addCustomColumn(name: "Double", formula: "[Amt] * 2")) == .applied)
        await settle(editor)
        #expect(editor.preview?.value(row: 1, column: 3) == .double(14))
    }

    @Test func changingReferencedQueryRecomputesDependents() async throws {
        let editor = makeEditor()
        select(editor, "Customers")
        editor.perform(.merge(otherQuery: "Orders", leftKeys: ["ID"], rightKeys: ["Cust"], kind: .inner, newColumn: "O"))
        editor.perform(.expandColumn(column: "O", names: ["Amt"], prefixed: false))
        await settle(editor)
        #expect(editor.preview?.rowCount == 3)

        select(editor, "Orders")
        #expect(editor.perform(.keepTopRows(1)) == .applied)
        select(editor, "Customers")
        await settle(editor)
        #expect(editor.preview?.rowCount == 1)
    }

    @Test func referenceCycleIsReported() async throws {
        let editor = makeEditor()
        select(editor, "Customers")
        #expect(editor.applyAdvancedSource("let\n    Source = Orders\nin\n    Source") == nil)
        select(editor, "Orders")
        #expect(editor.applyAdvancedSource("let\n    Source = Customers\nin\n    Source") == nil)
        await settle(editor)
        let message = try #require(editor.errorMessage)
        #expect(message.contains("vòng"))
        #expect(editor.preview == nil)
    }

    @Test func unsupportedFunctionNamesItself() async throws {
        let editor = makeEditor()
        select(editor, "Orders")
        #expect(editor.applyAdvancedSource("let\n    Source = Table.FuzzyJoin(1, 2)\nin\n    Source") == nil)
        await settle(editor)
        #expect(editor.errorMessage?.contains("Table.FuzzyJoin") == true)
    }

    @Test func nestedColumnsAndCandidatesForDialogs() async throws {
        let editor = makeEditor()
        select(editor, "Customers")
        #expect(editor.mergeCandidates.map(\.name) == ["Orders"])
        let ordersID = try #require(editor.queries.first { $0.name == "Orders" }?.id)
        let columns = try #require(await editor.resultColumns(ofQuery: ordersID))
        #expect(columns.map(\.name) == ["Cust", "Amt", "Region"])
        #expect(columns.map(\.type) == [.double, .double, .string])

        editor.perform(.merge(otherQuery: "Orders", leftKeys: ["ID"], rightKeys: ["Cust"], kind: .leftOuter, newColumn: "O"))
        await settle(editor)
        #expect(editor.nestedColumnNames == ["O"])
        #expect(editor.nestedColumns(of: "O")?.map(\.name) == ["Cust", "Amt", "Region"])
        #expect(editor.nestedColumns(of: "Name") == nil)

        // Orders giờ bị Customers dùng, nên khi chọn Orders thì Customers không còn là ứng viên (sẽ tạo vòng).
        select(editor, "Orders")
        #expect(editor.mergeCandidates.isEmpty)
    }

    @Test func dependencyGraphModelHasSourcesQueriesAndEdges() async throws {
        let editor = QueryEditorState()
        editor.addQuery(query("Raw", #"Excel.Workbook(File.Contents("C:\\d\\a.xlsx"), null, true)"#), base: nil)
        editor.addQuery(query("Clean", "Raw"), base: nil)
        let graph = editor.dependencyGraph
        #expect(graph.nodes.map(\.id) == ["source:C:\\\\d\\\\a.xlsx", "query:Raw", "query:Clean"])
        #expect(Set(graph.edges) == [DependencyEdge(from: "source:C:\\\\d\\\\a.xlsx", to: "query:Raw"), DependencyEdge(from: "query:Raw", to: "query:Clean")])
        #expect(graph.cycle == nil)
    }

    @Test func renamingAQueryUpdatesReferencesInOthers() async throws {
        let editor = makeEditor()
        select(editor, "Customers")
        editor.perform(.merge(otherQuery: "Orders", leftKeys: ["ID"], rightKeys: ["Cust"], kind: .inner, newColumn: "O"))
        let ordersID = try #require(editor.queries.first { $0.name == "Orders" }?.id)
        #expect(editor.renameQuery(ordersID, to: "Sales Lines") == nil)
        #expect(editor.queries.first { $0.name == "Customers" }?.steps.last?.expression.contains(#"#"Sales Lines""#) == true)
        select(editor, "Customers")
        await settle(editor)
        #expect(editor.errorMessage == nil)
        #expect(editor.preview?.rowCount == 2) // Inner NestedJoin: An và Chi
    }

    @Test func applyEvaluatesDependenciesInFullQuery() async throws {
        let editor = makeEditor()
        select(editor, "Customers")
        editor.perform(.merge(otherQuery: "Orders", leftKeys: ["ID"], rightKeys: ["Cust"], kind: .leftOuter, newColumn: "O"))
        editor.perform(.expandColumn(column: "O", names: ["Amt"], prefixed: false))
        let query = try #require(editor.selectedQuery)
        let table = try await editor.evaluateFull(query)
        #expect(table.rowCount == 4)
    }
}

@Suite struct QueryDependenciesTests {
    private func parse(_ s: String) throws -> MQuery { try MQuery.parse(s) }

    @Test func referencesAreFoundByIdentifierNotFieldName() throws {
        let q = try parse("let\n    Source = Table.NestedJoin(A, {\"x\"}, B, {\"y\"}, \"B\", JoinKind.Inner),\n    Next = Table.SelectRows(Source, each [C] = 1)\nin\n    Next")
        #expect(QueryDependencies.references(of: q, among: ["A", "B", "C", "Next"]) == ["A", "B"])
    }

    @Test func stepNamesShadowQueryNames() throws {
        let q = try parse("let\n    Orders = #table({\"a\"},{{1}}),\n    R = Table.RowCount(Orders)\nin\n    R")
        #expect(QueryDependencies.references(of: q, among: ["Orders"]).isEmpty)
    }

    @Test func cycleAndOrder() throws {
        let graph = ["A": ["B"], "B": ["C"], "C": []]
        #expect(QueryDependencies.cycle(in: graph) == nil)
        #expect(try QueryDependencies.evaluationOrder(for: "A", in: graph) == ["C", "B"])
        #expect(QueryDependencies.cycle(in: ["A": ["B"], "B": ["A"]]) == ["A", "B", "A"])
        #expect(throws: MError.self) { try QueryDependencies.evaluationOrder(for: "A", in: ["A": ["B"], "B": ["A"]]) }
    }

    @Test func externalSources() throws {
        let q = try parse(#"let\#n    Source = Excel.Workbook(File.Contents("C:\x\a.xlsx"), null, true)\#nin\#n    Source"#)
        #expect(QueryDependencies.externalSources(of: q) == [#"C:\x\a.xlsx"#])
    }
}
