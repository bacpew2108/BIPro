# Quan sát Power BI Desktop — VM-V11A: Biểu đồ, Slicer nâng cao & Phần tử chèn (2026-11-21)

**Môi trường:** Power BI Desktop 2.159 trên VM Windows 11 (Parallels), theo sự cho phép của người dùng ("nên làm VM trước chứ không suy đoán").
**Dữ liệu nguồn:** Bản sao chỉ-đọc `Nhom6_work.pbix` tại `C:\Temp\vm-v11a\obs.pbix` (đã đóng Desktop và xoá sạch sau buổi quan sát).
**Lược đồ PBIR (`$schema`):** `visualContainer/2.14.0/schema.json`.
**Bằng chứng:** 28 tệp JSON nguyên văn trong `json/` (`empty-*.visual.json`, `pop-*.visual.json`, `insert-*.visual.json`) và 2 ảnh cắt chỉ giữ vùng canvas (`desktop-batch2-visuals.png`, `desktop-batch3-elements.png`).

---

## 1. Tên `visualType` chính xác & Khung trống mặc định (Batch 1)

Tất cả visual tạo từ thư viện *Build visual* trên trang trống có kích thước mặc định **280×280** (hàng cuối sát mép dưới trang co còn `280×210`), và khi chưa có trường chỉ chứa đúng hai khoá trong `visual`: `visualType` và `drillFilterOtherVisuals: true`.

| Tên hiển thị Power BI Desktop | `visualType` thực tế ghi vào PBIR | Lưu ý quan trọng |
|---|---|---|
| Stacked bar chart | **`barChart`** | **Không** phải `stackedBarChart`! Giống cột xếp chồng ghi `columnChart`. |
| 100% stacked bar chart | `hundredPercentStackedBarChart` | — |
| Pie chart | `pieChart` | Hình tròn đặc không lỗ giữa, nhãn callout + chú giải |
| Table | `tableEx` | Bảng phẳng nhiều cột + dòng **Total** in đậm ở cuối |
| Scatter chart | `scatterChart` | Chấm tròn trên trục X/Y, chia màu theo Legend (`Series`), cỡ theo `Size` |
| Gauge | `gauge` | Cung bán nguyệt 180°; khi không có `MaxValue`, mặc định `Max = 2 × Value` (`5,369` → `0K`..`11K`) |
| KPI | `kpi` | Số chỉ báo lớn ở giữa (`1` = giá trị điểm mới nhất của trục Trend) đặt trên biểu đồ vùng nền xám nhạt |
| Button / Tile slicer | `advancedSlicerVisual` | Lưới các nút bo góc màu trắng (`Midwest`, `Northeast`, `South`, `West`) |
| List slicer | `listSlicer` | Danh sách chọn có ô radio/tick |
| Text slicer | `textSlicer` | Ô nhập văn bản lọc (`Enter <column>` + mũi tên `→`) |
| Slicer cổ điển (cột số) | `slicer` | Tự động ghi `objects.data[0].properties.mode = "'Between'"`, vẽ 2 ô Min/Max + thanh trượt 2 đầu (`1931`..`2007`) |
| Map | `map` | Bản đồ điểm (bong bóng theo `Size`) |
| Filled map | `filledMap` | Bản đồ tô màu theo vùng địa lý |

---

## 2. Cấu trúc `queryState`, `sortDefinition` & `objects` khi thả trường (Batch 2)

| `visualType` | Các ô `queryState` quan sát được | `active: true` trên cột | `sortDefinition` tự thêm | `objects` mặc định |
|---|---|---|---|---|
| `barChart` | `Category`, `Y` *(+ `Series`, `Tooltips`)* | Có (`Category`) | Có (giảm dần theo `Y`) | — |
| `hundredPercentStackedBarChart` | `Category`, `Y` *(+ `Series`, `Tooltips`)* | Có (`Category`) | Có (giảm dần theo `Y`) | — |
| `pieChart` | `Category`, `Y` *(+ `Series`, `Tooltips`)* | Có (`Category`) | Có (giảm dần theo `Y`) | — |
| `tableEx` | `Values` (trộn lẫn cột và measure theo thứ tự thêm) | **Không** | **Không** | — |
| `scatterChart` | `Category` (Values), `Series` (Legend), `X`, `Y`, `Size` | Có (`Category`, `X` khi là measure đầu?) | **Không** | — |
| `gauge` | `Y` (Value) *(+ `MinValue`, `MaxValue`, `TargetValue`)* | — | Có (giảm dần theo `Y`) | — |
| `kpi` | `Indicator` (Value), `TrendLine` (Trend axis) *(+ `Goal`)* | **Không** | **Không** | — |
| `advancedSlicerVisual` | `Values` | **Không** | **Không** | — |
| `listSlicer` | `Values` | **Không** | **Không** | — |
| `textSlicer` | `Values` | **Không** | **Không** | — |
| `slicer` (số) | `Values` | Có (`Values`) | **Không** | `data[0].mode = "'Between'"` |
| `map` | `Category` (Location), `Size` (Bubble size) *(+ `Series`, `Y`)* | Có (`Category`) | **Không** | — |
| `filledMap` | `Category` (Location), `Tooltips` *(+ `Series`, `Y`)* | Có (`Category`) | **Không** | — |

---

## 3. Phần tử chèn từ Ribbon *Insert* (Batch 3)

Tất cả 4 phần tử chèn đều ghi thêm khoá gốc `"howCreated": "InsertVisualButton"`:

| Phần tử | `visualType` | Kích thước mặc định | `objects` mặc định |
|---|---|---|---|
| Shape (Rectangle) | `shape` | `280 × 280` | `shape[0].tileShape = "'rectangle'"`, `rotation[0].shapeAngle = "0L"` |
| Page navigator | `pageNavigator` | `1000 × 50` | *(không có)* |
| Bookmark navigator | `bookmarkNavigator` | `600 × 50` | *(không có)* |
| Blank button | `actionButton` | `100 × 40` | `icon[0]{shapeType: "'blank'", selector: {id: "default"}}` |

*(Ghi chú: `multiRowCard` đã bị Microsoft ẩn khỏi thư viện mặc định trên Desktop 2.159 vì được thay bằng `cardVisual` mới, tuy nhiên các tệp `.pbix` cũ vẫn chứa `visualType: "multiRowCard"` với ô `Values`, nên BI Pro vẫn hỗ trợ vẽ đọc/hiển thị cho tệp mở có `multiRowCard`.)*
