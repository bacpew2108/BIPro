---
description: "Danh sách việc: D6, bookmark và bộ lọc người dùng ghi vào .pbix tầng T1"
---

# Việc cần làm: D6, bookmark và bộ lọc ghi vào file

**Đầu vào**: `specs/007-d6-bookmark-filter/` (spec.md, plan.md, research.md, data-model.md, contracts/bookmark-editing.md, contracts/filter-editing.md, contracts/bookmark-filter-save.md, quickstart.md)

**Kiểm thử**: spec yêu cầu (FR-001 đến FR-011, SC-001 đến SC-006): test thuần cho ghép byte bookmark và thẻ lọc, xuất trạng thái phiên sang JSON, luật gộp hai lớp; test thao tác và hoàn tác đan xen D1 đến D5; test lưu; test nặng `D6Nhom6` trên Nhom6.

**Người làm**: lead tự làm, tuần tự, không giao agy (Hiến pháp V: `LayoutEditor`, `DocumentState`, `ReportInteraction`, `ReportPanes` giao nhau với D1 đến D5). Không có việc `[P]`.

**Quy ước**: `[US1]` đến `[US6]` là câu chuyện trong spec (US1 thêm bookmark Display và lưu; US2 cập nhật, đổi tên, xoá, đổi thứ tự; US3 bộ lọc ghi vào file; US4 bookmark Data; US5 lưu và mở lại ở Desktop; US6 hoàn tác chung). Thứ tự: chuẩn bị, quan sát VM-D6 (cổng), nền tảng ghi, nền tảng trạng thái, US1, US2, US3, US4, US5, US6, hoàn thiện.

**Quyết định của người dùng (2026-11-11)**: (1) Xem chỉ để xem: sửa bookmark và bộ lọc chỉ ở Sửa; bấm bookmark để áp vẫn được. (2) Cho phép Claude điều khiển VM ở T004 đến T007 (lần này; quy tắc "agent không điều khiển VM" của hiến pháp vẫn giữ cho lần sau).

**Quy tắc cổng**: không viết bộ ghi của một dạng (bookmark Display mặc định, Data, Advanced, Top N…) trước khi T007 chốt dạng đó. Dạng không chốt được: `FilterExport`/`BookmarkExport` trả `sessionOnly` kèm lý do, không ghi (SC-005); ghi vào `STATE.md`.

## Giai đoạn 1: Chuẩn bị

- [X] T001 Tạo `specs/007-d6-bookmark-filter/measurements.md` (mốc trước khi sửa): số test `swift test` (1200), số golden nặng (89), thời gian lưu Nhom6 (`D5Nhom6`), để so ở T039.
- [X] T002 Thêm các file D6 vào `docs/phase-d-ownership.tsv` (lead giữ).

## Giai đoạn 2: Quan sát VM-D6 (cổng; chặn mã ghi)

