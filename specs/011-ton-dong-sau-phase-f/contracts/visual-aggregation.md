# Hợp đồng: trường gộp ngầm trong truy vấn visual (US1)

Chủ: lead (`Sources/BIPro/Visuals/Query/`, `Sources/BIPro/Report/Edit/`).

```swift
enum AggregateFunction: Int, CaseIterable, Sendable {   // rawValue = mã PBIR (VM-F10)
    case sum = 0, average = 1, countDistinct = 2, min = 3, max = 4, count = 5, median = 6, standardDeviation = 7, variance = 8
    var daxFunction: String     // SUM, AVERAGE, DISTINCTCOUNT, MIN, MAX, COUNTA, MEDIAN, STDEV.P, VAR.P
    var resultPrefix: String    // Sum, Average, DistinctCount, Min, Max, Count, Median, StandardDeviation, Variance
    func label(column:kind:) -> String   // "Tổng của X"; chữ: "Đầu tiên/Cuối cùng của X"; ngày: "Sớm nhất/Muộn nhất của X"
    static func menu(for: ColumnKind) -> [AggregateFunction]
}
struct QueryMeasure {           // thêm (thay cho enum Source của bản nháp: ít đụng chạm hơn)
    var aggregation: AggregateFunction? = nil   // khác nil: `measure` là tên cột, biểu thức CALCULATE(<HÀM>('T'[cột]))
}
```

Bản nháp ghi mã `[SUY ĐOÁN]` 2 = CountNonNull, 5 = DistinctCount; VM-F10 cho thấy ngược lại (2 = Count (Distinct), 5 = Count).
Visual không trục, không bộ lọc, không tô sáng: `EVALUATE ROW("…", …)` không IGNORE (VM-F10).

- `VisualQuerySpecReader`: trường `{"Aggregation": {"Expression": {"Column": …}, "Function": n}}` (PBIR và layout cũ) → `.aggregation`.
- `DAXQueryBuilder`: `.aggregation` → biểu thức và tên cột kết quả đúng văn bản Performance Analyzer (golden VM-F10).
- `WellRules.accepts(column:in:model:)`: ô giá trị nhận cột khi `!model.discourageImplicitMeasures`; trả phép gộp mặc định.
- Ghi: `PBIRNewVisual`/`PBIRQueryPatch`/`LegacyLayoutPatch` ghi `Aggregation` y như Desktop (`queryRef`, `nativeQueryRef`).
- Bất biến: golden 72 truy vấn visual (toàn measure) giữ nguyên văn bản.
