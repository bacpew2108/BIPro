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
        let expectedC = #"{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim"}},"Property":"Cột"}},"queryRef":"Dim.Cột","nativeQueryRef":"Cột","displayName":"Tên mới"}"#
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
        #expect(text(out).contains(#""queryRef":"Fact.Credit","nativeQueryRef":"Credit","displayName":"Doanh thu \"mới\"""#))
        // bỏ displayName: ra đúng phần tử của meaA không có khoá (với meaB về nguyên byte)
        back[1].elements[1].field.displayName = nil
        out = try PBIRQueryPatch.apply(back, to: out)
        #expect(text(out).contains(Self.meaB))
        // meaA khi bỏ displayName
        var wells2 = try PBIRQueryPatch.wells(in: Self.compact)
        wells2[1].elements[0].field.displayName = nil
        let cleared = try PBIRQueryPatch.apply(wells2, to: Self.compact)
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
        expectInvalid("không có queryState") { _ = try PBIRQueryPatch.apply([], to: Data(#"{"name":"x","visual":{"visualType":"textbox"}}"#.utf8)) }
        let ok = try PBIRQueryPatch.wells(in: Self.compact)
        var empty = ok
        empty[1].elements.append(PBIRQueryPatch.newElement(kind: .measure, entity: "", property: "P", displayName: nil, role: "Y"))
        expectInvalid("tên bảng rỗng") { _ = try PBIRQueryPatch.apply(empty, to: Self.compact) }
        var dup = ok
        dup[1].elements.append(dup[1].elements[0])
        expectInvalid("trùng queryRef trong ô") { _ = try PBIRQueryPatch.apply(dup, to: Self.compact) }
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
}
