import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct BookmarkExportTests {
    func visual(_ id: String, hidden: Bool = false) -> ReportVisual {
        ReportVisual(id: id, type: "card", width: 10, height: 10, isHidden: hidden)
    }

    func slicerVisual(_ id: String) -> ReportVisual { ReportVisual(id: id, type: "slicer", width: 10, height: 10) }

    @Test func aDataBookmarkWithoutSlicerSelectionIsWritableAndResetsSlicers() {
        var b = UserBookmark(id: "x", name: "B"); b.pageID = "p1"
        let spec = BookmarkExport.spec(for: b, name: "x", displayName: "B", pageVisuals: [visual("a"), slicerVisual("s")]).value
        #expect(spec?.suppressData == false && spec?.slicers.isEmpty == true)
    }

    @Test func slicerSelectionsAreExportedSortedAndSingleColumnOnly() {
        var b = UserBookmark(id: "x", name: "B"); b.pageID = "p1"
        var state = FilterState()
        state.setSlicer(visualID: "s", columns: [QueryColumn(table: "Dim_Trans_Type", column: "trans_type")],
                        selection: SlicerSelection([[.string("Debit")], [.string("Credit")]]))
        b.states["p1"] = state
        let spec = BookmarkExport.spec(for: b, name: "x", displayName: "B", pageVisuals: [slicerVisual("s")]).value
        #expect(spec?.slicers["s"]?.values == [.string("Credit"), .string("Debit")])
        #expect(spec?.slicers["s"]?.entity == "Dim_Trans_Type" && spec?.slicers["s"]?.property == "trans_type")
        var hier = FilterState()
        hier.setSlicer(visualID: "s", columns: [QueryColumn(table: "D", column: "year"), QueryColumn(table: "D", column: "q")],
                       selection: SlicerSelection([[.integer(2016)]]))
        b.states["p1"] = hier
        #expect(BookmarkExport.spec(for: b, name: "x", displayName: "B", pageVisuals: [slicerVisual("s")]).reason != nil)
    }

    @Test func dataWithDrillCrossFilterOrExpansionStaysInTheSession() {
        var b = UserBookmark(id: "x", name: "B"); b.pageID = "p1"
        b.drillDepth["v"] = 1
        #expect(BookmarkExport.spec(for: b, name: "x", displayName: "B", pageVisuals: [visual("a")]).reason?.contains("drill") == true)
        b.drillDepth = [:]
        b.slicerExpansion["s"] = [.integer(1)]
        #expect(BookmarkExport.spec(for: b, name: "x", displayName: "B", pageVisuals: [visual("a")]).reason != nil)
        b.slicerExpansion = [:]
        b.matrixExpansion["m"] = [[.integer(1)]]
        #expect(BookmarkExport.spec(for: b, name: "x", displayName: "B", pageVisuals: [visual("a")]).reason != nil)
    }

    @Test func displayOnlyBookmarkExportsHiddenStateOfThePageVisuals() {
        var b = UserBookmark(id: "x", name: "B"); b.pageID = "p1"; b.data = false
        b.visibility.setHidden("a", true)
        let spec = BookmarkExport.spec(for: b, name: "x", displayName: "B", pageVisuals: [visual("a"), visual("b"), visual("c", hidden: true)]).value
        #expect(spec?.visuals.map(\.hidden) == [true, false, true])
        #expect(spec?.suppressData == true && spec?.suppressActiveSection == false && spec?.suppressDisplay == false)
    }

    @Test func displayOffAndCurrentPageOffSetTheSuppressFlags() {
        var b = UserBookmark(id: "x", name: "B"); b.pageID = "p1"; b.data = false; b.display = false; b.currentPage = false
        let spec = BookmarkExport.spec(for: b, name: "x", displayName: "B", pageVisuals: [visual("a")]).value
        #expect(spec?.suppressActiveSection == true && spec?.suppressDisplay == true)
        #expect(spec?.visuals.allSatisfy { !$0.hidden } == true)
    }

    @Test func aMissingPageIsSessionOnly() {
        var b = UserBookmark(id: "x", name: "B"); b.data = false
        #expect(BookmarkExport.spec(for: b, name: "x", displayName: "B", pageVisuals: nil).reason != nil)
        b.pageID = "p9"
        #expect(BookmarkExport.spec(for: b, name: "x", displayName: "B", pageVisuals: nil).reason != nil)
    }

    @Test func nameValidation() {
        #expect(BookmarkExport.validateName("  Tên  ", others: []).value == "Tên")
        #expect(BookmarkExport.validateName("", others: []).reason != nil)
        #expect(BookmarkExport.validateName("a", others: ["A"]).reason != nil)
        #expect(BookmarkExport.validateName(String(repeating: "x", count: 129), others: []).reason != nil)
        #expect(BookmarkExport.validateName(String(repeating: "x", count: 128), others: []).value != nil)
    }
}
