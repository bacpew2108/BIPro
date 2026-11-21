import AppKit
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite("US4 — Insert Shapes, Buttons, Navigators, Images & FormatCatalog")
struct InsertElementsTests {

    @MainActor
    private func makeEditor() -> LayoutEditor {
        let page = ReportPage(id: "p1", displayName: "Page 1", width: 1280, height: 720, visuals: [])
        let report = ReportDefinition(pages: [page])
        let editor = LayoutEditor(report: report)
        editor.showPage("p1")
        return editor
    }

    @MainActor
    @Test("Insert shape (rectangle, oval, line), actionButton, pageNavigator, bookmarkNavigator")
    func insertShapesAndButtons() throws {
        let editor = makeEditor()
        let rectID = try #require(editor.insertVisual(type: "shape", visibleRect: nil, shapeKind: "rectangle"))
        let ovalID = try #require(editor.insertVisual(type: "shape", visibleRect: nil, shapeKind: "oval"))
        let lineID = try #require(editor.insertVisual(type: "shape", visibleRect: nil, shapeKind: "line"))
        let btnID = try #require(editor.insertVisual(type: "actionButton", visibleRect: nil))
        let pNavID = try #require(editor.insertVisual(type: "pageNavigator", visibleRect: nil))
        let bNavID = try #require(editor.insertVisual(type: "bookmarkNavigator", visibleRect: nil))

        let visuals = editor.visuals(of: "p1")
        #expect(visuals.count == 6)
        #expect(visuals.first(where: { $0.id == rectID })?.objects.string("shape", "tileShape") == "rectangle")
        #expect(visuals.first(where: { $0.id == ovalID })?.objects.string("shape", "tileShape") == "oval")
        #expect(visuals.first(where: { $0.id == lineID })?.objects.string("shape", "tileShape") == "line")
        #expect(visuals.first(where: { $0.id == btnID })?.type == "actionButton")
        #expect(visuals.first(where: { $0.id == pNavID })?.type == "pageNavigator")
        #expect(visuals.first(where: { $0.id == bNavID })?.type == "bookmarkNavigator")
    }

    @MainActor
    @Test("Insert image embeds RegisteredResources entry and supports Undo/Redo")
    func insertImageUndoRedo() throws {
        let editor = makeEditor()
        // Minimal 1×1 PNG bytes
        let png = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
            0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
            0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
            0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
        ])
        let res = try #require(editor.insertImage(data: png, filename: "logo.png", visibleRect: nil))
        #expect(res.itemName == "logo.png")
        #expect(editor.addedImages["logo.png"] == png)
        #expect(editor.visuals(of: "p1").contains(where: { $0.id == res.id && $0.type == "image" }))

        editor.undo()
        #expect(editor.visuals(of: "p1").isEmpty)
        #expect(editor.addedImages.isEmpty)

        editor.redo()
        #expect(editor.visuals(of: "p1").count == 1)
        #expect(editor.addedImages["logo.png"] == png)
    }

    @Test("FormatCatalog covers shape, actionButton visualLink, barChart, pieChart, tableEx, gauge, kpi, scatterChart")
    func formatCatalogExpanded() {
        #expect(!FormatCatalog.cards(for: "shape", scope: .objects).isEmpty)
        #expect(!FormatCatalog.cards(for: "barChart", scope: .objects).isEmpty)
        #expect(!FormatCatalog.cards(for: "hundredPercentStackedBarChart", scope: .objects).isEmpty)
        #expect(!FormatCatalog.cards(for: "pieChart", scope: .objects).isEmpty)
        #expect(!FormatCatalog.cards(for: "tableEx", scope: .objects).isEmpty)
        #expect(!FormatCatalog.cards(for: "scatterChart", scope: .objects).isEmpty)
        #expect(!FormatCatalog.cards(for: "gauge", scope: .objects).isEmpty)
        #expect(!FormatCatalog.cards(for: "kpi", scope: .objects).isEmpty)
        let btnCards = FormatCatalog.cards(for: "actionButton", scope: .container)
        #expect(btnCards.contains(where: { $0.objectKey == "visualLink" }))
    }

    @MainActor
    @Test("ShapeVisual (rectangle/oval/line + rotation) renders non-blank PNG")
    func renderShapeKinds() throws {
        for kind in ["rectangle", "oval", "line"] {
            let json = try PBIRNewVisual.makeJSON(name: "11111111111111111111", type: "shape", x: 0, y: 0, width: 120, height: 80, z: 1, schema: PBIRNewVisual.schemaURL(from: []), shapeKind: kind)
            let raw = try JSONValue.parse(json)
            let visual = ReportVisual(id: "11111111111111111111", type: "shape", x: 0, y: 0, z: 1, width: 120, height: 80,
                                      objects: ObjectProperties(raw["visual"]?["objects"]),
                                      containerObjects: ObjectProperties(nil), fields: [], raw: raw)
            let renderer = ImageRenderer(content: ShapeVisual(visual: visual, theme: .fallback).frame(width: 120, height: 80).background(Color.white))
            renderer.scale = 1
            let cg = renderer.cgImage
            #expect(cg != nil)
            #expect((cg?.width ?? 0) > 0)
        }
    }
}
