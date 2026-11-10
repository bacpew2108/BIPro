# Nghiên cứu và quyết định: D3

Mỗi mục: Quyết định, Lý do, Phương án đã loại. Mục nào còn [SUY ĐOÁN] thì chọn phương án thận trọng trong mã cho tới khi VM-D3 xác nhận.

## R1. Cấu trúc `visual.json` đã quan sát (Nhom6)

Đo trên `Nhom6_work.pbix`: 134 `visual.json`.

- Khoá gốc: `$schema`, `name`, `position` (mọi visual); `isHidden` (3); `filterConfig` (1). Không có khoá nào khác.
- Khoá trong `visual`: `visualType` (134), `visualContainerObjects` (134), `objects` (128), `query` (89), `drillFilterOtherVisuals` (52), `expansionStates` (1).
- Khoá `visual.objects` theo loại (số visual có khoá / tổng): card {labels 50, categoryLabels 50}; slicer {data 17, header 17, general 1}; textbox {general 7}; thanh nhóm (4) {dataPoint 2, labels 1, categoryAxis 1}; đường (3) {valueAxis 3, labels 3, categoryAxis 1, trend 1, forecast 1}; donut (3) {labels 3, legend 3, dataPoint 3, value 2}; treemap (1) {labels, legend}; matrix (2) {values, columnHeaders, rowHeaders, grid, columnWidth 2; subTotals 1}; bản đồ hình (1) {dataPoint, shape, defaultColors}; combo nhóm (4) {dataPoint 4, valueAxis 2, labels 2, legend 1}; combo xếp chồng (3) {valueAxis 2, labels 1, legend 1, categoryAxis 1}; cột 100% (1) {dataPoint, labels}.
- `drillFilterOtherVisuals` có ở card (30/50) và cả 4 thanh nhóm: không bắt buộc (card thiếu vẫn mở được trong Desktop).
- Cỡ do tác giả đặt: card 302×108 (và 236×26 cho nhãn nhỏ), slicer 364×64, thanh nhóm 616×380, hộp văn bản 1920×88. Không phải cỡ mặc định của Desktop.
- Hộp văn bản: `visual.objects.general[0].properties.paragraphs[]`, mỗi đoạn có `textRuns[]` với `value` và `textStyle`, tuỳ chọn `horizontalTextAlignment`; không có `query`.
- D1 đã quan sát Desktop khi dán một card: tên mới 20 hex, `z` = lớn nhất + 1, `tabOrder` = `z`, `$schema` nâng 2.13.0 → 2.14.0.

## R2. Loại thêm được ở bản đầu

**Quyết định**: thêm được loại có **ô ở mức `observed`** trong `WellRules` (D2): `card`, `slicer`, `clusteredBarChart`, `hundredPercentStackedColumnChart`, `lineChart`, `lineClusteredColumnComboChart`, `lineStackedColumnComboChart`, `donutChart`, `treemap`, `pivotTable`, `shapeMap`, cộng `textbox`. Các loại khác trong thư viện (cột nhóm, cột/thanh xếp chồng, 100% thanh, vùng, ribbon, waterfall, funnel, scatter, pie, map, gauge, KPI, multi-row card, table, image, shape, nút, điều hướng…) hiện mờ kèm lý do. Biến thể cột/thanh/vùng cùng họ trục XY sẽ được mở sau VM-D3 (chỉ cần quan sát tên ô Desktop ghi cho từng loại rồi thêm vào bảng `observed`).

**Lý do**: thêm một visual mà mọi ô đều "(chưa kiểm)" thì không thả trường vào được (D2 từ chối), nên vô dụng; mở loại nào thì phải có luật ô đã quan sát. Spec nói "biểu đồ cột": bản đầu thoả bằng cột 100% và combo cột; cột nhóm thường chờ VM-D3, ghi rõ ở báo cáo.

**Loại**: cho thêm mọi loại có renderer (`CartesianKind`): ô sẽ ở trạng thái "chưa kiểm" và chặn thả trường.

## R3. Mẫu `visual.json` của visual mới (`PBIRNewVisual`)

