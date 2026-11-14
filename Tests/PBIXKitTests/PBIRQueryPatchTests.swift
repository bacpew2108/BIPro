import Foundation
import Testing
@testable import PBIXKit

@Suite struct PBIRQueryPatchTests {
    // MARK: Mẫu

    static func col(_ entity: String, _ property: String, extra: String = "") -> String {
        #"{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"\#(entity)"}},"Property":"\#(property)"}},"queryRef":"\#(entity).\#(property)","nativeQueryRef":"\#(property)"\#(extra)}"#
    }
    static func mea(_ entity: String, _ property: String, extra: String = "") -> String {
        #"{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"\#(entity)"}},"Property":"\#(property)"}},"queryRef":"\#(entity).\#(property)","nativeQueryRef":"\#(property)"\#(extra)}"#
    }

    static let catA = col("Dim_Date", "month_name", extra: #","active":true"#)
    static let meaA = mea("Fact", "Credit", extra: #","displayName":"Tiền vào""#)
    static let meaB = mea("Fact", "Debit")
    static let meaC = mea("Fact", "Net")

    /// Visual gọn (Desktop ghi một dòng): Category (1), Y (2), Tooltips (1), và một khoá lạ ở ngoài `query`.
    static var compact: Data {
        Data(#"{"$schema":"s","name":"aaaaaaaaaaaaaaaaaaa1","position":{"x":1,"y":2,"z":3,"height":4,"width":5,"tabOrder":3},"visual":{"visualType":"lineChart","query":{"queryState":{"Category":{"projections":[\#(catA)]},"Y":{"projections":[\#(meaA),\#(meaB)]},"Tooltips":{"projections":[\#(meaC)]}},"sortDefinition":{"sort":[]}},"objects":{"x":[{"properties":{}}]}}}"#.utf8)
    }

    /// Cùng nội dung, có thụt lề.
    static var pretty: Data {
        Data("""
        {
          "name": "aaaaaaaaaaaaaaaaaaa1",
          "visual": {
            "visualType": "lineChart",
            "query": {
              "queryState": {
                "Category": {
                  "projections": [
                    \(catA)
                  ]
                },
                "Y": {
                  "projections": [
                    \(meaA),
                    \(meaB)
                  ]
                }
              }
            }
          }
        }
        """.utf8)
    }

    func text(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    func expectInvalid(_ message: String, _ body: () throws -> Void) {
        do { try body(); Issue.record("expected WriteError.invalid: \(message)") }
        catch let error as WriteError { if case .invalid = error { return }; Issue.record("expected .invalid, got \(error): \(message)") }
        catch { Issue.record("unexpected error \(error): \(message)") }
    }

    func well(_ role: String, in wells: [PBIRQueryPatch.Well]) -> PBIRQueryPatch.Well? { wells.first { $0.role == role } }

    // MARK: Đọc

    @Test func readsWellsInFileOrderWithSourceBytes() throws {
        let wells = try PBIRQueryPatch.wells(in: Self.compact)
        #expect(wells.map(\.role) == ["Category", "Y", "Tooltips"])
        let y = try #require(well("Y", in: wells))
        #expect(y.elements.count == 2)
        #expect(y.elements[0].field.kind == .measure && y.elements[0].field.property == "Credit" && y.elements[0].field.displayName == "Tiền vào")
        #expect(y.elements[0].field.nativeQueryRef == "Credit" && y.elements[0].field.queryRef == "Fact.Credit")
        #expect(y.elements[0].source == Data(Self.meaA.utf8))
        let c = try #require(well("Category", in: wells))
        #expect(c.elements[0].field.active == true && c.elements[0].field.kind == .column)
    }

    // MARK: Ghép

    @Test func unchangedWellsGiveIdenticalBytes() throws {
        let wells = try PBIRQueryPatch.wells(in: Self.compact)
        #expect(try PBIRQueryPatch.apply(wells, to: Self.compact) == Self.compact)
        let p = try PBIRQueryPatch.wells(in: Self.pretty)
        #expect(try PBIRQueryPatch.apply(p, to: Self.pretty) == Self.pretty)
    }

    @Test func newMeasureAndColumnUseDesktopTemplate() throws {
        var wells = try PBIRQueryPatch.wells(in: Self.compact)
        let measure = PBIRQueryPatch.newElement(kind: .measure, entity: "Fact", property: "Ví \"dụ\" \\ ñ", displayName: nil, role: "Y")
        let column = PBIRQueryPatch.newElement(kind: .column, entity: "Dim", property: "Cột", displayName: "Tên mới", role: "Category")
        wells[1].elements.append(measure)
        wells[0].elements.append(column)
        let out = try PBIRQueryPatch.apply(wells, to: Self.compact)
        let expectedY = #"{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Fact"}},"Property":"Ví \"dụ\" \\ ñ"}},"queryRef":"Fact.Ví \"dụ\" \\ ñ","nativeQueryRef":"Ví \"dụ\" \\ ñ"}"#
        let expectedC = #"{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim"}},"Property":"Cột"}},"queryRef":"Dim.Cột","nativeQueryRef":"Tên mới","displayName":"Tên mới"}"#
        let want = text(Self.compact)
            .replacingOccurrences(of: "\(Self.meaB)]", with: "\(Self.meaB),\(expectedY)]")
            .replacingOccurrences(of: "\(Self.catA)]", with: "\(Self.catA),\(expectedC)]")
        #expect(text(out) == want)
        // Đọc lại thấy đúng.
        let back = try PBIRQueryPatch.wells(in: out)
        #expect(try #require(well("Y", in: back)).elements.last?.field.property == "Ví \"dụ\" \\ ñ")
    }

    @Test func newWellIsAddedAndEmptyWellIsDropped() throws {
        var wells = try PBIRQueryPatch.wells(in: Self.compact)
        wells.append(.init(role: "Series", elements: [PBIRQueryPatch.newElement(kind: .column, entity: "Dim", property: "Vùng", displayName: nil, role: "Series")]))
        wells.removeAll { $0.role == "Tooltips" }
        let out = try PBIRQueryPatch.apply(wells, to: Self.compact)
        // Tooltips bị bỏ, Series thêm vào cuối queryState; phần còn lại giữ nguyên.
        let back = try PBIRQueryPatch.wells(in: out)
        #expect(back.map(\.role) == ["Category", "Y", "Series"])
        #expect(!text(out).contains("Tooltips"))
        #expect(text(out).contains(#""sortDefinition":{"sort":[]}"#) && text(out).contains(#""objects":{"x":[{"properties":{}}]}"#))
    }

    @Test func reorderAndMoveBetweenWellsKeepElementBytes() throws {
        var wells = try PBIRQueryPatch.wells(in: Self.compact)
        // đổi thứ tự trong Y
        wells[1].elements.reverse()
        // chuyển meaC từ Tooltips sang đầu Y
        let moved = wells[2].elements.removeFirst()
        wells[1].elements.insert(moved, at: 0)
        let out = try PBIRQueryPatch.apply(wells.filter { !$0.elements.isEmpty }, to: Self.compact)
        let y = try #require(well("Y", in: try PBIRQueryPatch.wells(in: out)))
        #expect(y.elements.map(\.field.property) == ["Net", "Debit", "Credit"])
        #expect(y.elements.map(\.source) == [Data(Self.meaC.utf8), Data(Self.meaB.utf8), Data(Self.meaA.utf8)])
        #expect(text(out).contains(#""Y":{"projections":[\#(Self.meaC),\#(Self.meaB),\#(Self.meaA)]}"#))
    }

    @Test func renameSetsChangesAndRemovesDisplayNameWithoutTouchingQueryRef() throws {
        var wells = try PBIRQueryPatch.wells(in: Self.compact)
        // meaA có displayName "Tiền vào": đổi tên; meaB không có: đặt; catA có active: giữ khoá active.
        wells[1].elements[0].field.displayName = "Doanh thu \"mới\""
        wells[1].elements[1].field.displayName = "Chi"
        var out = try PBIRQueryPatch.apply(wells, to: Self.compact)
        var back = try PBIRQueryPatch.wells(in: out)
        let y = try #require(well("Y", in: back))
        #expect(y.elements[0].field.displayName == "Doanh thu \"mới\"" && y.elements[0].field.queryRef == "Fact.Credit")
        #expect(y.elements[1].field.displayName == "Chi" && y.elements[1].field.queryRef == "Fact.Debit")
        // Desktop ghi tên mới cả vào nativeQueryRef (VM-D2 R-D2-h-rename); queryRef giữ nguyên.
        #expect(text(out).contains(#""queryRef":"Fact.Credit","nativeQueryRef":"Doanh thu \"mới\"","displayName":"Doanh thu \"mới\"""#))
        // bỏ displayName: ra đúng phần tử của meaA không có khoá (với meaB về nguyên byte)
        back[1].elements[1].field.displayName = nil
        out = try PBIRQueryPatch.apply(back, to: out)
        #expect(text(out).contains(Self.meaB))
        // meaA khi bỏ displayName
        var wells2 = try PBIRQueryPatch.wells(in: Self.compact)
        wells2[1].elements[0].field.displayName = nil
        let cleared = try PBIRQueryPatch.apply(wells2, to: Self.compact)
        // bỏ tên riêng: nativeQueryRef về tên của trường, đúng phần tử gốc không displayName
        #expect(text(cleared).contains(Self.mea("Fact", "Credit")))
        #expect(!text(cleared).contains("Tiền vào"))
    }

    @Test func everythingOutsideTheTouchedWellsStaysByteForByte() throws {
        var wells = try PBIRQueryPatch.wells(in: Self.compact)
        wells[1].elements.removeLast()
        let out = text(try PBIRQueryPatch.apply(wells, to: Self.compact))
        let want = text(Self.compact).replacingOccurrences(of: "\(Self.meaA),\(Self.meaB)]", with: "\(Self.meaA)]")
        #expect(out == want)
    }

    @Test func prettyDocumentStaysValidAndKeepsOtherBytes() throws {
        var wells = try PBIRQueryPatch.wells(in: Self.pretty)
        wells[1].elements.append(PBIRQueryPatch.newElement(kind: .measure, entity: "Fact", property: "Net", displayName: nil, role: "Y"))
        wells[1].elements.removeFirst()
        let out = try PBIRQueryPatch.apply(wells, to: Self.pretty)
        let back = try PBIRQueryPatch.wells(in: out)
        #expect(try #require(well("Y", in: back)).elements.map(\.field.property) == ["Debit", "Net"])
        #expect(try #require(well("Category", in: back)).elements.map(\.field.property) == ["month_name"])
        #expect(text(out).hasPrefix("{\n  \"name\": \"aaaaaaaaaaaaaaaaaaa1\",\n  \"visual\": {"))
        #expect(try JSONSerialization.jsonObject(with: out) is [String: Any])
    }

    @Test func applyThenRestoreGivesOriginalBytes() throws {
        let original = try PBIRQueryPatch.wells(in: Self.compact)
        var wells = original
        wells[1].elements.removeFirst()
        wells[1].elements[0].field.displayName = "X"
        let changed = try PBIRQueryPatch.apply(wells, to: Self.compact)
        #expect(changed != Self.compact)
        // `wells(in:)` của bản đã đổi, khôi phục phần tử gốc, áp lại trên bản đã đổi.
        let back = try PBIRQueryPatch.apply(original, to: changed)
        #expect(back == Self.compact)
    }

    @Test func invalidInputsAreRejected() throws {
        expectInvalid("không phải JSON object") { _ = try PBIRQueryPatch.wells(in: Data("[1]".utf8)) }
        // không có queryState và không có gì để ghi: giữ nguyên byte (D3); có gì để ghi mà không có `visual` thì lỗi
        let textbox = Data(#"{"name":"x","visual":{"visualType":"textbox"}}"#.utf8)
        #expect(try PBIRQueryPatch.apply([], to: textbox) == textbox)
        let element = PBIRQueryPatch.newElement(kind: .measure, entity: "F", property: "P", displayName: nil, role: "Y")
        expectInvalid("không có visual") { _ = try PBIRQueryPatch.apply([.init(role: "Y", elements: [element])], to: Data(#"{"name":"x"}"#.utf8)) }
        let ok = try PBIRQueryPatch.wells(in: Self.compact)
        var empty = ok
        empty[1].elements.append(PBIRQueryPatch.newElement(kind: .measure, entity: "", property: "P", displayName: nil, role: "Y"))
        expectInvalid("tên bảng rỗng") { _ = try PBIRQueryPatch.apply(empty, to: Self.compact) }
        // trùng queryRef trong ô thì được (Desktop cho thêm hai lần, VM-D2 R-D2-h-dup); chặn ở luật ô, không ở bộ ghi
        var dup = ok
        dup[1].elements.append(dup[1].elements[0])
        _ = try PBIRQueryPatch.apply(dup, to: Self.compact)
        var broken = ok
        broken[1].elements.append(.init(field: .init(role: "Y", kind: .measure, entity: "F", property: "Z", queryRef: "F.Z"), source: Data("{not json".utf8)))
        expectInvalid("source hỏng") { _ = try PBIRQueryPatch.apply(broken, to: Self.compact) }
    }

    // MARK: T006: ReportField đọc nativeQueryRef và active

    @Test func reportFieldsCarryNativeQueryRefAndActive() throws {
        let id = SyntheticPBIX.visualsA[0]
        var members = SyntheticPBIX.members()
        let index = try #require(members.firstIndex { $0.path == SyntheticPBIX.visualPath(SyntheticPBIX.pageA, id) })
        members[index].data = Data(#"{"name":"\#(id)","position":{"x":1,"y":2,"z":3,"height":4,"width":5,"tabOrder":3},"visual":{"visualType":"lineChart","query":{"queryState":{"Category":{"projections":[\#(Self.catA)]},"Y":{"projections":[\#(Self.meaA),\#(Self.meaB)]}}}}}"#.utf8)
        let list = members.map { (path: $0.path, source: ZipWriter.Source.bytes($0.data, method: $0.method)) }
        let pbix = try PBIXFile(data: try ZipWriter.write(list, modified: nil))
        let visual = try #require(try pbix.loadReport().pages.first { $0.id == SyntheticPBIX.pageA }?.visuals.first { $0.id == id })
        let byRef = Dictionary(uniqueKeysWithValues: visual.fields.map { ($0.queryRef, $0) })
        #expect(byRef["Dim_Date.month_name"]?.active == true && byRef["Dim_Date.month_name"]?.nativeQueryRef == "month_name")
        #expect(byRef["Fact.Credit"]?.active == nil && byRef["Fact.Credit"]?.nativeQueryRef == "Credit" && byRef["Fact.Credit"]?.displayName == "Tiền vào")
        #expect(visual.fields.count == 3)
    }

    // MARK: D3: visual chưa có query.queryState

    /// Visual mới: chỉ có loại và khoá lọc, như `PBIRNewVisual` ghi.
    static let bare = Data(#"{"$schema":"s","name":"aaaaaaaaaaaaaaaaaaa1","position":{"x":1,"y":2,"z":3,"height":4,"width":5,"tabOrder":3},"visual":{"visualType":"lineChart","drillFilterOtherVisuals":true}}"#.utf8)

    @Test func creatingQueryStateOnAVisualWithoutOne() throws {
        #expect(try PBIRQueryPatch.wells(in: Self.bare).isEmpty)
        let cat = PBIRQueryPatch.newElement(kind: .column, entity: "Dim_Date", property: "month_name", displayName: nil, role: "Category")
        let y = PBIRQueryPatch.newElement(kind: .measure, entity: "Fact", property: "Credit", displayName: "Tiền vào", role: "Y")
        let out = try PBIRQueryPatch.apply([.init(role: "Category", elements: [cat]), .init(role: "Y", elements: [y])], to: Self.bare)
        let catText = #"{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Property":"month_name"}},"queryRef":"Dim_Date.month_name","nativeQueryRef":"month_name"}"#
        let yText = #"{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Fact"}},"Property":"Credit"}},"queryRef":"Fact.Credit","nativeQueryRef":"Tiền vào","displayName":"Tiền vào"}"#
        let want = text(Self.bare).replacingOccurrences(of: #""visualType":"lineChart","#, with: #""visualType":"lineChart","query":{"queryState":{"Category":{"projections":[\#(catText)]},"Y":{"projections":[\#(yText)]}}},"#)
        #expect(text(out) == want)
        let back = try PBIRQueryPatch.wells(in: out)
        #expect(back.map(\.role) == ["Category", "Y"] && back[1].elements[0].field.displayName == "Tiền vào")
        // thêm trường nữa vào visual đã có queryState đi đường cũ
        var more = back
        more[1].elements.append(PBIRQueryPatch.newElement(kind: .measure, entity: "Fact", property: "Debit", displayName: nil, role: "Y"))
        let again = try PBIRQueryPatch.apply(more, to: out)
        #expect(try PBIRQueryPatch.wells(in: again)[1].elements.map(\.field.property) == ["Credit", "Debit"])
    }

    @Test func nothingToWriteLeavesAVisualWithoutQueryAlone() throws {
        #expect(try PBIRQueryPatch.apply([], to: Self.bare) == Self.bare)
        #expect(try PBIRQueryPatch.apply([.init(role: "Y", elements: [])], to: Self.bare) == Self.bare)
    }

    @Test func queryWithoutQueryStateGetsOneInside() throws {
        let json = Data(#"{"name":"x","visual":{"visualType":"lineChart","query":{"sortDefinition":{"sort":[]}}}}"#.utf8)
        let y = PBIRQueryPatch.newElement(kind: .measure, entity: "Fact", property: "Credit", displayName: nil, role: "Y")
        let out = try PBIRQueryPatch.apply([.init(role: "Y", elements: [y])], to: json)
        let root = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        let query = try #require((root["visual"] as? [String: Any])?["query"] as? [String: Any])
        #expect(query["sortDefinition"] != nil && query["queryState"] != nil)
        #expect(try PBIRQueryPatch.wells(in: out).map(\.role) == ["Y"])
    }

    @Test func removingEveryWellKeepsAnEmptyQueryState() throws {
        let y = PBIRQueryPatch.newElement(kind: .measure, entity: "Fact", property: "Credit", displayName: nil, role: "Y")
        let created = try PBIRQueryPatch.apply([.init(role: "Y", elements: [y])], to: Self.bare)
        let emptied = try PBIRQueryPatch.apply([], to: created)
        #expect(text(emptied).contains(#""query":{"queryState":{}}"#))
        #expect(try PBIRQueryPatch.wells(in: emptied).isEmpty)
    }

    // MARK: D2b: quan sát VM-D2

    /// Matrix như `2132ddc1…` của Nhom6: Rows (hour), Values (count), định dạng riêng theo trường và bộ lọc cấp visual.
    static var withFormats: Data {
        let hour = col("Fact", "trans_hour"), count = mea("Fact", "Count")
        return Data(#"""
        {"name":"aaaaaaaaaaaaaaaaaaa1","visual":{"visualType":"pivotTable","query":{"queryState":{"Rows":{"projections":[\#(hour)]},"Values":{"projections":[\#(count)]}}},
         "objects":{"columnWidth":[{"properties":{"value":{"expr":{"Literal":{"Value":"70D"}}}},"selector":{"metadata":"Fact.trans_hour"}},{"properties":{"value":{"expr":{"Literal":{"Value":"95D"}}}},"selector":{"metadata":"Fact.Count"}}],
                    "values":[{"properties":{"backColor":{}},"selector":{"metadata":"Fact.Count"}},{"properties":{"fontSize":{"expr":{"Literal":{"Value":"12D"}}}}}],
                    "grid":[{"properties":{"x":{}}}]}},
         "filterConfig":{"filters":[{"name":"f","field":{"Column":{"Expression":{"SourceRef":{"Entity":"Fact"}},"Property":"trans_hour"}},"type":"Categorical"}]}}
        """#.utf8)
    }

    @Test func aRemovedFieldTakesItsPerFieldFormattingAndKeepsTheFilter() throws {
        var wells = try PBIRQueryPatch.wells(in: Self.withFormats)
        wells.removeAll { $0.role == "Rows" }   // bỏ trans_hour
        let out = try PBIRQueryPatch.apply(wells, to: Self.withFormats)
        let root = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        let objects = try #require((root["visual"] as? [String: Any])?["objects"] as? [String: Any])
        let widths = try #require(objects["columnWidth"] as? [[String: Any]])
        #expect(widths.count == 1 && ((widths[0]["selector"] as? [String: Any])?["metadata"] as? String) == "Fact.Count")
        #expect((objects["values"] as? [[String: Any]])?.count == 2)      // Count còn trong visual: giữ
        #expect(objects["grid"] != nil)
        #expect(text(out).contains(#""filterConfig":{"filters":[{"name":"f""#))   // bộ lọc giữ nguyên
    }

    @Test func formattingOfTheLastMeasureGoesAndAnEmptiedObjectIsRemoved() throws {
        var wells = try PBIRQueryPatch.wells(in: Self.withFormats)
        wells.removeAll { $0.role == "Values" }   // bỏ Count: columnWidth còn trans_hour, values còn mục không selector
        let out = try PBIRQueryPatch.apply(wells, to: Self.withFormats)
        let objects = try #require(((try JSONSerialization.jsonObject(with: out) as? [String: Any])?["visual"] as? [String: Any])?["objects"] as? [String: Any])
        #expect((objects["columnWidth"] as? [[String: Any]])?.count == 1)
        let values = try #require(objects["values"] as? [[String: Any]])
        #expect(values.count == 1 && values[0]["selector"] == nil)
        // bỏ cả hai trường: columnWidth rỗng bị xoá hẳn khoá
        let none = try PBIRQueryPatch.apply([], to: Self.withFormats)
        let after = try #require(((try JSONSerialization.jsonObject(with: none) as? [String: Any])?["visual"] as? [String: Any])?["objects"] as? [String: Any])
        #expect(after["columnWidth"] == nil && after["values"] != nil && after["grid"] != nil)
    }

    @Test func aFieldThatMovesBetweenWellsKeepsItsFormatting() throws {
        var wells = try PBIRQueryPatch.wells(in: Self.withFormats)
        let moved = wells[1].elements.removeLast()   // Count sang Rows: vẫn còn trong visual
        wells[0].elements.append(moved)
        let out = try PBIRQueryPatch.apply(wells, to: Self.withFormats)
        #expect(text(out).contains(#""selector":{"metadata":"Fact.Count"}"#))
    }

    @Test func formatCleanupLeavesAVisualWithoutObjectsAlone() throws {
        let out = try PBIRQueryPatch.removingFormatSelectors(forQueryRefs: ["Fact.Credit"], in: Self.bare)
        #expect(out == Self.bare)
        let all = try PBIRQueryPatch.removingFormatSelectors(forQueryRefs: ["Fact.trans_hour", "Fact.Count"],
                                                              in: Data(#"{"visual":{"visualType":"x","objects":{"a":[{"selector":{"metadata":"Fact.Count"}}]},"z":1}}"#.utf8))
        #expect(text(all) == #"{"visual":{"visualType":"x","z":1}}"#)
    }

    @Test func theSameMeasureCanSitTwiceInAWell() throws {
        var wells = try PBIRQueryPatch.wells(in: Self.compact)
        wells[1].elements.append(wells[1].elements[1])   // Debit lần hai
        let out = try PBIRQueryPatch.apply(wells, to: Self.compact)
        let y = try #require(well("Y", in: try PBIRQueryPatch.wells(in: out)))
        #expect(y.elements.map(\.field.queryRef) == ["Fact.Credit", "Fact.Debit", "Fact.Debit"])
    }

    @Test func newElementWithDisplayNameWritesItAsNativeQueryRefToo() throws {
        let element = PBIRQueryPatch.newElement(kind: .measure, entity: "Fact", property: "Credit", displayName: "Thu", role: "Y")
        let out = try PBIRQueryPatch.apply([.init(role: "Y", elements: [element])], to: Self.bare)
        #expect(text(out).contains(#""queryRef":"Fact.Credit","nativeQueryRef":"Thu","displayName":"Thu""#))
    }
    // MARK: D3b: `active` và sắp xếp mặc định (VM-D3 mục B)

    static func element(_ kind: ReportField.Kind, _ property: String, role: String, active: Bool? = nil) -> PBIRQueryPatch.Element {
        PBIRQueryPatch.newElement(kind: kind, entity: "Fact", property: property, displayName: nil, role: role, active: active)
    }

    @Test func aNewColumnCarriesActiveBetweenNativeQueryRefAndDisplayName() throws {
        let first = Self.element(.column, "month", role: "Category", active: true)
        let second = Self.element(.column, "year", role: "Category", active: false)
        let out = text(try PBIRQueryPatch.apply([.init(role: "Category", elements: [first, second])], to: Self.bare))
        #expect(out.contains(#""queryRef":"Fact.month","nativeQueryRef":"month","active":true}"#))
        #expect(out.contains(#""queryRef":"Fact.year","nativeQueryRef":"year","active":false}"#))
        // Measure không có cờ, kể cả khi người gọi truyền vào.
        let measure = Self.element(.measure, "Credit", role: "Y", active: true)
        #expect(try !text(PBIRQueryPatch.apply([.init(role: "Y", elements: [measure])], to: Self.bare)).contains("\"active\""))
        // Đặt tên hiển thị sau đó: `active` đứng trước `displayName` như Desktop.
        var named = first
        named.field.displayName = "Tháng"
        let out2 = text(try PBIRQueryPatch.apply([.init(role: "Category", elements: [named])], to: Self.bare))
        #expect(out2.contains(#""nativeQueryRef":"Tháng","active":true,"displayName":"Tháng"}"#))
    }

    @Test func aVisualWithOnlyMeasuresGetsDesktopsDefaultSort() throws {
        let credit = Self.element(.measure, "Credit", role: "Y")
        let out = text(try PBIRQueryPatch.apply([.init(role: "Y", elements: [credit])], to: Self.bare))
        // Nguyên văn dạng Desktop ghi (VM-D3 B): `sortDefinition` sau `queryState`, giảm dần theo measure.
        #expect(out.contains(#""query":{"queryState":{"Y":{"projections":[\#(Self.mea("Fact", "Credit"))]}},"sortDefinition":{"sort":[{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Fact"}},"Property":"Credit"}},"direction":"Descending"}],"isDefaultSort":true}}"#))
        // Thêm measure thứ hai: sắp xếp giữ theo measure đầu.
        let debit = Self.element(.measure, "Debit", role: "Y")
        let two = try PBIRQueryPatch.apply([.init(role: "Y", elements: [credit, debit])], to: Data(out.utf8))
        #expect(text(two).components(separatedBy: "sortDefinition").count == 2 && text(two).contains(#""Property":"Credit"}},"direction""#))
    }

    @Test func noDefaultSortForOtherShapes() throws {
        let credit = Self.element(.measure, "Credit", role: "Y")
        // Có cột nhóm: Desktop tính theo kiểu cột nên không đoán.
        let month = Self.element(.column, "month", role: "Category", active: true)
        let withColumn = try PBIRQueryPatch.apply([.init(role: "Category", elements: [month]), .init(role: "Y", elements: [credit])], to: Self.bare)
        #expect(!text(withColumn).contains("sortDefinition"))
        // Loại không sắp theo measure: matrix, slicer.
        let matrix = Data(#"{"name":"aaaaaaaaaaaaaaaaaaa1","visual":{"visualType":"pivotTable"}}"#.utf8)
        let values = Self.element(.measure, "Credit", role: "Values")
        #expect(try !text(PBIRQueryPatch.apply([.init(role: "Values", elements: [values])], to: matrix)).contains("sortDefinition"))
        // `sortDefinition` có sẵn (người dùng đặt) giữ nguyên byte.
        let sorted = try PBIRQueryPatch.apply([.init(role: "Y", elements: [credit])], to: Self.compact)
        #expect(text(sorted).contains(#""sortDefinition":{"sort":[]}"#))
    }

    @Test func cardVisualSortsByTheMeasureOfItsDataWell() throws {
        let card = Data(#"{"name":"aaaaaaaaaaaaaaaaaaa1","visual":{"visualType":"cardVisual","drillFilterOtherVisuals":true}}"#.utf8)
        let out = text(try PBIRQueryPatch.apply([.init(role: "Data", elements: [Self.element(.measure, "Credit", role: "Data")])], to: card))
        #expect(out.contains(#""sortDefinition":{"sort":[{"field":{"Measure":"#) && out.contains(#""isDefaultSort":true"#))
    }

    @Test func aDefaultSortGoesWhenItsFieldIsGone() throws {
        let credit = Self.element(.measure, "Credit", role: "Y")
        let sorted = try PBIRQueryPatch.apply([.init(role: "Y", elements: [credit])], to: Self.bare)
        // Thêm cột nhóm: Desktop giữ sắp xếp theo measure (VM-D8c).
        let month = Self.element(.column, "month", role: "Category", active: true)
        let grouped = try PBIRQueryPatch.apply([.init(role: "Category", elements: [month]), .init(role: "Y", elements: [credit])], to: sorted)
        #expect(text(grouped).contains(#""sortDefinition":{"sort":[{"field":{"Measure":"#) && text(grouped).contains(#""isDefaultSort":true"#))
        // Bỏ measure mà sắp xếp trỏ tới.
        let debit = Self.element(.measure, "Debit", role: "Y")
        let swapped = try PBIRQueryPatch.apply([.init(role: "Y", elements: [debit])], to: sorted)
        #expect(!text(swapped).contains("Credit") && !text(swapped).contains("sortDefinition"))   // sắp xếp treo bị bỏ, không đoán lại
        // Chỉ khi ô `Y` vừa có measure đầu tiên mới tự thêm: sửa khác trên file không có sắp xếp thì không đụng.
        let twoMeasures = try PBIRQueryPatch.apply([.init(role: "Y", elements: [credit, debit])], to: swapped)
        #expect(!text(twoMeasures).contains("sortDefinition"))
        // Bỏ hết trường: không để lại `sortDefinition`.
        #expect(try !text(PBIRQueryPatch.apply([], to: sorted)).contains("sortDefinition"))
        // `sortDefinition` do người dùng đặt (không phải mặc định) không bị đụng.
        let custom = Data(text(sorted).replacingOccurrences(of: #""isDefaultSort":true"#, with: #""isDefaultSort":false"#).utf8)
        #expect(try text(PBIRQueryPatch.apply([.init(role: "Category", elements: [month]), .init(role: "Y", elements: [credit])], to: custom)).contains("sortDefinition"))
    }

    // MARK: VM-D9: sắp xếp mặc định theo Category

    private static func categoryVisual(_ column: String, type: String = "clusteredColumnChart") -> Data {
        Data(#"{"name":"aaaaaaaaaaaaaaaaaaa1","visual":{"visualType":"\#(type)","query":{"queryState":{"Category":{"projections":[\#(Self.col("Fact", column, extra: #","active":true"#))]},"Y":{"projections":[\#(Self.mea("Fact", "Credit"))]}}},"drillFilterOtherVisuals":true}}"#.utf8)
    }

    @Test func changingToAColumnChartSortsAscendingByTheCategory() throws {
        let line = Self.categoryVisual("month", type: "lineChart")
        let out = try PBIRQueryPatch.addingDefaultCategorySort(line)
        #expect(text(out).contains(#""sortDefinition":{"sort":[{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Fact"}},"Property":"month"}},"direction":"Ascending"}],"isDefaultSort":true}"#))
        // Đã có `sortDefinition` (kể cả của người dùng) thì giữ nguyên byte.
        #expect(try PBIRQueryPatch.addingDefaultCategorySort(out) == out)
        // Không có cột Category: không đoán.
        let bare = try PBIRQueryPatch.apply([.init(role: "Y", elements: [Self.element(.measure, "Credit", role: "Y")])], to: Self.bare)
        let sortedByMeasure = try PBIRQueryPatch.addingDefaultCategorySort(bare)
        #expect(sortedByMeasure == bare)
    }

    @Test func replacingTheSortedCategoryMovesTheDefaultSortToTheNewColumn() throws {
        let sorted = try PBIRQueryPatch.addingDefaultCategorySort(Self.categoryVisual("month"))
        let credit = Self.element(.measure, "Credit", role: "Y")
        let day = Self.element(.column, "full_date", role: "Category", active: true)
        let out = text(try PBIRQueryPatch.apply([.init(role: "Category", elements: [day]), .init(role: "Y", elements: [credit])], to: sorted))
        #expect(out.contains(#""sortDefinition":{"sort":[{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Fact"}},"Property":"full_date"}},"direction":"Ascending"}],"isDefaultSort":true}"#))
        #expect(!out.contains(#""Property":"month"}},"direction""#))
        // Thay bằng hai cột hoặc bỏ cột: không đoán, bỏ sắp xếp treo.
        let two = Self.element(.column, "year", role: "Category", active: false)
        let many = text(try PBIRQueryPatch.apply([.init(role: "Category", elements: [day, two]), .init(role: "Y", elements: [credit])], to: sorted))
        #expect(!many.contains("sortDefinition"))
        let removed = text(try PBIRQueryPatch.apply([.init(role: "Y", elements: [credit])], to: sorted))
        #expect(!removed.contains("sortDefinition"))
    }
}

/// VM-D11 mục 1: phân cấp thả vào ô Category thành một `HierarchyLevel` mỗi cấp, `active: true` cả bốn.
@Suite struct PBIRHierarchyTests {
    @Test func aHierarchyIsOneProjectionPerLevelAllActive() throws {
        let levels = ["Năm", "Quý"].map { PBIRQueryPatch.newHierarchyLevel(entity: "Dim_Date", hierarchy: "Thời gian", level: $0, role: "Category") }
        let measure = PBIRQueryPatch.newElement(kind: .measure, entity: "Fact", property: "Credit", displayName: nil, role: "Y")
        let out = String(decoding: try PBIRQueryPatch.apply([.init(role: "Category", elements: levels), .init(role: "Y", elements: [measure])],
                                                           to: PBIRQueryPatchTests.bare), as: UTF8.self)
        let first = #"{"field":{"HierarchyLevel":{"Expression":{"Hierarchy":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Hierarchy":"Thời gian"}},"Level":"Năm"}},"queryRef":"Dim_Date.Thời gian.Năm","nativeQueryRef":"Thời gian Năm","active":true}"#
        #expect(out.contains(first))
        #expect(out.contains(#""queryRef":"Dim_Date.Thời gian.Quý","nativeQueryRef":"Thời gian Quý","active":true}"#))
        // Đọc lại thành hai cấp của cùng phân cấp.
        let back = try PBIRQueryPatch.wells(in: Data(out.utf8)).first { $0.role == "Category" }
        #expect(back?.elements.map(\.field.kind) == [.hierarchyLevel, .hierarchyLevel] && back?.elements.map(\.field.property) == ["Năm", "Quý"])
    }

    // MARK: VM-D12: khoá Desktop thêm khi thành bản đồ hình

    @Test func shapeMapDefaultsCreateOrExtendObjects() throws {
        let bare = Data(#"{"name":"a","visual":{"visualType":"shapeMap","query":{"queryState":{}},"drillFilterOtherVisuals":true}}"#.utf8)
        let created = String(decoding: try PBIRVisualPatch.addingShapeMapDefaults(to: bare), as: UTF8.self)
        #expect(created.contains(#""query":{"queryState":{}},"objects":{"dataPoint":[{"properties":{"fillRule""#) && created.contains(#""shape":[{"properties":{"datasourceType""#))
        // Đã có dataPoint: thêm mục chuyển sắc vào cuối; khoá khác giữ nguyên byte.
        let withObjects = Data(#"{"visual":{"visualType":"shapeMap","objects":{"legend":[{"properties":{}}],"dataPoint":[{"properties":{"fill":1},"selector":{"id":"x"}}]}}}"#.utf8)
        let extended = String(decoding: try PBIRVisualPatch.addingShapeMapDefaults(to: withObjects), as: UTF8.self)
        #expect(extended.contains(#""legend":[{"properties":{}}],"dataPoint":[{"properties":{"fill":1},"selector":{"id":"x"}},{"properties":{"fillRule""#))
        #expect(extended.contains(#""shape":[{"properties":{"datasourceType""#))
        // Đã có `shape`: không làm gì.
        let again = try PBIRVisualPatch.addingShapeMapDefaults(to: Data(extended.utf8))
        #expect(again == Data(extended.utf8))
    }
}

