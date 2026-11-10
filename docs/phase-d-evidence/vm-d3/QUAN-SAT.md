# Quan sát VM-D3 (2026-11-10)

Làm bởi Claude, điều khiển VM Windows 11 (Parallels) theo lời cho phép một lần của người dùng; Power BI Desktop 2.159.x. Bản gốc `Nhom6_work.pbix` chép sang `C:\Users\bacpew\vmd3\base.pbix` (không ghi vào `~/Downloads`). Mỗi bước Lưu thành (Save As) trong VM rồi chép về đây. `$schema` của `visual.json` mọi file: **2.14.0**.

## A. Thêm visual vào trang trống (`R-D3-a-all-types.pbix`, trang `Page 1`)

Thêm 11 loại bằng thư viện, chưa thả trường.

- `visual.json` chỉ có: `$schema`, `name`, `position`, `visual{visualType, drillFilterOtherVisuals:true}`. Không có `query`, `objects`, `sortDefinition`. Thứ tự khoá và `position{x,y,z,height,width,tabOrder}` **trùng** `PBIRNewVisual` của BI Pro.
- `name`: 20 ký tự hex ngẫu nhiên (một mã chỉ toàn chữ số: `90904707620404647000`).
- `z` và `tabOrder` bằng nhau; trang trống bắt đầu từ 0, tăng 1 mỗi visual.
- **Nút "Card" trong thư viện ghi `cardVisual`** (card mới, có chỗ cho ảnh), không phải `card` như trong Nhom6. Ô của `cardVisual` tên `Data`. Loại khác: `clusteredColumnChart`, `clusteredBarChart`, `lineChart`, `lineClusteredColumnComboChart`, `donutChart`, `treemap`, `pivotTable`, `slicer`, `textbox`, `shapeMap`.
- Cỡ mặc định trên trang trống: **280×280** (ô lưới 10 px, cột xếp từ trên xuống rồi sang phải: x=10, 300, 590; y=0, 290, 580, 870); visual gần đáy trang bị co chiều cao còn 210 (870+210=1080, hết trang). Hộp văn bản mới: **không có `objects`**.

## B. Thả trường vào visual mới (`R-D3-b-fields.pbix`, `R-D3-b-card-bo-het.pbix`, `R-D3-b-*-query.txt`)

- Tick một **measure** vào card, cột nhóm, đường: Desktop ghi `query.queryState.<ô>.projections[]` (`field`, `queryRef:"Bảng.Tên"`, `nativeQueryRef:"Tên"`) và **tự thêm** `query.sortDefinition{sort:[{field, direction:"Descending"}], isDefaultSort:true}` theo chính measure đó. BI Pro hiện không ghi `sortDefinition`.
- Ô: `cardVisual` → `Data`; `clusteredColumnChart`/`lineChart` → `Y`; `slicer` → `Values`; `pivotTable` → `Rows` (cột), `Values` (measure).
- **Cột** trong ô Rows/Values/Category: projection có thêm `"active": true`; measure thì không.
- Slicer có trường: Desktop thêm `objects.data[0].properties.mode = 'Basic'` (literal `'Basic'`). Matrix: không có `sortDefinition`.
- **Bỏ hết trường của card**: `visual.json` quay về dạng trống `{visualType, drillFilterOtherVisuals}`; **không** để lại `queryState` rỗng hay `sortDefinition`.
- Truy vấn Performance Analyzer đã chép: `cardVisual` (`SUMMARIZECOLUMNS` với hai bộ lọc báo cáo `year<>9999`, `client_region<>"Unknown"` và `IGNORE(measure)`), matrix, slicer (`SUMMARIZE(VALUES('Dim_Date'), month_name, month_num)` + `TOPN(101…)` + `ORDER BY`), hai biểu đồ chỉ có measure.

## C. Đổi loại (D1 gốc; mỗi file đổi đúng một visual, hoàn tác giữa các lần)

| Đổi | Ô | `objects` | Khác |
|---|---|---|---|
| đường → thanh nhóm (`R-D3-c-duong-sang-thanh`) | tên ô giữ nguyên (`Category`, `Y`, `Tooltips`), mọi trường giữ | bỏ `forecast`; giữ `categoryAxis`, `labels`, `trend`, `valueAxis` | thêm `sortDefinition` tăng dần theo cột Category, `isDefaultSort:true`; vị trí, cỡ, `visualContainerObjects` giữ |
| đường → cột nhóm (`R-D3-c-duong-sang-cot`) | như trên | như trên | như trên |
| combo cột+đường → đường (`R-D3-c-combo-sang-duong`) | **giữ nguyên cả `Category` (3 cấp), `Y`, `Y2`**: Desktop không gộp `Y2` vào `Y`; `lineChart` có ô `Y2` ("Secondary y-axis") | không đổi | chỉ `visualType` đổi |
| donut → treemap (`R-D3-c-donut-sang-treemap`) | `Category`→`Group` (**giữ cả 3 cấp**), `Y`→`Values`, `Tooltips` giữ | bỏ `value`; giữ `dataPoint`, `labels`, `legend` | |
| combo → donut (`R-D3-c-combo-sang-donut`) | `Category` giữ 3 cấp; `Y` và `Y2` **gộp** thành một ô `Y` (3 measure) | bỏ `valueAxis`; giữ `dataPoint`, `labels`, `legend` | |
| card (measure) → slicer (`R-D3-c-card-sang-slicer`) | **không đổi gì**: bấm Slicer, visual vẫn là card; file lưu không khác bản gốc | | slicer không nhận measure |

Quy tắc suy ra: Desktop chỉ bỏ khoá `objects` không còn hợp lệ cho loại mới, giữ phần còn lại; trường chỉ bị gộp hoặc bỏ khi ô đích không có; ô đích cùng vai trò (`Y2` ở combo → đường) giữ vai trò nếu loại mới có ô đó.

## D. Vị trí khi thêm trên trang đã có visual (`R-D3-d-trang-day`, `-hai-card`, `-zoom-2`)

- Card thêm vào D1 (đã 36 visual, `z` lớn nhất 37000): `position {x:100, y:100, width:300, height:300, z:37001, tabOrder:37001}`.
- Thêm liên tiếp ba card: đều ở (100,100), `z` 37001, 37002, 37003: **không dời** nhau.
- Thu phóng 200% và cuộn xuống góc phải dưới không đổi vị trí (100,100): vị trí không theo vùng nhìn thấy; Desktop cuộn tới visual vừa thêm.
- Trang trống: lưới 280×280 như A (khác trang đã có visual).

## E. Hộp văn bản (`R-D3-e-textbox*.pbix`)

- Gõ "Tieu de thu": `objects.general[0].properties.paragraphs[0].textRuns[0].value`; không có `textStyle`. Cấu trúc trùng `PBIRVisualPatch.setText` của BI Pro.
- Xuống dòng (Enter) tạo thêm một phần tử `paragraphs[]`.
- Sửa chữ làm `z` và `tabOrder` của hộp văn bản đổi từ 10 lên 10000 (Desktop đưa lên trên cùng khi sửa).

## Chưa làm được / chưa kiểm

- Truy vấn Performance Analyzer cho các visual đã đổi loại (C) chưa chép; thân truy vấn B đã chép.
- Cột nhóm xếp chồng, thanh xếp chồng, vùng, 100% thanh: chỉ biết tên loại ở thư viện, chưa thêm và lưu thử. Chưa quan sát ô của `cardVisual` ngoài `Data` (chỉ ô `Data` có trường).
- Gõ chữ có dấu vào hộp văn bản chưa thử (dùng ASCII vì điều khiển bàn phím từ xa).