Làm theo bảng R2 của `research.md`. Cách làm như VM-D4/D5: bản sao Nhom6 trong VM (`C:\Users\bacpew\vmd6\`, xoá sau khi dùng), đổi một thứ trong Power BI Desktop, ⌘S/Ctrl+S, chép file sang Mac (`~/Desktop` bản sao, không ghi `~/Downloads`), so diff `bookmarks/`, `report.json`, `page.json`, `visual.json`. Chỉ quan sát giao diện và file Desktop ghi; không dịch ngược. Điều khiển VM: `prlctl exec --current-user`, `cliclick`, `osascript`, `screencapture` (xem mẹo trong `STATE.md`).

- [X] T003 Chuẩn bị buổi VM-D6: bản sao Nhom6 ở `docs/phase-d-evidence/vm-d6/work/` (tạm, xoá sau), thư mục VM, kịch bản từng bước (một thao tác một lần lưu) và mẫu `QUAN-SAT.md` ở `docs/phase-d-evidence/vm-d6/`.
- [X] T004 Quan sát bookmark (R2a–e, h, i): Add bookmark mặc định (Data, Display, Current page bật); tắt Data; tắt Display; tắt Current page; All visuals và Selected visuals; Update; Rename; Delete (kể cả bookmark cuối cùng: `bookmarks.json` còn hay mất); kéo đổi thứ tự; Group; Desktop có chuẩn hoá lại file bookmark không đổi khi lưu không; nút action `Bookmark` trỏ bookmark đã xoá. Lưu bản chụp từng file vào `docs/phase-d-evidence/vm-d6/json/`.
- [X] T005 Quan sát Filters pane (R2g): thêm Basic (là, không phải) ở visual, trang, báo cáo; Advanced chữ và số (Và/Hoặc); Top N; bỏ thẻ; Clear filter; Lock/Hide thẻ; ghi vị trí thẻ mới trong `filterConfig.filters`, tên thẻ Desktop sinh, bí danh `From`, `howCreated`, `filterConfig` khi chưa có và khi hết thẻ.
- [X] T006 Quan sát bookmark Data (R2f): Add bookmark Data sau khi đổi slicer và Filters pane; so với `bookmark-data.pbix`; thử xem phần nào Desktop chấp nhận khi thiếu (nếu muốn xác định dạng tối thiểu thì dựng bản BI Pro thử mở trong Desktop ở T035).
- [X] T007 Viết `docs/phase-d-evidence/vm-d6/QUAN-SAT.md` (bảng kết quả từng ô R2, ảnh `desktop-*.png`), cập nhật `research.md` R2 (đánh dấu đã quan sát) và R6/R7 (dạng ghi được), cập nhật các `contracts/` nếu quan sát khác dự kiến; ghi dạng nào chuyển `sessionOnly`. **Điểm kiểm cổng**: người viết xác nhận từng dạng "ghi được" hay "chỉ trong phiên" trước khi sang giai đoạn 3.

## Giai đoạn 3: Nền tảng ghi ở `PBIXKit` (chặn mọi câu chuyện)

- [X] T008 Tạo `Tests/PBIXKitTests/PBIRBookmarkPatchTests.swift` (test trước, phải thấy trượt) theo `contracts/bookmark-filter-save.md`: (a) dựng file bookmark từ `BookmarkSpec` khớp từng byte mẫu Desktop ở T004 cho từng tổ hợp tuỳ chọn; (b) thêm `{name}` cuối `items` của `bookmarks.json`, tạo `bookmarks.json` khi chưa có (theo T004); (c) đổi `displayName` chỉ đổi đúng đoạn byte; (d) xoá item và file (đã có `bookmarkItemsRemoving`), bookmark cuối theo T004; (e) đổi thứ tự `items`, bookmark nhóm `children` giữ nguyên; (f) bỏ mã visual khỏi `targetVisualNames` và `visualContainers`; (g) kiểm sau ghép: thất bại khi kết quả không khớp mô hình.
- [X] T009 Tạo `Sources/PBIXKit/Writing/PBIRBookmarkPatch.swift`: `BookmarkSpec`, `newBookmarkJSON(_:)`, `addingItem`, `renamingDisplayName`, `reorderingItems`, `removingVisuals` (dùng `JSONCursor`, cùng kiểu `PBIRPagePatch`); chạy T008 tới khi qua. Dạng chưa quan sát: không có hàm dựng.
- [X] T010 Tạo `Tests/PBIXKitTests/PBIRFilterPatchTests.swift` (trước): (a) thêm thẻ vào `filterConfig.filters` có sẵn (đúng chỗ theo T005, thẻ cũ nguyên byte); (b) tạo `filterConfig` ở `report.json`, `page.json`, `visual.json` khi chưa có; (c) thay thẻ theo `name`; (d) bỏ thẻ; hết thẻ thì theo T005; (e) dựng thẻ Categorical `In` và `Not In` khớp byte mẫu Desktop; (f) kiểm sau ghép.
- [X] T011 Tạo `Sources/PBIXKit/Writing/PBIRFilterPatch.swift`: `FilterCardSpec` (Basic; Advanced/TopN chỉ khi T007 chốt), `setCard`, `removeCard`, `categoricalCardJSON`; chạy T010 tới khi qua.
- [X] T012 **Điểm kiểm nền tảng ghi**: `swift build` và `swift test` qua (T008, T010 xanh, mọi test cũ giữ nguyên).

## Giai đoạn 4: Nền tảng trạng thái ở `BIPro` (chặn mọi câu chuyện)

- [X] T013 Tạo `Tests/BIProTests/Edit/ReportEditsTests.swift` (trước) theo `data-model.md`: (a) `ReportEdits` là giá trị thuần, so sánh bằng được; (b) hàm gộp `effectiveFilters(file, edits, session)` và `effectiveBookmarks(file, edits, session)` đúng thứ tự (file, tài liệu, phiên) và luật `deleted`, `renamed`, `order`, `.remove`; (c) `edits` nằm trong ảnh chụp nên `isDirty` (theo `cleanMark` như D1 đến D5) đổi khi thao tác và về sạch khi hoàn tác tới điểm đã lưu; (d) trang bị xoá thì thay đổi lọc của trang đó và bookmark trỏ trang đó bị bỏ khỏi gói ghi.
- [X] T014 Tạo `Sources/BIPro/Report/Edit/ReportEdits.swift` (`ReportEdits`, `BookmarkEdits`, `FilterChange`, `ExportResult`, các hàm gộp); mở rộng `LayoutSnapshot` (`edits`) trong `Sources/BIPro/Report/Edit/LayoutEditor.swift`; thêm `commitReport(_:)` (một bước hoàn tác, không gộp theo thời gian, có khoá gộp tuỳ chọn cho sửa liên tiếp cùng thẻ lọc) ở `Sources/BIPro/Report/Edit/LayoutEditor+Report.swift`. Chạy T013 tới khi qua.
- [X] T015 Tạo `Tests/BIProTests/Edit/BookmarkExportTests.swift` (trước) rồi `Sources/BIPro/Report/Edit/BookmarkExport.swift`: `UserBookmark` (tuỳ chọn, `pageID`, `visibility`) và tập visual từng trang của `LayoutEditor` → `ExportResult<BookmarkSpec>`; dạng chưa quan sát → `.sessionOnly(reason)`; không bao giờ ghi đoán (SC-005).
- [X] T016 Tạo `Tests/BIProTests/Edit/FilterExportTests.swift` (trước) rồi `Sources/BIPro/Report/Edit/FilterExport.swift`: `UserFilter` (Basic là/không phải; Advanced, Top N, thẻ measure theo T007) → `ExportResult<FilterCardSpec>`; chưa chọn giá trị theo T005; cột không còn trong mô hình thì `.sessionOnly("cột không còn trong mô hình")`.
- [X] T017 **Điểm kiểm nền tảng trạng thái**: `swift build` và `swift test` qua.

## Giai đoạn 5: Câu chuyện 1 (P1): thêm bookmark Display/trang và lưu vào file

**Mục tiêu**: ở Sửa, ẩn một visual, thêm bookmark (Data tắt, Display và Current page bật), lưu, mở lại; bookmark còn và áp đúng. Ở Xem các nút sửa bị mờ kèm lý do.

**Kiểm thử độc lập**: mở Nhom6, ⌘E, ẩn một visual, thêm bookmark, ⌘S, mở lại: bookmark có trong danh sách, bấm vào ẩn đúng visual và chuyển đúng trang.

- [X] T018 [US1] Tạo `Tests/BIProTests/Edit/BookmarkFilterSavingTests.swift` (trước, phần bookmark): (a) thêm bookmark rồi `makeChanges` ghi `bookmarks.json` (item cuối) và `<name>.bookmark.json` đúng mẫu T004, các part khác không có trong gói; (b) lưu hai lần liên tiếp: lần hai không ghi gì (R4); (c) mã 20 hex không trùng; (d) báo cáo định dạng cũ: không ghi, có lý do; (e) bookmark mồ côi trên đĩa (không có trong `items`) và bookmark nhóm không bị đụng; (f) bookmark `sessionOnly` bị bỏ qua, các bookmark khác vẫn ghi và có thông báo số bị bỏ qua.
- [X] T019 [US1] Mở rộng `Sources/BIPro/Report/Edit/LayoutEditor+Report.swift`: `addBookmark(name:options:)`, `bookmarkStatus(id:)` (ghi được / chỉ trong phiên + lý do); `makeChanges` ghi bookmark (dùng `BookmarkExport`, `PBIRBookmarkPatch`) so với bytes trên đĩa theo R4; mã mới qua `PBIRLayoutPatch.makePageName(avoiding:)`.
- [X] T020 [US1] Bọc trong `Sources/BIPro/DocumentState.swift`: `addBookmark`, `isBookmarkEditable` (lý do mờ: Xem, báo cáo cũ); bố trí lại `Sources/BIPro/Report/UserBookmark.swift` và `Sources/BIPro/Panes/ReportPanes.swift` (`BookmarksPane`): nút "+" gọi `DocumentState` ở Sửa, mờ ở Xem (các hàm `addBookmark`/`updateBookmark`/… trong `ReportInteraction` giữ cho test hiện có và cho trạng thái phiên do áp bookmark; giao diện không gọi chúng nữa); hàng bookmark `sessionOnly` hiện nhãn "chưa lưu được vào file: <lý do>"; `bookmarkRows` đọc giá trị gộp (file, tài liệu, phiên). Bấm bookmark để áp không đổi.
- [X] T021 [US1] Bấm thử trong app (chụp riêng cửa sổ app, tắt app sau): `zsh scripts/build-app.sh`, mở bản sao Nhom6 trên Desktop, ⌘E, ẩn một visual, thêm bookmark; đổi sang Xem: nút mờ; ⌘S rồi mở lại; ảnh vào `docs/phase-d-evidence/vm-d6/app-d6-*.png`.

## Giai đoạn 6: Câu chuyện 2 (P1): cập nhật, đổi tên, xoá, đổi thứ tự bookmark

**Mục tiêu**: các thao tác còn lại của Bookmarks pane ghi đúng vào file.

**Kiểm thử độc lập**: trên Nhom6 xoá `Bookmark_Q13_MuaVu`, đổi tên `Bookmark_Q13_GioThu`, lưu: file bookmark bị xoá và item bỏ khỏi `bookmarks.json`, bookmark còn lại có `displayName` mới còn mọi khoá khác như cũ.

- [X] T022 [US2] Mở rộng `BookmarkFilterSavingTests.swift` (trước): (a) đổi tên file bookmark chỉ đổi `displayName`; (b) xoá bỏ item và file, nút action `Bookmark` trỏ nó giữ nguyên; (c) cập nhật ghi lại cả file giữ `name`, `displayName`, tuỳ chọn; (d) kéo đổi thứ tự đổi `items`; (e) bookmark cuối: theo T004; (f) bookmark tạo rồi xoá trong cùng phiên không để lại gì; (g) tên trùng bookmark khác hoặc quá dài (hơn 128 ký tự) bị từ chối.
- [X] T023 [US2] Thêm `updateBookmark`, `renameBookmark`, `deleteBookmark`, `moveBookmark`, `setBookmarkOption` vào `LayoutEditor+Report.swift` (mỗi cái một bước; tên rỗng, trùng hoặc quá dài bị từ chối kèm lý do), ghi trong `makeChanges`; bọc trong `DocumentState`; nối menu và kéo thứ tự trong `BookmarksPane` (kèm cảnh báo khi xoá bookmark còn nút action trỏ tới; mờ ở Xem).
- [X] T024 [US2] Phối hợp D1 và D5 (FR-008): trong `LayoutEditor` bỏ mã visual đã xoá khỏi `targetVisualNames` của mọi bookmark (kèm `visualContainers` đã có); xoá trang bỏ bookmark thêm trong phiên trỏ trang đó và thay đổi lọc của trang; thêm test vào `BookmarkFilterSavingTests.swift` (trước khi viết logic).

## Giai đoạn 7: Câu chuyện 3 (P1): bộ lọc ghi vào file

**Mục tiêu**: thêm, sửa, bỏ thẻ ở cấp báo cáo, trang, visual ở Sửa; lưu; mở lại, số liệu khớp.

**Kiểm thử độc lập**: trên Nhom6 thêm Basic "là" ở cấp trang, sửa `fNoUnknownYear`, bỏ một thẻ cấp visual, lưu, mở lại: số liệu các visual khớp trước khi lưu; mỗi part đổi đúng một chỗ.

- [X] T025 [US3] Mở rộng `BookmarkFilterSavingTests.swift` (trước, phần lọc): (a) thêm thẻ Basic mới ở từng cấp ghi đúng part, thẻ cũ nguyên byte; (b) sửa giá trị và đổi là ↔ không phải thay đúng thẻ; (c) bỏ thẻ của file xoá thẻ trong `filterConfig`; (d) thẻ Advanced/Top N/measure theo T007 (ghi nếu chốt, ngược lại `sessionOnly` có lý do); (e) lưu hai lần: lần hai không ghi; (f) báo cáo cũ không ghi.
- [X] T026 [US3] Thêm `setFilter`, `removeFilter` vào `LayoutEditor+Report.swift` (khoá gộp theo `UserFilterKey` cho sửa liên tiếp), ghi trong `makeChanges` bằng `FilterExport` và `PBIRFilterPatch`; bọc trong `DocumentState` (`isFilterEditable`: Xem, báo cáo cũ).
- [X] T027 [US3] Đọc gộp (R3): thêm `ReportInteraction.effectiveUserFilters`/`effectiveRemovedFilters` (file, tài liệu, phiên) và đổi các chỗ đọc `userFilters`, `removedFilters` sang giá trị gộp (`grep -rn "userFilters\|removedFilters" Sources/BIPro`: `ReportPanes.swift`, `FilterEditor.swift`, `LiveVisual.swift`, `ReportInteraction.swift`); lớp phiên chỉ còn do áp bookmark và slicer. Test trước trong `ReportEditsTests.swift`: sửa lọc ở Sửa đổi số liệu của visual; áp bookmark Data đè lớp phiên mà không đổi `edits`.
- [X] T028 [US3] Nối `FilterEditor` và thẻ trong `Sources/BIPro/Panes/ReportPanes.swift`: ở Sửa mọi sửa đi qua `DocumentState.setFilter/removeFilter`; ở Xem thẻ chỉ đọc (mờ kèm lý do); thẻ `sessionOnly` có nhãn "chưa lưu được vào file: <lý do>".
- [X] T029 [US3] Bấm thử trong app: thêm Basic cấp trang, sửa thẻ cấp visual, bỏ thẻ, ⌘Z từng bước, ⌘S, mở lại; số liệu khớp; ảnh vào `docs/phase-d-evidence/vm-d6/app-d6-*.png`.

## Giai đoạn 8: Câu chuyện 4 (P2): bookmark có Data

**Mục tiêu**: thêm bookmark Data (mặc định của Power BI) sau khi đổi slicer và bộ lọc; bấm thì khôi phục. **Chỉ làm phần ghi nếu T006/T007 chốt dạng tối thiểu Desktop chấp nhận**; nếu không, giữ `sessionOnly` (đã có từ T015) và ghi "chưa làm" vào `STATE.md`.

- [X] T030 [US4] Test trước (`BookmarkExportTests.swift`, `BookmarkFilterSavingTests.swift`): bookmark Data xuất `explorationState` đúng dạng T006 (bộ lọc cấp báo cáo và visual, lựa chọn slicer ở `objects.merge.general`); đối chiếu `bookmark-data.pbix` (trans_type = Credit, năm 2016) áp lại khôi phục đúng.
- [X] T031 [US4] Mở rộng `PBIRBookmarkPatch.swift` (`BookmarkSpec.data`) và `BookmarkExport.swift` cho Data; chỉ bật khi T007 xác nhận; ghi nhận bản chưa đủ quan sát vẫn `sessionOnly`.

## Giai đoạn 9: Câu chuyện 5 (P1): lưu và mở lại được trong Power BI Desktop

**Mục tiêu**: cả file (bookmark, bộ lọc, mọi sửa D1 đến D5) lưu một lần, kiểm trong bộ nhớ, mở lại ở BI Pro và Desktop.

- [X] T032 [US5] Mở rộng `DocumentSaver.verifyLayout` trong `Sources/BIPro/Report/Edit/DocumentSaver.swift` theo `contracts/bookmark-filter-save.md`: `targetVisualNames` và `visualContainers` chỉ trỏ visual có thật ở đúng trang; `activeSection` và khoá `sections` trỏ trang có thật; mọi thẻ lọc parse lại được, thẻ đã đổi khớp mong muốn và cột của thẻ có trong mô hình; `displayName` khớp. Test trước trong `BookmarkFilterSavingTests.swift`: mỗi kiểu sai bị từ chối, file đích nguyên vẹn.
- [X] T033 [US5] Tạo `Tests/BIProTests/Edit/D6Nhom6Tests.swift` (test nặng, `BIPRO_HEAVY`): kịch bản trên Nhom6 (ẩn visual, thêm bookmark Display, cập nhật, đổi tên, xoá `Bookmark_Q13_MuaVu`, thêm bộ lọc cấp trang, sửa bộ lọc cấp visual, hoàn tác và làm lại, lưu `build/d-out/D6/Nhom6_d6.pbix`), mở lại, so bookmark, thẻ lọc, số liệu vẽ, part không đổi khớp từng byte; ghi `build/d-out/D6/CHECKLIST.md`; đo thời gian (SC-003, SC-004). Dựng thêm `Nhom6_d6_pre.pbix` (chỉ bookmark) để chia đôi nếu Desktop từ chối.
- [X] T034 [US5] Chạy `D6Nhom6` và toàn bộ `swift test`, golden nặng theo `quickstart.md` (SC-006); sửa tới khi qua.
- [X] T035 [US5] VM: mở `Nhom6_d6.pbix` trong Power BI Desktop (Claude điều khiển VM theo lời cho phép): không báo lỗi, bookmark áp đúng (ẩn visual, chuyển trang), bộ lọc đúng số liệu; ghi `docs/phase-d-evidence/vm-d6/CHECKLIST-KET-QUA.md` và ảnh; trượt thì dùng `Nhom6_d6_pre.pbix` chia đôi (như D1) rồi sửa.

## Giai đoạn 10: Câu chuyện 6 (P2): hoàn tác chung một lịch sử

- [X] T036 [US6] Tạo `Tests/BIProTests/Edit/BookmarkFilterUndoTests.swift` (trước): (a) mỗi thao tác bookmark và mỗi lần sửa lọc là một bước ⌘Z/⇧⌘Z; (b) xoá bookmark rồi ⌘Z phục hồi đúng vị trí; (c) xen kẽ với di chuyển visual (D1), thêm trường (D2), định dạng (D4), xoá trang (D5): ⌘Z ba lần đưa về ban đầu theo đúng thứ tự, ⌘S sau đó không đổi file; (d) sửa liên tiếp một thẻ lọc trong 0,5 s gộp một bước; (e) hoàn tác về trạng thái đã lưu thì `isDirty` = false.
- [X] T037 [US6] Sửa `LayoutEditor`/`DocumentState` cho tới khi T036 qua (ảnh chụp `edits`, gộp, `cleanMark`); thêm kiểm: chuyển Xem ⇄ Sửa giữa các thao tác không làm mất `edits`.

## Giai đoạn 11: Hoàn thiện

- [X] T038 `/code-review` (medium) trên các file D6, sửa phát hiện; `/speckit-converge`, bổ sung task nếu còn khoảng cách.
- [X] T039 Đo lại số liệu vào `measurements.md` (test thường, golden nặng, thời gian thao tác và lưu: SC-003, SC-004), so với mốc T001.
- [X] T040 Cập nhật `docs/STATE.md` (ngắn gọn: D6 xong, còn lại, dạng `sessionOnly`), `docs/BIPRO_BUILD_PLAN.md` (đánh dấu D6), `docs/phase-d-ownership.tsv`; xoá bản sao Nhom6 tạm trong `docs/phase-d-evidence/vm-d6/work/` và file VM đã dùng. Không commit khi người dùng chưa bảo.

## Phụ thuộc và thứ tự

- T001, T002 → giai đoạn 2 (T003 → T004, T005, T006 → T007) là cổng.
- T007 → giai đoạn 3 (T008 → T009; T010 → T011; T012).
- T012 → giai đoạn 4 (T013 → T014 → T015, T016 → T017).
- T017 → US1 (T018 → T019 → T020 → T021) → US2 (T022 → T023, T024) → US3 (T025 → T026 → T027 → T028 → T029) → US4 (T030 → T031, tuỳ T007) → US5 (T032 → T033 → T034 → T035) → US6 (T036 → T037) → T038 đến T040.
- Vì `LayoutEditor`, `DocumentState`, `ReportPanes` dùng chung, các giai đoạn làm tuần tự.

## Chiến lược

- Bản nhỏ nhất dùng được: T001 đến T021 (bookmark Display thêm và lưu) rồi T032 đến T035 (kiểm Desktop); sau đó mở rộng dần US2, US3, US4, US6.
- Dạng nào T007 không chốt thì để `sessionOnly` thay vì ghi đoán.