**Quyết định**: sinh gọn một dòng, thứ tự khoá như Desktop ghi trong Nhom6:

```
{"$schema":"<lấy từ một visual có sẵn của báo cáo; không có thì .../visualContainer/2.13.0/schema.json>",
 "name":"<20 hex>","position":{"x":…,"y":…,"z":…,"height":…,"width":…,"tabOrder":<z>},
 "visual":{"visualType":"<loại>","drillFilterOtherVisuals":true}}
```

- Loại dữ liệu (card, slicer, biểu đồ, matrix, treemap, bản đồ hình): không `query` cho tới khi có trường (R4); không ghi `objects` và `visualContainerObjects` (Nhom6 không bắt buộc: 6 visual không có `objects`; `visualContainerObjects` có ở cả 134 nhưng đây có thể là do Desktop ghi mặc định; **[SUY ĐOÁN]** Desktop chấp nhận vắng mặt, xác nhận ở VM-D3; nếu Desktop từ chối thì thêm `visualContainerObjects` rỗng hoặc giá trị Nhom6 hay dùng).
- Hộp văn bản: thêm `visual.objects.general[0].properties.paragraphs` với một đoạn văn bản mặc định "Hộp văn bản", không `drillFilterOtherVisuals`.
- Cỡ mặc định theo loại (bản đầu, theo Nhom6): card 302×108; slicer 364×64; biểu đồ và treemap, bản đồ hình, matrix 616×380; hộp văn bản 400×100; chỉnh theo VM-D3. Kẹp vừa trang.
- `z` = z lớn nhất của trang + 1000 và `tabOrder` = `z` (cùng quy tắc nhân bản của D1; Desktop dùng +1 nhưng cả hai hợp lệ, xem D1 R14).

**Lý do**: mẫu tối thiểu tránh ghi khoá mà ta không hiểu; kiểm bằng cách mở trong Desktop.

**Loại**: chép nguyên một visual cùng loại của báo cáo rồi xoá trường (mang theo `objects`, nhãn, màu của visual đó: không phải điều người dùng yêu cầu).

## R4. Tạo `visual.query.queryState` khi visual chưa có

**Quyết định**: `PBIRQueryPatch.apply` khi `visual.query.queryState` vắng mà có ô cần ghi thì chèn `"query":{"queryState":{<ô>}}` ngay sau `visualType` trong `visual` (đúng thứ tự Desktop: `visualType`, `query`, `objects`…); ô thành trống thì giữ `queryState:{}`. `FieldEditor` và `LayoutEditor.fieldEditingBlocker` cho phép visual dữ liệu mới chưa có `query`. [SUY ĐOÁN: `queryState:{}` rỗng khi bỏ hết trường của visual mới, và việc Desktop chấp nhận visual dữ liệu không có `query`: VM-D3.]

**Lý do**: D2 từ chối "chưa có cấu hình trường"; D3 cần visual mới nhận trường.

## R5. Đặt visual mới

**Quyết định**: tâm của visual mới trùng tâm vùng nhìn thấy của canvas (R6), làm tròn lưới 8, kẹp trong trang; nếu khung đó trùng ≥ 90% diện tích với visual đã có (ví dụ vừa thêm lần trước) thì lệch thêm 16 mỗi lần (`duplicateOffset`) tối đa 10 lần rồi dừng ở vị trí cuối. Lưới 8 và kẹp dùng `LayoutGeometry` của D1.

**Lý do**: cùng tinh thần dán của D1; Desktop đặt visual ở vị trí đang nhìn (chưa quan sát chính xác: VM-D3).

## R6. Vùng nhìn thấy của canvas

**Quyết định**: `ReportCanvas` báo `visibleRect` (toạ độ trang) về `DocumentState` bằng `onScrollGeometryChange` (macOS 15): khi thu phóng "vừa trang" (`zoom == nil`) là cả trang; khi có zoom thì phần cuộn tới. Không có thông tin thì dùng cả trang.

