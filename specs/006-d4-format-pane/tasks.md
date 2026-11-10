---
description: "Danh sách việc: D4, Format pane sửa được và lưu .pbix tầng T1"
---

# Việc cần làm: D4, Format pane sửa được

**Đầu vào**: `specs/006-d4-format-pane/` (spec.md, plan.md, research.md, data-model.md, contracts/format-editing.md, contracts/format-save.md, quickstart.md); quan sát VM-D4 ở `docs/phase-d-evidence/vm-d4/QUAN-SAT.md`

**Kiểm thử**: spec yêu cầu (FR-001 đến FR-012, SC-001 đến SC-006): test thuần cho ghép byte định dạng, danh mục và kiểm giá trị; test thao tác và hoàn tác đan xen D1 đến D5; test lưu; test nặng `D4Nhom6` trên Nhom6 (đổi định dạng, lưu, mở lại, so số liệu vẽ).

**Người làm**: lead tự làm, tuần tự, không giao agy (xem `plan.md`, Hiến pháp V: `LayoutEditor`, `DocumentState`, `ReportPanes` giao nhau với D1 đến D5). Vì vậy không có việc `[P]`.

**Quy ước**: `[US1]` đến `[US5]` là câu chuyện trong spec (US1 sửa định dạng đã có; US2 thêm thuộc tính chưa có và đặt lại; US3 định dạng chung của khung visual; US4 lưu và mở lại ở Desktop; US5 hoàn tác chung). Thứ tự: chuẩn bị, nền tảng, US1, US2, US3, US4, US5, hoàn thiện. Lệnh build/test là các lệnh của `CLAUDE.md`; thêm `D4Nhom6` vào bộ lọc golden nặng: `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D5Nhom6|D4Nhom6|EditNhom6|BatchedSerial"`.

**Phần cần người dùng**: T027 (mở `Nhom6_d4.pbix` trong Desktop) cần VM: Claude làm khi người dùng cho phép lần đó, hoặc người dùng làm tay. T028 (VM-D4 vòng 2, mở rộng danh mục) cũng cần VM; chưa có thì giữ danh mục bản đầu, ghi vào `STATE.md`, phần còn lại của lát vẫn xong được.

## Giai đoạn 1: Chuẩn bị

- [X] T001 Tạo `specs/006-d4-format-pane/measurements.md` (mốc trước khi sửa): số test `swift test` (1116), số golden nặng (88), thời gian lưu Nhom6 (`D5Nhom6`), để so ở T037.
- [X] T002 Kiểm kê cặp (khoá, thuộc tính) mà đường vẽ đang đọc: `grep -rhoE "\.(color|number|bool|string|literal|raw|opacity)\(\"[A-Za-z]+\", ?\"[A-Za-z]+\"" Sources/BIPro Sources/PBIXKit`; ghi bảng kết quả vào `research.md` R9 (đã có bản nháp) để T009 đặt cờ `rendered` của danh mục đúng.

## Giai đoạn 2: Nền tảng ghi, giá trị và danh mục (chặn mọi câu chuyện)

**Quan trọng**: chưa làm thao tác và giao diện trước khi qua T010.

