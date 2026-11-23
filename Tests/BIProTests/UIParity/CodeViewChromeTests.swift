import Foundation
import PBIXKit
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — CodeView & Model/Table Chrome (US8, T075)")
@MainActor
struct CodeViewChromeTests {
    @Test func daxChromeHasDismissibleBannerEmptyResultsTextAndQueryTabs() {
        #expect(DAXQueryChrome.infoBannerText.en == "DAX queries will be saved to your model. They won't be visible when published in the Power BI service.")
        #expect(!DAXQueryChrome.infoBannerText.vi.isEmpty)
        #expect(DAXQueryChrome.emptyResultsText.en == "Your query results will show up here")
        #expect(!DAXQueryChrome.emptyResultsText.vi.isEmpty)
        #expect(DAXQueryChrome.defaultTabTitle(index: 1, language: .en) == "Query 1")
        #expect(DAXQueryChrome.defaultTabTitle(index: 2, language: .en) == "Query 2")
        #expect(DAXQueryChrome.defaultTabTitle(index: 1, language: .vi) == "Truy vấn 1")
    }

    @Test func tmdlChromeHasProblemsOutputTabsAndFirstTimeIntroPersisted() {
        let suiteName = "bipro.test.tmdl.intro.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AppPreferences(defaults: defaults)
        #expect(TMDLViewChrome.shouldShowIntro(preferences: prefs) == true)
        #expect(TMDLViewChrome.introTitle.en == "Edit your model with TMDL")
        #expect(!TMDLViewChrome.introTitle.vi.isEmpty)

        TMDLViewChrome.markIntroSeen(preferences: prefs)
        #expect(prefs.tmdlIntroSeen == true)
        #expect(TMDLViewChrome.shouldShowIntro(preferences: prefs) == false)

        #expect(TMDLViewChrome.problemsTabTitle(count: 0, language: .en) == "Problems (0)")
        #expect(TMDLViewChrome.problemsTabTitle(count: 3, language: .en) == "Problems (3)")
        #expect(TMDLViewChrome.outputTabTitle.en == "Output")
        #expect(TMDLViewChrome.defaultScriptTabTitle(index: 1, language: .en) == "Script 1")
    }

    @Test func modelPropertiesPanelHasThreeCardSwitchesWithDefaultNoYesNo() {
        let state = ModelCardsSettings()
        #expect(state.showDatabaseInHeader == false)      // No
        #expect(state.showRelatedWhenCollapsed == true)   // Yes
        #expect(state.pinRelatedFieldsToTop == false)     // No

        let items = ModelPropertiesPanel.cardOptions
        #expect(items.count == 3)
        #expect(items.map(\.title.en) == [
            "Show the database in the header when applicable",
            "Show related fields when card is collapsed",
            "Pin related fields to top of card",
        ])
        #expect(items.map(\.defaultValue) == [false, true, false])
    }

    @Test func tableWorkspaceAndModelWorkspaceUseWindowStatusBarWithoutDuplicateInnerBar() {
        #expect(TableWorkspace.usesInnerStatusBar == false)
        #expect(ModelWorkspace.usesInnerStatusBar == false)
        #expect(DAXQueryWorkspace.usesInnerStatusBar == false)
        #expect(TMDLWorkspace.usesInnerStatusBar == false)
    }
}
}
