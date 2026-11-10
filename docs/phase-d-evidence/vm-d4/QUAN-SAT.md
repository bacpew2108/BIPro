# Quan sát VM-D4 (2026-11-10, Claude điều khiển VM theo lời cho phép của người dùng)

Làm trên bản chép của `Nhom6_work.pbix` trong VM (`C:\Users\bacpew\vmd4\work.pbix`, đã xoá sau khi dùng), Power BI Desktop 2.159.x. Cách làm: chọn một visual, đổi **một** thuộc tính trong Format pane, ⌘S (lưu tại chỗ), chép file sang Mac, so `visual.json` trước và sau (chỉ khoá `objects` và `visualContainerObjects`). Không dịch ngược; chỉ quan sát giao diện và file Desktop ghi. Visual dùng: biểu đồ cột xếp chồng 100% + đường Q3.4 (`e32431…`, trang D3), card (`595dca…`), slicer (`9261e4…`), và một `cardVisual` mới do Desktop thêm vào trang trống. Bản chụp `visual.json` cuối: thư mục `json/`; ảnh: `desktop-*.png`.

## 0. Điều chung

- **Desktop ghi lại cả `visual.json` khi lưu** (chuẩn hoá): `$schema` nâng từ 2.13.0 lên **2.14.0**, đổi thứ tự khoá trong `projections` (`active` trước `displayName`), đổi chỗ ô `Tooltips` trong `queryState`. Phần định dạng thì giữ nguyên nội dung. Vậy ghép byte của BI Pro (giữ nguyên phần không đổi) là hợp lệ vì Desktop mở được cả hai dạng.
- File ghi gọn một dòng (không thụt dòng). Thứ tự khoá trong `visual`: `visualType`, `query`, `objects`, `visualContainerObjects`, `drillFilterOtherVisuals`. Khoá `objects` mới chèn **trước** `visualContainerObjects`; `visualContainerObjects` mới chèn trước `drillFilterOtherVisuals` (visual mới thêm không có cả hai).
- **Khoá mới đặt ở cuối** `objects` / `visualContainerObjects`; **thuộc tính mới đặt ở cuối** `properties` của mục đang có (thứ tự chèn, không sắp lại).
- Mục không có `selector` khi định dạng chung. Riêng `cardVisual` mới ghi `"selector":{"id":"default"}` **sau** `properties`.

## 1. Kiểu giá trị

| Điều khiển | Giá trị ghi | Ví dụ |
|---|---|---|
| Công tắc (bật/tắt) | `{"expr":{"Literal":{"Value":"true"}}}` / `"false"` | `show`, `showAxisTitle`, `invertAxis`, `areaShow` |
| Số thực (cỡ chữ, bo góc, độ rộng, đệm, độ trong suốt, min/max trục) | `"16D"` (số + đuôi `D`, không có `pt`/`px`/`%`) | `fontSize 16D`, `radius 20D`, `width 3D`, `transparency 25D`, `padding 12D` |
| Số nguyên (độ chính xác thập phân) | `"1L"` | `labelPrecision` |
| Danh sách cố định kiểu chữ | chuỗi trong nháy đơn | `alignment 'center'`, `position 'Bottom'` |
| Danh sách cố định kiểu số | số `D` | `labelOrientation 0D` (Vertical), `labelDisplayUnits 1D` |
| Chuỗi tự do | chuỗi trong nháy đơn, **nháy đơn trong chuỗi gấp đôi** | `'It''s a test'` |
| Màu theme | `{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":2,"Percent":0.2}}}}}` | ô lưới theme cột 3, hàng 3 |
| Màu tự chọn (hộp "More colors", gõ hex chữ thường) | `{"solid":{"color":{"expr":{"Literal":{"Value":"'#E4572E'"}}}}}` (**hex viết hoa**) | |

Cỡ chữ: gõ 500 ở ô cỡ chữ của tiêu đề → Desktop ghi `50D` (rồi `60D` sau thao tác kế tiếp): ô bị kẹp giới hạn; khoảng đúng chưa chốt (xem mục 8).

## 2. Thêm thuộc tính hoặc thẻ chưa có trong file

| Thao tác | Kết quả |
|---|---|
| Data labels Off → On (combo, chưa có `labels`) | `objects.labels = [{"properties":{"show":true}}]`, thêm ở **cuối** `objects` |
| Chọn Orientation = Vertical trong thẻ đó | thêm `labelOrientation: 0D` cuối `properties` |
| Header icons Off (General, chưa có) | `visualContainerObjects.visualHeader = [{"properties":{"show":false}}]` |
| Background Transparency 0 → 25 (chưa có `background`) | `background = [{"properties":{"transparency":25D}}]` (**không** có `show`) |
| Shadow On | `dropShadow = [{"properties":{"show":true}}]` |
| Visual border On, bo góc 20, rộng 3 | `border` có `show true`, `radius 20D`, `width 3D` (theo thứ tự chèn) |
| Zoom slider On | `objects.zoom = [{"properties":{"show":true}}]` |
| Shade area On (thẻ chung với Lines) | **`objects.lineStyles.areaShow: true`**: tên khoá và thuộc tính **không** trùng tên thẻ |
| Y-axis › Title On | `valueAxis.showAxisTitle: true` |
| Y-axis › Values Off | `valueAxis.show: false` |
| Y-axis › Invert range On | `valueAxis.invertAxis: true` |
| Slicer › Values › Padding 8 → 12 | `objects.items = [{"properties":{"padding":12D}}]` (thẻ "Values" của slicer là khoá `items`) |