**Lý do**: đủ cho "giữa phần trang đang nhìn thấy" mà không thêm khái niệm mới.

**Kết quả bước thử T001 (2026-11-10, chạy trong app thật):** `onScrollGeometryChange` báo vùng nhìn thấy đổi theo thu phóng và cuộn (ví dụ rộng 1150 đơn vị trang ở zoom đã chọn, `x` tăng khi cuộn); phép đổi toạ độ nằm ở `CanvasViewport.visibleRect` (hàm thuần, có test). Ở chế độ "vừa trang" (`zoom == nil`) báo `nil` nghĩa là cả trang. Cổng qua.

## R7. Đổi loại: ánh xạ ô

**Quyết định** (`TypeChange.plan(visual, wells, to:)`, hàm thuần), cho từng ô cũ theo thứ tự trong ô mới:

1. Ô mới cùng tên (`Category`, `Y`, `Y2`, `Series`, `Tooltips`, `Values`, `Rows`, `Columns`, `Group`) và `observed` và nhận loại trường: chuyển nguyên (giữ byte phần tử).
2. Ô cũ không có tên trùng: chuyển sang ô `observed` đầu tiên cùng loại trường nhận được và chưa đầy (ví dụ `Y2` → `Y` khi loại mới không có `Y2`; `Series` → `Category` không được vì khác nghĩa: chỉ cho các cặp trong bảng cặp cho phép: `Y2→Y`, `Group→Category`, `Values→Y` và ngược lại cho `card`/`slicer` chỉ khi cùng loại trường).
3. Ô mới là ô một trường (isSingle) mà có hơn một trường cũ muốn vào: giữ trường đầu, các trường sau bị bỏ.
4. Còn lại bị bỏ; danh sách trường bị bỏ hiện thành thông báo ngay sau thao tác (`LayoutEditor.notice`), và hoàn tác trả lại.
5. Trường bị bỏ mà còn được nhắc ở sắp xếp, bộ lọc cấp visual hoặc định dạng theo trường (`FieldReferences`) và không còn phần tử nào khác trong visual mới có cùng `queryRef`: chặn cả thao tác, nêu lý do (như D2).

[SUY ĐOÁN: bảng cặp cho phép và việc Desktop giữ `Y2`→`Y` khi đổi sang loại một trục: VM-D3 xác nhận; bản đầu chỉ cho đổi giữa các loại có `observed` đủ để quy tắc 1 và 2 áp dụng.]

**Lý do**: đủ cho các cặp trong tiêu chí (thanh ↔ đường ↔ cột 100% ↔ combo): cùng tên ô nên chuyển nguyên.

**Loại**: gộp mọi trường vào một ô duy nhất (mất cấu trúc); bỏ trường âm thầm (vi phạm spec: "báo rõ").

## R8. Đổi loại: `objects` (định dạng)

**Quyết định**: sau khi đổi `visualType`, `visual.objects` chỉ giữ các khoá có thấy trên ít nhất một visual cùng loại đích trong chính báo cáo đang mở (hiện `baseline`); khoá khác bị bỏ; nếu báo cáo không có visual nào cùng loại đích thì bỏ cả `objects` (trừ khi loại đích là `textbox`). Thông báo cho người dùng nếu có khoá bị bỏ. `visualContainerObjects` (khung, tiêu đề, nền) giữ nguyên vì không phụ thuộc loại.

**Lý do**: không có bảng khoá hợp lệ theo loại; bằng chứng từ chính file là cách an toàn không đoán. Mất một số định dạng (ví dụ `dataPoint` khi chuyển thanh sang đường) là hy sinh có chủ ý; quan sát VM-D3 sẽ nới nếu Desktop giữ nhiều hơn.

**Loại**: giữ mọi `objects` (rủi ro file không hợp lệ); bỏ mọi `objects` (mất định dạng cả khi loại gần giống, ví dụ cột sang thanh).

## R9. Sửa nội dung hộp văn bản (`PBIRVisualPatch.setText`)

