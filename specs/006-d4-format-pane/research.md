# Nghiên cứu: D4, Format pane sửa được

Nguồn quan sát: `docs/phase-d-evidence/vm-d4/QUAN-SAT.md` (VM-D4, 2026-11-10), `Nhom6_work.pbix` (thống kê bằng script trên 134 `visual.json`), mã hiện có (`Sources/BIPro/Panes/ReportPanes.swift`, `Sources/PBIXKit/Writing/*`, `LayoutEditor`). Mục [SUY ĐOÁN] là điều chưa quan sát; kế hoạch giữ chỉ-đọc hoặc không đưa vào danh mục.

## R1. Cách Desktop ghi mỗi thao tác (đã quan sát)

Tóm tắt (chi tiết ở `QUAN-SAT.md`):

- Bật thuộc tính hoặc thẻ chưa có: khoá mới ở **cuối** `objects` / `visualContainerObjects`, thuộc tính mới ở **cuối** `properties` của mục hiện có.
- Tắt công tắc của thẻ đã có: sửa `show` thành `false` tại chỗ, giữ thuộc tính khác.
- Số: `"16D"` (không đơn vị); số nguyên `"1L"`; chuỗi trong nháy đơn, nháy đơn trong chuỗi gấp đôi; danh sách cố định là chuỗi hoặc số `D`; màu theme `ThemeDataColor{ColorId, Percent}`; màu tự chọn hex **viết hoa** trong nháy đơn.
- "Reset to default" của thẻ: xoá cả khoá; của một thuộc tính màu: bỏ thuộc tính đó.
- Thứ tự khoá trong `visual`: `visualType`, `query`, `objects`, `visualContainerObjects`, `drillFilterOtherVisuals`.
- Desktop chuẩn hoá lại toàn bộ file khi lưu (`$schema` 2.14.0, đổi thứ tự khoá trong `projections`); nó mở được cả file chưa chuẩn hoá (Nhom6 là 2.13.0, và mọi file D1 đến D5 của BI Pro).

## R2. Thuật toán ghép byte (`PBIRFormatPatch`)

**Quyết định**: dùng `JSONCursor` (`locate`, `children(at:in:)`) như `PBIRQueryPatch`; mỗi `FormatEdit` là một trong:

- `set(scope, object, property, valueJSON)`: nếu `scope.object[0].properties.property` có thì thay đúng đoạn byte của giá trị; nếu `properties` có mà thiếu thuộc tính thì chèn `,"property":valueJSON` trước `}` cuối của `properties`; nếu khoá `object` thiếu thì chèn `,"object":[{"properties":{"property":valueJSON}}]` ở cuối `scope`; nếu `scope` thiếu thì tạo `"objects":{…}` hoặc `"visualContainerObjects":{…}` đúng chỗ (R1) rồi chèn.
- `removeProperty(scope, object, property)`: bỏ cặp khoá-giá trị cùng dấu phẩy; nếu `properties` hết thì bỏ cả mục; nếu khoá hết mục thì bỏ khoá; nếu `scope` hết khoá thì bỏ `scope` (R7).
- `removeObject(scope, object)`: bỏ cả khoá (và bỏ `scope` nếu rỗng).

Mục được sửa là mục không có `selector` hoặc `selector.id == "default"` (mục đầu tiên như vậy); mục có selector khác không bị đụng. Chèn mục mới vào khoá đã có chỉ khi khoá không có mục chung nào: thêm `{"properties":{…}}` sau các mục cũ (hiếm; chưa quan sát, nên chỉ làm khi khoá toàn mục có selector và danh mục cho phép; mặc định từ chối "thẻ này đã có định dạng riêng theo trường, chưa sửa").

Kiểm: đọc lại bằng `JSONSerialization`, so với cấu trúc mong đợi dựng từ bản trước (thay/chèn/bỏ trên cây), như `PBIRPatch.setVisualTitle`. Thất bại thì ném `WriteError.verificationFailed`, không ghi. Chèn giữ nguyên khoảng trắng của file (không giả định một dòng).

**Phương án bị loại**: ghi lại cả khoá `objects` bằng serializer (đổi thứ tự khoá, khác các lát trước); dùng `JSONValue` (từ điển, mất thứ tự khoá).

## R3. Tên thẻ trong giao diện ≠ tên khoá trong file

Đã thấy: Callout value (card) = `labels`; Category label = `categoryLabels`; Data labels = `labels`; Zoom slider = `zoom`; Shade area (thẻ Lines) = `lineStyles.areaShow`; Y-axis › Values = `valueAxis.show`, Title = `valueAxis.showAxisTitle`; Slicer › Values = `items`; Slicer header = `header`; Image của `cardVisual` = `cardImage`; Header icons = `visualHeader`.

