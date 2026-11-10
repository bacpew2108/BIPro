# Nghiên cứu và quyết định: D2

Mỗi mục: Quyết định, Lý do, Phương án đã loại. Mục nào còn [SUY ĐOÁN] thì chặn trong mã cho tới khi VM-D2 xác nhận.

## R1. Cấu trúc `queryState` đã quan sát (Nhom6)

Đo trên `Nhom6_work.pbix`: 134 `visual.json`, 89 có `visual.query.queryState`, 171 phần tử `projections[]` ở 137 ô.

- Mỗi ô là một đối tượng chỉ có khoá `projections` (137/137; không có khoá nào khác như `fieldParameters`).
- Phần tử `projections[]` có `field`, `queryRef`, `nativeQueryRef` (171/171), `displayName` (149/171), `active` (115/171).
- `field` là một trong `Column`, `Measure`, `HierarchyLevel` (47, 106, 18). Không có `Aggregation`.
- `queryRef` = `<Bảng>.<Tên>` (cột, measure); cấp hierarchy = `<Bảng>.<Hierarchy>.<Cấp>`. `nativeQueryRef` = tên ngắn (với cấp hierarchy là tên cấp).
- `displayName` hiện cả khi người dùng đặt tên riêng (ví dụ card "Giá trị TB/GD" cho measure `Avg Trans Value`) và có thể trùng tên gốc: không dùng sự có mặt của nó để suy ra "đã đổi tên".
- `active: true` xuất hiện ở trường nằm trong cấp drill/hierarchy mở; ý nghĩa với trường thường chưa rõ. Giữ nguyên khi chép phần tử cũ.
- Ngoài `queryState`, `visual.query.sortDefinition` có ở 4 visual (`sort[].field`, `direction`, `isDefaultSort`); `filterConfig` (cấp visual) ở 1 visual (trường trong `field` và `filter.From/Where` dùng bí danh `Source`); 14 chỗ trong `objects` có `selector.metadata` = `queryRef` của một trường (định dạng theo trường, ví dụ màu hoặc nhãn riêng của một measure).

Bảng ô đã quan sát (loại visual, ô → loại trường, số trường lớn nhất gặp). Đây là **danh sách cho phép ban đầu** của D2 (R5):

| Visual | Ô | Loại trường | Số lớn nhất gặp |
|---|---|---|---|
| card | Values | Measure | 1 |
| slicer | Values | Column, HierarchyLevel | 3 |
| clusteredBarChart, hundredPercentStackedColumnChart, lineChart, lineStackedColumnComboChart, lineClusteredColumnComboChart | Category | Column (combo: cả HierarchyLevel) | 1 đến 3 |
| các biểu đồ trên | Y, Y2 (combo) | Measure | 1 đến 3 |
| các biểu đồ trên | Series | Column | 1 |
| các biểu đồ trên, donut, shapeMap, treemap | Tooltips | Measure | 1 đến 3 |
| donutChart | Category, Y | Column; Measure | 3; 1 |
| treemap | Group, Values | Column; Measure | 2; 1 |
| pivotTable | Rows, Columns, Values | Column; Column và HierarchyLevel; Measure | 1; 3; 1 |
| shapeMap | Category | Column | 1 |

## R2. Mô hình sửa: mở rộng `PageEdit` của D1

**Quyết định**: thêm `queries: [String: QueryEdit]` vào `PageEdit` (mã visual → cấu hình trường đã sửa của visual đó); thao tác sửa trường đi qua `LayoutEditor.commit`, nên hoàn tác/làm lại, `isDirty`, giới hạn lịch sử, ảnh chụp đều dùng nguyên. Một lần thả = một `commit` = một bước hoàn tác.

**Lý do**: D1 đã chứng minh mô hình ảnh chụp cả trang chạy đủ nhanh (kéo 19–32 ms mỗi khung) và đã được test hoàn tác trên chuỗi ngẫu nhiên. Cấu hình trường nhỏ (vài trường) nên ảnh chụp rẻ.