**Quyết định**: `setText(in:lines:)` thay `paragraphs[]` như sau: đoạn i của file có đúng một lượt (`textRuns` một phần tử) thì chỉ thay chuỗi `value` của nó (giữ `textStyle`, `horizontalTextAlignment`); đoạn có nhiều lượt: lượt đầu nhận văn bản mới, các lượt sau bị bỏ; đoạn thừa mới (dòng nhiều hơn đoạn): nhân bản byte của đoạn cuối với `value` mới; dòng ít hơn đoạn: bỏ các đoạn cuối. Chỉ văn bản thuần; không có kiểu chữ, liên kết, danh sách. Giao diện: ô `TextEditor` "Nội dung" ở Build pane khi chọn hộp văn bản; một lần xong chỉnh (mất tiêu điểm hoặc ⌘↩) là một bước hoàn tác.

**Lý do**: giữ kiểu chữ có sẵn (Nhom6 dùng nhiều kiểu trong cùng hộp) mà vẫn sửa được chữ; sửa kiểu chữ là việc của Format pane (lát sau).

## R10. Công thức sửa trong `PageEdit` và thứ tự áp khi lưu

**Quyết định**: `PageEdit` thêm `retyped: [String: Retype]` (loại mới, khoá `objects` cần bỏ) và `texts: [String: [String]]` (các dòng văn bản) cạnh `queries` (D2). `makeChanges` với visual có trong file áp theo thứ tự: `setVisualType` + tỉa `objects` → `setText` → `PBIRQueryPatch.apply` → `setPosition`; với visual mới (có trong `added`), byte `added[id]` là kết quả đã áp, nên chỉ ghép vị trí. Các thao tác trên visual mới (thả trường, đổi loại, văn bản) cập nhật thẳng `added[id]` (như D2 cho bản sao). Sau mỗi thao tác phân tích lại byte để cập nhật `ReportVisual` (`type`, `objects`, `containerObjects`, `fields`, `raw`).

**Lý do**: cùng mô hình D2 (một nguồn sự thật cho vẽ và lưu); thứ tự cố định làm kết quả xác định.

## R11. Giao diện

**Quyết định**: thư viện biểu tượng của Build pane bấm được: không chọn visual và đang Sửa → `insertVisual(type)`; chọn đúng một visual → `changeType(to:)`; loại không hỗ trợ hoặc chế độ Xem → biểu tượng mờ và `.help` nêu lý do, bấm vào đặt `layout.notice`. Ribbon: "Visual mới" → card, "Hộp văn bản" → textbox (cả Trang chủ và Chèn), mờ khi không ở chế độ Sửa. `layout.notice` hiện ở Build pane (trường bị bỏ, khoá `objects` bị bỏ) và tự xoá ở thao tác kế.

## R12. Lưu và kiểm

**Quyết định**: dùng nguyên đường lưu D1 (`DocumentSaver`). `verifyLayout` thêm: `type` của từng visual khớp, và với hộp văn bản các đoạn (chuỗi `value` ghép lại) khớp `LayoutEditor`. Phần mới đã đi qua `addedParts` của `PBIXWriter` (đặt sau `visual.json` cuối của cùng trang).

## R13. Kiểm thử

- `swift test`: `PBIRNewVisualTests` (mẫu theo loại, `$schema`, thứ tự khoá, escape, cỡ), `PBIRVisualPatchTests` (đổi `visualType` giữ byte khác, tỉa khoá `objects`, `setText` các ca một lượt/nhiều lượt/thêm/bớt đoạn), thêm ca tạo `queryState` cho `PBIRQueryPatchTests`, `TypeChangeTests` (ánh xạ ô các cặp: thanh↔đường↔cột 100%↔combo, card↔slicer, trường bị bỏ, chặn khi còn tham chiếu), `InsertVisualTests` (mã mới, vị trí giữa vùng nhìn thấy, lệch bậc khi bị chiếm, kẹp trang, từ chối loại chưa hỗ trợ/chế độ Xem), `TextboxEditingTests`, mở rộng `FieldEditingUndoTests` (chuỗi ngẫu nhiên có thêm visual và đổi loại).
- Test nặng `D3Nhom6`: trên Nhom6 thật thêm card và biểu đồ, thả trường, đổi loại ba cặp, lưu, mở lại, so loại/ô/trường/vị trí; chạy truy vấn qua engine; số card khớp DAX viết tay; đo thời gian.
- Golden `BIPRO_HEAVY=1 … --filter "Nhom6|ORA|VIS"` giữ nguyên số khớp.
- Tay: VM-D3 (quan sát) và `CHECKLIST.md` (mở file đã sửa trong Power BI Desktop).