**Quyết định**: danh mục lưu cả tên hiển thị tiếng Việt (theo nhóm giao diện của Desktop) lẫn tên khoá; công tắc đầu thẻ ánh xạ về thuộc tính thật (`show`, `areaShow`, …). Tên Việt dùng `FormatNames` (đã có) và bổ sung.

## R4. Phạm vi danh mục bản đầu

Chỉ đưa vào thuộc tính có quan sát cả cách ghi lẫn kiểu giá trị.

Phạm vi Chung (`visualContainerObjects`), mọi loại visual:

| Thẻ (khoá) | Thuộc tính | Kiểu | Nguồn |
|---|---|---|---|
| Tiêu đề (`title`) | `show` bool; `text` chuỗi; `fontSize` số; `bold` bool; `alignment` chuỗi (`center`; giá trị khác chưa thấy); `fontColor` màu | | Nhom6 + VM-D4 |
| Phụ đề (`subTitle`) | `show`, `text`, `fontSize`, `fontColor` | | Nhom6 |
| Nền (`background`) | `show`, `color`, `transparency` | | Nhom6 + VM-D4 (`transparency` một mình, không `show`) |
| Viền (`border`) | `show`, `radius`, `width`, `color` | | VM-D4 (`color` thêm ở vòng 2) |
| Bóng (`dropShadow`) | `show` | | Nhom6 + VM-D4 |
| Đệm (`padding`) | `top`, `bottom`, `left`, `right` | số | Nhom6 |
| Biểu tượng tiêu đề (`visualHeader`) | `show` | | VM-D4 |

Phạm vi Visual (`objects`), theo nhóm loại:

| Nhóm loại | Thẻ (khoá) và thuộc tính |
|---|---|
| `card` | `labels`: `fontSize`, `color`, `labelDisplayUnits`, `labelPrecision`, `bold`; `categoryLabels`: `show`, `color`, `fontSize` |
| `slicer` | `header`: `show`, `fontColor`, `textSize`; `items`: `padding` |
| Biểu đồ trục (cột/thanh/đường/combo) | `legend`: `show`, `position`, `fontSize`; `labels`: `show`, `fontSize`, `labelOrientation`, `labelDisplayUnits`, `labelPrecision`; `valueAxis`: `show`, `showAxisTitle`, `invertAxis`, `start`, `end`, `labelDisplayUnits`, `labelPrecision`; `categoryAxis`: `fontSize`; `zoom`: `show`; `lineStyles`: `areaShow` |
| `donutChart` | `legend`, `labels` (`show`, `labelStyle`, `fontSize`, `labelDisplayUnits`) |
| `pivotTable` | `columnHeaders`: `fontSize`, `autoSizeColumnWidth`; `rowHeaders`: `fontSize`; `values`: `fontSize`; `grid`: `rowPadding`; `subTotals`: `rowSubtotals`, `columnSubtotals` (chỉ có ở Nhom6, chưa quan sát ghi ở Desktop: **chỉ sửa giá trị có sẵn, không thêm mới** cho tới khi quan sát) |
| `actionButton` | `text` (`show`, `text`, `fontColor`, `fontSize`, `bold`), `fill` (`show`, `fillColor`, `transparency`), `outline` (`show`, `lineColor`, `weight`): chỉ sửa giá trị có sẵn |
| `cardVisual` | `cardImage.show` (với selector `default`); phần còn lại chỉ-đọc |

Không đưa vào: `dataPoint`, `selector.metadata`, `defaultColors`, `shape`, `image`, `textbox.general`, `trend`, `forecast`, `data.mode` (danh sách `Dropdown` mới thấy một giá trị), phông, điều kiện định dạng (màu theo measure `color:Measure`).

**Ghi chú về danh sách giá trị**: danh sách chọn chỉ có giá trị đã quan sát: `labelDisplayUnits` {`0D`: Tự động, `1D`: Không}; `legend.position` {`'Bottom'`, `'Top'`}; `labelOrientation` {`0D`: Dọc}; `title.alignment` {`'left'`, `'center'`, `'right'`: đã quan sát đủ ở VM-D4 vòng 2; bấm "trái" cũng ghi `'left'`}. Giá trị khác hiện chỉ-đọc ("giá trị chưa quan sát"). Rủi ro: danh sách ngắn hơn kỳ vọng; mở rộng bằng một buổi VM-D4 vòng 2 (R12).

## R5. Điều khiển và kiểm giá trị

