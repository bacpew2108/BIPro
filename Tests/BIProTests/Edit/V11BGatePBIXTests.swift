import AppKit
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("v1.1b (T024) — Power BI Desktop 2.159 VM Gate PBIX Generator")
struct V11BGatePBIXTests {
    private var nhom6: URL? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], fm.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        let home = fm.homeDirectoryForCurrentUser
        for rel in [
            "Downloads/Nhom6_Dashboard_chiase.pbix",
            "Downloads/Nhom6_Dashboard.pbix",
            "Downloads/bipro-golden/Nhom6_work.pbix",
        ] {
            let url = home.appendingPathComponent(rel)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    @MainActor
    @Test("Generate build/v11-out/bipro-v11b-gate.pbix with all Wave 3 features and verify round-trip")
    func generateV11BGatePBIX() async throws {
        guard ProcessInfo.processInfo.environment["BIPRO_V11B_GATE"] == "1" else { return }
        let savedLast = UserDefaults.standard.string(forKey: "lastWorkspace")
        defer {
            if let savedLast { UserDefaults.standard.set(savedLast, forKey: "lastWorkspace") }
            else { UserDefaults.standard.removeObject(forKey: "lastWorkspace") }
        }
        let source = try #require(nhom6, "Nhom6 PBIX not found in ~/Downloads")
        let stamp = try FileStamp.of(source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .report
        state.editMode = true

        // 1. Tạo trang mới "v1.1b Gate" và chuyển sang làm trang hoạt động
        let pageID = try #require(state.layout.addPage())
        #expect(state.layout.renamePage(pageID, to: "v1.1b Gate") == nil)
        state.layout.showPage(pageID)
        state.pageID = pageID

        // 2. Thêm measure Wave 3 DAX (IFERROR + WEEKNUM type 21 + TOTALYTD)
        let isoMeasure = NewMeasure(table: "Dim_Client", name: "V11B_ISO_Week",
                                    expression: "IFERROR(WEEKNUM(DATE(2024, 12, 31), 21), 0)",
                                    formatString: "0", dataType: ModelMetadata.DataType.int64.rawValue)
        let ytdMeasure = NewMeasure(table: "Fact_Transaction", name: "V11B_Inflow_YTD",
                                    expression: "TOTALYTD([Total_Credit_Inflow], Dim_Date[full_date])",
                                    formatString: "#,0", dataType: ModelMetadata.DataType.double.rawValue)
        #expect(state.modelEditor.apply([.addMeasure(isoMeasure), .addMeasure(ytdMeasure)]) == nil)

        let region = FieldRef(kind: .column, entity: "Dim_District", property: "region", family: .text)
        let stateCol = FieldRef(kind: .column, entity: "Dim_District", property: "state_name", family: .text)
        let sex = FieldRef(kind: .column, entity: "Dim_Client", property: "sex", family: .text)
        let clients = FieldRef(kind: .measure, entity: "Dim_Client", property: "Total_Clients")
        let isoRef = FieldRef(kind: .measure, entity: "Dim_Client", property: "V11B_ISO_Week")
        let ytdRef = FieldRef(kind: .measure, entity: "Fact_Transaction", property: "V11B_Inflow_YTD")

        func place(_ type: String, x: Int, y: Int, w: Int, h: Int) throws -> String {
            let id = try #require(state.layout.insertVisual(type: type, visibleRect: CGRect(x: x, y: y, width: w, height: h)))
            state.layout.apply(frames: [id: Frame(x: x, y: y, width: w, height: h)])
            return id
        }

        // 3. Visual 1: Clustered Column Chart + Analytics Constant Line + Average + Max Lines
        let vCol = try place("clusteredColumnChart", x: 20, y: 20, w: 580, h: 320)
        #expect(state.layout.addField(region, to: "Category", visual: vCol) == nil)
        #expect(state.layout.addField(clients, to: "Y", visual: vCol) == nil)
        let constLineJSON = #"[{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"displayName":{"expr":{"Literal":{"Value":"'Target 1K'"}}},"value":{"expr":{"Literal":{"Value":"1000D"}}},"lineColor":{"solid":{"color":{"expr":{"Literal":{"Value":"'#D64554'"}}}}},"style":{"expr":{"Literal":{"Value":"'dashed'"}}}},"selector":{"id":"1"}}]"#
        let refLineJSON = #"[{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"displayName":{"expr":{"Literal":{"Value":"'Average'"}}},"value":{"expr":{"Aggregation":{"Expression":{"SelectRef":{"ExpressionName":"Dim_Client.Total_Clients"}},"Function":1}}},"style":{"expr":{"Literal":{"Value":"'dashed'"}}}},"selector":{"metadata":"Dim_Client.Total_Clients","id":"1"}},{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"displayName":{"expr":{"Literal":{"Value":"'Max'"}}},"value":{"expr":{"Aggregation":{"Expression":{"SelectRef":{"ExpressionName":"Dim_Client.Total_Clients"}},"Function":4}}},"style":{"expr":{"Literal":{"Value":"'dotted'"}}}},"selector":{"metadata":"Dim_Client.Total_Clients","id":"2"}}]"#
        state.layout.setRawObjectArray(object: "y1AxisReferenceLine", arrayJSON: constLineJSON, visual: vCol)
        state.layout.setRawObjectArray(object: "referenceLine", arrayJSON: refLineJSON, visual: vCol)

        // 4. Visual 2: Donut Chart + Edit Interactions (Donut -> Column = NoFilter, Column -> Matrix = DataFilter)
        let vDonut = try place("donutChart", x: 620, y: 20, w: 340, h: 320)
        #expect(state.layout.addField(sex, to: "Category", visual: vDonut) == nil)
        #expect(state.layout.addField(clients, to: "Y", visual: vDonut) == nil)

        // 5. Visual 3 & 4: KPI Cards showing Wave 3 DAX measures
        let vCard1 = try place("card", x: 980, y: 20, w: 280, h: 150)
        #expect(state.layout.addField(isoRef, to: "Values", visual: vCard1) == nil)
        let vCard2 = try place("card", x: 980, y: 190, w: 280, h: 150)
        #expect(state.layout.addField(ytdRef, to: "Values", visual: vCard2) == nil)

        // 6. Visual 5: Matrix with 2-level Row Hierarchy + Conditional Formatting Rules + Data Bars
        let vMat = try place("pivotTable", x: 20, y: 360, w: 1240, h: 340)
        #expect(state.layout.addField(region, to: "Rows", visual: vMat) == nil)
        #expect(state.layout.addField(stateCol, to: "Rows", visual: vMat) == nil)
        #expect(state.layout.addField(clients, to: "Values", visual: vMat) == nil)
        let cfValuesJSON = #"[{"properties":{"backColor":{"solid":{"color":{"expr":{"Conditional":{"Cases":[{"Condition":{"Comparison":{"ComparisonKind":3,"Left":{"Measure":{"Expression":{"SourceRef":{"Entity":"Dim_Client"}},"Property":"Total_Clients"}},"Right":{"Literal":{"Value":"500D"}}}},"Value":{"Literal":{"Value":"'#FCE4D6'"}}}]}}}}}},"selector":{"data":[{"dataViewWildcard":{"matchingOption":1}}],"metadata":"Dim_Client.Total_Clients"}}]"#
        let dataBarsJSON = #"[{"properties":{"dataBars":{"positiveColor":{"solid":{"color":{"expr":{"Literal":{"Value":"'maxColor'"}}}}},"negativeColor":{"solid":{"color":{"expr":{"Literal":{"Value":"'minColor'"}}}}},"axisColor":{"solid":{"color":{"expr":{"Literal":{"Value":"'foreground'"}}}}},"reverseDirection":{"expr":{"Literal":{"Value":"false"}}},"hideText":{"expr":{"Literal":{"Value":"false"}}},"totalMatchingOption":{"expr":{"Literal":{"Value":"1L"}}}}},"selector":{"metadata":"Dim_Client.Total_Clients"}}]"#
        state.layout.setRawObjectArray(object: "values", arrayJSON: cfValuesJSON, visual: vMat)
        state.layout.setRawObjectArray(object: "columnFormatting", arrayJSON: dataBarsJSON, visual: vMat)

        // 7. Edit Interactions trên trang v1.1b Gate (VM-V11B)
        state.layout.setVisualInteraction(source: vDonut, target: vCol, type: .noFilter, on: pageID)
        state.layout.setVisualInteraction(source: vCol, target: vMat, type: .dataFilter, on: pageID)

        // 8. Date Advanced Filter cấp trang (`Dim_Date[full_date] >= 2018-01-01`)
        let dateCol = QueryColumn(table: "Dim_Date", column: "full_date")
        let dateRule = FilterRule.advanced(
            first: FilterCondition(kind: .greaterOrEqual, operand: "2018-01-01"),
            second: nil, useOr: false, numeric: false, isDate: true
        )
        let dateFilter = UserFilter(column: dateCol, rule: dateRule)
        let filterKey = UserFilterKey(level: .page, scope: pageID, filterID: "v11b-date-filter")
        state.layout.setFilter(dateFilter, for: filterKey)

        // 9. Theme Switcher: áp dụng chủ đề Executive vào RegisteredResources
        let execTheme = ThemeCatalog.presets[1]
        state.applyTheme(name: execTheme.fileName, data: execTheme.jsonData)

        // 10. Lưu file gate ra `build/v11-out/bipro-v11b-gate.pbix`
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let outDir = repoRoot.appendingPathComponent("build/v11-out", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let outURL = outDir.appendingPathComponent("bipro-v11b-gate.pbix")
        try? FileManager.default.removeItem(at: outURL)
        _ = try DocumentSaver.save(editor: state.layout, source: source, to: outURL, expectedStamp: stamp)

        // 11. Mở lại & xác minh tất cả 6 nhóm tính năng Wave 3 đều round-trip hoàn hảo!
        let reopened = try Workspace(data: Data(contentsOf: outURL))
        let gatePage = try #require(reopened.report.pages.first { $0.displayName == "v1.1b Gate" })
        #expect(gatePage.visualInteractions.count == 2)
        #expect(reopened.report.customThemeName == execTheme.fileName)
        #expect(reopened.pbix.archive.entry("Report/StaticResources/RegisteredResources/\(execTheme.fileName)") != nil)
        #expect(reopened.measure(table: "Dim_Client", name: "V11B_ISO_Week") != nil)
        #expect(reopened.measure(table: "Fact_Transaction", name: "V11B_Inflow_YTD") != nil)
        let isoVal = try await reopened.daxEngine().evaluate(measure: "V11B_ISO_Week", table: "Dim_Client", filters: [])
        #expect(try isoVal.asDouble() == 1)

        let reopenedCol = try #require(gatePage.visuals.first { $0.id == vCol })
        let colFmt = VisualFormat(objects: reopenedCol.objects)
        #expect(colFmt.analytics.constantLines.count == 1)
        #expect(colFmt.analytics.dynamicLines.count == 2)

        let reopenedMat = try #require(gatePage.visuals.first { $0.id == vMat })
        let matFmt = VisualFormat(objects: reopenedMat.objects)
        #expect(matFmt.conditionalRules.count == 1)
        #expect(matFmt.dataBars.count == 1)
    }
}
