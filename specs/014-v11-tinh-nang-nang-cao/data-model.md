# Mô hình dữ liệu & Hợp đồng PBIR: Đợt 3 (v1.1b)

**Thư mục spec:** `specs/014-v11-tinh-nang-nang-cao/`
**Ngày lập:** 2026-11-21
**Tham chiếu quan sát:** [QUAN-SAT.md](file:///Users/macprom114/Desktop/PowerBINative/docs/phase-v11-evidence/vm-v11b/QUAN-SAT.md)

---

## 1. Edit Interactions (`page.json` `visualInteractions`)

### Kiểu Swift (`PBIXKit`)
```swift
public enum PBIRInteractionType: String, Sendable, Equatable, Hashable, Codable {
    case dataFilter = "DataFilter"
    case highlightFilter = "HighlightFilter"
    case noFilter = "NoFilter"
}

public struct PageVisualInteraction: Sendable, Equatable, Hashable {
    public var source: String
    public var target: String
    public var type: PBIRInteractionType
}
```
### JSON PBIR (đã xác nhận `VM-V11B` `b2-d1.page.json`)
```json
"visualInteractions": [
  {"source": "b1106ee1bf9281ad7b51", "target": "c36625920078b7e0c75a", "type": "NoFilter"},
  {"source": "b1106ee1bf9281ad7b51", "target": "bd7c2a2d8369e704295f", "type": "HighlightFilter"}
]
```
- Quy tắc ghép byte (`PBIRPagePatch.settingVisualInteractions`): thay thế mảng `"visualInteractions"` nếu đã tồn tại, chèn trước dấu `}` cuối `page.json` nếu chưa có, hoặc xoá khoá nếu mảng rỗng.

---

## 2. Matrix Row Hierarchy Expansion (`visual.json` `expansionStates`)

### Kiểu Swift (`BIPro`)
```swift
struct MatrixRowNode: Hashable, Sendable {
    var path: [Value]          // Giá trị từng cấp từ gốc tới dòng này
    var level: Int             // 0 = cấp gốc, 1 = cấp con...
    var hasChildren: Bool      // true nếu còn cấp con trong rowLevels
    var isExpanded: Bool       // true nếu đang mở nút (−)
    var isSubtotal: Bool
    var isGrandTotal: Bool
}
```
### JSON PBIR (đã xác nhận `VM-V11B` `b3-*-928f08c931d640590cd0.visual.json`)
```json
"expansionStates": [{
  "roles": ["Rows"],
  "levels": [
    {
      "queryRefs": ["Dim_Client.client_region"],
      "isCollapsed": true,
      "identityKeys": [{"Column": {"Expression": {"SourceRef": {"Entity": "Dim_Client"}}, "Property": "client_region"}}],
      "isPinned": true
    },
    {
      "queryRefs": ["Dim_Client.age_group_current"],
      "isCollapsed": true,
      "isPinned": true
    }
  ],
  "root": {
    "children": [
      {"identityValues": [{"Literal": {"Value": "'Midwest'"}}], "isToggled": true}
    ]
  }
}]
```

---

## 3. Conditional Formatting (`objects.values` & `objects.columnFormatting`)

### Kiểu Swift (`VisualFormat.swift`)
```swift
enum RuleComparisonOp: Int, Hashable, Sendable {
    case equal = 0
    case greaterThan = 1
    case greaterOrEqual = 2
    case lessThan = 3
    case lessOrEqual = 4
}

struct ConditionalRuleCase: Hashable, Sendable {
    var minOp: RuleComparisonOp?
    var minValue: Double?
    var minIsPercent: Bool = false
    var maxOp: RuleComparisonOp?
    var maxValue: Double?
    var maxIsPercent: Bool = false
    var color: ReportLiteral
}

struct ConditionalColorRule: Hashable, Sendable {
    var property: String          // "backColor" hoặc "fontColor"
    var target: String?           // selector.metadata
    var sourceTable: String
    var sourceMeasure: String
    var cases: [ConditionalRuleCase]
    var matchingOption: Int       // 1 = Values only, 2 = Values and totals, 3 = Totals only
}

struct DataBarRule: Hashable, Sendable {
    var target: String            // selector.metadata
    var positiveColor: ReportLiteral
    var negativeColor: ReportLiteral
    var axisColor: ReportLiteral
    var reverseDirection: Bool = false
    var hideText: Bool = false
    var totalMatchingOption: Int = 1
    var minValue: Double?
    var maxValue: Double?
}
```
### JSON PBIR (đã xác nhận `VM-V11B`)
- **Data Bars:** `visual.objects.columnFormatting[].properties.dataBars` với `selector: {"metadata": "<queryRef>"}`.
- **Rules:** `visual.objects.values[].properties.{backColor|fontColor}.solid.color.expr.Conditional.Cases` với `selector: {"data": [{"dataViewWildcard": {"matchingOption": 1}}], "metadata": "<queryRef>"}`.
- **Gradient:** `visual.objects.values[].properties.{backColor|fontColor}.solid.color.expr.FillRule` (`linearGradient2` / `linearGradient3`).
- **Field Value:** `visual.objects.values[].properties.{backColor|fontColor}.solid.color.expr.Measure`.

---

## 4. Analytics Reference Lines (`objects.y1AxisReferenceLine` & `objects.referenceLine`)

### Kiểu Swift (`VisualFormat.swift`)
```swift
enum AnalyticsLineStyle: String, Hashable, Sendable {
    case dashed, solid, dotted
}

struct ConstantReferenceLine: Hashable, Sendable {
    var id: String
    var displayName: String
    var show: Bool = true
    var value: Double
    var color: ReportLiteral?
    var style: AnalyticsLineStyle = .dashed
    var transparency: Double = 0
}

enum DynamicReferenceKind: Int, Hashable, Sendable {
    case average = 1
    case min = 3
    case max = 4
}

struct DynamicReferenceLine: Hashable, Sendable {
    var id: String
    var displayName: String
    var show: Bool = true
    var kind: DynamicReferenceKind
    var target: String?           // SelectRef.ExpressionName / selector.metadata
    var color: ReportLiteral?
    var style: AnalyticsLineStyle = .dashed
}
```
### JSON PBIR (đã xác nhận `VM-V11B` `b2-q11.visual.json`)
- Constant line → `objects.y1AxisReferenceLine` (`show`, `displayName`, `value`, `lineColor`, `style`, `selector: {"id": "..."}`).
- Average / Min / Max → `objects.referenceLine` (`show`, `displayName`, `value.expr.Aggregation.{Expression.SelectRef.ExpressionName, Function: 1|3|4}`, `selector: {"metadata": "...", "id": "..."}`).

---

## 5. Theme Preset & Custom Theme (`report.json`)

```swift
struct ThemePreset: Identifiable, Hashable, Sendable {
    let id: String                // e.g. "BIPro_Executive"
    let fileName: String          // e.g. "BIPro_Executive.json"
    let titleVI: String
    let titleEN: String
    let swatches: [String]        // 6 mã màu hex xem trước
    let jsonData: Data            // Tệp Power BI theme JSON hợp lệ
}
```
- Khi áp dụng preset hoặc file `.json` nhập từ ngoài:
  1. Lưu tệp JSON vào `Report/StaticResources/RegisteredResources/<fileName>`.
  2. `PBIRResourcePatch.settingCustomTheme(name:path:to:)` cập nhật `themeCollection.customTheme` (`type: "RegisteredResources"`) và mục `{"name": "<fileName>", "path": "<fileName>", "type": "CustomTheme"}` trong `resourcePackages[RegisteredResources].items` (thay thế mục `CustomTheme` cũ nếu có).

---

## 6. Làm mới dữ liệu (Refresh) & Cascade Rename

### Refresh Status Model (`BIPro`)
```swift
struct TableRefreshResult: Identifiable, Sendable {
    enum Status: Sendable {
        case pending, running
        case succeeded(oldRows: Int, newRows: Int, durationMs: Int)
        case skipped(reason: String)   // Enter Data, bảng tính toán DAX
        case failed(error: String)
    }
    let id: String   // tên bảng
    var status: Status
}
```

### Cascade Rename Plan (`BIPro`)
```swift
enum RenameTarget: Hashable, Sendable {
    case table(old: String, new: String)
    case column(table: String, old: String, new: String)
    case measure(table: String, old: String, new: String)
}

struct CascadeRenamePlan: Sendable {
    var target: RenameTarget
    var daxRewrites: [(owner: String, oldExpr: String, newExpr: String)]
    var pbirFilesAffected: Int
    var totalReferences: Int
}
```

---

## 7. Mở rộng DAX Engine (Window & Table Clauses)

```swift
struct WindowOrderSpec {
    var expr: BoundExpr
    var descending: Bool
}

enum WindowBoundKind: String {
    case absolute = "ABS"
    case relative = "REL"
}
```
- **Mệnh đề hàm:** `ORDERBY` và `PARTITIONBY` được phân tích trong `Binder` thành các đối số đặc biệt để `OFFSET`, `INDEX`, `WINDOW` tách và thực thi phân vùng (partition) + sắp xếp ổn định trước khi chọn dòng tương đối (`REL`) hoặc tuyệt đối (`ABS`).
- **Quy tắc ngữ nghĩa đã khoá theo `dax-golden.json`:**
  - `UNION` & `INTERSECT` giữ bản sao theo multiset (`INTERSECT` giữ số lượng bản sao theo bảng bên trái).
  - `COUNTBLANK` trả `.blank` (không phải `0`) khi không có ô trống.
  - `WEEKNUM(..., 21)` tính tuần ISO 8601 (tuần 1 là tuần chứa ngày Thứ Năm đầu tiên / ngày 4 tháng 1).
  - `TIME(h, m, s)` chuẩn hoá tổng giây theo modulo `86_400` về khoảng `[0, 1)` (ngày `1899-12-30`).
  - `CALENDARAUTO([fyEndMonth])` trả bảng 1 cột `[Date]` phủ trọn các năm tài chính chứa mọi giá trị ngày hợp lệ trong mô hình.
