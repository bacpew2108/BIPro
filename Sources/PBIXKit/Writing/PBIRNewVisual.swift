import Foundation

/// The `visual.json` of a visual that is new: written in the shape Power BI Desktop uses (keys and key order observed in
/// Nhom6), on one line, with nothing the file does not need (`specs/004-d3-them-visual-doi-loai/research.md` R3).
public enum PBIRNewVisual {
    /// Default size by type (width, height): observed in Nhom6 and VM-V11A (`docs/phase-v11-evidence/vm-v11a/QUAN-SAT.md`).
    private static let sizes: [String: (width: Int, height: Int)] = {
        var table: [String: (Int, Int)] = [
            "card": (302, 108), "cardVisual": (302, 108), "multiRowCard": (320, 220),
            "slicer": (364, 64), "advancedSlicerVisual": (300, 220), "listSlicer": (240, 260), "textSlicer": (280, 120),
            "textbox": (400, 100),
            "gauge": (360, 240), "kpi": (320, 220),
            // VM-V11A Batch 3 (InsertVisualButton):
            "shape": (280, 280), "pageNavigator": (1000, 50), "bookmarkNavigator": (600, 50),
            "actionButton": (100, 40), "image": (320, 240),
        ]
        for type in ["barChart", "stackedBarChart", "clusteredBarChart", "hundredPercentStackedBarChart",
                     "clusteredColumnChart", "columnChart", "hundredPercentStackedColumnChart",
                     "lineChart", "lineClusteredColumnComboChart", "lineStackedColumnComboChart",
                     "donutChart", "pieChart", "treemap", "pivotTable", "tableEx",
                     "scatterChart", "shapeMap", "map", "filledMap",
                     "areaChart", "stackedAreaChart", "hundredPercentStackedAreaChart", "ribbonChart", "waterfallChart", "funnel"] {
            table[type] = (616, 380)
        }
        return table
    }()

    public static func defaultSize(for type: String) -> (width: Int, height: Int)? { sizes[type] }

    static let defaultSchema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.13.0/schema.json"

    /// The `$schema` of the first visual that has one, so a new visual matches the report; the 2.13.0 schema otherwise.
    public static func schemaURL(from existing: [Data]) -> String {
        for json in existing {
            if let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any], let schema = root["$schema"] as? String {
                return schema
            }
        }
        return defaultSchema
    }

    public static func makeJSON(name: String, type: String, x: Int, y: Int, width: Int, height: Int, z: Int,
                                schema: String? = nil, shapeKind: String = "rectangle",
                                imageItemName: String? = nil, imageCaption: String? = nil) throws -> Data {
        guard PBIRLayoutPatch.isValidVisualName(name) else { throw WriteError.invalid("visual name must be 20 lowercase hex characters") }
        guard sizes[type] != nil else { throw WriteError.invalid("cannot create a visual of type \(type)") }
        guard width >= 1, height >= 1 else { throw WriteError.invalid("a visual needs a size") }
        guard x >= 0, y >= 0 else { throw WriteError.invalid("x and y must not be negative") }
        func token(_ text: String) -> String { String(decoding: PBIRPatch.jsonStringToken(text), as: UTF8.self) }
        let body: String
        var isInsertButton = false
        switch type {
        case "textbox":
            body = #"{"visualType":"textbox","objects":{"general":[{"properties":{"paragraphs":[{"textRuns":[{"value":"\#(lt("Hộp văn bản", "Text box"))"}]}]}}]}}"#
        case "shape":
            isInsertButton = true
            let literal = token("'\(shapeKind)'")
            body = #"{"visualType":"shape","objects":{"shape":[{"properties":{"tileShape":{"expr":{"Literal":{"Value":\#(literal)}}}}}],"rotation":[{"properties":{"shapeAngle":{"expr":{"Literal":{"Value":"0L"}}}}}]},"drillFilterOtherVisuals":true}"#
        case "actionButton":
            isInsertButton = true
            body = #"{"visualType":"actionButton","objects":{"icon":[{"properties":{"shapeType":{"expr":{"Literal":{"Value":"'blank'"}}}},"selector":{"id":"default"}}]},"drillFilterOtherVisuals":true}"#
        case "pageNavigator", "bookmarkNavigator":
            isInsertButton = true
            body = #"{"visualType":\#(token(type)),"drillFilterOtherVisuals":true}"#
        case "image":
            isInsertButton = true
            if let item = imageItemName, !item.isEmpty {
                body = #"{"visualType":"image","objects":{"general":[{"properties":{"imageUrl":{"expr":{"ResourcePackageItem":{"PackageName":"RegisteredResources","PackageType":1,"ItemName":\#(token(item))}}}}}],"imageScaling":[{"properties":{"imageScalingType":{"expr":{"Literal":{"Value":"'Fit'"}}}}}]},"drillFilterOtherVisuals":true}"#
            } else {
                body = #"{"visualType":"image","drillFilterOtherVisuals":true}"#
            }
        default:
            body = #"{"visualType":\#(token(type)),"drillFilterOtherVisuals":true}"#
        }
        let tail = isInsertButton ? #","howCreated":"InsertVisualButton""# : ""
        let text = #"{"$schema":\#(token(schema ?? defaultSchema)),"name":\#(token(name)),"position":{"x":\#(x),"y":\#(y),"z":\#(z),"height":\#(height),"width":\#(width),"tabOrder":\#(z)},"visual":\#(body)\#(tail)}"#
        let data = Data(text.utf8)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["name"] as? String) == name, (root["visual"] as? [String: Any])?["visualType"] as? String == type else {
            throw WriteError.verificationFailed("new visual JSON is not valid")
        }
        return data
    }
}
