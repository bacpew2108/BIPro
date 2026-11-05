import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Gói P: ẩn/hiện, bookmark, bộ lọc người dùng")
struct ViewStateTests {
    private func visual(_ id: String, hidden: Bool = false) -> ReportVisual {
        ReportVisual(id: id, type: "card", isHidden: hidden)
    }

    // MARK: Ẩn/hiện

    @Test func ghiDeLenGiaTriTrongFile() {
        var state = VisibilityState()
        let a = visual("a"), b = visual("b", hidden: true)
        #expect(!state.isHidden(a)); #expect(state.isHidden(b))
        state.toggle(a); state.toggle(b)
        #expect(state.isHidden(a)); #expect(!state.isHidden(b))
        state.toggle(a)
        #expect(!state.isHidden(a))
    }

    // MARK: Bookmark (dữ liệu thật của Nhom6: `Bookmark_Q13_GioThu`)

    private static let gioThu = """
    {"displayName":"Q1.3 · Giờ × Thứ","name":"Bookmark_Q13_GioThu","options":{"applyOnlyToTargetVisuals":true,
    "targetVisualNames":["m","btnA","line","btnB"],"suppressActiveSection":true,"suppressData":true},
    "explorationState":{"version":"1.0","activeSection":"d1_giaodich","sections":{"d1_giaodich":{"visualContainers":{
    "m":{"singleVisual":{"visualType":"pivotTable"}},
    "btnA":{"singleVisual":{"visualType":"actionButton"}},
    "line":{"singleVisual":{"visualType":"lineChart","display":{"mode":"hidden"}}},
    "btnB":{"singleVisual":{"visualType":"actionButton","display":{"mode":"hidden"}}}}}}}}
    """

    @Test func docBookmarkPBIR() throws {
        let json = try JSONValue.parse(Data(Self.gioThu.utf8))
        let bookmark = ReportBookmark.parse(json, fallbackName: "x", group: nil)
        #expect(bookmark.id == "Bookmark_Q13_GioThu")
        #expect(bookmark.displayName == "Q1.3 · Giờ × Thứ")
        #expect(bookmark.suppressData && bookmark.suppressActiveSection)
        #expect(bookmark.targetVisualNames == ["m", "btnA", "line", "btnB"])
        #expect(bookmark.hidden == ["m": false, "btnA": false, "line": true, "btnB": true])
    }

    @Test func apDungBookmarkDoiDungTapVisualAn() throws {
        let bookmark = ReportBookmark.parse(try JSONValue.parse(Data(Self.gioThu.utf8)), fallbackName: "x", group: nil)
        var state = VisibilityState()
        let page = state.apply(bookmark)
        #expect(page == nil, "suppressActiveSection → không chuyển trang")
        #expect(state.isHidden(visual("line"))); #expect(state.isHidden(visual("btnB")))
        #expect(!state.isHidden(visual("m"))); #expect(!state.isHidden(visual("btnA")))
        #expect(!state.isHidden(visual("khac")), "visual ngoài bookmark giữ nguyên")
        #expect(state.activeBookmarkID == "Bookmark_Q13_GioThu")
        state.toggle(visual("m"))
        #expect(state.activeBookmarkID == nil, "đổi tay thì bỏ đánh dấu bookmark")
    }

    @Test func bookmarkChiAnhHuongVisualDich() {
        let bookmark = ReportBookmark(id: "b", displayName: "b", group: nil, activeSection: "p2", targetVisualNames: ["a"],
                                      hidden: ["a": true, "z": true])
        var state = VisibilityState()
        #expect(state.apply(bookmark) == "p2")
        #expect(state.isHidden(visual("a"))); #expect(!state.isHidden(visual("z")))
    }

    @Test func haiBookmarkDoiQuaLai() throws {
        let a = ReportBookmark.parse(try JSONValue.parse(Data(Self.gioThu.utf8)), fallbackName: "x", group: nil)
        let b = ReportBookmark(id: "B", displayName: "B", group: nil, suppressActiveSection: true, suppressData: true,
                               targetVisualNames: ["m", "btnA", "line", "btnB"],
                               hidden: ["m": true, "btnA": true, "line": false, "btnB": false])
        var state = VisibilityState()
        state.apply(a); state.apply(b)
        #expect(!state.isHidden(visual("line"))); #expect(state.isHidden(visual("m")))
        state.apply(a)
        #expect(state.isHidden(visual("line"))); #expect(!state.isHidden(visual("m")))
    }

    // MARK: Bộ lọc người dùng

    private let year = QueryColumn(table: "Dim_Date", column: "year")
    private let region = QueryColumn(table: "Dim_Client", column: "client_region")

