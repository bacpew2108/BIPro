import Foundation
import PBIXKit
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — RibbonTabs (US1)")
struct RibbonTabsTests {
    @Test func catalogTabsMatchReferenceForAllViews() {
        for expected in RibbonReference.tabsByView {
            let mode = WorkspaceMode(rawValue: expected.modeRaw)!
            let actual = RibbonCatalog.tabs(mode: mode, visualSelected: expected.visualSelected)
            #expect(actual.map(\.rawValue) == expected.tabs, "Lệch danh sách tab ở mode=\(mode.rawValue), visualSelected=\(expected.visualSelected)")

            // Tab ngữ cảnh luôn ở cuối cùng
            var sawContextual = false
            for tab in actual {
                if tab.isContextual {
                    sawContextual = true
                } else {
                    #expect(!sawContextual, "Tab thường \(tab.rawValue) xuất hiện sau tab ngữ cảnh ở \(mode.rawValue)")
                }
            }
        }
    }

    @Test func resolvedTabFallsBackToHomeWhenTabDisappearsOrIsFile() {
        #expect(RibbonCatalog.resolvedTab(.insert, mode: .table, visualSelected: false) == .home)
        #expect(RibbonCatalog.resolvedTab(.format, mode: .report, visualSelected: false) == .home)
        #expect(RibbonCatalog.resolvedTab(.dataDrill, mode: .report, visualSelected: false) == .home)
        #expect(RibbonCatalog.resolvedTab(.file, mode: .report, visualSelected: false) == .home)
        #expect(RibbonCatalog.resolvedTab(.design, mode: .report, visualSelected: false) == .design)
        #expect(RibbonCatalog.resolvedTab(.format, mode: .report, visualSelected: true) == .format)
        #expect(RibbonCatalog.resolvedTab(.columnTools, mode: .table, visualSelected: false) == .columnTools)
    }

    @Test @MainActor func documentStateTabsAndContextualResetAndFileBackstage() throws {
        let dir = SyntheticReport.temporaryDirectory("us1-tabs")
        let url = try SyntheticReport.make(in: dir)
        let workspace = try Workspace(data: Data(contentsOf: url))
        let state = DocumentState(workspace: workspace, fileName: "Test.pbix")

        // Report không chọn visual
        state.mode = .report
        state.visualID = nil
        #expect(state.tabs.map(\.rawValue) == ["file", "home", "insert", "modeling", "design", "view", "optimize", "help"])

        // Chọn visual -> xuất hiện Format, Data / Drill
        state.visualID = SyntheticReport.a1
        #expect(state.tabs.map(\.rawValue) == ["file", "home", "insert", "modeling", "design", "view", "optimize", "help", "format", "dataDrill"])

        // Đang xem Format mà bỏ chọn visual -> tự về Home
        state.ribbonTab = .format
        state.visualID = nil
        #expect(state.ribbonTab == .home)

        // Đang xem Design ở Report mà chuyển sang Table view -> tự về Home
        state.ribbonTab = .design
        state.mode = .table
        #expect(state.tabs.map(\.rawValue) == ["file", "home", "help", "tableTools", "columnTools"])
        #expect(state.ribbonTab == .home)

        // Chuyển sang Model/DAX/TMDL
        for m in [WorkspaceMode.model, .daxQuery, .tmdl] {
            state.mode = m
            #expect(state.tabs.map(\.rawValue) == ["file", "home", "help"])
        }

        // Bấm tab File -> đặt showBackstage = true và không giữ ribbonTab ở .file
        state.mode = .report
        state.ribbonTab = .home
        #expect(state.showBackstage == false)
        state.selectRibbonTab(.file)
        #expect(state.showBackstage == true)
        #expect(state.ribbonTab == .home)
    }

    @Test @MainActor func ribbonCollapsedPersistsInAppPreferences() {
        let suiteName = "bipro.test.us1.collapsed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AppPreferences(defaults: defaults)
        #expect(prefs.ribbonCollapsed == false)
        prefs.ribbonCollapsed = true

        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.ribbonCollapsed == true)
    }
}
}
