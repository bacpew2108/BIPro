import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Wave 3A (v1.1b) — Edit Interactions, Matrix Row Expansion, Date Advanced Filter & Bookmarks")
@MainActor
struct V11BInteractionsAndMatrixTests {
    @Test("LayoutEditor.setVisualInteraction lưu đúng và hỗ trợ Undo/Redo")
    func layoutEditorVisualInteractionsUndoRedo() throws {
        let v1 = ReportVisual(id: "v1", type: "donutChart", x: 10, y: 10, width: 200, height: 200)
        let v2 = ReportVisual(id: "v2", type: "lineChart", x: 250, y: 10, width: 200, height: 200)
        let page = ReportPage(id: "p1", displayName: "P1", width: 1280, height: 720, visuals: [v1, v2])
        let editor = LayoutEditor(report: ReportDefinition(pages: [page]), sourceJSON: { _, _ in nil })

        #expect(editor.visualInteractions(on: "p1").isEmpty)
        editor.setVisualInteraction(source: "v1", target: "v2", type: .noFilter, on: "p1")
        #expect(editor.visualInteractions(on: "p1") == [PageVisualInteraction(source: "v1", target: "v2", type: .noFilter)])
        #expect(editor.page("p1")?.visualInteractions.first?.type == .noFilter)

        editor.setVisualInteraction(source: "v1", target: "v2", type: .dataFilter, on: "p1")
        #expect(editor.visualInteractions(on: "p1") == [PageVisualInteraction(source: "v1", target: "v2", type: .dataFilter)])

        editor.undo()
        #expect(editor.visualInteractions(on: "p1") == [PageVisualInteraction(source: "v1", target: "v2", type: .noFilter)])
        editor.undo()
        #expect(editor.visualInteractions(on: "p1").isEmpty)
        editor.redo()
        #expect(editor.visualInteractions(on: "p1").first?.type == .noFilter)
    }

    @Test("FilterRule & FilterExport hỗ trợ Advanced filter cột ngày (DAX DATE & PBIR datetime)")
    func dateAdvancedFilterRuleAndExport() throws {
        let rule = FilterRule.advanced(
            first: FilterCondition(kind: .greaterThan, operand: "2020-01-15"),
            second: FilterCondition(kind: .lessOrEqual, operand: "2024-06-30"),
            useOr: false, numeric: false, isDate: true
        )
        let col = QueryColumn(table: "Dim_Date", column: "full_date")
        let dax = try #require(rule.predicate(column: col))
        #expect(dax.contains("DATE(2020, 1, 15)"))
        #expect(dax.contains("DATE(2024, 6, 30)"))
        #expect(dax.hasPrefix("AND("))

        let uf = UserFilter(column: col, rule: rule)
        let key = UserFilterKey(level: .page, scope: "p1", filterID: "added-date")
        let exported = FilterExport.card(for: uf, key: key)
        guard case .writable(let spec) = exported else {
            Issue.record("Expected writable date filter card")
            return
        }
        let rawFilter = try #require(spec.filter)
        #expect(rawFilter.contains("datetime'2020-01-15T00:00:00'"))
        #expect(rawFilter.contains("datetime'2024-06-30T00:00:00'"))

        // Round-trip parseAdvanced từ JSON vừa xuất
        let parsedJSON = try JSONValue.parse(Data(rawFilter.utf8))
        let reparsed = try #require(FilterRule.parseAdvanced(parsedJSON["Where"]?[0]?["Condition"]))
        #expect(reparsed == rule)
    }