Ánh xạ tên thẻ trong giao diện → khoá trong file (đã thấy): Callout value (card) = `labels`; Category label = `categoryLabels`; Data labels = `labels`; Zoom slider = `zoom`; Shade area/Lines = `lineStyles`; Y-axis = `valueAxis`; Legend = `legend`; Slicer header = `header`; Slicer › Values = `items`; Title/Subtitle/Effects›Background/Visual border/Shadow = `title`/`subTitle`/`background`/`border`/`dropShadow`; Header icons = `visualHeader`; `cardVisual` › Image = `cardImage`.

## 3. Sửa giá trị đã có (ghi tại chỗ hay thêm cuối)

- Tắt công tắc của thẻ đã có (Legend, Category label, Slicer header): sửa `show` thành `false` **tại chỗ**, giữ nguyên các thuộc tính khác (`position`, `fontSize`, `color`…).
- Đổi giá trị thuộc tính đã có: thay giá trị tại chỗ. Thuộc tính chưa có trong mục thì thêm cuối mục (ví dụ tiêu đề: `fontSize`, `bold`, `alignment`, `fontColor` thêm lần lượt sau `show`, `text`).
- `bold`: bấm "B" ở tiêu đề (giao diện đang hiện đậm) ghi `bold: false` (mặc định tiêu đề là đậm, không ghi khi chưa đổi).
- Min/Max trục: `start`/`end` (đã có trong Nhom6); `secStart`, `labelDisplayUnits` cũng có.

## 4. Đặt lại về mặc định

- Nút "Reset to default" của **thẻ** (Data labels đang có `show:true`, `labelOrientation`): **xoá cả khoá** (`labels` biến khỏi `objects`), kể cả `show`; nếu `objects` hết khoá thì xem ở mục 7 (chưa thử riêng).
- "Reset to default" trong hộp màu của **một thuộc tính** (tiêu đề): chỉ bỏ thuộc tính đó (`fontColor`), giữ nguyên thuộc tính khác của mục.

## 5. Visual chưa có định dạng nào

- Visual mới (D3) chưa có trường: **Format pane trống**, chỉ ghi "Add data to your visual to start formatting". Thêm trường thì pane hiện thẻ (với `cardVisual`: Multi-card layout, Cards, Callout, Image, Reference labels…).
- Tiêu đề hiện "On" dù file không có `title` (mặc định bật). Tắt thì ghi `visualContainerObjects.title = [{"properties":{"show":false}}]` và tạo khoá `visualContainerObjects` (chèn trước `drillFilterOtherVisuals`).

## 6. `cardVisual` (card mới)

- Thẻ Image ("Apply settings to: Cards = All, States = All"): bật ghi `objects.cardImage = [{"properties":{"show":true},"selector":{"id":"default"}}]`.
- Cả hai chọn "All" thì `selector` là `id: default`; chọn một thẻ hoặc trạng thái cụ thể thì ghi selector khác (chưa quan sát).

## 7. Chưa quan sát ở VM-D4

- Matrix/bảng (`pivotTable`): `columnHeaders`, `rowHeaders`, `grid`, `columnWidth`, `subTotals`.
- Định dạng riêng theo trường (`selector.metadata`) và theo điểm dữ liệu (`dataPoint`, `selector.data`).
- Font family (ô chọn phông), "Heading" của tiêu đề, `titleWrap`, các thẻ con "Divider", "Spacing"; màu viền, màu nền, màu bóng và các thuộc tính con của `dropShadow`.
- Khoảng đúng của cỡ chữ và ô số (min, max), nhập chữ không phải số.
- Reset thẻ cuối cùng làm `objects` rỗng: Desktop bỏ khoá `objects` hay để `{}`.
- Điều kiện định dạng (nút fx), thêm nhiều mục cho một khoá (mỗi `selector` một mục).
- Mở lại file BI Pro ghi trong Desktop (đã làm cho D5; D4 sẽ làm sau khi có code).

## Bản chụp

- `json/combo-q34.visual.json`: combo Q3.4 sau mọi thay đổi (legend, zoom, lineStyles, valueAxis, title, border, background, shadow, visualHeader).
- `json/card.visual.json`: card với `categoryLabels.show:false`, `labels.fontSize 28D`, `labelPrecision 1L`.
- `json/slicer.visual.json`: slicer với `header.show:false`, `items.padding 12D`.
- `json/new-cardvisual.visual.json`: `cardVisual` mới với `cardImage`, `visualContainerObjects.title.show:false`.
- Ảnh: `desktop-format-pane-combo.png`, `desktop-title-card.png`, `desktop-cardvisual-image.png`, `desktop-empty-visual-no-format.png`.

## Vòng 2 (2026-11-10, sau khi làm code D4; trên `Nhom6_d4.pbix` do BI Pro lưu, mở trong Desktop)

| Quan sát | Kết quả |
|---|---|
| Căn lề tiêu đề (3 nút trái/giữa/phải) | `title.alignment` = `'left'`, `'center'`, `'right'`; **bấm "trái" cũng ghi `'left'`** (không bỏ thuộc tính) |
| Màu viền (`border.color`) chọn từ lưới theme | `border.color` = `{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":2,"Percent":…}}}}}`; thuộc tính mới đặt cuối `properties` (sau `show`, `radius`) |
| Lưới màu theme: `Percent` từng hàng (cột 3, `ColorId` 2) | hàng gốc **0**, rồi **0.6, 0.4, 0.2, -0.25, -0.5** (5 hàng biến thể từ sáng đến tối) |

Còn chưa quan sát ở vòng 2: màu nền/bóng và các thuộc tính con của `dropShadow`, matrix thêm mới `subTotals`, phông, khoảng đúng của ô số, reset thẻ cuối làm `objects` rỗng. Ảnh: `desktop-vong2-bang-mau-vien.png`.
