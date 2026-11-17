# VM-F10 (T009): phép gộp ngầm trong Power BI Desktop

Ngày 2026-11-17, Desktop 2.159, Claude lái VM. Tài liệu mới (Blank report), nạp `build/f2-out/samples/sales_2026.xlsx` (trang Sales, 500 dòng) qua "Import data from Excel". File Desktop lưu: `f10-desktop.pbix` (ngoài git). Performance Analyzer xuất: `pa-f10.json` (golden văn bản truy vấn). Ảnh đã cắt: `a1`–`a7`.

## 1. Phép gộp mặc định theo `Column.SummarizeBy`

Mô hình mới: `Model.DiscourageImplicitMeasures = 0`. Desktop đặt `SummarizeBy` khi nạp (đọc từ `metadata.sqlitedb`):

| Cột | Kiểu | `SummarizeBy` | Kéo hoặc tích vào ô giá trị thành |
|---|---|---|---|
| Amount, Price (số thực), Qty (số nguyên) | 8 / 6 | 3 (Sum) | "Sum of X", Function 0 |
| OrderID, CustomerID, ProductID (số nguyên, tên kết thúc bằng "ID") | 6 | 6 (Count) | "Count of X", Function 5 |
| Region (chữ) | 2 | 2 (None) | card ô Value: "First Region", Function 3 (Min) |
| OrderDate, OrderTime (ngày, ngày giờ) | 9 | 2 (None) | (không quan sát được, xem mục 6) |

- Data pane vẫn hiện Σ cho cột ID, nhưng phép gộp mặc định là Count (`a3`).
- Tích một cột số khi chưa chọn visual thì Desktop tạo **biểu đồ cột nhóm** (`clusteredColumnChart`) với cột ở Y-axis (`a1`).
- Khi đang chọn visual, tích thêm cột số thì cột vào Y-axis với phép gộp mặc định, tích cột chữ thì vào X-axis.
- Tích cột ngày thì tạo bảng theo phân cấp ngày Year/Quarter/Month/Day (Auto date/time, ghi ở VM-F11).

## 2. Menu phép gộp của trường (mũi tên ở trường trong ô)

- **Cột số** (`a2`): Remove field, Rename for this visual, Move/Move to, rồi **Sum, Average, Minimum, Maximum, Count (Distinct), Count, Standard deviation, Variance, Median** (dấu tích ở mục đang chọn), Show value as ▸, New quick measure.
- **Cột chữ** (`a7`): **First, Last, Count (Distinct), Count**, New quick measure.
- Menu mở lên trên khi trường nằm thấp.

## 3. PBIR lưu trường gộp

```json
{"field": {"Aggregation": {"Expression": {"Column": {"Expression": {"SourceRef": {"Entity": "Sales"}}, "Property": "Amount"}},
           "Function": 1}},
 "queryRef": "Sum(Sales.Amount)", "nativeQueryRef": "Average of Amount"}
```

| Phép gộp (menu) | `Function` | Nhãn (`nativeQueryRef`) | DAX Performance Analyzer | Tên cột kết quả |
|---|---|---|---|---|
| Sum | 0 | Sum of X | `CALCULATE(SUM('T'[X]))` | `SumX` |
| Average | 1 | Average of X | `CALCULATE(AVERAGE('T'[X]))` | `AverageX` |
| Count (Distinct) | 2 | Count of X | `CALCULATE(DISTINCTCOUNT('T'[X]))` | `DistinctCountX` |
| Minimum / First (chữ) | 3 | Min of X / X | `CALCULATE(MIN('T'[X]))` | `MinX` |
| Maximum / Last (chữ, [SUY ĐOÁN]) | 4 | Max of X | `CALCULATE(MAX('T'[X]))` | `MaxX` |
| Count | 5 | Count of X | `CALCULATE(COUNTA('T'[X]))` | `CountX` |
| Median | 6 | Median of X | `CALCULATE(MEDIAN('T'[X]))` | `MedianX` |
| Standard deviation | 7 | Standard deviation of X | `CALCULATE(STDEV.P('T'[X]))` | `StandardDeviationX` |
| Variance | 8 | Variance of X | `CALCULATE(VAR.P('T'[X]))` | `VarianceX` |