| Kiểu | Điều khiển | Giá trị ghi | Kiểm |
|---|---|---|---|
| bool | công tắc | `true`/`false` | không |
| số thực (`D`) | ô số có mũi tên | `"<n>D"` | số hữu hạn; `fontSize` giới hạn 1 đến 50 (VM-D4 thấy Desktop kẹp ở 50 rồi 60, khoảng đúng chưa chốt: dùng 1 đến 50, bảo thủ); các số khác không âm; `transparency` 0 đến 100; `radius`, `width`, `padding` 0 đến 100 (bảo thủ) |
| số nguyên (`L`) | ô số | `"<n>L"` | 0 đến 10 (độ chính xác); nếu giá trị hiện có là `D` (Nhom6) thì giữ đuôi `D` |
| danh sách | `Picker` | chuỗi trong nháy đơn hoặc số `D` theo thuộc tính | chỉ giá trị trong danh sách đã quan sát |
| chuỗi | ô chữ | DAX literal (`'…'`, nháy đơn gấp đôi) | không rỗng với `text` của tiêu đề (rỗng thì từ chối, "xoá tiêu đề" dùng công tắc `show`); độ dài tối đa 200 |
| màu | ô màu + popover | theme: `ThemeDataColor{ColorId, Percent}`; tự chọn: hex chữ hoa `'#RRGGBB'` | hex 6 chữ số |

**Đuôi số**: đọc giá trị hiện có và giữ đuôi (`D` hoặc `L`) của chính nó; thuộc tính mới dùng đuôi quan sát ở VM-D4 (`D`, riêng `labelPrecision` là `L`).

## R6. Selector

- Mục không có `selector` hoặc `selector.id == "default"`: sửa được.
- `cardVisual` mới do Desktop ghi mục có `selector:{id:"default"}` **sau** `properties` (VM-D4 mục 6); khi tạo mục mới cho khoá của `cardVisual` ghi đúng thứ tự đó. Các loại khác ghi mục không có `selector`.
- Mục `metadata`/`data` và `id` khác `default`: chỉ-đọc, giữ nguyên byte (FR-007).

## R7. Đặt lại về mặc định

- Theo thẻ: `removeObject` (VM-D4: Desktop xoá cả khoá, kể cả `show`).
- Theo thuộc tính: `removeProperty` (VM-D4: màu bỏ thuộc tính, giữ thuộc tính khác).
- Khoá cuối cùng của `objects` hay `visualContainerObjects` bị bỏ: bỏ luôn khoá phạm vi ([SUY ĐOÁN]: Desktop bỏ hay để `{}`; chưa quan sát). Bảo thủ: bỏ khoá phạm vi, vì file `visual` mới do Desktop ghi không có khoá rỗng và Desktop mở được file không có khoá.

## R8. Ghi vào bộ nhớ và hoàn tác

- `PageEdit.formats: [String: [FormatEdit]]` (mã visual → danh sách đã gộp: mỗi `(scope, object, property)` có một giá trị cuối; `removeObject` xoá mọi edit con của khoá đó và đứng đầu). Ghi lại `bytes = apply(formats, to: baseJSON)`, rồi `raw`, `objects`, `containerObjects` của visual đổi theo (như `setText` của D3). Visual mới trong `added` thì `added[id] = bytes`.
- Hoàn tác: `LayoutSnapshot` đã chụp cả `edited` nên `formats` đi theo; không đổi cơ chế.
- **Dựng `raw` mới**: áp `formats` lên bản đã gồm đổi loại, sửa trường (`queries`) và văn bản đang chờ (cùng thứ tự với `makeChanges`), không lên `baseJSON` trơn, để không mất sửa khác trong bộ nhớ.
- **Đổi loại bỏ khoá**: khi `changeType` đưa khoá `objects` vào `dropObjectKeys`, dọn mọi `FormatEdit` của khoá đó trong `formats` (nếu không áp lại sẽ tạo lại khoá vừa bị bỏ).
- **Bản sao**: nhân bản visual hoặc trang đi theo `raw` hiện tại nên mang định dạng đã sửa; test ở `FormatEditingTests` và `FormatSavingTests`.
- Gộp bước: khoá gộp `"format:<mã visual>:<scope>.<khoá>.<thuộc tính>"` dùng cơ chế `lastCoalesce` của D1 (kéo thanh trượt, gõ liên tiếp): một chuỗi sửa liên tục cùng thuộc tính là một bước; đổi thuộc tính khác hoặc ngừng thì bước mới.
- Giá trị trùng giá trị hiện có: không tạo bước (như D5).

## R9. Đường vẽ

