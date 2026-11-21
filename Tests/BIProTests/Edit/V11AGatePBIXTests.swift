import AppKit
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("v1.1a (T023) — Power BI Desktop VM Gate PBIX Generator")
struct V11AGatePBIXTests {

    private var nhom6: URL? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], fm.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        let home = fm.homeDirectoryForCurrentUser
        for rel in ["Downloads/Nhom6_Dashboard.pbix", "Downloads/bipro-golden/Nhom6_work.pbix"] {
            let url = home.appendingPathComponent(rel)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    @MainActor
    @Test("Generate build/v11-out/bipro-v11a-gate.pbix with all new 2A-2D visuals and verify round-trip")
    func generateV11AGatePBIX() async throws {
        guard ProcessInfo.processInfo.environment["BIPRO_V11A_GATE"] == "1" else { return }
        let source = try #require(nhom6, "Nhom6_work.pbix not found")
        let stamp = try FileStamp.of(source)
        let archive = try PBIXFile(url: source).archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor.reading(archive: archive, report: workspace.report)
        editor.modelBase = workspace.metadata
        editor.modelColumns = workspace.metadata?.columns ?? []
        if let first = workspace.report.pages.first { editor.showPage(first.id) }

        let pageID = try #require(editor.addPage())
        #expect(editor.renamePage(pageID, to: "v1.1a Gate") == nil)
        editor.showPage(pageID)

        let region = FieldRef(kind: .column, entity: "Dim_District", property: "region", family: .text)
        let stateCol = FieldRef(kind: .column, entity: "Dim_District", property: "state_name", family: .text)
        let year = FieldRef(kind: .column, entity: "Dim_Date", property: "year", family: .numeric)
        let birthYear = FieldRef(kind: .column, entity: "Dim_Client", property: "birth_year", family: .numeric)
        let sex = FieldRef(kind: .column, entity: "Dim_Client", property: "sex", family: .text)
        let inflow = FieldRef(kind: .measure, entity: "Fact_Transaction", property: "Total_Credit_Inflow")
        let outflow = FieldRef(kind: .measure, entity: "Fact_Transaction", property: "Total_Debit_Outflow")
        let clients = FieldRef(kind: .measure, entity: "Dim_Client", property: "Total_Clients")

        func place(_ type: String, x: Int, y: Int, w: Int, h: Int, shapeKind: String? = nil) throws -> String {
            let id = try #require(editor.insertVisual(type: type, visibleRect: CGRect(x: x, y: y, width: w, height: h), shapeKind: shapeKind), Comment(rawValue: type))
            editor.apply(frames: [id: Frame(x: x, y: y, width: w, height: h)])
            return id
        }

        // Row 1 (y=10): 2A Stacked Bar, 100% Stacked Bar, Pie, Gauge
        let vBar = try place("barChart", x: 10, y: 10, w: 300, h: 200)
        #expect(editor.addField(region, to: "Category", visual: vBar) == nil)
        #expect(editor.addField(sex, to: "Series", visual: vBar) == nil)
        #expect(editor.addField(inflow, to: "Y", visual: vBar) == nil)

        let vBar100 = try place("hundredPercentStackedBarChart", x: 320, y: 10, w: 300, h: 200)
        #expect(editor.addField(region, to: "Category", visual: vBar100) == nil)
        #expect(editor.addField(sex, to: "Series", visual: vBar100) == nil)
        #expect(editor.addField(inflow, to: "Y", visual: vBar100) == nil)

        let vPie = try place("pieChart", x: 630, y: 10, w: 300, h: 200)
        #expect(editor.addField(region, to: "Category", visual: vPie) == nil)
        #expect(editor.addField(inflow, to: "Y", visual: vPie) == nil)

        let vGauge = try place("gauge", x: 940, y: 10, w: 320, h: 200)
        #expect(editor.addField(clients, to: "Y", visual: vGauge) == nil)

        // Row 2 (y=220): 2B TableEx, Scatter, KPI, MultiRowCard
        let vTable = try place("tableEx", x: 10, y: 220, w: 300, h: 220)
        #expect(editor.addField(region, to: "Values", visual: vTable) == nil)
        #expect(editor.addField(inflow, to: "Values", visual: vTable) == nil)
        #expect(editor.addField(outflow, to: "Values", visual: vTable) == nil)

        let vScatter = try place("scatterChart", x: 320, y: 220, w: 300, h: 220)
        #expect(editor.addField(region, to: "Category", visual: vScatter) == nil)
        #expect(editor.addField(inflow, to: "X", visual: vScatter) == nil)
        #expect(editor.addField(outflow, to: "Y", visual: vScatter) == nil)
        #expect(editor.addField(clients, to: "Size", visual: vScatter) == nil)

        let vKPI = try place("kpi", x: 630, y: 220, w: 300, h: 220)
        #expect(editor.addField(inflow, to: "Indicator", visual: vKPI) == nil)
        #expect(editor.addField(year, to: "TrendLine", visual: vKPI) == nil)

        let vMRC = try place("multiRowCard", x: 940, y: 220, w: 320, h: 220)
        #expect(editor.addField(region, to: "Values", visual: vMRC) == nil)
        #expect(editor.addField(inflow, to: "Values", visual: vMRC) == nil)

        // Row 3 (y=450): 2C Slicers (Range, Tile, List, Text) & Map
        let vRange = try place("slicer", x: 10, y: 450, w: 220, h: 120)
        #expect(editor.addField(birthYear, to: "Values", visual: vRange) == nil)

        let vTile = try place("advancedSlicerVisual", x: 240, y: 450, w: 220, h: 120)
        #expect(editor.addField(sex, to: "Values", visual: vTile) == nil)

        let vList = try place("listSlicer", x: 470, y: 450, w: 220, h: 120)
        #expect(editor.addField(region, to: "Values", visual: vList) == nil)

        let vText = try place("textSlicer", x: 700, y: 450, w: 220, h: 120)
        #expect(editor.addField(stateCol, to: "Values", visual: vText) == nil)

        let vMap = try place("map", x: 930, y: 450, w: 330, h: 180)
        #expect(editor.addField(stateCol, to: "Category", visual: vMap) == nil)
        #expect(editor.addField(clients, to: "Size", visual: vMap) == nil)

        // Row 4 (y=585): 2D Insert Elements (Shape rectangle/oval, ActionButton, PageNavigator, BookmarkNavigator, Image)
        _ = try place("shape", x: 10, y: 585, w: 90, h: 60, shapeKind: "rectangle")
        _ = try place("shape", x: 110, y: 585, w: 90, h: 60, shapeKind: "oval")
        _ = try place("actionButton", x: 210, y: 585, w: 110, h: 45)
        _ = try place("pageNavigator", x: 330, y: 585, w: 360, h: 45)
        _ = try place("bookmarkNavigator", x: 700, y: 585, w: 210, h: 45)

        // Visible crisp blue-gold 48x48 badge SVG/PNG embedded via RegisteredResources (tests [Content_Types].xml png extension too!)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<48 {
            for x in 0..<48 {
                let border = x < 4 || x >= 44 || y < 4 || y >= 44
                let color = border ? NSColor(calibratedRed: 0.96, green: 0.72, blue: 0.12, alpha: 1) : NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)
                rep.setColor(color, atX: x, y: y)
            }
        }
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let imgRes = try #require(editor.insertImage(data: png, filename: "bipro_v11a_badge.png", visibleRect: CGRect(x: 10, y: 650, width: 60, height: 60)))
        editor.apply(frames: [imgRes.id: Frame(x: 10, y: 650, width: 60, height: 60)])

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let outDir = root.appendingPathComponent("build/v11-out", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let output = outDir.appendingPathComponent("bipro-v11a-gate.pbix")
        try? FileManager.default.removeItem(at: output)
        let backups = FileManager.default.temporaryDirectory.appendingPathComponent("bipro-v11a-backups-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: backups) }
        let outcome = try DocumentSaver.save(editor: editor, source: source, to: output, expectedStamp: stamp, backupDirectory: backups)
        #expect(outcome.didWrite)

        // Verify round-trip in BI Pro
        let reopened = try Workspace(data: Data(contentsOf: output))
        let gatePage = try #require(reopened.report.pages.first(where: { $0.id == pageID }))
        #expect(gatePage.visuals.count == 19)
        #expect(reopened.pbix.resource(named: "bipro_v11a_badge.png") == png)
        // Verify range slicer got 'Between' mode written
        let savedRange = try #require(gatePage.visuals.first(where: { $0.id == vRange }))
        #expect(savedRange.objects.string("data", "mode") == "Between")
    }
}