- [X] T003 Tạo `Tests/PBIXKitTests/PBIRFormatPatchTests.swift` (test trước, phải thấy trượt) theo `contracts/format-save.md`: (a) đặt thuộc tính đã có: chỉ đổi đúng đoạn byte giá trị; (b) thêm thuộc tính vào mục có sẵn: chèn ở cuối `properties`; (c) thêm khoá vào `objects` / `visualContainerObjects` đã có: chèn cuối; (d) tạo phạm vi mới: `objects` ngay sau `query` và trước `visualContainerObjects`, `visualContainerObjects` trước `drillFilterOtherVisuals`, và khi thiếu cả hai khoá lân cận; (e) `removeProperty` (hết thuộc tính bỏ mục, hết mục bỏ khoá, hết khoá bỏ phạm vi) và `removeObject`; (f) mục có `selector` khác `default` không bị đụng, mục `selector:{id:"default"}` sửa được; tạo mục mới với `selectorDefault` ghi selector sau `properties`; (g) file một dòng và file nhiều dòng có thụt dòng; (h) chuỗi có nháy đơn, tiếng Việt có dấu, `"` và `\`; (i) kết quả khớp các thao tác của VM-D4: nạp `docs/phase-d-evidence/vm-d4/json/*.visual.json`, bỏ khoá định dạng tương ứng rồi áp lại đúng `FormatEdit` thì `objects` và `visualContainerObjects` bằng bản Desktop (so cây JSON); (j) cấu trúc lạ (không có `visual`, khoá là mảng rỗng) ném `WriteError.invalid`.
- [X] T004 Tạo `Sources/PBIXKit/Writing/PBIRFormatPatch.swift` theo `data-model.md` và `contracts/format-save.md`: `FormatScope`, `FormatEdit` (kèm `merging`), `apply(_:to:)` bằng `JSONCursor` (`locate`, `children(at:in:)`) như `PBIRQueryPatch`, kiểm sau ghép bằng `JSONSerialization`, `entries(in:scope:object:)`. Chạy T003 tới khi qua.
- [X] T005 Tạo `Tests/BIProTests/Edit/FormatValueTests.swift` (trước) theo `research.md` R5 và `data-model.md`: (a) đọc từng kiểu từ JSON (bool, số `D` và `L`, chuỗi, màu theme, màu hex, giá trị lạ → `unsupported`); (b) dựng JSON giá trị: `"16D"`, `"1L"`, giữ đuôi của giá trị cũ, hex chữ hoa `'#E4572E'`, nháy đơn gấp đôi `'It''s a test'`, màu theme `ThemeDataColor{ColorId, Percent}`; (c) `validate`: số ngoài khoảng, không phải số, hex thiếu chữ số, chuỗi rỗng ở `title.text`, chuỗi quá 200 ký tự, giá trị ngoài danh sách; (d) khoá gộp `coalesceKey`.
- [X] T006 Tạo `Sources/BIPro/Report/Edit/FormatValue.swift`: `FormatKind`, `FormatChoice`, `NumberTail`, `FormatValue` (`init?(json:kind:)`, `json(kind:)`, `validate(kind:)`), `FormatTarget.coalesceKey`. Chạy T005 tới khi qua.
- [X] T007 Tạo `Tests/BIProTests/Edit/FormatCatalogTests.swift` (trước) theo `research.md` R4 và R13: (a) mọi thuộc tính có `observed` không rỗng; (b) không trùng `(khoá, thuộc tính)` trong một thẻ; (c) danh sách giá trị chỉ gồm giá trị đã quan sát (R4 ghi chú); (d) với Nhom6 (test nặng ở T033, ở đây dùng `SyntheticReport`): mọi cặp (khoá, thuộc tính) mục chung có trong danh mục của loại visual hoặc nằm trong `readOnlyKeys`; (e) `cards(for:scope:)` đúng cho `card`, `slicer`, biểu đồ trục, `donutChart`, `pivotTable`, `actionButton`, `cardVisual`, `textbox`, và phạm vi Chung dùng cho mọi loại.
- [X] T008 Tạo `Sources/BIPro/Report/Edit/FormatCatalog.swift`: `FormatProperty`, `FormatCard`, `FormatCatalog` theo bảng R4 (thẻ, tên Việt, kiểu điều khiển, khoảng, `observed`, `rendered` theo T002, `addable`); bổ sung tên Việt vào `FormatNames` (`Sources/BIPro/Formatting.swift` hoặc nơi `FormatNames` đang ở). Chạy T007 tới khi qua.
- [X] T009 Mở rộng `Tests/BIProTests/Edit/SyntheticReport.swift`: visual mẫu `card`, `slicer`, `lineClusteredColumnComboChart`, `pivotTable`, `cardVisual` (không có `objects`), và visual có mục `selector` `metadata`/`data`, để các test T010 trở đi dùng.
- [X] T010 **Điểm kiểm nền tảng**: `swift build` và `swift test` qua (T003, T005, T007 xanh, mọi test cũ giữ nguyên).

## Giai đoạn 3: Câu chuyện 1 (P1): sửa định dạng đã có của visual

**Mục tiêu**: ở Sửa, chọn một visual, đổi giá trị thuộc tính đang hiện trong Format pane; canvas vẽ lại ngay.

**Kiểm thử độc lập**: mở Nhom6, chọn card ở trang D3, đổi cỡ chữ "Giá trị" và tắt "Nhãn danh mục"; card vẽ lại ngay; ⌘Z trả về giá trị cũ.

- [X] T011 [US1] Tạo `Tests/BIProTests/Edit/FormatEditingTests.swift` (trước) theo `contracts/format-editing.md`: (a) `setFormat` trên thuộc tính đã có đổi `raw`, `objects` và `containerObjects` của `ReportVisual`; (b) từ chối khi chế độ Xem, báo cáo cũ, nhiều visual, visual trong nhóm (kèm lý do, không bước hoàn tác); (c) từ chối số ngoài khoảng, hex sai, chuỗi rỗng ở tiêu đề, giá trị ngoài danh sách; (d) giá trị trùng giá trị hiện có không tạo bước; (e) mục có selector `metadata`/`data` không sửa được; (f) `formatState(of:)` trả thẻ, thuộc tính, giá trị hiện tại, cờ chỉ-đọc, cờ `rendered`; (g) visual mới (`added`) cập nhật `added[id]`; (h) sửa định dạng rồi nhân bản visual (D1) hoặc nhân bản trang (D5): bản sao mang định dạng đã sửa; (i) sửa trường (D2) chưa lưu rồi sửa định dạng: `fields` và `raw.query` còn nguyên (A1); (j) sửa định dạng của khoá rồi đổi loại làm khoá đó bị bỏ (D3): khoá không xuất hiện lại, `formats` của khoá được dọn (A2).
- [X] T012 [US1] Mở rộng `PageEdit` (`formats: [String: [FormatEdit]]`) trong `Sources/BIPro/Report/Edit/LayoutEditor.swift`; tạo `Sources/BIPro/Report/Edit/LayoutEditor+Format.swift`: `setFormat(_:value:visual:)`, `formatState(of:)`, dựng lại `bytes = PBIRFormatPatch.apply(formats, to: base)` rồi cập nhật `raw`, `objects`, `containerObjects` (như `setText` của D3) nhưng áp `formats` lên bản đã gồm sửa trường (`queries`) và văn bản đang chờ, như `makeChanges`, để `raw` không mất sửa khác (A1); `changeType` khi bỏ khoá `objects` thì dọn `formats` của các khoá đó (A2); `commit` nhận khoá gộp (`FormatTarget.coalesceKey`), giá trị trùng thì không commit. Chạy T011 tới khi qua.
- [X] T013 [US1] Bọc trong `Sources/BIPro/DocumentState.swift`: `setFormat`, `formatState`, `isFormatEditable` (lý do mờ: Xem, báo cáo cũ, nhiều visual). Không đổi `DocumentState` ngoài phần này.
- [X] T014 [US1] Tạo `Sources/BIPro/Panes/FormatPane.swift` (giao diện): hai phạm vi Visual/Chung, thẻ `DisclosureGroup` theo `FormatCatalog`, công tắc đầu thẻ, hàng thuộc tính với điều khiển theo `FormatKind` (công tắc, ô số có mũi tên và kẹp, `Picker`, ô chữ, ô màu chỉ gồm swatch + popover hàng theme gốc + ô hex), ghi chú "BI Pro chưa vẽ thuộc tính này" khi `rendered == false`, mục "Khác (chỉ đọc)" cho khoá ngoài danh mục, mờ kèm lý do; thay `FormatCard` và `format` trong `Sources/BIPro/Panes/ReportPanes.swift` bằng `FormatPane`.
- [X] T015 [US1] Bấm thử trong app (chụp riêng cửa sổ, tắt app sau): `zsh scripts/build-app.sh`, mở bản sao Nhom6 trên Desktop, ⌘E, chọn card D3 đổi cỡ chữ và tắt nhãn danh mục, chọn biểu đồ đổi `legend`/`labels`; ⌘Z; ảnh vào `docs/phase-d-evidence/vm-d4/app-d4-*.png`. Ghi kết quả vào `STATE.md`.

## Giai đoạn 4: Câu chuyện 2 (P1): thêm thuộc tính chưa có và đặt lại về mặc định

**Mục tiêu**: bật legend, tiêu đề trục, nhãn dữ liệu chưa có trong file; đặt lại thẻ hoặc thuộc tính về mặc định.

**Kiểm thử độc lập**: thêm một biểu đồ cột nhóm mới (D3), thả trường, bật nhãn dữ liệu và tiêu đề trục, "Đặt lại" thẻ nhãn: `visual.json` trong bộ nhớ quay về y như trước khi bật.

- [X] T016 [US2] Mở rộng `FormatEditingTests.swift` (trước): (a) bật thẻ chưa có (`labels.show`) thêm khoá ở cuối `objects`; thêm thuộc tính vào mục có sẵn ở cuối `properties`; (b) visual không có `objects` (`cardVisual`, biểu đồ mới) tạo `objects` đúng chỗ; visual không có `visualContainerObjects` tạo đúng chỗ khi bật hoặc tắt `title`; (c) `cardVisual` ghi `selector:{id:default}` sau `properties`; (d) thuộc tính `addable == false` (`subTotals`, `actionButton`) không thêm được khi chưa có trong file, sửa được khi có; (e) `resetFormat(card:)` bỏ cả khoá, `resetFormat(property:card:)` bỏ thuộc tính; đặt lại khi khoá không có thì không tạo bước; (f) khoá phạm vi cuối cùng bị bỏ khi hết khoá (R7); (g) đặt lại rồi hoàn tác khôi phục đúng.
- [X] T017 [US2] Thêm `resetFormat(card:visual:)`, `resetFormat(property:card:visual:)` và logic `addable` vào `Sources/BIPro/Report/Edit/LayoutEditor+Format.swift`; bọc trong `DocumentState`; nút "Đặt lại" ở chân thẻ và "Đặt lại" trong popover màu của `FormatPane.swift`; visual thuộc loại có ô trường (theo `WellRules`) mà chưa có trường hiện "Thêm trường để bắt đầu định dạng" thay cho thẻ (R11); loại không có ô trường (hộp văn bản, ảnh, nút) vẫn hiện thẻ của loại đó nếu danh mục có (A4). Chạy T016 tới khi qua.

## Giai đoạn 5: Câu chuyện 3 (P1): định dạng chung của khung visual

**Mục tiêu**: đổi tiêu đề, phụ đề, nền, viền, bóng, đệm, biểu tượng tiêu đề ở phạm vi "Chung".

**Kiểm thử độc lập**: chọn một biểu đồ thanh ở D3, đổi chữ tiêu đề, bật viền và đổi màu nền; canvas đổi ngay.

- [X] T018 [US3] Tạo test trong `FormatEditingTests.swift` (trước) cho phạm vi Chung: (a) `title` (`show`, `text`, `fontSize`, `bold`, `alignment`, `fontColor`) sửa và thêm; `subTitle`; `background` (`transparency` một mình không ghi `show`); `border` (`show`, `radius`, `width`); `dropShadow.show`; `padding` bốn cạnh; `visualHeader.show`; (b) `visualLink` chỉ-đọc; (c) tiêu đề rỗng từ chối; chữ có nháy đơn ghi gấp đôi; (d) đổi tiêu đề của visual có `title.text` đổi `containerObjects.title` mà `ReportInteraction` hiển thị (kiểm bằng `visual.containerObjects.string("title","text")`).
- [X] T019 [US3] Hoàn thiện phạm vi Chung trong `FormatCatalog.swift` và `FormatPane.swift` nếu T018 phát hiện thiếu (cờ `rendered`: `padding`, `subTitle`, `visualHeader` là `false`); kiểm đường vẽ vẽ lại ngay `title`, `background`, `border` (chụp riêng cửa sổ app cho `title`, `background`, `border` sau khi đổi, ảnh vào `docs/phase-d-evidence/vm-d4/app-d4-chung-*.png`, ghi vào `STATE.md`; A7). Chạy T018 tới khi qua.

## Giai đoạn 6: Câu chuyện 4 (P1): lưu và mở lại được trong Power BI Desktop

**Mục tiêu**: ⌘S ghi định dạng vào `.pbix` T1; mở lại ở BI Pro và Desktop không lỗi, đúng định dạng.

**Kiểm thử độc lập**: kịch bản Nhom6 (card, slicer, combo, matrix, visual mới) rồi ⌘S; đọc lại bằng `PBIXFile`; Desktop mở `Nhom6_d4.pbix`.

- [X] T020 [US4] Tạo `Tests/BIProTests/Edit/FormatSavingTests.swift` (trước) theo `contracts/format-save.md`: (a) chỉ `visual.json` của visual đã sửa đổi trong `changes.reportParts`; các part khác không có; (b) `visual.json` ghi ra đúng mong đợi (đặt, thêm, bỏ, tạo phạm vi); (c) visual `added` mang định dạng trong `added[id]`; (d) sửa định dạng và đổi loại/văn bản/trường cùng visual: các bước ghép theo thứ tự, kết quả đúng; (e) `verifyLayout` chấp nhận bản dựng thật và từ chối khi `objects`/`containerObjects` đọc lại khác trạng thái đang sửa; (f) lưu lần hai không có gì mới thì không ghi gì; (g) hoàn tác về trạng thái đã lưu: `isDirty` false; (h) bản sao visual hoặc trang mang định dạng đã sửa vào file (A3).
- [X] T021 [US4] Thêm vào `makeChanges` ở `Sources/BIPro/Report/Edit/LayoutEditor.swift` bước `PBIRFormatPatch.apply` (sau đổi loại, văn bản, truy vấn; trước `patch` vị trí) và vào `DocumentSaver.verifyLayout` (`Sources/BIPro/Report/Edit/DocumentSaver.swift`) phép so `objects` và `containerObjects`. Chạy T020 tới khi qua.
- [X] T022 [US4] Tạo `Tests/BIProTests/Edit/D4Nhom6Tests.swift` (nặng, `BIPRO_HEAVY=1`, như `D5Nhom6Tests`): mở Nhom6, (a) card D3 đổi cỡ chữ và tắt nhãn danh mục; (b) slicer tắt header, đổi `items.padding`; (c) combo Q3.4 bật nhãn dữ liệu, đổi legend, tiêu đề (chữ, cỡ, màu hex), nền, viền; (d) matrix D1 đổi cỡ chữ `columnHeaders`; (e) thêm một visual mới (D3) bật/tắt tiêu đề; lưu bằng `DocumentSaver` vào `build/d-out/D4/Nhom6_d4.pbix`; mở lại bằng `PBIXFile`: định dạng đúng, mọi part khác khớp byte (trừ `SecurityBindings` và `[Content_Types].xml`), số liệu và truy vấn của visual không sửa vẽ cùng số, ghi thời gian từng thao tác (SC-001) và lưu (SC-003) vào `measurements.md`; ghi `build/d-out/D4/CHECKLIST.md` (mục kiểm cho Desktop). Thêm kiểm kê ở test này: mọi cặp (khoá, thuộc tính) mục chung của Nhom6 có trong danh mục hoặc `readOnlyKeys` (hoàn tất ý (d) của T007).
- [X] T023 [US4] Chạy `swift build`, `swift test`, và golden nặng (có `D4Nhom6`): số qua không thấp hơn mốc ở T001 cộng test mới; ghi vào `measurements.md`.

## Giai đoạn 7: Câu chuyện 5 (P2): hoàn tác chung một lịch sử

**Mục tiêu**: mỗi lần sửa định dạng là một bước chung ngăn xếp với D1 đến D5; sửa liên tiếp cùng thuộc tính gộp một bước.

**Kiểm thử độc lập**: xen kẽ kéo visual, đổi màu nền, thả trường, đổi cỡ chữ, thêm trang, rồi ⌘Z/⇧⌘Z lần lượt.

- [X] T024 [US5] Tạo `Tests/BIProTests/Edit/FormatUndoTests.swift`: (a) chuỗi hỗn hợp (kéo, thả trường, đổi loại, thao tác trang D5, sửa định dạng) hoàn tác và làm lại từng bước, `objects` và `containerObjects` từng visual trở về đúng giá trị trước (kể cả khoá vắng mặt); (b) gõ liên tiếp cùng thuộc tính (ví dụ 5 lần đổi `fontSize`) là một bước, đổi thuộc tính khác thì bước mới; (c) hoàn tác về trước khi có sửa: `isDirty` false, ⌘S không còn việc; (d) hoàn tác đổi loại rồi định dạng giữ đúng thứ tự; (e) giới hạn lịch sử vẫn đúng với bước định dạng. Sửa `LayoutEditor+Format.swift` nếu T024 phát hiện lệch.

## Giai đoạn 8: Hoàn thiện

- [X] T025 Chạy `swift test` toàn bộ và golden nặng một lần nữa; không còn test trượt; ghi số vào `measurements.md` (T001 so T023).
- [X] T026 Chạy `/code-review`; xử lý phát hiện nghiêm trọng; không dùng skill mattpocock khác.
- [X] T027 Kiểm Power BI Desktop (VM): mở `Nhom6_d4.pbix` trong Desktop (VM, người dùng làm tay hoặc Claude khi được phép) theo `build/d-out/D4/CHECKLIST.md`; ghi kết quả.
- [X] T028 VM-D4 vòng 2 (khi có quyền): lưới màu theme đủ `Percent` từng hàng; giá trị `title.alignment`; `border.color`; màu nền/bóng; matrix (`columnHeaders`, `subTotals` thêm mới); phông; khoảng đúng của ô số; reset thẻ cuối làm `objects` rỗng. Mỗi mục đã quan sát thì thêm vào `FormatCatalog.swift` và test; ghi vào `QUAN-SAT.md`.
- [X] T029 Cập nhật `docs/STATE.md` (D4 xong, bằng chứng, việc dở), `docs/BIPRO_BUILD_PLAN.md` (đánh dấu D4 trong Phase D), `docs/phase-d-ownership.tsv` (đã thêm D4; kiểm đủ file), `specs/006-d4-format-pane/research.md` (cập nhật R4, R5 theo điều đã làm).
- [X] T030 Chạy `/speckit-converge` trên `specs/006-d4-format-pane/` và xử lý việc nó thêm vào.

## Phụ thuộc và thứ tự

- Giai đoạn 2 chặn mọi câu chuyện; T010 là điểm kiểm.
- US1 (T011 đến T015) trước US2 và US3, vì cùng `LayoutEditor+Format.swift` và `FormatPane.swift`.
- US4 cần US1 (có thao tác để lưu); US5 cần US1 và US2.
- T027 và T028 phụ thuộc T022 và quyền điều khiển VM; không chặn T025, T026, T029.
- T030 (converge) làm cuối, sau T029.

## Phủ yêu cầu

| Yêu cầu | Việc |
|---|---|
| FR-001 | T005, T006, T011 đến T014 |
| FR-002 | T003, T004, T012, T022 |
| FR-003 | T007, T008, T022 |
| FR-004 | T016, T017 |
| FR-005 | T016, T017 |
| FR-006 | T018, T019 |
| FR-007 | T003, T011, T016 |
| FR-008 | T024 |
| FR-009 | T020, T021, T022 |
| FR-010 | T020 đến T023, T027 |
| FR-011 | T011, T013, T014 |
| FR-012 | T023, T025 |
| SC-001 | T022 |
| SC-002 | T016, T024 |
| SC-003 | T022 |
| SC-004 | T027 |
| SC-005 | T007, T022 |
| SC-006 | T023, T025 |

## Chiến lược

- **MVP**: giai đoạn 1 đến 3 (sửa giá trị đã có) đã dùng được; thêm thuộc tính, phạm vi Chung và lưu làm tiếp theo thứ tự (lưu cần có để thành tính năng thật, nên giai đoạn 6 không bỏ).
- Phần cần VM (T027, T028) không chặn MVP; điều chưa quan sát giữ chỉ-đọc hoặc không có trong danh mục.
- Mỗi giai đoạn dừng được: danh mục chỉ-đọc cho phần chưa quan sát nên không có lối thoát hỏng file.

## Giai đoạn 9: Hội tụ (Convergence)

- [X] T031 Thêm test cho SC-005 (0 khoá bịa) ở `Tests/BIProTests/Edit/FormatCatalogTests.swift`: mọi `(khoá, thuộc tính)` của danh mục có nguồn `VM-D4` mà không có `Nhom6` phải xuất hiện trong `docs/phase-d-evidence/vm-d4/json/*.visual.json` hoặc được liệt kê trong `docs/phase-d-evidence/vm-d4/QUAN-SAT.md`; mọi `(khoá, thuộc tính)` có nguồn `Nhom6` phải xuất hiện ở Nhom6 (kiểm trong `D4Nhom6Tests`), per SC-005, FR-003 (partial)
- [X] T032 Hiện lý do ở hàng thuộc tính có kiểu giá trị chưa hỗ trợ (màu theo công thức, biểu thức khác) trong `Sources/BIPro/Panes/FormatPane.swift`: nhãn "chỉ đọc: <lý do>" và `.help`, per US1/AC5 (partial)
- [X] T033 Khi công tắc đầu thẻ tắt, mờ các hàng thuộc tính con của thẻ nhưng giữ nguyên giá trị (không xoá) trong `Sources/BIPro/Panes/FormatPane.swift`, per US2/AC4 (partial)
- [X] T034 Đồng bộ `specs/006-d4-format-pane/data-model.md` với mã: bỏ `PBIRFormatPatch.entries(in:scope:object:)` (không cần), ghi `FormatEdit.merging` và các kiểu `FormatState`/`FormatCardState`/`FormatReadOnlyItem` thực tế, per plan: cấu trúc mã nguồn (partial)