Đường vẽ đọc `visual.objects` / `visual.containerObjects` qua `ObjectProperties`; sửa `raw`, `objects`, `containerObjects` là đủ để canvas vẽ lại. Kiểm kê nhanh (grep, 2026-11-10): đường vẽ đang đọc khoảng 70 cặp (khoá, thuộc tính), gồm `title.show/text/fontSize/fontColor/bold/alignment`, `background.show/color/transparency`, `border.show/color/radius/width`, `dropShadow.show`, `labels.show/fontSize/color/labelStyle/labelPrecision/labelDisplayUnits/bold`, `legend.show/position/fontSize`, `valueAxis.*`, `categoryLabels.*`, `header.*`, `columnHeaders.*`, `grid.rowPadding`. Chưa đọc: `padding`, `subTitle`, `visualHeader`, `lineStyles.areaShow`, `zoom`, `valueAxis.show/showAxisTitle/invertAxis`, `labels.labelOrientation`, `items.padding`: các thuộc tính này ghi được nhưng BI Pro chưa vẽ; điều khiển hiện ghi chú "BI Pro chưa vẽ thuộc tính này" (cờ `rendered` trong danh mục). Làm vẽ thêm là việc sau, không thuộc lát này.

## R10. Lưu và kiểm

- `makeChanges`: với visual có trong file, thêm `if let edits = edit.formats[visual.id] { json = try PBIRFormatPatch.apply(edits, to: json) }` sau các bước đổi loại, văn bản, truy vấn và trước `patch` (vị trí). Visual trong `added` đã chứa định dạng trong `added[id]`.
- `DocumentSaver.verifyLayout`: thêm so `actual.objects.json == visual.objects.json` và `actual.containerObjects.json == visual.containerObjects.json`.
- Thứ tự khoá và byte của phần không sửa: test so `PBIRFormatPatch.apply` với bản chụp `json/*.visual.json` của VM-D4 (cùng thao tác, cùng kết quả khoá và giá trị; Desktop còn chuẩn hoá thứ tự `projections` nên chỉ so `objects`/`visualContainerObjects`).

## R11. Giao diện

`FormatPane` giữ hai phạm vi "Visual" và "Chung" của pane hiện có. Mỗi thẻ là một `DisclosureGroup` với công tắc đầu thẻ (nếu thẻ có thuộc tính bật/tắt chính), các hàng thuộc tính, và nút "Đặt lại" ở chân thẻ (chỉ khi thẻ có trong file). Ô màu: swatch mở popover có hàng màu theme gốc (`ColorId` 0 đến 9, `Percent` 0), ô hex, và "Đặt lại"; lưới đủ 6 hàng × 10 cột sau VM-D4 vòng 2 (`Percent` 0, 0.6, 0.4, 0.2, -0.25, -0.5). Mờ kèm lý do ở chế độ Xem, báo cáo định dạng cũ; nhiều visual chọn → "Chọn một visual". Visual chưa có trường: Desktop không hiện thẻ nào ("Thêm trường để bắt đầu định dạng"); BI Pro làm giống (VM-D4 mục 5). Mục "Khác (chỉ đọc)" liệt kê khoá có sẵn ngoài danh mục.

**Ô lưới màu theme**: đã đo ở VM-D4 vòng 2: cột 3 (`ColorId` 2) cho `Percent` 0 (hàng gốc), 0.6, 0.4, 0.2, -0.25, -0.5; BI Pro dựng đủ lưới 6 hàng × 10 cột (`ColorId` 0 đến 9).

## R12. Việc còn lại sau bản đầu (không chặn)

VM-D4 vòng 2: lưới màu theme đủ `Percent` từng hàng; `title.alignment` đủ giá trị; `border.color`; màu nền/bóng; matrix (`columnHeaders`, `subTotals` thêm mới); phông; khoảng đúng của ô số; reset thẻ cuối làm `objects` rỗng. Mỗi mục xong thì thêm vào danh mục (chỉ sửa `FormatCatalog` và test).

## R13. Kiểm thử

- `PBIRFormatPatchTests`: từng thao tác (thêm khoá phạm vi, khoá, thuộc tính; sửa tại chỗ; bỏ thuộc tính, mục, khoá, phạm vi), file nhiều dòng và một dòng, nháy đơn gấp đôi, tiếng Việt có dấu, mục có selector không bị đụng, so với `json/*.visual.json` của VM-D4.
- `FormatCatalogTests`: mọi thuộc tính của danh mục có nguồn quan sát; không trùng khoá; mọi `(khoá, thuộc tính)` của Nhom6 thuộc danh mục hoặc thuộc nhóm chỉ-đọc đã khai báo.
- `FormatValueTests`: chuẩn hoá và kiểm từng kiểu (R5), đuôi `D`/`L`, hex hoa, ThemeDataColor.
- `FormatEditingTests`, `FormatUndoTests` (gộp bước, đổi giá trị trùng, hoàn tác xen D1 đến D5), `FormatSavingTests` (chỉ `visual.json` đã sửa đổi, byte khác khớp, kiểm `verify`), `D4Nhom6Tests` (kịch bản Nhom6: card, slicer, combo, matrix; lưu; mở lại; số liệu vẽ cùng; gói `Nhom6_d4.pbix` cho Desktop).
