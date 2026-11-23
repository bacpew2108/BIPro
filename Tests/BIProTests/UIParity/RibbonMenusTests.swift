import Foundation
import PBIXKit
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — RibbonMenus (US2)")
struct RibbonMenusTests {
    @Test func buttonsMenuHasTenEntriesAndUnobservedNavigatorSubmenu() {
        let entries = RibbonMenus.buttonsEntries
        #expect(entries.count == 10)
        #expect(entries.map(\.title.en) == [
            "Right arrow", "Reset", "Back", "Information", "Help",
            "Bookmark", "Blank", "Apply all slicers", "Clear all slicers", "Navigator",
        ])

        // Blank bật, các nút chưa cài đặt bị vô hiệu
        let blank = entries.first { $0.id == "blank" }
        #expect(blank?.enabled == true)
        let rightArrow = entries.first { $0.id == "rightArrow" }
        #expect(rightArrow?.enabled == false)
        #expect(rightArrow?.disabledReason?.isNonEmpty == true)

        // Menu con Navigator được đánh dấu observed == false ([SUY ĐOÁN])
        let nav = entries.first { $0.id == "navigator" }
        #expect(nav?.observed == false)
        #expect(nav?.note?.contains("[SUY ĐOÁN]") == true)
        #expect(RibbonMenus.navigatorSubmenuEntries.map(\.title.en) == ["Page navigator", "Bookmark navigator"])
        #expect(RibbonMenus.navigatorSubmenuEntries.allSatisfy { $0.enabled })
    }

    @Test func shapesMenuHasRectanglesBasicShapesAndBlockArrows() {
        let sections = RibbonMenus.shapeSections
        #expect(sections.count == 3)
        #expect(sections[1].title?.en == "Basic Shapes")
        #expect(sections[2].title?.en == "Block Arrows")

        let allShapes = sections.flatMap(\.items)
        // Các hình đã hỗ trợ trong BI Pro: rectangle, oval, line
        let enabledIDs = Set(allShapes.filter(\.enabled).map(\.id))
        #expect(enabledIDs == ["rectangle", "oval", "line"])
        // Hình chưa hỗ trợ bị vô hiệu có lý do song ngữ
        for item in allShapes where !item.enabled {
            #expect(item.disabledReason?.isNonEmpty == true)
        }
    }

    @Test func newPagePageViewAndRefreshMenusMatchDesktop() {
        // New page ▾
        #expect(RibbonMenus.newPageEntries.map(\.title.en) == ["New page", "Duplicate page"])
        #expect(RibbonMenus.newPageEntries.allSatisfy { $0.enabled })

        // Page view ▾
        #expect(RibbonMenus.pageViewEntries.map(\.title.en) == ["Fit to page", "Fit to width", "Actual size"])
        #expect(RibbonMenus.pageViewEntries.allSatisfy { $0.enabled })

        // Refresh ▾
        #expect(RibbonMenus.refreshEntries.map(\.title.en) == ["Schema and data", "Schema", "Data"])
        #expect(RibbonMenus.refreshEntries[0].enabled == true)
        #expect(RibbonMenus.refreshEntries[1].enabled == false)
        #expect(RibbonMenus.refreshEntries[2].enabled == false)
    }

    @Test func themesMenuHasBannerThisReportPowerBINineTilesAndGallery() {
        #expect(RibbonMenus.themesBanner.en == "Previous color-only themes are now color palettes. Open theme format pane.")
        #expect(RibbonMenus.themesBanner.isNonEmpty)
        #expect(RibbonMenus.themesPowerBITiles.count == 9)
        #expect(RibbonMenus.themesPowerBITiles[0].isDefaultClear == true)
    }

    @Test @MainActor func reportRibbonActionsExecuteWithoutRegression() async throws {
        let blank = try NewDocument.blank()
        let workspace = try Workspace(data: blank)
        let state = DocumentState(workspace: workspace, fileName: "US2Actions.pbix")
        var enter = EnterDataTable(name: "Sales")
        _ = try enter.paste("Region\tAmount\nNorth\t100\nSouth\t200")
        #expect(await state.loadEnterData(enter) == nil)

        state.mode = .report
        state.editMode = true
        let initialPages = state.pages.count
        let initialVisuals = state.page?.visuals.count ?? 0

        // Get data / Enter data
        RibbonActions.perform(.getData, state: state)
        #expect(state.getDataState != nil)
        state.closeGetData()
        RibbonActions.perform(.enterData, state: state)
        #expect(state.enterData != nil)
        state.closeEnterData()

        // New visual, Text box, Buttons ▸ Blank, Shapes ▸ Rectangle
        RibbonActions.perform(.newVisual, state: state, tab: .insert)
        RibbonActions.perform(.textBox, state: state)
        RibbonMenus.performButton("blank", state: state)
        RibbonMenus.performShape("rectangle", state: state)
        #expect((state.page?.visuals.count ?? 0) == initialVisuals + 4)

        // New page + Duplicate page
        RibbonMenus.performNewPage("newPage", state: state)
        #expect(state.pages.count == initialPages + 1)
        RibbonMenus.performNewPage("duplicatePage", state: state)
        #expect(state.pages.count == initialPages + 2)

        // Manage roles / View as
        RibbonActions.perform(.manageRoles, state: state)
        #expect(state.showManageRolesSheet == true)
        state.showManageRolesSheet = false
        RibbonActions.perform(.viewAs, state: state)
        #expect(state.showViewAsRoleSheet == true)
        state.showViewAsRoleSheet = false

        // Manage relationships mở hộp danh sách quan hệ (trước đây chỉ chuyển view Model nên ở view Model là nút chết)
        RibbonActions.perform(.manageRelationships, state: state)
        #expect(state.showManageRelationshipsSheet == true)
        state.showManageRelationshipsSheet = false
    }
}
}