    @Test func viTuVaTomTat() {
        #expect(UserFilter(column: year, values: [], exclude: false).predicate == nil)
        #expect(UserFilter(column: year, values: [.integer(2017), .integer(2016)], exclude: false).predicate
                == "'Dim_Date'[year] IN {2016, 2017}")
        #expect(UserFilter(column: region, values: [.string("Unknown")], exclude: true).predicate
                == "NOT('Dim_Client'[client_region] IN {\"Unknown\"})")
        #expect(UserFilter(column: year, values: [.integer(9999)], exclude: true).summary == "không phải 9999")
        #expect(UserFilter(column: year, values: [], exclude: false).summary == "là (Tất cả)")
    }

    private func filter(_ id: String, level: ReportFilter.Level, table: String, column: String, not: Bool, literal: String) throws -> ReportFilter {
        let inList = "{\"In\":{\"Expressions\":[],\"Values\":[[{\"Literal\":{\"Value\":\"\(literal)\"}}]]}}"
        let condition = not ? "{\"Not\":{\"Expression\":\(inList)}}" : inList
        let raw = try JSONValue.parse(Data("""
        {"name":"\(id)","type":"Categorical","field":{"Column":{"Expression":{"SourceRef":{"Entity":"\(table)"}},"Property":"\(column)"}},
         "filter":{"Where":[{"Condition":\(condition)}]}}
        """.utf8))
        return ReportFilter(id: id, level: level, field: nil, type: "Categorical", summary: "", isHidden: false, isLocked: false, raw: raw)
    }

    @Test func docBoLocTrongFileThanhDangSuaDuoc() throws {
        let f = try filter("f1", level: .report, table: "Dim_Date", column: "year", not: true, literal: "9999L")
        #expect(UserFilter.from(f) == UserFilter(column: year, values: [.integer(9999)], exclude: true))
        let g = try filter("f2", level: .report, table: "Dim_Client", column: "client_region", not: true, literal: "'Unknown'")
        #expect(UserFilter.from(g) == UserFilter(column: region, values: [.string("Unknown")], exclude: true))
    }

    @Test func boLocKhongPhaiCategoricalThiKhongSuaDuoc() throws {
        var f = try filter("f", level: .page, table: "T", column: "c", not: false, literal: "1L")
        f = ReportFilter(id: "f", level: .page, field: nil, type: "TopN", summary: "", isHidden: false, isLocked: false, raw: f.raw)
        #expect(UserFilter.from(f) == nil)
    }

    @Test func gopBoLocTinhKhongSuaGiuNguyenVanBan() throws {
        let y = try filter("fy", level: .report, table: "Dim_Date", column: "year", not: true, literal: "9999L")
        let r = try filter("fr", level: .report, table: "Dim_Client", column: "client_region", not: true, literal: "'Unknown'")
        let merged = ReportInteraction.mergeStatics(visual: [], visualID: "v", page: [], pageID: "p", report: [y, r], user: [:])
        #expect(merged.map(\.predicate) == ["NOT('Dim_Date'[year] IN {9999})", "NOT('Dim_Client'[client_region] IN {\"Unknown\"})"])
        #expect(merged.allSatisfy { $0.scope == .report })
    }

    @Test func suaBoLocThayViTuGiuViTri() throws {
        let y = try filter("fy", level: .report, table: "Dim_Date", column: "year", not: true, literal: "9999L")
        let r = try filter("fr", level: .report, table: "Dim_Client", column: "client_region", not: true, literal: "'Unknown'")
        let edit = UserFilter(column: year, values: [.integer(2016)], exclude: false)
        let merged = ReportInteraction.mergeStatics(visual: [], visualID: "v", page: [], pageID: "p", report: [y, r],
                                                    user: [UserFilterKey(level: .report, scope: "", filterID: "fy"): edit])
        #expect(merged.map(\.predicate) == ["'Dim_Date'[year] IN {2016}", "NOT('Dim_Client'[client_region] IN {\"Unknown\"})"])
    }

    @Test func xoaGiaTriThiBoLocBienMat() throws {
        let y = try filter("fy", level: .report, table: "Dim_Date", column: "year", not: true, literal: "9999L")
        let cleared = UserFilter(column: year, values: [], exclude: false)
        let merged = ReportInteraction.mergeStatics(visual: [], visualID: "v", page: [], pageID: "p", report: [y],
                                                    user: [UserFilterKey(level: .report, scope: "", filterID: "fy"): cleared])
        #expect(merged.isEmpty)
    }

    @Test func theNgamCuaVisualDuocThemVaoDungCap() {
        let edit = UserFilter(column: region, values: [.string("West")], exclude: false)
        let user = [
            UserFilterKey(level: .visual, scope: "v1", filterID: "implicit-x"): edit,
            UserFilterKey(level: .visual, scope: "v2", filterID: "implicit-x"): edit,
            UserFilterKey(level: .page, scope: "p1", filterID: "implicit-y"): edit,
        ]
        let merged = ReportInteraction.mergeStatics(visual: [], visualID: "v1", page: [], pageID: "p1", report: [], user: user)
        #expect(merged.map(\.scope) == [.visual, .page], "chỉ lấy thẻ của visual v1 và trang p1, theo thứ tự visual → page")
    }
}

@Suite("Gói P: FilterEditing")
@MainActor
struct FilterEditingTests {
    private let year = QueryColumn(table: "Dim_Date", column: "year")

    @Test func batTatGiaTri() {
        var f = UserFilter(column: year, values: [], exclude: false)
        f = FilterEditing.toggle(.integer(2016), in: f)
        f = FilterEditing.toggle(.integer(2017), in: f)
        #expect(f.predicate == "'Dim_Date'[year] IN {2016, 2017}")
        f = FilterEditing.toggle(.integer(2016), in: f)
        #expect(f.values == [.integer(2017)])
    }

    @Test func chonTatCaXoaLocVaVeCheDoLa() {
        let f = UserFilter(column: year, values: [.integer(9999)], exclude: true)
        let all = FilterEditing.selectAll(in: f)
        #expect(all.values.isEmpty && !all.exclude && all.predicate == nil)
    }

    @Test func timKiemKhongPhanBietHoaThuong() {
        let values: [Value] = [.string("Midwest"), .string("West"), .string("Northeast"), .integer(2016)]
        #expect(FilterEditing.matching(values, search: "west") == [.string("Midwest"), .string("West")])
        #expect(FilterEditing.matching(values, search: "") == values)
        #expect(FilterEditing.matching(values, search: "201") == [.integer(2016)])
    }
}
