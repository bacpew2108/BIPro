import Foundation
import Testing
@testable import PBIXKit

/// Đợt 2 (v1.1a, T001–T003): đối chiếu PBIR JSON sinh bởi `PBIRNewVisual` & `PBIRResourcePatch` với mẫu Power BI Desktop 2.159 (`VM-V11A`).
@Suite("V11A — PBIRNewVisual & PBIRResourcePatch")
struct PBIRNewVisualV11Tests {
    private static let evidenceDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/phase-v11-evidence/vm-v11a/json", isDirectory: true)

    @Test("T001: PBIRNewVisual sinh visual.json hợp lệ cho đủ 17 loại mới theo VM-V11A")
    func newVisualTypesMatchDesktopShape() throws {
        let dataTypes = [
            "barChart", "hundredPercentStackedBarChart", "pieChart",
            "tableEx", "scatterChart", "gauge", "kpi", "multiRowCard",
            "advancedSlicerVisual", "listSlicer", "textSlicer",
            "map", "filledMap",
        ]
        let id = "a1b2c3d4e5f60718293a"
        for type in dataTypes {
            let size = try #require(PBIRNewVisual.defaultSize(for: type), "Thiếu defaultSize cho \(type)")
            let data = try PBIRNewVisual.makeJSON(name: id, type: type, x: 10, y: 0, width: size.width, height: size.height, z: 0)
            let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let visual = try #require(obj["visual"] as? [String: Any])
            #expect(visual["visualType"] as? String == type)
            #expect(visual["drillFilterOtherVisuals"] as? Bool == true)
            #expect(obj["howCreated"] == nil)
        }
    }

    @Test("T001: Phần tử chèn InsertVisualButton khớp nguyên cấu trúc Desktop VM-V11A (shape, pageNavigator, bookmarkNavigator, actionButton, image)")
    func insertButtonVisualsMatchDesktopV11A() throws {
        let schema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.14.0/schema.json"
        let id = "07b5c98d29d9bee1e007"

        // 1. shape rectangle
        let shapeData = try PBIRNewVisual.makeJSON(name: id, type: "shape", x: 10, y: 0, width: 280, height: 280, z: 0, schema: schema, shapeKind: "rectangle")
        let shapeDesktopURL = Self.evidenceDir.appendingPathComponent("insert-shape.visual.json")
        if FileManager.default.fileExists(atPath: shapeDesktopURL.path) {
            let desktop = try JSONSerialization.jsonObject(with: Data(contentsOf: shapeDesktopURL)) as? NSDictionary
            let ours = try JSONSerialization.jsonObject(with: shapeData) as? NSDictionary
            #expect(ours == desktop, "insert-shape phải khớp từng khoá với Desktop 2.159")
        }

        // 2. pageNavigator
        let pageNav = try PBIRNewVisual.makeJSON(name: id, type: "pageNavigator", x: 0, y: 0, width: 1000, height: 50, z: 1, schema: schema)
        let pageNavObj = try #require(JSONSerialization.jsonObject(with: pageNav) as? [String: Any])
        #expect(pageNavObj["howCreated"] as? String == "InsertVisualButton")
        #expect((pageNavObj["visual"] as? [String: Any])?["visualType"] as? String == "pageNavigator")

        // 3. bookmarkNavigator
        let bmNav = try PBIRNewVisual.makeJSON(name: id, type: "bookmarkNavigator", x: 0, y: 0, width: 600, height: 50, z: 2, schema: schema)
        let bmNavObj = try #require(JSONSerialization.jsonObject(with: bmNav) as? [String: Any])
        #expect(bmNavObj["howCreated"] as? String == "InsertVisualButton")
        #expect((bmNavObj["visual"] as? [String: Any])?["visualType"] as? String == "bookmarkNavigator")

        // 4. actionButton (blank)
        let btn = try PBIRNewVisual.makeJSON(name: id, type: "actionButton", x: 0, y: 0, width: 100, height: 40, z: 3, schema: schema)
        let btnObj = try #require(JSONSerialization.jsonObject(with: btn) as? [String: Any])
        #expect(btnObj["howCreated"] as? String == "InsertVisualButton")
        let icon = (((btnObj["visual"] as? [String: Any])?["objects"] as? [String: Any])?["icon"] as? [[String: Any]])?.first
        #expect((icon?["selector"] as? [String: Any])?["id"] as? String == "default")

        // 5. image with registered resource item
        let img = try PBIRNewVisual.makeJSON(name: id, type: "image", x: 20, y: 20, width: 320, height: 240, z: 4, schema: schema,
                                             imageItemName: "logo_123.png", imageCaption: "logo.png")
        let imgText = try #require(String(data: img, encoding: .utf8))
        #expect(imgText.contains(#""ItemName":"logo_123.png""#))
        #expect(imgText.contains(#""howCreated":"InsertVisualButton""#))
    }

