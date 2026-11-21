import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("US2 — Query Pipeline & Real DAX Execution for Table, Scatter, Gauge, KPI, MultiRowCard")
struct NewVisualQueryTests {

    @MainActor
    private func makeTestEnvironment() async throws -> (VisualQuerySpecReader, DAXEngine, URL) {
        let savedMode = UserDefaults.standard.string(forKey: "lastWorkspace")
        defer {
            if let savedMode { UserDefaults.standard.set(savedMode, forKey: "lastWorkspace") }
            else { UserDefaults.standard.removeObject(forKey: "lastWorkspace") }
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bipro-us2-query-\(UUID().uuidString)", isDirectory: true)
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(
            workspace: try Workspace(data: Data(contentsOf: untitled)),
            fileName: untitled.lastPathComponent,
            fileURL: untitled
        )
        state.mode = .report
        state.editMode = true

        var sales = EnterDataTable(name: "Sales")
        try sales.paste("Region\tYear\tAmount\tProfit\nNorth\t2022\t100\t25\nSouth\t2023\t200\t60\nEast\t2024\t300\t90\n")
        #expect(await state.loadEnterData(sales) == nil)

        for formula in [
            "Revenue = SUM(Sales[Amount])",
            "NetProfit = SUM(Sales[Profit])",
            "Goal = 250",
        ] {
            state.beginNewMeasure(table: "Sales")
            state.measureDraft?.text = formula
            await state.applyMeasureDraft()
            #expect(state.measureDraft?.message == nil)
        }

        let metadata = try #require(state.workspace.metadata)
        let engine = try state.workspace.daxEngine()
        return (VisualQuerySpecReader(metadata: metadata), engine, root)
    }

    private func visualFromJSON(_ type: String, queryStateJSON: String) throws -> ReportVisual {
        let json = """
        {"name":"v1","position":{"x":0,"y":0,"z":1,"width":300,"height":200},"visual":{"visualType":"\(type)","query":{"queryState":\(queryStateJSON)}}}
        """
        let raw = try JSONValue.parse(Data(json.utf8))
        return ReportVisual(id: "v1", type: type, x: 0, y: 0, z: 1, width: 300, height: 200,
                            objects: ObjectProperties(nil), containerObjects: ObjectProperties(nil), fields: [], raw: raw)
    }

    @MainActor
    @Test("tableEx builds dual-EVALUATE DAX, executes in DAXEngine, and maps TableDataView with Total row")
    func tableExPipeline() async throws {
        let (reader, engine, root) = try await makeTestEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }
        let v = try visualFromJSON("tableEx", queryStateJSON: """
        {"Values":{"projections":[
            {"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Region"}},"queryRef":"Sales.Region"},
            {"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Revenue"}},"queryRef":"Sales.Revenue"}
        ]}}
        """)
        let spec = try reader.spec(for: v, filters: [])
        #expect(spec.shape == .table)
        #expect(spec.orderedFields.map(\.displayName) == ["Region", "Revenue"])

        let dax = DAXQueryBuilder.build(spec)
        let result = try await engine.execute(dax)
        let view = DataViewMapper.map(result, spec: spec)
        guard case .table(let tv) = view else { Issue.record("Expected .table"); return }
        #expect(tv.columns.count == 2)
        #expect(tv.rows.count == 3)
        #expect(tv.totals?.count == 2)
        #expect(tv.totals?[0].value == .blank)
        #expect(NumberDisplay.numericValue(tv.totals?[1].value ?? .blank) == 600)
    }

    @MainActor
    @Test("scatterChart builds DAX, executes in DAXEngine, and maps ScatterData")
    func scatterPipeline() async throws {
        let (reader, engine, root) = try await makeTestEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }
        let v = try visualFromJSON("scatterChart", queryStateJSON: """
        {
            "Category":{"projections":[{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Region"}},"queryRef":"Sales.Region"}]},
            "X":{"projections":[{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Revenue"}},"queryRef":"Sales.Revenue"}]},
            "Y":{"projections":[{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"NetProfit"}},"queryRef":"Sales.NetProfit"}]}
        }
        """)
        let spec = try reader.spec(for: v, filters: [])
        #expect(spec.shape == .scatter)
        let result = try await engine.execute(DAXQueryBuilder.build(spec))
        let view = DataViewMapper.map(result, spec: spec)
        guard case .scatter(let sd) = view else { Issue.record("Expected .scatter"); return }
        #expect(sd.points.count == 3)
        let north = try #require(sd.points.first(where: { $0.categoryLabel == "North" }))
        #expect(north.x == 100 && north.y == 25)
    }

    @MainActor
    @Test("gauge builds scalar DAX, executes in DAXEngine, and maps GaugeData")
    func gaugePipeline() async throws {
        let (reader, engine, root) = try await makeTestEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }
        let v = try visualFromJSON("gauge", queryStateJSON: """
        {
            "Y":{"projections":[{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Revenue"}},"queryRef":"Sales.Revenue"}]},
            "TargetValue":{"projections":[{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Goal"}},"queryRef":"Sales.Goal"}]}
        }
        """)
        let spec = try reader.spec(for: v, filters: [])
        #expect(spec.shape == .gauge)
        let result = try await engine.execute(DAXQueryBuilder.build(spec))
        let view = DataViewMapper.map(result, spec: spec)
        guard case .gauge(let gd) = view else { Issue.record("Expected .gauge"); return }
        #expect(NumberDisplay.numericValue(gd.value.value) == 600)
        #expect(NumberDisplay.numericValue(gd.target?.value ?? .blank) == 250)
        #expect(gd.max == nil)
    }

    @MainActor
    @Test("kpi builds TrendLine DAX, executes in DAXEngine, and maps latestValue + trendPoints")
    func kpiPipeline() async throws {
        let (reader, engine, root) = try await makeTestEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }
        let v = try visualFromJSON("kpi", queryStateJSON: """
        {
            "Indicator":{"projections":[{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Revenue"}},"queryRef":"Sales.Revenue"}]},
            "TrendLine":{"projections":[{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Year"}},"queryRef":"Sales.Year"}]},
            "Goal":{"projections":[{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Goal"}},"queryRef":"Sales.Goal"}]}
        }
        """)
        let spec = try reader.spec(for: v, filters: [])
        #expect(spec.shape == .kpi)
        let result = try await engine.execute(DAXQueryBuilder.build(spec))
        let view = DataViewMapper.map(result, spec: spec)
        guard case .kpi(let kd) = view else { Issue.record("Expected .kpi"); return }
        #expect(kd.trendPoints.count == 3)
        #expect(NumberDisplay.numericValue(kd.latestValue.value) == 300)
        #expect(NumberDisplay.numericValue(kd.goalValue?.value ?? .blank) == 250)
    }

    @MainActor
    @Test("multiRowCard executes in DAXEngine and maps MultiRowCardData")
    func multiRowCardPipeline() async throws {
        let (reader, engine, root) = try await makeTestEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }
        let v = try visualFromJSON("multiRowCard", queryStateJSON: """
        {"Values":{"projections":[
            {"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Region"}},"queryRef":"Sales.Region"},
            {"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"Revenue"}},"queryRef":"Sales.Revenue"}
        ]}}
        """)
        let spec = try reader.spec(for: v, filters: [])
        #expect(spec.shape == .multiRowCard)
        let result = try await engine.execute(DAXQueryBuilder.build(spec))
        let view = DataViewMapper.map(result, spec: spec)
        guard case .multiRowCard(let mc) = view else { Issue.record("Expected .multiRowCard"); return }
        #expect(mc.fields.count == 2)
        #expect(mc.rows.count == 3)
    }
}
