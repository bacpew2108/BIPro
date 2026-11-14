# VM-D12: bốn mục còn lại của Phase D (2026-11-14)

Bạn cho phép dùng VM. Claude điều khiển Power BI Desktop trên bản sao `Nhom6_work.pbix` (trong VM, đã xoá cùng thư mục thử và bản chép về Mac). Chỉ thao tác giao diện, lưu, đọc diff `visual.json` / `report.json`. Mẫu trong `json/`. Mọi bản thử đều đi từ biểu đồ đường "Giá trị giao dịch…" của D1 (Category `Dim_Date[month_start]`, không có `sortDefinition`), trở lại bằng ⌘Z rồi lưu và kiểm `visualType` về `lineChart` trước khi thử loại tiếp (lần đầu chuỗi hoàn tác hỏng nên đã làm lại hết).

## 1. Sắp xếp mặc định khi đổi loại (`json/retype-*.visual.json`)

Đổi đường → loại khác, Desktop thêm `query.sortDefinition` = `[{field: Column Dim_Date.month_start, direction: "Ascending"}]`, `isDefaultSort: true` ở các loại: vùng, vùng xếp chồng, vùng 100%, hai loại combo (cột xếp chồng + đường, cột nhóm + đường), ruy-băng, thác nước, donut, phễu, **slicer** (`Values`), thẻ mới `cardVisual` (cột ngày vào ô `Rows`). Cùng với cột và thanh ở VM-D9.

**Không** thêm sắp xếp: treemap (`Group`), bảng `tableEx` (`Values`), matrix `pivotTable` (`Rows`), KPI, bản đồ hình `shapeMap`.

Cách Desktop xếp ô khi đổi đường sang loại khác (Category ngày, Y và Tooltips là measure):

| Đích | Ô nhận |
|---|---|
| vùng, combo, ruy-băng, thác nước, donut, phễu | `Category` (cột ngày), `Y`, `Tooltips` giữ nguyên |
| slicer | `Values` = cột ngày (`active: true`); measure bị bỏ |
| matrix | `Rows` = cột ngày; `Values` = các measure của `Y` rồi `Tooltips` |
| treemap | `Group`, `Values`, `Tooltips` |
| bản đồ hình | cột ngày vào `Series` (ô "Legend"), `Y` vào `Value` ("Color saturation"), `Tooltips`; Desktop tự thêm `objects.shape.map` trỏ `usa.states.topo` |
| `cardVisual` | `Data` = measure, `Rows` = cột ngày, `Tooltips` |

Đổi sang vùng bỏ khoá `forecast` (chỉ có ở đường), giữ `trend`, `valueAxis`, `labels`, `categoryAxis`.

BI Pro: `LayoutEditor.defaultSortRole` (thêm sắp xếp cho các loại trên, ô `Category` hoặc `Values` của slicer; chỉ khi cột là kiểu ngày và chưa có `sortDefinition`), `TypeChange.targetFallbacks` (Category → `Values` ở slicer, Category → `Rows` và Tooltips → `Values` ở matrix). Loại vùng, ruy-băng, thác nước, phễu, thẻ có `Rows` chưa có trong thư viện đích của BI Pro nên chưa dùng được; quy tắc đã sẵn khi thêm. **Chưa làm:** đích bản đồ hình (Category → `Series`, `Y` → `Value`, thêm `objects.shape`), vì đường vẽ bản đồ hình của BI Pro chỉ đọc ô `Category`.

## 2. Dọn tài nguyên khi xoá trang

Nhom6 có 17 mục `RegisteredResources` (16 icon `Image` + `Nhom6Theme.json`) và `SharedResources` (`Fluent2…` `BaseTheme`, `usa.states.topo` `ShapeMap`). Trang tham chiếu bằng `"ItemName":"<tên>"` trong `visual.json`.

1. Xoá D2 khi D1 đã có bản đồ hình (tạo bằng cách đổi biểu đồ đường, mục 1): `usa.states.topo` **còn**, file `Shapemaps/usa.states.topo.json` còn (D1 vẫn dùng). Icon dùng chung với trang khác còn.
2. Xoá D3: `icon_check_o.svg` và `icon_star_p.svg` (chỉ D3 dùng) **bị bỏ** khỏi `resourcePackages` và khỏi `Report/StaticResources/RegisteredResources/`; icon còn trang khác dùng, `usa.states.topo`, `Fluent2…`, `Nhom6Theme.json` còn. Danh sách ở `json/resourcePackages.json`.
3. Xoá trang cuối cùng dùng bản đồ hình: khớp VM-D8 (bỏ mục và file).

Quy tắc: mục `ShapeMap` hoặc `Image` bị bỏ khi mọi trang nhắc tới nó đã xoá; theme không bị đụng. **Kiểm ngược:** BI Pro xoá D2 và D3 khỏi `Nhom6_work.pbix` rồi lưu (`Nhom6_d12_xoa.pbix`, `D5Nhom6Tests.xoaTrangDonTaiNguyenNhuDesktop`); Power BI Desktop mở bình thường (2 trang, icon còn dùng hiện đúng, không báo lỗi). BI Pro: `PBIRResourcePatch` (ghép byte `items` của `resourcePackages`) và `LayoutEditor.addResourceChanges`; tính lại từ byte lúc mở mỗi lần lưu, nên hoàn tác xoá trang sau khi lưu đưa mục và file trở lại.

Ghi chú chưa giải thích được: khi còn ba trang, menu chuột phải của tab D1 (trang đầu, cũng là trang mở khi vào file) chỉ có "Set as landing page", "Duplicate", "Rename"; menu của các tab khác có thêm "Delete", "Hide", "Move to". Sau khi đặt trang khác làm landing page, menu của D1 vẫn như vậy (có thể do menu bị cắt ở mép cửa sổ). Không dựa vào đây để đổi hành vi xoá trang của BI Pro.

## 3. Giá trị mặc định công tắc ở visual mới (thẻ Format)

Mẫu: visual mới trên trang trống, Format > Visual.

| Visual | Công tắc | Mặc định |
|---|---|---|
| cột nhóm, có Chú giải | Legend | **On** (không có trường Chú giải: mờ, Off) |
| cột nhóm | Data labels, Zoom slider | Off |
| donut | Legend, Detail labels, Center value | **On** |
| slicer | Slicer header | **On** |
| matrix | Blank rows Off; Column subtotals, Row subtotals **On** | |
| thẻ `cardVisual` | (không có công tắc đầu thẻ ở mức trên) | |

BI Pro: `FormatCatalog` ghi `defaultOn` cho `legend.show` (biểu đồ trục, donut), `labels.show` của donut, `header.show` của slicer. Các thẻ khác chưa lấy mẫu.

## 4. Màu theo điểm dữ liệu khi có Chú giải hoặc nhiều measure

Cột nhóm có Chú giải: thẻ Columns > "Apply settings to" chỉ có **All** và các giá trị của Chú giải; không có "Categories". Với nhiều measure thì danh sách là các measure (VM-D8c). Cả hai dạng BI Pro đã làm (màu theo chuỗi, màu giá trị Chú giải). Không còn việc ở mục này.
