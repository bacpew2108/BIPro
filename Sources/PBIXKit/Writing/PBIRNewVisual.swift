import Foundation

/// The `visual.json` of a visual that is new: written in the shape Power BI Desktop uses (keys and key order observed in
/// Nhom6), on one line, with nothing the file does not need (`specs/004-d3-them-visual-doi-loai/research.md` R3).
public enum PBIRNewVisual {
    /// Default size by type (width, height): the sizes seen most in Nhom6. Types not listed cannot be added.
    private static let sizes: [String: (width: Int, height: Int)] = {
        var table: [String: (Int, Int)] = [
            "card": (302, 108), "cardVisual": (302, 108), "slicer": (364, 64), "textbox": (400, 100),
        ]
        for type in ["clusteredBarChart", "clusteredColumnChart", "columnChart", "hundredPercentStackedColumnChart", "lineChart", "lineClusteredColumnComboChart",
                     "lineStackedColumnComboChart", "donutChart", "treemap", "pivotTable", "shapeMap"] {
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
                                schema: String? = nil) throws -> Data {
        guard PBIRLayoutPatch.isValidVisualName(name) else { throw WriteError.invalid("visual name must be 20 lowercase hex characters") }
        guard sizes[type] != nil else { throw WriteError.invalid("cannot create a visual of type \(type)") }
        guard width >= 1, height >= 1 else { throw WriteError.invalid("a visual needs a size") }
        guard x >= 0, y >= 0 else { throw WriteError.invalid("x and y must not be negative") }
        func token(_ text: String) -> String { String(decoding: PBIRPatch.jsonStringToken(text), as: UTF8.self) }
        let body: String
        if type == "textbox" {
            body = #"{"visualType":"textbox","objects":{"general":[{"properties":{"paragraphs":[{"textRuns":[{"value":"Hộp văn bản"}]}]}}]}}"#
        } else {
            body = #"{"visualType":\#(token(type)),"drillFilterOtherVisuals":true}"#
        }
        let text = #"{"$schema":\#(token(schema ?? defaultSchema)),"name":\#(token(name)),"position":{"x":\#(x),"y":\#(y),"z":\#(z),"height":\#(height),"width":\#(width),"tabOrder":\#(z)},"visual":\#(body)}"#
        let data = Data(text.utf8)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["name"] as? String) == name, (root["visual"] as? [String: Any])?["visualType"] as? String == type else {
            throw WriteError.verificationFailed("new visual JSON is not valid")
        }
        return data
    }
}
