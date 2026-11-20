import AppKit
import Foundation
import Testing
@testable import BIPro

@Suite("PhaseG — AppPreferences")
@MainActor
struct AppPreferencesTests {
    private func makeIsolatedDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let suite = "bipro.test.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Giá trị mặc định khi UserDefaults sạch")
    func defaultsOnFreshSuite() {
        let defaults = makeIsolatedDefaults()
        let prefs = AppPreferences(defaults: defaults, preferredLanguagesProvider: { ["vi-VN"] })
        #expect(prefs.appearance == .system)
        #expect(prefs.language == .vi)
        #expect(prefs.effectiveLanguage == .vi)
        #expect(prefs.snapToGrid == true)
        #expect(prefs.gridSize == 8)
        #expect(prefs.onboardingSeen == false)
        #expect(prefs.sqliteOdbcDriver == SQLiteODBC.defaultDriver)
        #expect(prefs.preferredColorScheme == nil)
        #expect(prefs.nsAppearance == nil)
    }

    @Test("Lưu bền vững mọi tuỳ chọn qua UserDefaults và đồng bộ SQLiteODBC")
    func persistsAcrossInstances() {
        let suite = UUID().uuidString
        let defaults = makeIsolatedDefaults(suite)
        let first = AppPreferences(defaults: defaults, preferredLanguagesProvider: { ["en-US"] })
        first.appearance = .dark
        first.language = .en
        first.snapToGrid = false
        first.gridSize = 16
        first.onboardingSeen = true
        first.sqliteOdbcDriver = "SQLite3 ODBC Driver"

        let reloaded = AppPreferences(defaults: defaults, preferredLanguagesProvider: { ["vi-VN"] })
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.preferredColorScheme == .dark)
        #expect(reloaded.nsAppearance?.name == .darkAqua)
        #expect(reloaded.language == .en)
        #expect(reloaded.effectiveLanguage == .en)
        #expect(reloaded.snapToGrid == false)
        #expect(reloaded.gridSize == 16)
        #expect(reloaded.onboardingSeen == true)
        #expect(reloaded.sqliteOdbcDriver == "SQLite3 ODBC Driver")
        #expect(SQLiteODBC.savedDriver(in: defaults) == "SQLite3 ODBC Driver")
    }

    @Test("Chế độ ngôn ngữ Theo hệ thống phân giải đúng en* → .en, còn lại → .vi")
    func systemLanguageResolution() {
        let d1 = makeIsolatedDefaults()
        let enPrefs = AppPreferences(defaults: d1, preferredLanguagesProvider: { ["en-GB", "vi-VN"] })
        enPrefs.language = .system
        #expect(enPrefs.effectiveLanguage == .en)

        let d2 = makeIsolatedDefaults()
        let viPrefs = AppPreferences(defaults: d2, preferredLanguagesProvider: { ["vi-VN", "en-US"] })
        viPrefs.language = .system
        #expect(viPrefs.effectiveLanguage == .vi)

        let d3 = makeIsolatedDefaults()
        let otherPrefs = AppPreferences(defaults: d3, preferredLanguagesProvider: { ["fr-FR"] })
        otherPrefs.language = .system
        #expect(otherPrefs.effectiveLanguage == .vi)
    }

    @Test("gridSize chỉ chấp nhận 8 hoặc 16 và resetToDefaults khôi phục đúng")
    func gridSizeValidationAndReset() {
        let defaults = makeIsolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.gridSize = 16
        #expect(prefs.gridSize == 16)
        prefs.gridSize = 99
        #expect(prefs.gridSize == 8)

        prefs.appearance = .light
        prefs.language = .en
        prefs.snapToGrid = false
        prefs.gridSize = 16
        prefs.sqliteOdbcDriver = "Custom Driver"
        prefs.resetToDefaults()

        #expect(prefs.appearance == .system)
        #expect(prefs.language == .vi)
        #expect(prefs.snapToGrid == true)
        #expect(prefs.gridSize == 8)
        #expect(prefs.sqliteOdbcDriver == SQLiteODBC.defaultDriver)
    }
}