**Loại**: ngăn xếp hoàn tác riêng cho trường (hai lịch sử, thứ tự đan xen sai, phá FR-009); lưu lệnh đảo ngược (mỗi loại thao tác phải viết hai chiều, dễ lệch).

## R3. Một đường duy nhất cho vẽ lại và lưu

**Quyết định**: `PBIRQueryPatch.apply(to: visualJSON, edit:)` ghép byte và trả `visual.json` mới. Editor phân tích lại byte này (`JSONValue.parse`) để cập nhật `ReportVisual.raw` và `fields` của visual trong `PageEdit.visuals`. Bộ đọc truy vấn Phase C chỉ đọc `visual.raw`, nên không đổi. Lúc lưu, `makeChanges` chạy lại `apply` trên `visual.json` đang có trên đĩa.

**Lý do**: cái vẽ trong app và cái ghi vào file là cùng một chuỗi byte; lỗi lệch giữa hai nơi không thể xảy ra. Chi phí: ghép byte + phân tích một `visual.json` vài KB, dưới 1 ms.

**Điều kiện**: editor cần byte `visual.json` gốc lúc sửa. D1 đã có đường đọc (`json(of:page:)` cho nhân bản); dùng lại.

**Loại**: sửa `JSONValue` rồi serialize lại (mất thứ tự khoá và định dạng; `JSONValue.object` là từ điển không giữ thứ tự: trái nguyên tắc ghép byte của D1).

## R4. Ghép byte `queryState`

**Quyết định**:

- Ô đã có: thay đoạn byte của mảng `projections`. Phần tử không đổi hoặc chỉ đổi vị trí/ô được chép nguyên byte (kể cả `active` và khoá lạ); phần tử đổi tên chỉ thay hoặc thêm khoá `displayName` ngay trong byte của nó; phần tử mới do hàm sinh theo mẫu (R6) với cùng cách trình bày (có hay không khoảng trắng, xuống dòng) như tài liệu đang sửa.
- Ô chưa có: thêm khoá mới vào đối tượng `queryState` (xử lý dấu phẩy).
- Ô thành trống: xoá khoá của ô. [SUY ĐOÁN: Desktop có xoá khoá hay để `projections: []` chưa quan sát; VM-D2 xác nhận. Cả hai dạng đều là JSON hợp lệ; chọn xoá khoá vì file do Desktop ghi không thấy ô trống trong Nhom6: 137/137 ô có phần tử.]
- Sau mỗi ghép: phân tích lại và so với cấu trúc mong đợi (như `PBIRLayoutPatch`), sai thì ném `WriteError.verificationFailed`.

**Lý do**: giữ nguyên mọi byte khác như D1 (SC-004). `JSONCursor.children/removing` đã có cho mảng và đối tượng.

## R5. Ô nào nhận loại trường nào

**Quyết định**: bảng `WellRules` có hai mức cho mỗi (loại visual, ô): `observed` (có trong bảng R1) và `known-from-docs` (kiến thức chung, chưa quan sát). **D2 chỉ cho thêm khi `observed`**; mức `known-from-docs` hiện ô nhưng từ chối thả với lý do "chưa kiểm với Power BI Desktop" cho tới khi VM-D2 nâng lên `observed`. Số trường tối đa: lấy `max(quan sát, 1)` cho ô một trường (Series, Category của biểu đồ trục, slicer: Desktop không giới hạn slicer ở một cột nhưng Nhom6 có đến 3 là cấp hierarchy; đặt tối đa 1 cột nếu không phải hierarchy [SUY ĐOÁN]).

**Lý do**: bài học D1 (ghi sai làm Desktop từ chối file). Tổ hợp đã quan sát đủ để chứng minh luồng lõi: thêm measure vào Y, thêm cột vào Category, chuyển measure giữa Y và Y2 của combo.

**Loại**: cho thêm mọi thứ ngay và dựa vào "Desktop sẽ lỗi thì biết": file hỏng nằm trên đĩa.

## R6. Phần tử `projections[]` mới (mẫu theo Desktop)

**Quyết định**: sinh theo đúng thứ tự khoá đã quan sát:

