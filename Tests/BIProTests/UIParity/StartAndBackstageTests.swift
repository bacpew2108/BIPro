import Foundation
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — Start, Backstage & Options (US7, T066)")
@MainActor
struct StartAndBackstageTests {
    @Test func startScreenHasSixDesktopEntriesWithCorrectAvailability() {
        let entries = StartEntry.all
        #expect(entries.count == 6)
        #expect(entries.map(\.id) == [
            "blankReport",
            "oneLake",
            "excel",
            "sqlServer",
            "sampleData",
            "otherSources",
        ])
        #expect(entries.map(\.title.en) == [
            "Blank report",
            "OneLake catalog",
            "Excel workbook",
            "SQL Server",
            "Learn with sample data",
            "Get data from other sources",
        ])

        // OneLake và Learn with sample data là unsupported (vô hiệu + tooltip)
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        #expect(byID["blankReport"]?.isSupported == true)
        #expect(byID["oneLake"]?.isSupported == false)
        #expect(byID["excel"]?.isSupported == true)
        #expect(byID["sqlServer"]?.isSupported == true)
        #expect(byID["sampleData"]?.isSupported == false)
        #expect(byID["otherSources"]?.isSupported == true)

        for entry in entries where !entry.isSupported {
            #expect(!(entry.disabledReason?.vi.isEmpty ?? true))
            #expect(!(entry.disabledReason?.en.isEmpty ?? true))
        }
    }

    @Test func backstageItemsFollowExactDesktopOrderAndHideSignOut() {
        let items = BackstageItem.all
        #expect(items.map(\.id) == [
            "home",
            "open",
            "save",
            "saveAs",
            "share",
            "getData",
            "importFile",
            "export",
            "publish",
            "optionsAndSettings",
            "about",
        ])
        // Sign out ẩn hoàn toàn
        #expect(!items.contains { $0.id == "signOut" })

        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(byID["share"]?.isSupported == false)
        #expect(byID["importFile"]?.isSupported == false)
        #expect(byID["publish"]?.isSupported == false)
        #expect(byID["home"]?.isSupported == true)
        #expect(byID["export"]?.isSupported == true)
        #expect(byID["optionsAndSettings"]?.isSupported == true)
    }

    @Test func recentFileNonexistentIsMarkedMissingAndNotOpenable() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bipro-missing-\(UUID().uuidString).pbix")
        let missingItem = RecentFileEntry(url: missingURL, openedAt: Date())
        #expect(missingItem.exists == false)
        #expect(missingItem.canOpen == false)

        let existingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bipro-exists-\(UUID().uuidString).pbix")
        try Data("test".utf8).write(to: existingURL)
        defer { try? FileManager.default.removeItem(at: existingURL) }

        let existingItem = RecentFileEntry(url: existingURL, openedAt: Date())
        #expect(existingItem.exists == true)
        #expect(existingItem.canOpen == true)
    }

    @Test func optionsDialogHasFifteenGlobalAndSevenCurrentFileSections() {
        let global = OptionsSection.global
        let currentFile = OptionsSection.currentFile

        #expect(global.count == 15)
        #expect(global.map(\.title.en) == [
            "Data Load",
            "Power Query Editor",
            "DirectQuery",
            "R scripting",
            "Python scripting",
            "Security",
            "Privacy",
            "Regional Settings",
            "Updates",
            "Usage Data",
            "Diagnostics",
            "Preview features",
            "Save and Recover",
            "Report settings",
            "Copilot (preview)",
        ])

        #expect(currentFile.count == 7)
        #expect(currentFile.map(\.title.en) == [
            "Data Load",
            "Regional Settings",
            "Privacy",
            "Auto recovery",
            "Published semantic model settings",
            "Query reduction",
            "Report settings",
        ])

        // Các mục có tính năng thật bật (`available == true`), mục chưa có tính năng `available == false`
        let globalByEN = Dictionary(uniqueKeysWithValues: global.map { ($0.title.en, $0) })
        let currentByEN = Dictionary(uniqueKeysWithValues: currentFile.map { ($0.title.en, $0) })
        #expect(globalByEN["Data Load"]?.available == true)
        #expect(globalByEN["Regional Settings"]?.available == true)
        #expect(globalByEN["Report settings"]?.available == true)
        #expect(globalByEN["Copilot (preview)"]?.available == false)
        #expect(globalByEN["R scripting"]?.available == false)
        #expect(currentByEN["Data Load"]?.available == true)
        #expect(currentByEN["Published semantic model settings"]?.available == false)
    }
}
}