Ghi chú:
- **`queryRef` giữ phép gộp lúc trường được thêm** (Sum hay CountNonNull) và không đổi khi đổi phép gộp trong menu, ví dụ "Average of Amount" vẫn có `queryRef` `Sum(Sales.Amount)`. Chỉ `Function` và `nativeQueryRef` đổi.
- Count và Count (Distinct) cùng nhãn "Count of X" (`a4`). Trong file, trường CustomerID sau khi đổi sang Count (Distinct) có `nativeQueryRef` "Count of CustomerID1": Desktop thêm hậu tố cho khỏi trùng nhãn khác trong cùng visual ([SUY ĐOÁN] cơ chế; "Count of OrderID" không trùng chữ, có thể Desktop so khoá nội bộ).
- Card mới (`cardVisual`): ô Value lưu với vai trò `Data`, `nativeQueryRef` là tên cột trần ("Region") dù nhãn hiện "First Region".
- Dời trường từ Categories sang Value qua menu "Move to ▸ Value".

## 4. Truy vấn DAX (Performance Analyzer, nguyên văn ở `pa-f10.json`)

Biểu đồ cột không có trục X:

```
EVALUATE
	ROW(
		"AverageAmount", CALCULATE(AVERAGE('Sales'[Amount])),
		"DistinctCountCustomerID", CALCULATE(DISTINCTCOUNT('Sales'[CustomerID])),
		"CountOrderID", CALCULATE(COUNTA('Sales'[OrderID])),
		"MaxPrice", CALCULATE(MAX('Sales'[Price])),
		"StandardDeviationProductID", CALCULATE(STDEV.P('Sales'[ProductID])),
		"MinQty", CALCULATE(MIN('Sales'[Qty]))
	)
```

Biểu đồ cột theo Region: `SUMMARIZECOLUMNS('Sales'[Region], "SumAmount", CALCULATE(SUM('Sales'[Amount])), "VarianceQty", CALCULATE(VAR.P('Sales'[Qty])), "MedianPrice", CALCULATE(MEDIAN('Sales'[Price])))`, rồi `TOPN(1001, __DS0Core, [SumAmount], 0, 'Sales'[Region], 1)` và `ORDER BY [SumAmount] DESC, 'Sales'[Region]`. Cùng khuôn như measure (Phase C); chỉ thay `[Measure]` bằng `CALCULATE(<HÀM>('T'[C]))`.

Card cột chữ: `EVALUATE ROW("MinRegion", CALCULATE(MIN('Sales'[Region])))`.

## 5. Phân cấp ngày (dùng cho VM-F11b)

- Trường lưu dạng `HierarchyLevel` → `Hierarchy` → `PropertyVariationSource {Entity: Sales, Name: "Variation", Property: "OrderDate"}`, `Hierarchy: "Date Hierarchy"`, `Level: "Year"`. `queryRef` `Sales.OrderDate.Variation.Date Hierarchy.Year`, `nativeQueryRef` "OrderDate Year".
- Truy vấn: `SUMMARIZE('LocalDateTable_<guid>', [Year], [Quarter], [QuarterNo], [Month], [MonthNo], [Day])`, `TOPN(21, …)` sắp theo Year, QuarterNo, Quarter, MonthNo, Month, Day.

## 6. Chưa quan sát được

- Phép gộp của cột ngày trong ô Value (Earliest/Latest?): menu trường phân cấp ngày trong card không mở được khi lái VM. Để `[SUY ĐOÁN]`: theo nhãn Desktop "Earliest"/"Latest", Function 3/4. Kiểm lại ở gate T016 nếu tiện.
- Phép gộp "Last" của cột chữ: chưa chọn thử, suy ra Function 4 (Max).
- Kéo cùng cột hai lần: kéo thả trong Desktop không ăn khi lái bằng cliclick. Hiện tượng "Count of CustomerID1" ở trên cho thấy Desktop thêm số vào nhãn để khỏi trùng.
