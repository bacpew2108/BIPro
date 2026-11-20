# Mô hình dữ liệu: Phase G — Hoàn thiện ứng dụng (v1.0)

## 1. `AppPreferences` (`Sources/BIPro/Settings/AppPreferences.swift`)

`@MainActor @Observable final class AppPreferences` — lưu bền vững trong `UserDefaults` (nhận `UserDefaults = .standard` qua `init` để test cô lập không làm bẩn cài đặt máy thật).

| Thuộc tính | Kiểu | Khoá `UserDefaults` | Mặc định |
|---|---|---|---|
| `appearance` | `AppAppearance` (`.system`, `.light`, `.dark`) | `bipro.appearance` | `.system` |
| `language` | `AppLanguage` (`.system`, `.vi`, `.en`) | `bipro.language` | `.vi` |
| `snapToGrid` | `Bool` | `bipro.edit.snapToGrid` | `true` |
| `gridSize` | `Int` (`8` hoặc `16`) | `bipro.edit.gridSize` | `8` |
| `onboardingSeen` | `Bool` | `bipro.onboarding.seen` | `false` |
| `sqliteOdbcDriver` | `String` | `bipro.sqlite.odbcDriver` *(đã có từ T044)* | `"Devart ODBC Driver for SQLite"` |

Thuộc tính suy diễn:
- `effectiveLanguage: ResolvedLanguage` (`.vi` | `.en`): khi `language == .system`, kiểm tra `Locale.preferredLanguages.first?.hasPrefix("en") == true ? .en : .vi`.
- `preferredColorScheme: ColorScheme?`: `.system -> nil`, `.light -> .light`, `.dark -> .dark`.
- `nsAppearance: NSAppearance?`: `.system -> nil`, `.light -> .init(named: .aqua)`, `.dark -> .init(named: .darkAqua)`.

## 2. `L10n` (`Sources/BIPro/Settings/L10n.swift`)

```swift
enum ResolvedLanguage: String, Sendable, Equatable { case vi, en }

enum L10n {
    enum Key: String, CaseIterable, Sendable { ... }
    static func string(_ key: Key, language: ResolvedLanguage) -> String
    static func format(_ key: Key, language: ResolvedLanguage, _ args: CVarArg...) -> String
}
```
- Wrapper tiện lợi cho SwiftUI `@MainActor`: `func tr(_ key: L10n.Key) -> String` đọc `AppPreferences.shared.effectiveLanguage`.
- Nhãn phép gộp ngầm tách rõ: `AggregateFunction.displayLabel(column: String, language: ResolvedLanguage)` (UI) vs `nativeQueryRef` (PBIR, luôn tiếng Anh cố định theo Desktop).

## 3. `ReportExporter` (`Sources/BIPro/Export/`)

- `ExportPDFScope`: `.allVisiblePages` | `.currentPage`
- `ExportPNGScale`: `.x1` (`1.0`) | `.x2` (`2.0`)
- `VisualCSVExporter`:
  - Input: `DataView`, `title: String?`
  - Output: `Data` (UTF-8 BOM + nội dung RFC 4180) hoặc `ExportError.noData(reason: String)`
  - Hỗ trợ: `.single`, `.categorical`, `.matrix`, `.slicer`; từ chối `.empty`.
- `ReportPageExporter`:
  - `preload(page: ReportPage, workspace: Workspace, interaction: ReportInteraction) async -> [String: LiveVisualData]`
  - `renderPNG(page: ReportPage, workspace: Workspace, preloaded: [String: LiveVisualData], interaction: ReportInteraction, scale: ExportPNGScale) throws -> Data`
  - `renderPDF(pages: [ReportPage], workspace: Workspace, preloadedByPage: [String: [String: LiveVisualData]], interaction: ReportInteraction) throws -> Data`

## 4. `PBIXQuickLookSummary` (`Sources/PBIXKit/QuickLookSummary.swift`)

Struct `Sendable, Equatable` nằm trong `PBIXKit` để cả `BIPro`, Quick Look extension và `PBIXKitTests` dùng chung:

```swift
public struct PBIXQuickLookSummary: Sendable, Equatable {
    public struct PageOutline: Sendable, Equatable {
        public let name: String
        public let isHidden: Bool
        public let width: Double
        public let height: Double
        public let visuals: [VisualBox]
    }
    public struct VisualBox: Sendable, Equatable {
        public let type: String
        public let title: String?
        public let x: Double, y: Double, width: Double, height: Double
    }
    public let fileName: String
    public let formatLabel: String       // "PBIR" | "Layout (cũ)"
    public let pages: [PageOutline]
    public let activePageIndex: Int
    public let tableCount: Int
    public let columnCount: Int
    public let measureCount: Int
    public let relationshipCount: Int
    public let hasDataModel: Bool
}
```
Hàm tạo: `PBIXQuickLookSummary.load(from url: URL) throws -> PBIXQuickLookSummary` — chỉ mở ZIP + `ReportDefinition` + (nếu có `DataModel`) giải nén `metadata.sqlitedb` để lấy số đếm bảng/cột/measure/quan hệ, **tuyệt đối không giải mã VertiPaq**.

## 5. `VisualAccessibilitySummary` (`Sources/BIPro/Report/AccessibilitySummary.swift`)

```swift
struct VisualAccessibilitySummary: Equatable, Sendable {
    let label: String   // "<Loại>: <Tiêu đề>"
    let value: String   // tóm tắt dữ liệu ngắn cho VoiceOver
    let hint: String    // hướng dẫn thao tác ngắn
}
```
Hàm thuần `VisualAccessibilitySummary.describe(visual: ReportVisual, data: DataView?, language: ResolvedLanguage) -> VisualAccessibilitySummary`.
