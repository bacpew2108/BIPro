import AppKit
import Observation
import SwiftUI

/// Chế độ giao diện người dùng chọn trong Cài đặt.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

/// Tuỳ chọn ngôn ngữ giao diện.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case vi
    case en

    var id: String { rawValue }
}

/// Ngôn ngữ hiển thị thực tế sau khi phân giải `.system`.
public enum ResolvedLanguage: String, CaseIterable, Identifiable, Sendable {
    case vi
    case en

    public var id: String { rawValue }
}

/// Tập tuỳ chọn toàn cục của BI Pro, lưu bền vững trong `UserDefaults`.
/// Nhận `defaults` qua `init` để kiểm thử tự động cô lập không đụng cài đặt máy thật.
@MainActor
@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    enum Keys {
        static let appearance = "bipro.appearance"
        static let language = "bipro.language"
        static let snapToGrid = "bipro.edit.snapToGrid"
        static let gridSize = "bipro.edit.gridSize"
        static let onboardingSeen = "bipro.onboarding.seen"
        static let sqliteOdbcDriver = SQLiteODBC.defaultsKey
    }

    static let allowedGridSizes: [Int] = [8, 16]

    private let defaults: UserDefaults
    private let preferredLanguagesProvider: () -> [String]

    var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
        }
    }

    var snapToGrid: Bool {
        didSet {
            defaults.set(snapToGrid, forKey: Keys.snapToGrid)
        }
    }

    var gridSize: Int {
        didSet {
            let clamped = Self.allowedGridSizes.contains(gridSize) ? gridSize : 8
            if clamped != gridSize {
                gridSize = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.gridSize)
        }
    }

    var onboardingSeen: Bool {
        didSet {
            defaults.set(onboardingSeen, forKey: Keys.onboardingSeen)
        }
    }

    var sqliteOdbcDriver: String {
        didSet {
            SQLiteODBC.save(driver: sqliteOdbcDriver, in: defaults)
        }
    }

    /// Tăng lên mỗi lần người dùng bấm "Xem lại hướng dẫn" trong Settings hoặc menu Trợ giúp.
    var onboardingRequestToken: Int = 0

    init(
        defaults: UserDefaults = .standard,
        preferredLanguagesProvider: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.defaults = defaults
        self.preferredLanguagesProvider = preferredLanguagesProvider

        if let raw = defaults.string(forKey: Keys.appearance), let parsed = AppAppearance(rawValue: raw) {
            self.appearance = parsed
        } else {
            self.appearance = .system
        }

        if let raw = defaults.string(forKey: Keys.language), let parsed = AppLanguage(rawValue: raw) {
            self.language = parsed
        } else {
            self.language = .vi
        }

        if defaults.object(forKey: Keys.snapToGrid) != nil {
            self.snapToGrid = defaults.bool(forKey: Keys.snapToGrid)
        } else {
            self.snapToGrid = true
        }

        let storedGrid = defaults.integer(forKey: Keys.gridSize)
        self.gridSize = Self.allowedGridSizes.contains(storedGrid) ? storedGrid : 8

        self.onboardingSeen = defaults.bool(forKey: Keys.onboardingSeen)
        self.sqliteOdbcDriver = SQLiteODBC.savedDriver(in: defaults)
    }

    /// Ngôn ngữ hiệu lực cho toàn bộ UI (`.vi` hoặc `.en`).
    var effectiveLanguage: ResolvedLanguage {
        switch language {
        case .vi: return .vi
        case .en: return .en
        case .system:
            let first = preferredLanguagesProvider().first?.lowercased() ?? ""
            return first.hasPrefix("en") ? .en : .vi
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Áp dụng giao diện lên `NSApp` (an toàn khi chạy trong unit test mà `NSApp == nil`).
    func applyAppearance() {
        guard let app = NSApp else { return }
        app.appearance = nsAppearance
    }

    func requestShowOnboarding() {
        onboardingRequestToken += 1
    }

    func resetToDefaults() {
        appearance = .system
        language = .vi
        snapToGrid = true
        gridSize = 8
        sqliteOdbcDriver = SQLiteODBC.defaultDriver
    }
}