- Cột: `{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"<Bảng>"}},"Property":"<Cột>"}},"queryRef":"<Bảng>.<Cột>","nativeQueryRef":"<Cột>"}`
- Measure: như trên với `"Measure"`.
- Thêm `"active":true` và `"displayName"` chỉ khi người dùng đổi tên hoặc khi chép từ phần tử cũ; không thêm khoá thừa.
- Cấp hierarchy: không sinh (ngoài phạm vi); chỉ chép phần tử cũ.
- `Aggregation`: **chưa sinh** [SUY ĐOÁN] (R8).
- Chuỗi JSON thoát đúng (`"`, `\`, ký tự điều khiển, Unicode giữ nguyên); `queryRef`/`nativeQueryRef` dùng `PBIRPatch.jsonStringToken`.

**Cần VM-D2 xác nhận**: khi người dùng kéo cột/measure vào ô, Desktop có ghi `displayName` và `active` không (Nhom6 có phần tử thiếu cả hai, nên cả hai đều hợp lệ).

## R7. Tham chiếu tới trường ở nơi khác trong `visual.json`

**Quyết định**: `FieldReferences.find(in: visualJSON, for: field)` tìm: (a) `query.sortDefinition.sort[].field` cùng bảng/thuộc tính; (b) `filterConfig.filters[].field`; (c) bất kỳ `selector.metadata` bằng `queryRef` của trường (định dạng theo trường). D2:

- **Thêm, đổi thứ tự, chuyển ô, đổi tên hiển thị**: không động tới các nơi này (`queryRef` không đổi; metadata và sort vẫn trỏ đúng). Đổi tên hiển thị không đổi `queryRef`.
- **Bỏ trường** còn được nhắc ở (a), (b) hoặc (c): **chặn** và báo "trường đang dùng để sắp xếp / lọc / định dạng; xử lý ở lát sau, chưa kiểm với Power BI Desktop", cho tới khi VM-D2 cho biết Desktop làm gì (ví dụ có xoá `sortDefinition`, xoá thẻ lọc, xoá mục `metadata` không). Sau VM-D2 thì làm đúng theo đó.
- Bỏ trường cũng có thể làm một `queryRef` khác trùng ở ô khác (cùng trường ở hai ô): chỉ chặn khi không còn phần tử nào khác có cùng `queryRef`.

**Lý do**: tham chiếu treo có thể làm Desktop từ chối file (bài học D1); bằng chứng Nhom6 cho thấy chúng không hiếm (4 sort, 1 filter, 14 metadata).

## R8. Phép gộp

**Quyết định**: tách lát thành D2a (không phép gộp) và D2b (phép gộp, sau VM-D2). Trong D2a, cột số thả vào ô giá trị bị từ chối với lý do "cần phép gộp, làm sau khi quan sát". D2b dùng `ModelMetadata.Column.summarizeBy` (AMO: 1 mặc định, 2 không, 3 tổng, 4 nhỏ nhất, 5 lớn nhất, 6 đếm, 7 trung bình, 8 đếm khác biệt) làm mặc định khi thả, đúng cách Desktop chọn phép gộp mặc định. Bảng mã `Function` trong `field.Aggregation` do VM-D2 xác nhận (bộ đọc hiện đã giả định 0 Sum, 1 Average, 2 Count, 3 Min, 4 Max, 5 Count distinct, 6 Median: [SUY ĐOÁN] chưa kiểm).

**Lý do**: Nhom6 không có mẫu `Aggregation`; ghi sai sẽ làm file hỏng. Phần còn lại của lát không phụ thuộc phép gộp.

## R9. Kéo thả

**Quyết định**: dữ liệu kéo là `FieldRef` (bảng, tên, loại: cột hay measure, kiểu dữ liệu; xem `data-model.md`), `Codable`, đi qua `NSItemProvider` dạng văn bản (tiền tố `bipro-field:` rồi JSON); `DataPane` dùng `.onDrag`, ô của Build pane dùng `.onDrop(of: [.plainText])`; kéo trong Build pane (đổi thứ tự, chuyển ô) dùng cùng cơ chế.

**Kết quả bước thử T001 (2026-11-10, chạy trong app thật):** (1) `.draggable`/`.dropDestination` với `Transferable` KHÔNG chạy (thả không bao giờ tới); (2) `.onDrag`/`.onDrop` với `NSItemProvider` chạy: kéo từ pane Dữ liệu sang ô "Chú thích công cụ" của Build pane ghi nhận kéo, thả và đọc lại đúng `Fact_Transaction.trans_hour`; (3) `Button` nuốt thao tác kéo, nên hàng kéo được của pane Dữ liệu dùng cử chỉ chạm (`onTapGesture`) thay cho `Button`; (4) vùng thả cần `contentShape(Rectangle())` vì ô trống chỉ có nét viền. Kéo trong Build pane (đổi thứ tự) kiểm ở T028 bằng cùng cơ chế. Cổng qua. Bước thử T001 (như D1): chắc `draggable`/`dropDestination` chạy được trong `DocumentGroup(viewing:)` và với cửa sổ có sidebar. Không chạy được thì giữ menu "Thêm trường" của ô và nút tick, báo bạn; không tự đổi cách dựng cửa sổ.

**Lý do**: API gốc của SwiftUI, không thư viện ngoài (Hiến pháp III).

**Loại**: `NSItemProvider` thủ công (đã dùng một chỗ ở `ReportCanvas`, dài và dễ sai kiểu); trạng thái kéo toàn cục trong `DocumentState` (không chạy với menu ngữ cảnh và không kiểm được bằng test).

## R10. Vẽ lại đúng một visual

**Quyết định**: thêm `fieldsKey` (băm của `visual.raw["visual"]["query"]`) vào `LoadKey` của `LiveVisualView`. `ReportInteraction` có cache theo visual: cần xoá cache của visual đã sửa (xem task) để không hiện số cũ.

**Đo trước khi chốt**: mục tiêu dưới 150 ms ở visual nặng nhất (SC-005); đo bằng test nặng `D2Nhom6` như D1 (`measurements.md`).

## R11. Lưu

**Quyết định**: `LayoutEditor.makeChanges` thêm: với visual có `queries[id]`, chạy `PBIRQueryPatch.apply` rồi mới ghép vị trí (nếu có), kết quả vào `changes.reportParts[path]`. `verifyLayout` của `DocumentSaver` thêm kiểm trường: mở lại file mới, `loadReport()`, so danh sách ô và trường (loại, bảng, tên, thứ tự, tên hiển thị) với `LayoutEditor`.

**Lý do**: đúng đường kiểm ba lớp của D1; không đổi hợp đồng `PBIXChanges`.

## R12. Hai thay đổi nhỏ trong đọc

**Quyết định**: `ReportField` thêm `nativeQueryRef: String?` và `active: Bool?` (giá trị mặc định nil, không đổi chữ ký các hàm hiện có). `VisualCatalog.wells` lấy nhãn tiếng Việt từ `WellRules`.

## R13. Kiểm thử

- `swift test`: `PBIRQueryPatchTests` (thêm/bỏ/đổi thứ tự/chuyển ô/đổi tên trên tài liệu mẫu gọn và pretty; ô mới; ô thành trống; escape; phần còn lại giữ nguyên byte), `WellRulesTests` (30 tổ hợp đã quan sát đều nhận; tổ hợp chưa quan sát bị từ chối), `FieldReferencesTests` (trên 4 visual có sort, 1 filter, 14 metadata của Nhom6 trích ra), `FieldEditingUndoTests` (chuỗi ngẫu nhiên đan xen kéo/đổi cỡ của D1 với sửa trường, hoàn tác về đúng trạng thái đầu).
- Test nặng `D2Nhom6`: trên Nhom6 thật sửa 4 loại visual, lưu, mở lại, so ô/trường; chạy truy vấn của visual đã sửa qua engine và so với truy vấn DAX viết tay cho cùng cấu hình (SC-001); đo thời gian vẽ lại và lưu.
- Golden `BIPRO_HEAVY=1 … --filter "Nhom6|ORA|VIS"` giữ nguyên số khớp.
- Tay: VM-D2 (quan sát) và `CHECKLIST.md` (mở file đã sửa trong Power BI Desktop).

## R14. Buổi quan sát VM-D2 (bạn làm tay, ngắn)

Làm trên bản sao `Nhom6_work.pbix`; mỗi bước đổi một thứ rồi Lưu thành file riêng; mình so `visual.json`. Danh sách chốt ở `tasks.md`/`VM-D2-QUAN-SAT.md`:

1. Thả cột số, cột văn bản, cột ngày, measure vào ô giá trị của card và của biểu đồ cột; Desktop ghi `field`, `queryRef`, `nativeQueryRef`, `displayName`, `active` thế nào (cả phép gộp mặc định và mã `Function`).
2. Đổi phép gộp qua menu trường (Sum, Average, Count, Count distinct, Min, Max).
3. Thêm cột vào ô Trục, Chú giải, Chi tiết; thêm measure vào Trục Y và Chú giải (không được?); Desktop có từ chối không.
4. Bỏ trường đang dùng làm sắp xếp, làm bộ lọc cấp visual, có định dạng riêng theo trường: `sortDefinition`, `filterConfig`, `objects` đổi thế nào.
5. Bỏ trường cuối cùng của một ô: Desktop xoá khoá ô hay để `projections: []`.
6. Đổi thứ tự trong ô; chuyển trường giữa hai ô (Y ↔ Y2).
7. "Rename for this visual": `displayName` ghi ở đâu; đặt lại tên gốc thì sao.
8. Thêm cùng một trường hai lần vào một ô.
9. Với mỗi visual đã sửa ở các bước trên, bật Performance Analyzer, làm mới, chép truy vấn DAX của visual đó (Copy query) vào một file `R-D2-<chữ>-query.txt`: làm mẫu golden cho FR-017 (văn bản truy vấn Desktop sinh cho cấu hình trường mới).

## R15. Nơi đọc trường của visual (rà soát T002, 2026-11-10)

`ReportVisual.fields` và `ReportVisual.raw` đến từ `state.page` (bản đã sửa: `DocumentState.page` → `LayoutEditor.page`) ở mọi nơi vẽ và nạp; sửa hai thuộc tính này trong `PageEdit.visuals` là đủ để mọi nơi thấy trường mới.

| Nơi | Đọc | Quyết định |
|---|---|---|
| `DocumentState.usedFields` (ô tick pane Dữ liệu) | `visual.fields` của `state.visual` | đã dùng bản sửa |
| `VisualCatalog.wells/summary`, Build pane, `DataPlaceholders`, `ReportCanvas` (nhãn tạm) | `visual.fields` | đã dùng bản sửa |
| `VisualQuerySpecReader.spec` | `visual.raw["visual"]["query"]` | giữ nguyên; nhận `ReportVisual` đã sửa từ `ReportInteraction.load(page:visual:state:)` |
| `LiveVisualView.task(id: LoadKey)` | không có trường nào trong khoá | **SỬA (T017)**: thêm băm cấu hình trường vào `LoadKey` |
| `VisualDataLoader` cache | khoá là văn bản DAX | không phải xoá: trường đổi thì văn bản DAX đổi, cùng cấu hình thì trúng cache |
| `ReportInteraction.slicerColumns` (áp bookmark) | `visual.fields` của `workspace.page(id:)` (bản gốc) | giữ bản gốc: bookmark nói về file lúc mở, ghi bookmark là lát sau |
| `ReportInteraction.staticFilters` / `workspace.visualFilters[visual.id]` | bộ lọc cấp visual của file lúc mở | giữ: D2 không đổi `filterConfig` (bỏ trường còn lọc bị chặn, R7) |
| `ShellView` tìm kiếm | `v.fields` của trang gốc | giữ bản gốc: tìm trong file lúc mở (chấp nhận được; đổi sang `state.page` nếu cần ở T039) |
| `ReportPanes.swift:55` (Filters pane: "implicit" = trường của visual chưa có thẻ lọc) | `visual.fields` | dùng bản sửa (cùng `state.visual`) |