## R14. Buổi quan sát VM-D3 (bạn làm tay, ngắn)

Làm trên bản sao `Nhom6_work.pbix`; mỗi bước đổi một thứ rồi Lưu thành file riêng; mình so `visual.json`. Danh sách chốt ở `tasks.md` / `VM-D3-QUAN-SAT.md`:

1. Trang mới trống (hoặc xoá hết visual một trang): thêm lần lượt từng loại (card, cột nhóm, thanh nhóm, đường, combo, donut, treemap, matrix, slicer, hộp văn bản, bản đồ hình) và lưu một file mỗi loại; ghi `visual.json` mới (khoá, cỡ, `z`).
2. Với mỗi loại dữ liệu: thả một trường vào rồi lưu: `queryState` ghi thế nào khi visual mới có trường đầu tiên; bỏ trường đó thì `queryState` còn gì.
3. Đổi loại bằng thư viện: cột nhóm → thanh nhóm → đường → donut; card → slicer; combo → đường; mỗi lần lưu file riêng; ghi trường đi về ô nào, trường nào bị bỏ, `objects` còn gì.
4. Thêm visual khi trang đã có visual ở giữa: đặt ở đâu; khi trang thu phóng 200% và cuộn sang phải: đặt ở đâu.
5. Hộp văn bản mới: nội dung mặc định và `paragraphs` ghi thế nào; gõ chữ rồi lưu.
6. Với mỗi visual đã thêm hoặc đổi loại có trường, chép truy vấn Performance Analyzer (như VM-D2 bước 9).

## R15. Nơi đọc loại và định dạng của visual (rà soát T002, 2026-11-10)

`ReportVisual.type`, `.objects`, `.containerObjects`, `.fields`, `.raw` đến từ `state.page` (bản đã sửa) ở mọi nơi vẽ. Sửa loại hoặc văn bản phải cập nhật **cả** `type`, `objects`, `containerObjects`, `raw` và `fields` từ byte mới (không chỉ `raw` như D2).

| Nơi | Đọc | Quyết định |
|---|---|---|
| `VisualCatalog.wells/displayTitle/summary` | `visual.type`, `objects`, `containerObjects` | đã dùng bản sửa |
| `TextboxVisual` (`ReportCanvas`) | `visual.objects.raw("general", "paragraphs")` (không đọc `raw`) | cập nhật `objects` khi `setText` (T029) |
| `ReportCanvas.liveTypes` / `isStatic` / `switch visual.type` | `visual.type` | tự đúng khi `type` đổi; loại không có renderer rơi về placeholder |
| `LiveVisualView` (`categoricalView`, `placeholder`, `VisualFormat(objects:)`) | `visual.type`, `visual.objects` | tự đúng khi `type` và `objects` đổi; `LoadKey` đã theo `raw["visual"]["query"]` nên đổi loại (đổi `visualType`, không đổi `query`) phải thêm `visualType` vào `LoadKey` (T021) |
| `VisualQuerySpecReader.spec` | `visual.type`, `visual.objects`, `raw` | tự đúng; đọc từ visual đã sửa do `ReportInteraction.load` |
| `ReportInteraction` (`canSelect`, slicer, bookmark) | `visual.type` | slicer ở bookmark đọc trang gốc (như D2); không đổi |
| Format pane (`ReportPanes`) | `visual.objects`, `containerObjects` | hiển thị bản sửa; đọc-only (Format pane là lát sau) |
| `DataPlaceholders` | `visual.type`, `objects`, `fields` | đã dùng bản sửa |