    @Test("Matrix phân cấp hàng đọc expansionStates (roles: Rows) và chạy DAX trả dòng cha + dòng con")
    func matrixRowHierarchyExpansionEndToEnd() async throws {
        // Dựng báo cáo trắng có bảng phân cấp Region -> Age -> Count để kiểm thử đầy đủ pipeline
        let savedLast = UserDefaults.standard.string(forKey: "lastWorkspace")
        defer {
            if let savedLast { UserDefaults.standard.set(savedLast, forKey: "lastWorkspace") }
            else { UserDefaults.standard.removeObject(forKey: "lastWorkspace") }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("v11b-mat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let doc = try UntitledDocuments.create(root: root)
        let ws = try Workspace(data: try Data(contentsOf: doc))
        let state = DocumentState(workspace: ws, fileName: "test.pbix", fileURL: doc)
        state.mode = .table
        var enterTable = EnterDataTable(name: "Sales")
        _ = try enterTable.paste("Region\tSegment\tAmount\nNorth\tRetail\t100\nNorth\tCorp\t250\nSouth\tRetail\t80\nSouth\tCorp\t120")
        let loadErr = await state.loadEnterData(enterTable)
        #expect(loadErr == nil)
        state.newMeasureInTableView(table: "Sales")
        state.measureDraft?.text = "TotalAmt = SUM(Sales[Amount])"
        await state.applyMeasureDraft()

        // Tạo Matrix JSON với 2 cấp Rows + expansionStates mở "North" (khớp VM-V11B)
        let visualJSON = Data(#"""
        {
          "$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.14.0/schema.json",
          "name":"mat1",
          "position":{"x":10,"y":10,"z":1,"height":300,"width":400},
          "visual":{
            "visualType":"pivotTable",
            "query":{
              "queryState":{
                "Rows":{"projections":[
                  {"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Region"}},"queryRef":"Sales.Region","nativeQueryRef":"Region","active":true},
                  {"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Segment"}},"queryRef":"Sales.Segment","nativeQueryRef":"Segment","active":true}
                ]},
                "Values":{"projections":[
                  {"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"TotalAmt"}},"queryRef":"Sales.TotalAmt","nativeQueryRef":"TotalAmt"}
                ]}
              }
            },
            "expansionStates":[{
              "roles":["Rows"],
              "levels":[
                {"queryRefs":["Sales.Region"],"isCollapsed":true,"identityKeys":[{"Column":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Region"}}],"isPinned":true},
                {"queryRefs":["Sales.Segment"],"isCollapsed":true,"isPinned":true}
              ],
              "root":{"children":[{"identityValues":[{"Literal":{"Value":"'North'"}}],"isToggled":true}]}
            }]
          }
        }
        """#.utf8)
        let raw = try JSONValue.parse(visualJSON)
        let visual = ReportVisual(id: "mat1", type: "pivotTable", x: 10, y: 10, width: 400, height: 300,
                                  fields: [], raw: raw)
        let page = ReportPage(id: "p1", displayName: "P1", width: 1280, height: 720, visuals: [visual])
        let loaded = try await state.interaction.load(page: page, visual: visual, state: FilterState())
        guard case .matrix(let mat) = loaded.view else {
            Issue.record("Expected MatrixData, got \(loaded.view)")
            return
        }
        // North (level 0, expanded, 350) + North/Corp (level 1, 250) + North/Retail (level 1, 100) + South (level 0, collapsed, 200) + Total (550)
        #expect(mat.rowLevels.count == 2)
        let northRow = mat.rows.first { $0.level == 0 && $0.path == [Value.string("North")] }
        let southRow = mat.rows.first { $0.level == 0 && $0.path == [Value.string("South")] }
        let childRows = mat.rows.filter { $0.level == 1 }
        #expect(northRow?.isExpanded == true)
        #expect(northRow?.hasChildren == true)
        #expect(southRow?.isExpanded == false)
        #expect(southRow?.hasChildren == true)
        #expect(childRows.count == 2)
        #expect(childRows.allSatisfy { $0.path.first == Value.string("North") })

        // Kiểm Bookmark chụp & khôi phục matrixRowExpansion
        state.interaction.matrixRowExpansion["mat1"] = [[Value.string("South")]]
        let bmID = state.interaction.addBookmark(currentPageID: "p1")
        state.interaction.matrixRowExpansion["mat1"] = []
        _ = state.interaction.applyAnyBookmark(id: bmID)
        #expect(state.interaction.matrixRowExpansion["mat1"] == [[Value.string("South")]])
    }
}
