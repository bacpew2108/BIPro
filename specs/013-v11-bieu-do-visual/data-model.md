# Mô hình dữ liệu: Đợt 2 (v1.1a) — `specs/013-v11-bieu-do-visual`

## 1. Mở rộng `enum DataView` (`Sources/BIPro/Visuals/Query/DataView.swift`)

```swift
enum DataView: Hashable, Sendable {
    case empty(reason: String)
    case single(SingleValueData)
    case categorical(CategoricalData)
    case matrix(MatrixData)
    case slicer(SlicerData)
    // Mới ở Đợt 2 (v1.1a):
    case table(TableDataView)
    case scatter(ScatterData)
    case gauge(GaugeData)
    case kpi(KPIData)
    case multiRowCard(MultiRowCardData)
}
```

### Chi tiết các kiểu mới

| Kiểu | Thuộc tính chính | Quy tắc dữ liệu |
|---|---|---|
| `TableDataView` | `columns: [FieldInfo]`, `rows: [[DataCell]]`, `totals: [DataCell]?`, `isReduced: Bool` | `columns` giữ nguyên thứ tự trong ô `Values` của `tableEx`. `totals` cùng chiều dài `columns` (ô cột danh mục là `.blank`, ô measure là tổng cộng từ DAX). |
| `ScatterPoint` | `id: DataPointID`, `categoryLabel: String`, `seriesValue: Value?`, `x: Double`, `y: Double`, `size: Double?`, `xCell: DataCell`, `yCell: DataCell`, `sizeCell: DataCell?`, `tooltips: [(String, DataCell)]` | Bỏ điểm mà `x` hoặc `y` là BLANK/NaN; nếu chỉ có `X` mà chưa có `Y` (như trạng thái trung gian vừa tick 1 measure) dùng `y = 0` để vẽ dải 1D giống Desktop (`desktop-batch2-visuals.png`). |
| `ScatterData` | `categoryField: FieldInfo?`, `seriesField: FieldInfo?`, `series: [Value]`, `xField: FieldInfo?`, `yField: FieldInfo?`, `sizeField: FieldInfo?`, `points: [ScatterPoint]`, `isReduced: Bool` | — |
| `GaugeData` | `valueField: FieldInfo`, `value: DataCell`, `min: DataCell?`, `max: DataCell?`, `target: DataCell?` | Khi `min == nil` dùng `0`; khi `max == nil` dùng `max(value * 2, value > 0 ? value * 2 : 1)` (đã quan sát `VM-V11A`: `5,369 → 0K..11K`). |
| `KPITrendPoint` | `label: String`, `value: Double` | Sắp tăng dần theo `TrendLine`. |
| `KPIData` | `indicatorField: FieldInfo`, `trendField: FieldInfo?`, `goalField: FieldInfo?`, `latestValue: DataCell`, `goalValue: DataCell?`, `trendPoints: [KPITrendPoint]` | Giá trị hiển thị lớn là điểm cuối cùng của `trendPoints` (hoặc tổng `Indicator` nếu chưa có `TrendLine`). |
| `MultiRowCardData` | `fields: [FieldInfo]`, `rows: [[DataCell]]`, `isReduced: Bool` | Mỗi phần tử của `rows` là một thẻ hàng. |

---

## 2. Mở rộng `SlicerData` & `SlicerSelection`

```swift
struct SlicerRange: Hashable, Sendable {
    var min: Value?
    var max: Value?
    var isEmpty: Bool { min == nil && max == nil }
}

struct SlicerSelection: Hashable, Sendable {
    var paths: Set<[Value]>
    var range: SlicerRange? = nil
    var searchText: String? = nil

    var isEmpty: Bool {
        paths.isEmpty && (range?.isEmpty ?? true) && (searchText?.isEmpty ?? true)
    }
}
```

- `SlicerData` bổ sung tuỳ chọn `domainRange: SlicerRange? = nil` (biên nhỏ nhất & lớn nhất toàn miền cho `slicer` chế độ `'Between'`) và `isDateColumn: Bool = false`.

---

## 3. Mở rộng `WellRules.observed` (`Sources/BIPro/Report/Edit/WellRules.swift`)

Đổi kiểu giá trị của bảng `observed` từ `(kind: WellKind, single: Bool)` sang `(accepts: Set<WellKind>, single: Bool)` để hỗ trợ ô hỗn hợp `Values` của `tableEx` và `multiRowCard`:

| `visualType` | Luật ô (`VM-V11A`) |
|---|---|
| `barChart`, `stackedBarChart`, `hundredPercentStackedBarChart` | `Category` (`[.column]`, single), `Series` (`[.column]`, single), `Y` (`[.measure]`, multi), `Tooltips` (`[.measure]`, multi) |
| `pieChart` | `Category` (`[.column]`, multi), `Series` (`[.column]`, single), `Y` (`[.measure]`, multi), `Tooltips` (`[.measure]`, multi) |
| `tableEx`, `multiRowCard` | `Values` (`[.column, .measure]`, multi) |
| `scatterChart` | `Category` (`[.column]`, single), `Series` (`[.column]`, single), `X` (`[.measure]`, single), `Y` (`[.measure]`, single), `Size` (`[.measure]`, single), `Tooltips` (`[.measure]`, multi) |
| `gauge` | `Y` (`[.measure]`, single), `MinValue` (`[.measure]`, single), `MaxValue` (`[.measure]`, single), `TargetValue` (`[.measure]`, single), `Tooltips` (`[.measure]`, multi) |
| `kpi` | `Indicator` (`[.measure]`, single), `TrendLine` (`[.column]`, single), `Goal` (`[.measure]`, single) |
| `advancedSlicerVisual`, `listSlicer`, `textSlicer` | `Values` (`[.column]`, single) |
| `map` | `Category` (`[.column]`, single), `Series` (`[.column]`, single), `Size` (`[.measure]`, single), `Tooltips` (`[.measure]`, multi) |
| `filledMap` | `Category` (`[.column]`, single), `Series` (`[.column]`, single), `Y` (`[.measure]`, single), `Tooltips` (`[.measure]`, multi) |