    @Test("T002: PBIRResourcePatch.addingRegisteredImage thêm mục Image vào report.json trống hoặc đã có RegisteredResources")
    func addingRegisteredImageSplicesCleanly() throws {
        // Trường hợp 1: tài liệu mới chỉ có SharedResources (chưa có RegisteredResources)
        let blankReport = Data(NewDocument.reportJSON(theme: "CY24SU10").utf8)
        let withFirst = try PBIRResourcePatch.addingRegisteredImage(name: "pic1.png", path: "pic1.png", to: blankReport)
        let items1 = PBIRResourcePatch.items(in: withFirst)
        #expect(items1.contains { $0.package == "RegisteredResources" && $0.name == "pic1.png" && $0.type == "Image" })
        #expect(items1.contains { $0.package == "SharedResources" && $0.type == "BaseTheme" })

        // Trường hợp 2: thêm ảnh thứ hai vào RegisteredResources đã có
        let withSecond = try PBIRResourcePatch.addingRegisteredImage(name: "pic2.svg", path: "pic2.svg", to: withFirst)
        let regItems = PBIRResourcePatch.items(in: withSecond).filter { $0.package == "RegisteredResources" }
        #expect(regItems.map(\.name) == ["pic1.png", "pic2.svg"])

        // Idempotent khi thêm trùng tên
        let again = try PBIRResourcePatch.addingRegisteredImage(name: "pic1.png", path: "pic1.png", to: withSecond)
        #expect(again == withSecond)

        // [Content_Types].xml thêm phần mở rộng mới (ví dụ png) cho OPC / Power BI Desktop
        let xml = Data(#"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="svg" ContentType="" /><Default Extension="json" ContentType="" /></Types>"#.utf8)
        let extended = try #require(PBIXWriter.addingMissingExtensions(["png", "json"], to: xml))
        let text = String(decoding: extended, as: UTF8.self)
        #expect(text.contains(#"<Default Extension="png" ContentType="" />"#))
        #expect(PBIXWriter.addingMissingExtensions(["png", "svg"], to: extended) == nil)
    }

    @Test("T003: PBIRQueryPatch tự thêm sortDefinition giảm dần theo Y cho barChart, pieChart, gauge; không thêm cho tableEx và kpi")
    func defaultSortMatchesV11A() throws {
        let schema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.14.0/schema.json"
        let id = "112233445566778899aa"
        let measureEl = PBIRQueryPatch.newElement(kind: .measure, entity: "Dim_Client", property: "Total_Clients", displayName: nil, role: "Y")

        for type in ["barChart", "hundredPercentStackedBarChart", "pieChart", "gauge"] {
            let empty = try PBIRNewVisual.makeJSON(name: id, type: type, x: 10, y: 0, width: 280, height: 280, z: 0, schema: schema)
            let patched = try PBIRQueryPatch.apply([PBIRQueryPatch.Well(role: "Y", elements: [measureEl])], to: empty)
            let text = try #require(String(data: patched, encoding: .utf8))
            #expect(text.contains(#""sortDefinition""#), "\(type) phải có sortDefinition mặc định theo Y")
            #expect(text.contains(#""direction":"Descending""#))
        }

        let valEl = PBIRQueryPatch.newElement(kind: .measure, entity: "Dim_Client", property: "Total_Clients", displayName: nil, role: "Values")
        let emptyTable = try PBIRNewVisual.makeJSON(name: id, type: "tableEx", x: 10, y: 0, width: 280, height: 280, z: 0, schema: schema)
        let patchedTable = try PBIRQueryPatch.apply([PBIRQueryPatch.Well(role: "Values", elements: [valEl])], to: emptyTable)
        #expect(try #require(String(data: patchedTable, encoding: .utf8)).contains("sortDefinition") == false)
    }
}