## R16. Kết quả buổi VM-D3 (2026-11-10, chốt T033)

Quan sát đầy đủ ở `docs/phase-d-evidence/vm-d3/QUAN-SAT.md` (file `R-D3-*.pbix`, `R-D3-*-query.txt`). Claude điều khiển VM theo lời cho phép một lần của người dùng. Điều đã quan sát, và chỗ khác với phương án thận trọng của R3 đến R9:

| Mục | Quan sát | Khác BI Pro hiện tại |
|---|---|---|
| R3 khoá `visual.json` mới | `$schema`, `name`, `position{x,y,z,height,width,tabOrder}`, `visual{visualType, drillFilterOtherVisuals:true}`; hộp văn bản mới không có `objects` | trùng, trừ hộp văn bản: BI Pro thêm đoạn "Hộp văn bản" mặc định |
| R4 `queryState` | visual có trường mới: `query.queryState` + `sortDefinition` (measure: giảm dần theo chính nó; cột: tăng dần) `isDefaultSort:true`; bỏ hết trường: về dạng trống, không giữ `queryState` rỗng | BI Pro chưa ghi `sortDefinition` |
| R5 đặt và cỡ | trang đã có visual: (100,100), 300×300, `z` = max+1, không dời giữa các lần thêm, không theo thu phóng; trang trống: lưới 280×280 | BI Pro đặt giữa vùng nhìn thấy, cỡ 302×108 / 616×380 |
| R7 đổi loại: ô | tên ô giữ khi loại mới có ô đó (kể cả `Y2` ở đường); combo→đường giữ `Y2`; donut→treemap `Category`→`Group`, `Y`→`Values`, giữ cả 3 cấp; combo→donut gộp `Y2` vào `Y`; card(measure)→slicer không đổi | BI Pro gộp `Y2` vào `Y` ở combo→đường và bỏ hai cấp Category ở donut→treemap |
| R8 `objects` | chỉ bỏ khoá không hợp lệ cho loại mới (`forecast` khi đường→cột/thanh, `value` khi donut→treemap, `valueAxis` khi combo→donut); giữ `trend`, `valueAxis`, `labels`, `categoryAxis`, `dataPoint`, `legend` | BI Pro bỏ `valueAxis`, `trend`, `forecast` khi đường→thanh |
| R9 hộp văn bản | `objects.general[0].properties.paragraphs[].textRuns[].value`; Enter thêm một `paragraphs[]`; sửa chữ đưa `z` lên 10000 | trùng cấu trúc |
| Mới | thư viện "Card" ghi `cardVisual` (ô `Data`), không phải `card`; `lineChart` có ô `Y2`; cột trong ô có `"active": true`; slicer có `objects.data.mode='Basic'` | cần thêm `cardVisual`, ô `Y2` của `lineChart`, `sortDefinition`, `active` khi D3b |

T034 và T035 hết chặn (phần việc là D3b: sửa `TypeChange`, `WellRules`, `PBIRNewVisual`, `PBIRQueryPatch` theo bảng trên, thêm loại cột nhóm/xếp chồng/vùng sau khi quan sát thêm).

### R16 bổ sung (2026-11-10): loại cột

`R-D3-t-clusteredColumn.pbix`, `R-D3-t-stackedColumn.pbix`: cột nhóm là `clusteredColumnChart`, **cột xếp chồng là `columnChart`** (không phải `stackedColumnChart`). Cả hai có ô `Category` (cột, `active:true`), `Series` (cột), `Y` (measure); không có `sortDefinition` khi thêm theo thứ tự trục, chú giải, giá trị. Đã thêm hai loại vào `VisualTypes`, `WellRules`, bộ vẽ (`CartesianKind` nhận `columnChart`), thư viện, `PBIRNewVisual`; `Nhom6_d3.pbix` có hai visual cột mới và mở được trong Desktop (`k-nhom6-d3-cot-moi-mo-duoc.png`). Loại thanh xếp chồng, vùng, ruy băng… BI Pro chưa vẽ nên chưa thêm.
