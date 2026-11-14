import Foundation
import PBIXKit

/// Một `.pbix` nhỏ (PBIR) cho test lưu: 2 trang, vài visual, 1 bookmark. Không cần file thật của người dùng.
enum SyntheticReport {
    static let a1 = "aaaaaaaaaaaaaaaaaaa1"
    static let a2 = "aaaaaaaaaaaaaaaaaaa2"
    static let a3 = "aaaaaaaaaaaaaaaaaaa3"
    static let b1 = "bbbbbbbbbbbbbbbbbbb1"
    /// Combo có đủ các ô, cộng sắp xếp theo cột trục X (chỉ có khi `withChart`), dùng cho test sửa trường (D2).
    static let c1 = "ccccccccccccccccccc1"

    static func proj(_ kind: String, _ entity: String, _ property: String, extra: String = "") -> String {
        #"{"field":{"\#(kind)":{"Expression":{"SourceRef":{"Entity":"\#(entity)"}},"Property":"\#(property)"}},"queryRef":"\#(entity).\#(property)","nativeQueryRef":"\#(property)"\#(extra)}"#
    }

    static var chartJSON: Data {
        Data(#"{"$schema":"s","name":"\#(c1)","position":{"x":600,"y":100,"z":4000,"height":300,"width":400,"tabOrder":4000},"visual":{"visualType":"lineClusteredColumnComboChart","query":{"queryState":{"Category":{"projections":[\#(proj("Column", "Dim_Date", "month_name"))]},"Y":{"projections":[\#(proj("Measure", "Fact", "Credit", extra: #","displayName":"Tiền vào""#)),\#(proj("Measure", "Fact", "Debit"))]},"Y2":{"projections":[\#(proj("Measure", "Fact", "Net"))]},"Tooltips":{"projections":[\#(proj("Measure", "Fact", "Avg"))]}},"sortDefinition":{"sort":[{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Property":"month_name"}},"direction":"Ascending"}],"isDefaultSort":true}}}}"#.utf8)
    }


    // MARK: Visual có định dạng (D4)

    static let f1 = "fffffffffffffffffff1"   // card có objects và visualContainerObjects
    static let f2 = "fffffffffffffffffff2"   // slicer
    static let f3 = "fffffffffffffffffff3"   // matrix (pivotTable)
    static let f4 = "fffffffffffffffffff4"   // cardVisual trống, không objects, không visualContainerObjects
    static let f5 = "fffffffffffffffffff5"   // card có mục theo trường (selector metadata) và mục chung
    static let f6 = "fffffffffffffffffff6"   // hộp văn bản

    static func lit(_ value: String) -> String { #"{"expr":{"Literal":{"Value":"\#(value)"}}}"# }

    static func formatVisual(_ id: String, type: String, x: Int, body: String) -> Data {
        Data(#"{"$schema":"s","name":"\#(id)","position":{"x":\#(x),"y":600,"z":\#(x),"height":100,"width":200,"tabOrder":\#(x)},"visual":{"visualType":"\#(type)",\#(body)}}"#.utf8)
    }

    /// Visual mẫu cho test định dạng, đặt sau `a3` của trang p1 (qua `members(extra:)`).
    static var formatExtras: [(path: String, data: Data)] {
        let measure = proj("Measure", "Fact", "Balance")
        return [
            (visualPath("p1", f1), formatVisual(f1, type: "card", x: 5000, body: #""query":{"queryState":{"Values":{"projections":[\#(measure)]}}},"objects":{"labels":[{"properties":{"fontSize":\#(lit("20D")),"labelPrecision":\#(lit("1D"))}}],"categoryLabels":[{"properties":{"show":\#(lit("true")),"fontSize":\#(lit("10D"))}}]},"visualContainerObjects":{"title":[{"properties":{"show":\#(lit("true"))}}]},"drillFilterOtherVisuals":true"#)),
            (visualPath("p1", f2), formatVisual(f2, type: "slicer", x: 5100, body: #""query":{"queryState":{"Values":{"projections":[\#(proj("Column", "Dim", "region"))]}}},"objects":{"header":[{"properties":{"show":\#(lit("true")),"textSize":\#(lit("10D"))}}]},"visualContainerObjects":{"title":[{"properties":{"show":\#(lit("true"))}}]},"drillFilterOtherVisuals":true"#)),
            (visualPath("p1", f3), formatVisual(f3, type: "pivotTable", x: 5200, body: #""query":{"queryState":{"Values":{"projections":[\#(measure)]}}},"objects":{"columnHeaders":[{"properties":{"fontSize":\#(lit("12D"))}}],"subTotals":[{"properties":{"rowSubtotals":\#(lit("false"))}}]},"visualContainerObjects":{"title":[{"properties":{"show":\#(lit("true"))}}]},"drillFilterOtherVisuals":true"#)),
            (visualPath("p1", f4), formatVisual(f4, type: "cardVisual", x: 5300, body: #""query":{"queryState":{"Data":{"projections":[\#(measure)]}}},"drillFilterOtherVisuals":true"#)),
            (visualPath("p1", f5), formatVisual(f5, type: "card", x: 5400, body: #""query":{"queryState":{"Values":{"projections":[\#(measure)]}}},"objects":{"labels":[{"properties":{"color":{"solid":{"color":{"expr":{"Literal":{"Value":"'#111111'"}}}}}},"selector":{"metadata":"Fact.Balance"}},{"properties":{"fontSize":\#(lit("14D"))}}]},"drillFilterOtherVisuals":true"#)),
            (visualPath("p1", f6), formatVisual(f6, type: "textbox", x: 5500, body: #""objects":{"general":[{"properties":{"paragraphs":[{"textRuns":[{"value":"Xin chào"}]}]}}]},"visualContainerObjects":{"title":[{"properties":{"show":\#(lit("false"))}}]},"drillFilterOtherVisuals":true"#)),
        ]
    }

    static func visualPath(_ page: String, _ id: String) -> String { "Report/definition/pages/\(page)/visuals/\(id)/visual.json" }

    static func visualJSON(_ id: String, x: Int, y: Int, z: Int, w: Int, h: Int) -> Data {
        Data(#"{"$schema":"s","name":"\#(id)","position":{"x":\#(x),"y":\#(y),"z":\#(z),"height":\#(h),"width":\#(w),"tabOrder":\#(z)},"visual":{"visualType":"card"}}"#.utf8)
    }

    static func members(withChart: Bool = false, chart: Data? = nil, p1Page: String? = nil,
                        extra: [(path: String, data: Data)] = [], bookmarks: [(name: String, json: String)]? = nil,
                        reportJSON: String? = nil) -> [(path: String, data: Data, method: UInt16)] {
        func text(_ s: String) -> Data { Data(s.utf8) }
        var members: [(path: String, data: Data, method: UInt16)] = [
            ("Version", text("1.32"), 0),
            ("[Content_Types].xml", Data("\u{FEFF}<?xml version=\"1.0\" encoding=\"utf-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"json\" ContentType=\"\" /><Override PartName=\"/Version\" ContentType=\"\" /><Override PartName=\"/SecurityBindings\" ContentType=\"\" /><Override PartName=\"/DataModel\" ContentType=\"\" /></Types>".utf8), 8),
            ("DataModel", Data((0..<4000).map { UInt8(truncatingIfNeeded: $0 &* 7 ^ ($0 >> 2)) }), 0),
            ("SecurityBindings", Data([9, 8, 7]), 0),
            ("Report/definition/version.json", text(#"{"version":"2.0.0"}"#), 8),
            ("Report/definition/report.json", text(reportJSON ?? #"{"themeCollection":{"baseTheme":{"name":"CY"}}}"#), 8),
            ("Report/definition/pages/pages.json", text(#"{"pageOrder":["p1","p2"],"activePageName":"p1"}"#), 8),
            ("Report/definition/bookmarks/bookmarks.json", text(#"{"items":[{"name":"bm1"}]}"#), 8),
            ("Report/definition/bookmarks/bm1.bookmark.json",
             text(#"{"name":"bm1","options":{"targetVisualNames":["\#(a1)","\#(a2)"]},"explorationState":{"sections":{"p1":{"visualContainers":{"\#(a1)":{"singleVisual":{"visualType":"card"}},"\#(a2)":{"singleVisual":{"visualType":"card"}}}}}}}"#), 8),
            ("Report/definition/pages/p1/page.json", text(p1Page ?? #"{"name":"p1","displayName":"P1","width":1920,"height":1080}"#), 8),
            (visualPath("p1", a1), visualJSON(a1, x: 40, y: 40, z: 1000, w: 100, h: 50), 8),
            (visualPath("p1", a2), visualJSON(a2, x: 200, y: 40, z: 2000, w: 150, h: 80), 8),
            (visualPath("p1", a3), visualJSON(a3, x: 400, y: 400, z: 3000, w: 100, h: 50), 8),
            ("Report/definition/pages/p2/page.json", text(#"{"name":"p2","displayName":"P2","width":1280,"height":720}"#), 8),
            (visualPath("p2", b1), visualJSON(b1, x: 8, y: 8, z: 1000, w: 100, h: 50), 8),
        ]
        for item in extra {
            let index = members.firstIndex { $0.path == visualPath("p1", a3) }! + 1
            members.insert((item.path, item.data, 8), at: index)
        }
        if let bookmarks {
            members.removeAll { $0.path.hasPrefix("Report/definition/bookmarks/") }
            let at = members.firstIndex { $0.path == "Report/definition/pages/pages.json" }! + 1
            var added: [(path: String, data: Data, method: UInt16)] = [("Report/definition/bookmarks/bookmarks.json",
                text(#"{"items":[\#(bookmarks.map { #"{"name":"\#($0.name)"}"# }.joined(separator: ","))]}"#), 8)]
            for bookmark in bookmarks { added.append(("Report/definition/bookmarks/\(bookmark.name).bookmark.json", text(bookmark.json), 8)) }
            members.insert(contentsOf: added, at: at)
        }
        if withChart || chart != nil {
            let index = members.firstIndex { $0.path == visualPath("p1", a3) }! + 1
            members.insert((visualPath("p1", c1), chart ?? chartJSON, 8), at: index)
        }
        return members
    }

    @discardableResult
    static func make(in directory: URL, name: String = "report.pbix", withChart: Bool = false, chart: Data? = nil,
                     p1Page: String? = nil, extra: [(path: String, data: Data)] = [],
                     bookmarks: [(name: String, json: String)]? = nil, reportJSON: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let list = members(withChart: withChart, chart: chart, p1Page: p1Page, extra: extra, bookmarks: bookmarks, reportJSON: reportJSON).map { (path: $0.path, source: ZipWriter.Source.bytes($0.data, method: $0.method)) }
        let url = directory.appendingPathComponent(name)
        try ZipWriter.write(list, modified: nil).write(to: url)
        return url
    }

    static func temporaryDirectory(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bipro-\(label)-\(UUID().uuidString)", isDirectory: true)
    }
}
