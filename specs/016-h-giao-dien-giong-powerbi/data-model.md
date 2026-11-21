# Mô hình dữ liệu: Phase H — Giao diện giống Power BI Desktop

Chỉ là mô hình dữ liệu **giao diện**; không có thay đổi lược đồ `.pbix`. Kiểu viết bằng Swift giả định (chữ ký, không phải mã hoàn chỉnh). Hợp đồng chi tiết: [contracts/ribbon-catalog.md](contracts/ribbon-catalog.md), [contracts/ui-tokens.md](contracts/ui-tokens.md).

## 1. Ribbon

```swift
struct Bilingual: Hashable { let vi: String; let en: String }          // en dùng đúng chữ của Desktop

enum RibbonTabID: String { case file, home, insert, modeling, design, view, optimize, help,
                           format, dataDrill, tableTools, columnTools }

struct RibbonTabSpec  { let id: RibbonTabID; let title: Bilingual; let contextual: Bool; let groups: [RibbonGroupSpec] }
struct RibbonGroupSpec{ let id: String; let title: Bilingual; let items: [RibbonItemSpec] }

struct RibbonItemSpec {
    let id: RibbonCommandID            // enum: mỗi lệnh một ID ổn định
    let title: Bilingual
    let symbol: String                 // SF Symbol
    let tint: RibbonTint               // cặp màu cho palette hai màu
    let kind: RibbonItemKind
    let hasMenu: Bool                  // vẽ ▾
    let availability: Availability     // hàm của RibbonContext
    let observed: Bool                 // false = [SUY ĐOÁN]
    let note: String?                  // bắt buộc không rỗng khi observed == false
}

enum RibbonItemKind {
    case large                          // biểu tượng lớn + nhãn dưới
    case smallStack([RibbonItemSpec])   // 2–3 nút nhỏ xếp dọc
    case checkbox                       // Gridlines / Snap to grid / Lock objects
    case field(FieldControl)            // ô Name, Data type, Format, Summarization, Data category (kèm nhãn)
    case gallery(GalleryKind)           // ô mẫu theme
    case toggle                         // nút bật/tắt (Filters, Bookmarks, Selection…)
}

enum Availability {
    case always
    case when((RibbonContext) -> Bool, disabledReason: Bilingual)
    case unsupported(Bilingual)         // nút Windows/cloud: luôn vô hiệu
}

struct RibbonContext {                  // ảnh chụp bất biến dựng từ DocumentState
    let mode: WorkspaceMode
    let hasModel, hasData, canEditModel, canEditCanvas, viewOnly: Bool
    let visualSelected, multiSelected, groupSelected: Bool
    let tableSelected, columnSelected, measureSelected: Bool
    let clipboardHasVisual, pageCount: Int
}
```

**Quy tắc kiểm được (test):**
- `RibbonCatalog.tabs(mode:visualSelected:)` trả đúng danh sách tab theo bảng 3.4 của tài liệu cấp trên (thứ tự, tab ngữ cảnh ở cuối).
- Mỗi `RibbonCommandID` xuất hiện ≤ 1 lần trong một tab (trừ lệnh lặp có chủ đích: `manageRelationships`, `newMeasure`… ở Table tools/Home).
- `Availability.unsupported` ⇒ có tooltip song ngữ không rỗng.
- `title.vi` và `title.en` không rỗng; `en` khớp bảng chuẩn.
- Mọi `RibbonCommandID` có đúng một hành động trong `RibbonActions` (hoặc là `.noop` nếu `unsupported`).

**Chuyển trạng thái:** `ribbonTab` hiện tại hợp lệ nếu có trong `tabs(...)`; khi view đổi hoặc tab ngữ cảnh biến mất thì về `.home`. Ribbon thu gọn: `Bool` toàn app.

## 2. Số đo và màu

```swift
enum UIMetrics { static let titleBar = 36.0, tabRow = 32.0, ribbonPanel = 98.0, rail = 42.0,
                 pageTabs = 35.0, statusBar = 23.0, pane = 181.0, collapsedPane = 31.0,
                 ribbonButtonIcon = 28.0, ribbonCorner = 6.0 }
extension DS.Palette { static let accent, accentPressed, canvasWell, chrome, tabUnderline … }  // sáng/tối
```

Quan hệ: mọi khung dùng `UIMetrics`; không còn số cứng trong view. Bảng giá trị chuẩn và dung sai ở [contracts/ui-tokens.md](contracts/ui-tokens.md).

## 3. Trạng thái giao diện lưu giữ (`AppPreferences`, `UserDefaults`)

| Khoá | Kiểu | Mặc định | Ghi chú |
|---|---|---|---|
| `bipro.ribbon.collapsed` | Bool | false | UI-A3 |
| `bipro.edit.viewOnlyDefault` | Bool | false | FR-018; chỉ có hiệu lực nếu spike R-02 đạt, ngược lại giữ hành vi cũ |
| `bipro.tmdl.introSeen` | Bool | false | UI-G2 |

Trạng thái theo cửa sổ, không lưu: Filters mở/thu gọn, Ribbon tab hiện tại, tab ngữ cảnh.

## 4. Màn hình khởi động, File, Options

- **StartEntry**: thẻ khởi động (`blankReport`, `oneLake` [unsupported], `excel`, `sqlServer`, `sampleData` [unsupported], `otherSources`).
- **RecentFile**: tên, thư mục, thời điểm mở gần nhất (từ danh sách gần đây của macOS); `exists: Bool` (mờ nếu false).
- **BackstageItem**: `home, open, save, saveAs, share[unsupported], getData, import[unsupported], export, publish[unsupported], signOut[hidden], optionsAndSettings, about`.
- **OptionsSection**: `scope: global | currentFile`, `title: Bilingual`, `available: Bool`, `body` (nối vào tuỳ chọn tệp hiện có khi `available`).

## 5. Khung các view mã và mô hình

- **CodeViewChrome**: dải thông báo (có thể đóng, nhớ theo phiên), hàng nút chính (Run/Update model hoặc Apply/Preview, trạng thái bật/tắt), khu kết quả hoặc Problems/Output, tab con (`Query n`/`Script n`) kèm `+`.
- **ModelPropertiesPanel**: nhóm "Cards" với ba công tắc (`showDatabaseInHeader`, `showRelatedFieldsWhenCollapsed`, `pinRelatedFieldsToTop`), mặc định theo ảnh (No / Yes / No), lưu trong bố cục sơ đồ nếu đã có chỗ, ngược lại theo phiên.
- **StatusLine**: chuỗi do `mode` quyết định (`Page n of m`, `Table: … (n rows) Column: …`, `Query n of m`, `Script n of m`).
