import Foundation
import PBIXKit
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — StatusLine & StatusBar (US6, T061)")
@MainActor
struct StatusLineTests {
    @Test func statusLineFormatsAllFiveViewsCorrectly() async throws {
        let savedLang = AppPreferences.shared.language
        defer { AppPreferences.shared.language = savedLang }

        let state = try await ParityRenderTests.makeSampleState()

        // English strings matching Power BI Desktop (o_now.png, t_colsel.png, v_dax_1.png, v_tmdl_2.png)
        AppPreferences.shared.language = .en

        // Report: "Page 1 of 1" (and "Page 2 of 2" after adding a page)
        state.mode = .report
        #expect(StatusLine.text(mode: .report, state: state, language: .en) == "Page 1 of 1")
        state.addPage()
        #expect(StatusLine.text(mode: .report, state: state, language: .en) == "Page 2 of 2")

        // Table: "Table: Sales (2 rows) Column: Amount (2 distinct values)"
        state.mode = .table
        state.select(table: "Sales", column: "Amount")
        let tableStatus = StatusLine.text(mode: .table, state: state, language: .en)
        #expect(tableStatus.contains("Table: Sales"))
        #expect(tableStatus.contains("2 rows"))
        #expect(tableStatus.contains("Column: Amount"))
        #expect(tableStatus.contains("2 distinct values"))

        // DAX query: "Query 1 of 1"
        state.mode = .daxQuery
        #expect(StatusLine.text(mode: .daxQuery, state: state, language: .en) == "Query 1 of 1")

        // TMDL: "Script 1 of n"
        state.mode = .tmdl
        let tmdlStatus = StatusLine.text(mode: .tmdl, state: state, language: .en)
        #expect(tmdlStatus.hasPrefix("Script "))
        #expect(tmdlStatus.contains(" of "))

        // Model: shows tables/relationships count
        state.mode = .model
        let modelStatus = StatusLine.text(mode: .model, state: state, language: .en)
        #expect(!modelStatus.isEmpty)

        // Vietnamese non-empty localized variants
        AppPreferences.shared.language = .vi
        #expect(StatusLine.text(mode: .report, state: state, language: .vi).contains("Trang"))
        #expect(StatusLine.text(mode: .daxQuery, state: state, language: .vi).contains("Truy vấn"))
        #expect(StatusLine.text(mode: .tmdl, state: state, language: .vi).contains("Kịch bản"))
    }

    @Test func zoomSliderClampsBetween25And400Percent() {
        #expect(StatusBarZoom.minScale == 0.25)
        #expect(StatusBarZoom.maxScale == 4.0)
        #expect(StatusBarZoom.clamped(0.10) == 0.25)
        #expect(StatusBarZoom.clamped(0.25) == 0.25)
        #expect(StatusBarZoom.clamped(1.0) == 1.0)
        #expect(StatusBarZoom.clamped(4.0) == 4.0)
        #expect(StatusBarZoom.clamped(5.5) == 4.0)
        #expect(StatusBarZoom.stepOut(from: 0.30) == 0.25)
        #expect(StatusBarZoom.stepIn(from: 3.95) == 4.0)
    }
}
}
