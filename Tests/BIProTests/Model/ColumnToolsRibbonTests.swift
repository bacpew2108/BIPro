import AppKit
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

/// Kiểm thử thanh Ribbon `Công cụ cột` (Column Tools) & `Công cụ bảng` (Table Tools) sau khi mở khoá sửa trực tiếp.
@Suite("Column Tools Ribbon")
@MainActor
struct ColumnToolsRibbonTests {
    // MARK: - ColumnFormatShortcut

    @Test func currencyShortcutFormatsNumbersAndPreservesPrecision() {
        #expect(ColumnFormatShortcut.currency(current: nil) == "\\$#,0.00")
        #expect(ColumnFormatShortcut.currency(current: "") == "\\$#,0.00")
        #expect(ColumnFormatShortcut.currency(current: "0") == "\\$#,0.00")
        #expect(ColumnFormatShortcut.currency(current: "#,0.0") == "\\$#,0.0")
        #expect(ColumnFormatShortcut.currency(current: "\\$#,0") == "\\$#,0")
    }

    @Test func percentShortcutFormatsAndPreservesPrecision() {
        #expect(ColumnFormatShortcut.percent(current: nil) == "0.00%")
        #expect(ColumnFormatShortcut.percent(current: "#,0") == "0.00%")
        #expect(ColumnFormatShortcut.percent(current: "#,0.0") == "0.0%")
        #expect(ColumnFormatShortcut.percent(current: "0.0%") == "0.0%")
    }

    @Test func thousandsSeparatorTogglesCleanly() {
        #expect(ColumnFormatShortcut.toggleThousandsSeparator(current: nil) == "#,0")
        #expect(ColumnFormatShortcut.toggleThousandsSeparator(current: "0") == "#,0")
        #expect(ColumnFormatShortcut.toggleThousandsSeparator(current: "#,0") == "0")
        #expect(ColumnFormatShortcut.toggleThousandsSeparator(current: "0.00") == "#,0.00")
        #expect(ColumnFormatShortcut.toggleThousandsSeparator(current: "#,0.00") == "0.00")
        #expect(ColumnFormatShortcut.toggleThousandsSeparator(current: "\\$0.00") == "\\$#,0.00")
        #expect(ColumnFormatShortcut.toggleThousandsSeparator(current: "\\$#,0.00") == "\\$0.00")
    }

    @Test func twoDecimalsShortcutTogglesCleanlyAcrossFormats() {
        #expect(ColumnFormatShortcut.toggleTwoDecimals(current: nil) == "#,0.00")
        #expect(ColumnFormatShortcut.toggleTwoDecimals(current: "#,0") == "#,0.00")
        #expect(ColumnFormatShortcut.toggleTwoDecimals(current: "#,0.00") == "#,0")
        #expect(ColumnFormatShortcut.toggleTwoDecimals(current: "0%") == "0.00%")
        #expect(ColumnFormatShortcut.toggleTwoDecimals(current: "0.0%") == "0.00%")
        #expect(ColumnFormatShortcut.toggleTwoDecimals(current: "0.00%") == "0%")
        #expect(ColumnFormatShortcut.toggleTwoDecimals(current: "\\$#,0") == "\\$#,0.00")
        #expect(ColumnFormatShortcut.toggleTwoDecimals(current: "\\$#,0.00") == "\\$#,0")
        #expect(ColumnFormatShortcut.toggleTwoDecimals(current: "General Date") == "#,0.00")
    }

    // MARK: - Live editing & Undo on blank document + Enter Data

    @Test func columnToolsEditsApplyAndUndoOnInMemoryTable() async throws {
        let blank = try NewDocument.blank()
        let workspace = try Workspace(data: blank)
        let state = DocumentState(workspace: workspace, fileName: "Test.pbix")
        state.mode = .table

        var enter = EnterDataTable(name: "Sales")
        _ = try enter.paste("Region\tAmount\tOrder\nNorth\t1000\t1\nSouth\t2500\t2")
        #expect(await state.loadEnterData(enter) == nil)

        state.select(table: "Sales", column: "Amount")
        let initialFormat = state.workspace.column(table: "Sales", name: "Amount")?.formatString

        // Áp dụng nhanh định dạng tiền tệ ($) và 2 số thập phân (.00)
        let curFmt = ColumnFormatShortcut.currency(current: initialFormat)
        #expect(state.updateColumn(table: "Sales", name: "Amount", patch: ColumnPatch(formatString: .set(curFmt))) == nil)
        #expect(state.workspace.column(table: "Sales", name: "Amount")?.formatString == "\\$#,0.00")

        // Đổi tổng hợp sang Average (7), danh mục địa lý cho Region, sắp xếp theo Order
        #expect(state.updateColumn(table: "Sales", name: "Amount", patch: ColumnPatch(summarizeBy: 7)) == nil)
        #expect(state.workspace.column(table: "Sales", name: "Amount")?.summarizeBy == 7)

        #expect(state.updateColumn(table: "Sales", name: "Region", patch: ColumnPatch(dataCategory: .set("StateOrProvince"), sortBy: .set("Order"))) == nil)
        let regionCol = try #require(state.workspace.column(table: "Sales", name: "Region"))
        let orderCol = try #require(state.workspace.column(table: "Sales", name: "Order"))
        #expect(regionCol.dataCategory == "StateOrProvince")
        #expect(regionCol.sortByColumnID == orderCol.id)

        // Hoàn tác lần lượt
        state.layout.undo()
        #expect(state.workspace.column(table: "Sales", name: "Region")?.dataCategory == nil)
        state.layout.undo()
        #expect(state.workspace.column(table: "Sales", name: "Amount")?.summarizeBy != 7)
        state.layout.undo()
        #expect(state.workspace.column(table: "Sales", name: "Amount")?.formatString == initialFormat)
    }

    @Test func ribbonRendersTableAndColumnToolsInBothLanguagesWithoutCrash() async throws {
        let blank = try NewDocument.blank()
        let workspace = try Workspace(data: blank)
        let state = DocumentState(workspace: workspace, fileName: "RibbonTest.pbix")
        state.mode = .table

        var enter = EnterDataTable(name: "Metrics")
        _ = try enter.paste("Label\tValue\nA\t10\nB\t20")
        #expect(await state.loadEnterData(enter) == nil)
        state.select(table: "Metrics", column: "Value")

        let savedLang = AppPreferences.shared.language
        defer { AppPreferences.shared.language = savedLang }

        for lang in [AppLanguage.vi, .en] {
            AppPreferences.shared.language = lang
            for tab in [RibbonTab.tableTools, .columnTools] {
                state.ribbonTab = tab
                let host = NSHostingView(rootView: RibbonView(state: state).frame(width: 1200, height: 124))
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.width > 0)
            }
        }
    }

    @Test func tmdlParserMessagesDoNotReferenceStalePhaseF() {
        let old = [("tables/Sales.tmdl", "table Sales\n\tcolumn amount\n\t\tdataType: double\n\t\tsummarizeBy: sum\n")]
        let new = [
            ("tables/Sales.tmdl", "table Sales\n\tcolumn amount\n\t\tdataType: double\n\t\tsummarizeBy: sum\n\tcolumn extra\n\t\tdataType: string\n"),
            ("tables/Other.tmdl", "table Other\n"),
        ]
        let result = TMDLParser.edits(old: old, new: new)
        #expect(!result.issues.isEmpty)
        for issue in result.issues {
            #expect(!issue.message.contains("Phase F"), "Thông báo TMDL vẫn còn nhắc Phase F cũ: \(issue.message)")
        }
    }
}
