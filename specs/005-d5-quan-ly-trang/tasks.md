---
description: "Danh sách việc: D5, quản lý trang (thêm, đổi tên, đổi thứ tự, nhân bản, xoá) và lưu .pbix tầng T1"
---

# Việc cần làm: D5, quản lý trang

**Đầu vào**: `specs/005-d5-quan-ly-trang/` (spec.md, plan.md, research.md, data-model.md, contracts/page-operations.md, contracts/page-save.md, quickstart.md)

**Kiểm thử**: spec yêu cầu (FR-001 đến FR-012, SC-001 đến SC-006): test thuần cho ghép byte trang và luật cấu trúc, test thao tác và hoàn tác đan xen với D1 đến D3, test lưu, test nặng `D5Nhom6` trên Nhom6 (thêm, đổi tên, kéo, nhân bản, xoá, lưu, mở lại, so số liệu); golden Phase B/C giữ nguyên. Viết test trước, thấy trượt, rồi code.

**Người làm**: lead tự làm, tuần tự, không giao agy (xem `plan.md`, Hiến pháp V: `LayoutEditor`, `DocumentState`, `PageTabs` giao nhau với D1 đến D3). Vì vậy không có việc `[P]`.

**Quy ước**: `[US1]` đến `[US5]` là câu chuyện trong spec (US1 thêm, đổi tên, đổi thứ tự; US2 nhân bản; US3 xoá; US4 lưu và mở lại ở Desktop; US5 hoàn tác chung). Thứ tự giai đoạn: chuẩn bị, nền tảng, US1, US2, US3, US4, US5, hoàn thiện. Lệnh build/test là các lệnh trong `CLAUDE.md`. Fixture: `~/Downloads/bipro-golden/Nhom6_work.pbix` (chỉ đọc; test ghi vào `build/d-out/D5/`).

**Phần cần người dùng**: T032 và T033 cần mở file trong Power BI Desktop trên VM (người dùng làm tay, hoặc Claude khi được phép). Chưa có thì giữ trạng thái chặn, ghi vào `STATE.md`, phần còn lại của lát vẫn xong được.

## Giai đoạn 1: Chuẩn bị

- [X] T001 Cổng mềm R9, thử kéo tab: thêm tạm vào `PageTabs` (`Sources/BIPro/Report/ReportWorkspace.swift`) `onDrag { NSItemProvider(object: id as NSString) }` và `onDrop(of: [.plainText])` in mã trang kéo và thả ra `/tmp/d5-tabdrag.log`; chạy app (`zsh scripts/build-app.sh`), kéo một tab sang tab khác trong `DocumentGroup`; ghi kết quả vào `research.md` R13. Không chạy được thì giữ Sang trái/Sang phải ở menu, bỏ phần kéo ở T015 và báo người dùng.
- [X] T002 Rà soát nơi đọc danh sách trang theo bảng R10 của `research.md`: `grep -rn "report.pages\|workspace.page(\|visiblePages\|drillthroughPages" Sources/BIPro`; với mỗi chỗ ghi quyết định (`state.pages`, lọc trang đã xoá, giữ nguyên) vào `research.md` R13 trước khi sửa.
- [X] T003 Tạo `specs/005-d5-quan-ly-trang/measurements.md` (mốc trước khi sửa): số test `swift test`, số golden nặng, thời gian lưu Nhom6 (`D2Nhom6`/`D3Nhom6`), thời gian nhân bản 36 visual hiện có của D1 (`duplicate`), để so ở T036.

## Giai đoạn 2: Nền tảng ghi, luật và hoàn tác (chặn mọi câu chuyện)

**Quan trọng**: chưa làm thao tác và giao diện trước khi qua T011.

- [X] T004 Tạo `Tests/PBIXKitTests/PBIRPagePatchTests.swift` (test trước, phải thấy trượt) theo `contracts/page-save.md`: (a) `newPageJSON` ra đúng từng byte mẫu Desktop (một dòng, không BOM, chữ Việt và dấu `"` trong tên được escape); (b) `setPageOrder` đổi `pageOrder` (một dòng) và `activePageName`, mọi byte khác giữ nguyên, kiểm với `pages.json` của Nhom6 và bản có thụt lề; (c) `setPageDisplayName` ghép byte, đổi rồi đổi lại ra đúng byte gốc; (d) `duplicatedPageJSON` thay `name` và `displayName`, bỏ `pageBinding` (trang `d4_chinhanh` của Nhom6), đổi mã trong `visualInteractions` theo bảng, giữ `objects` và `filterConfig`; (e) `renamedVisualJSON` chỉ đổi `name` và `parentGroupName`, giữ `position` (cả số thực như `218.8235294117647`); (f) `removingPageReferences`: bookmark có `activeSection` = trang xoá → `.remove`; `sections` nhiều mục chỉ nhắc trang xoá → `.trimmed` bỏ đúng mục; không nhắc → `.unchanged` và giữ byte; (g) `bookmarkItemsRemoving` bỏ đúng mục `items[]`; (h) `pageNavigationTargets` đọc `visualLink` loại `PageNavigation` (mẫu tổng hợp vì Nhom6 không có); (i) đầu vào hỏng ném `WriteError`.
- [X] T005 Tạo `Sources/PBIXKit/Writing/PBIRPagePatch.swift` theo hợp đồng `contracts/page-save.md`; thêm `PBIRLayoutPatch.makeObjectName(avoiding:)` dùng chung bộ sinh 20 hex (giữ `makeVisualName` làm bí danh) ở `Sources/PBIXKit/Writing/PBIRLayoutPatch.swift`. Mỗi hàm ghép byte, phân tích lại và so cấu trúc mong đợi. T004 phải qua.
- [X] T006 Mở rộng `Tests/PBIXKitTests/PBIXWriterEditTests.swift` rồi `Sources/PBIXKit/Writing/PBIXWriter.swift` `insertionIndex`: part của trang mới chưa có thư mục ra sau thành viên cuối dưới `Report/definition/pages/`; bớt part cả thư mục trang không phá đếm thành viên (test trước: thêm một trang với 2 visual, bớt một trang với nhiều visual, file mở lại được).
- [X] T007 Tạo `Tests/BIProTests/Edit/PageStructureTests.swift` (trước) theo `data-model.md`: (a) tên mặc định "Page N" = số lớn nhất của `Page <số>` đang có + 1 (có khoảng trống, có tên khác dạng, không có trang Page nào); (b) trang liền kề sau khi xoá (phải, hoặc trái nếu cuối, trang duy nhất → từ chối); (c) `canRemove`: chỉ còn một trang bị chặn; trang có nút `PageNavigation` trỏ tới bị chặn kèm tên nút; (d) `BookmarkImpact` thuần: từ danh sách (tên, `activeSection`, `sections`) và mã trang xoá ra tập bookmark gỡ và tập bookmark chỉ bỏ mục; (e) tên hợp lệ (cắt khoảng trắng, 1 đến 100 ký tự); (f) bất biến `order` không trùng, không rỗng.
- [X] T008 Tạo `Sources/BIPro/Report/Edit/PageStructure.swift`: `PageStructure`, `NewPage`, `BookmarkImpact`, hàm thuần ở T007. T007 phải qua.
- [X] T009 Viết `Tests/BIProTests/Edit/PageUndoTests.swift` (trước, phần hồi quy): toàn bộ hành vi hoàn tác của D1 đến D3 giữ nguyên (chạy lại các test hiện có làm chuẩn) và hoán đổi snapshot toàn trạng thái (sửa `edited` rồi `structure` thì `undo` hoàn lại cả hai). Rồi sửa `Sources/BIPro/Report/Edit/LayoutEditor.swift`: `LayoutSnapshot` thành `{ edited, structure, currentPageID, selection, primary }`, `snapshot()`/`restore()` toàn trạng thái, `structure: PageStructure`, `pages: [ReportPage]` (theo `order`, tên đã đổi, visual đã sửa), `basePage(_:)` tra `baseline` rồi `structure.created` (thay mọi `baseline.pages.first { $0.id == … }` trong `commit`, `pageBounds`, `delete`, `page(_:)`). `swift test` toàn bộ phải giữ xanh như trước (không test cũ nào trượt).
- [X] T010 `Sources/BIPro/DocumentState.swift`: `pages` chuyển tiếp từ `layout.pages`; giữ `pageID` và `visualID` khớp `layout.currentPageID` sau thao tác trang; tạo `Tests/BIProTests/Edit/PageOperationsTests.swift` với test nhỏ cho `DocumentState.pages` và đổi trang (T012, T019, T024 mở rộng file này).
- [X] T011 Cổng nền tảng: T004 đến T010 xong, `swift test` xanh. Không qua thì không sang giai đoạn 3.

## Giai đoạn 3: Câu chuyện 1 (P1): thêm, đổi tên, đổi thứ tự trang

**Mục tiêu**: thêm trang trống, đổi tên, kéo hoặc dời trang; lưu được ba thao tác đó.

**Kiểm thử độc lập**: Nhom6: thêm trang, đổi tên, đưa lên đầu, lưu, mở lại thấy đúng thứ tự và tên; `pages.json` và `page.json` chỉ đổi đúng khoá.

- [X] T012 [US1] Tạo `Tests/BIProTests/Edit/PageOperationsTests.swift` (trước): `addPage` (tên N, cỡ 1920×1080, cuối `order`, thành trang đang mở, trống vẫn thêm visual và thả trường được), `renamePage` (đổi, rỗng và quá dài bị từ chối, không đổi thì không bước, tên trùng được), `movePage` (đổi `order`, chỉ số sai từ chối, cùng chỗ không bước), mỗi cái đúng một bước hoàn tác, `isDirty` đúng, chế độ Xem và báo cáo cũ bị mờ kèm lý do; trang ẩn và trang drillthrough (`d4_chinhanh`) đổi tên và dời được như trang thường.
- [X] T013 [US1] Tạo `Sources/BIPro/Report/Edit/PageOperations.swift` (extension `LayoutEditor`): `addPage()`, `renamePage(_:to:)`, `movePage(_:to:)` theo `contracts/page-operations.md`; mã mới tránh `usedPageIDs`. T012 phải qua.
- [X] T014 [US1] Tạo `Tests/BIProTests/Edit/PageSavingTests.swift` (trước, phần US1) rồi mở rộng `LayoutEditor.makeChanges`: trang tạo → `addedParts[page.json]`; đổi tên trang của file → `reportParts[page.json]`; thứ tự/thêm/trang mở → `reportParts[pages.json]` (`activePageName` = trang đang mở nếu còn trong dãy); không có thay đổi cấu trúc thì không đụng `pages.json`; mọi part khác khớp byte; lưu qua `DocumentSaver.save` vào `build/d-out/D5/`, mở lại bằng `PBIXFile` thấy đúng thứ tự và tên.
- [X] T015 [US1] `Sources/BIPro/Report/ReportWorkspace.swift` (`PageTabs`): đọc `state.pages`; nút "+" bật ở chế độ Sửa; menu chuột phải (Đổi tên…, Sang trái, Sang phải; mờ ở đầu/cuối); bấm đúp tab và "Đổi tên…" mở `alert` có `TextField` như D2; kéo tab theo T001 (nếu chạy được); mờ kèm `help` ở chế độ Xem và báo cáo cũ; thông báo từ chối ở thanh trạng thái như D2/D3.
- [X] T016 [US1] Sửa các nơi đọc danh sách trang theo quyết định ở T002 (`ShellView` tìm kiếm, `Workspace.drillthroughPages` lọc trang đã xoá, điều hướng của `ReportInteraction` bỏ qua đích đã xoá, `pageNavigator` nếu có): mỗi nơi có test hoặc ghi chú trong `research.md` R13.
- [X] T017 [US1] *Bỏ 2026-11-10: `D5Nhom6Tests` dựng cả `Nhom6_d5.pbix` lẫn `Nhom6_d5_pre.pbix` qua `LayoutEditor` và `DocumentSaver` nên không viết lại logic trong CLI (hai chỗ dễ lệch).* `Sources/pbix-dump/main.swift`: lệnh phụ `add-page <in> <out> [tên]`, `rename-page <in> <mã> <tên> <out>`, `move-page <in> <mã> <chỉ số> <out>` (qua `LayoutEditor` và `DocumentSaver`/`PBIXWriter`, như `add-visual` của D3).
- [X] T018 [US1] Chạy app, chụp cửa sổ app (chỉ cửa sổ, `screencapture -x -o -l <windowID>`) thanh tab với trang mới, đổi tên, kéo; lưu ảnh vào `docs/phase-d-evidence/vm-d5/`; xem ảnh không trống, không lỗi.

## Giai đoạn 4: Câu chuyện 2 (P1): nhân bản trang

**Mục tiêu**: nhân bản một trang kèm mọi visual với mã mới, chạy như trang gốc.

**Kiểm thử độc lập**: nhân bản `d1_giaodich` của Nhom6: 36 visual cùng loại, vị trí, `z`, mã mới không trùng; số liệu vẽ ra bằng trang gốc; lưu và mở lại được.

- [X] T019 [US2] Mở rộng `PageOperationsTests.swift` (trước): `duplicatePage` (tên "Duplicate of <tên>", cuối `order`, thành trang đang mở, mọi visual mã mới 20 hex không trùng mã nào đang có, vị trí kể cả số thực và `z` giữ nguyên, sửa chưa lưu của D1 đến D3 (kéo, thả trường, đổi loại, văn bản) mang sang bản sao, trang gốc không đổi, `parentGroupName` và `visualInteractions` đổi theo bảng mã, trang có `pageBinding` → bản sao không có và `notice`), một bước hoàn tác, nhân bản trang tạo trong phiên.
- [X] T020 [US2] `PageOperations.swift`: `duplicatePage(_:)`: lấy `visual.json` hiện tại của từng visual (đường `json(of:page:)` đã áp sửa), đổi `name`/`parentGroupName` bằng `PBIRPagePatch.renamedVisualJSON`, dựng `PageEdit` cho trang mới (`visuals`, `added`), `page.json` bằng `duplicatedPageJSON` từ `page.json` gốc (đọc qua nguồn của editor). T019 phải qua.
- [X] T021 [US2] `LayoutEditor.makeChanges` + `PageSavingTests.swift` (trước): trang nhân bản → `addedParts` `page.json` và `visual.json` từng visual; byte `visual.json` của bản sao chỉ khác bản gốc ở `name` (và `parentGroupName`); lưu, mở lại thấy 36 visual và truy vấn sinh ra cho từng visual giống trang gốc (so `ReportInteraction.load(...).query` sau khi bỏ khác biệt mã).
- [X] T022 [US2] `PageTabs`: mục menu "Nhân bản" và hiện `notice` (cấu hình drillthrough không mang sang); chụp cửa sổ app lưu vào `docs/phase-d-evidence/vm-d5/`.
- [X] T023 [US2] *Bỏ như T017 (thay bằng `D5Nhom6Tests`).* `pbix-dump`: lệnh phụ `dup-page <in> <mã> <out>`.

## Giai đoạn 5: Câu chuyện 3 (P1): xoá trang và dọn tham chiếu

**Mục tiêu**: xoá trang, bookmark trỏ tới được gỡ, không còn tham chiếu treo; hoàn tác phục hồi đủ.

**Kiểm thử độc lập**: xoá `d1_giaodich` của Nhom6 (có 2 bookmark): lưu, mở lại; không bookmark nào còn trỏ trang đã mất, tìm mã trang trong `definition/` không thấy; hoàn tác phục hồi.

- [X] T024 [US3] Mở rộng `PageOperationsTests.swift` (trước): `removePage` (từ chối trang cuối và nút `PageNavigation` kèm tên nút; trang liền kề thành trang đang mở; bookmark `activeSection` = trang xoá bị gỡ, bookmark chỉ có `sections` nhắc trang xoá chỉ bỏ mục; `notice` nêu số và tên bookmark; xoá trang tạo trong phiên; xoá trang đã sửa chưa lưu; xoá trang ẩn và trang drillthrough như trang thường), hoàn tác phục hồi trang, visual đã sửa, bookmark gỡ, vị trí trong `order` và trang đang mở; làm lại xoá lại.
- [X] T025 [US3] `PageOperations.swift` và `LayoutEditor.init`: đưa vào nguồn bookmark của file đang mở (closure `bookmarks: () -> [(name: String, json: Data)]` lấy từ `ZipArchive`, như `sourceJSON`) và `DocumentState` truyền vào; `removePage(_:)` theo R7 (dùng `PBIRPagePatch.removingPageReferences` để tính `BookmarkImpact`, `pageNavigationTargets` trên `visual.json` của mọi trang còn lại). T024 phải qua.
- [X] T026 [US3] `LayoutEditor.makeChanges` + `PageSavingTests.swift` (trước): `removedParts` mọi part dưới `pages/<mã>/` có trong file; visual của trang xoá vào `removedIDs` (dọn `targetVisualNames` và `explorationState` ở bookmark còn lại như D1); bookmark gỡ → `removedParts` + sửa `bookmarks.json`; bookmark chỉ bỏ mục → `reportParts`; `pages.json` bỏ mã và đặt `activePageName`; lưu, mở lại; mã trang đã xoá không còn trong `definition/`; xoá trang tạo trong phiên sau khi đã lưu một lần (so với file trên đĩa, không cần theo dõi riêng).
- [X] T027 [US3] `PageTabs`: mục "Xoá" với hộp xác nhận "Xoá trang "…"? Có thể hoàn tác bằng ⌘Z." (`confirmationDialog`); hiện `notice` bookmark đã gỡ; chụp cửa sổ app lưu vào `docs/phase-d-evidence/vm-d5/`.
- [X] T028 [US3] *Bỏ như T017.* `pbix-dump`: lệnh phụ `remove-page <in> <mã> <out>` (in danh sách bookmark gỡ).

## Giai đoạn 6: Câu chuyện 4 (P1): lưu, kiểm và mở lại ở Power BI Desktop

**Mục tiêu**: file lưu ra qua đường kiểm của D1 và mở được ở BI Pro lẫn Desktop.

**Kiểm thử độc lập**: kịch bản Nhom6 đầy đủ qua `DocumentSaver.save`; mở lại; so; người dùng (hoặc Claude khi được phép) mở ở Desktop.

- [X] T029 [US4] Mở rộng `Sources/BIPro/Report/Edit/DocumentSaver.swift` `verifyLayout` theo `contracts/page-save.md` (thứ tự và tên trang khớp `editor.pages`, trang tạo đủ visual, bookmark không trỏ trang mất, không mã trang đã xoá trong `definition/`); `Tests/BIProTests/Edit/PageSavingTests.swift` (trước, phần kiểm): bản dựng cố tình sai (thiếu trang, sai thứ tự, bookmark mồ côi) bị từ chối với file đích nguyên vẹn.
- [X] T030 [US4] Tạo `Tests/BIProTests/Edit/D5Nhom6Tests.swift` (nặng, `BIPRO_HEAVY=1`, tên có "D5Nhom6"): kịch bản SC-001 (thêm trang, đổi tên, kéo lên đầu, nhân bản D1, xoá `d2_khoanvay` hoặc trang có bookmark; đo từng thao tác), lưu `build/d-out/D5/Nhom6_d5.pbix` (SC-003, thử lại tối đa hai lần khi máy tải như `D3Nhom6`), mở lại và so thứ tự, tên, số visual, bookmark, truy vấn từng visual của trang nhân bản bằng trang gốc, phần không sửa khớp byte (trừ `SecurityBindings`, `[Content_Types].xml`), `unzip -tq`, file nguồn không đổi.
- [X] T031 [US4] Dựng sớm `build/d-out/D5/Nhom6_d5_pre.pbix` (chia đôi nếu Desktop từ chối: chỉ thêm và đổi tên) bằng `pbix-dump` và viết `build/d-out/D5/CHECKLIST.md` và `CHECKLIST-pre.md` (mỗi mục đạt/trượt như `build/d-out/D3/CHECKLIST.md`): mở không lỗi, thứ tự và tên tab, trang nhân bản vẽ như gốc, bookmark còn lại bấm được, số liệu khớp BI Pro.
- [X] T032 [US4] *Xong 2026-11-10: 8/8 mục đạt hoặc không kết luận (mục 6), xem `docs/phase-d-evidence/vm-d5/CHECKLIST-KET-QUA.md`.* Mở `build/d-out/D5/Nhom6_d5.pbix` trong Power BI Desktop theo `CHECKLIST.md`; kết quả vào `docs/phase-d-evidence/vm-d5/CHECKLIST-KET-QUA.md`. Trượt thì dùng `Nhom6_d5_pre.pbix` và chia đôi như D1.
- [X] T033 [US4] *Xong một phần 2026-11-10: đã quan sát mở lại file xoá trang, nhân bản trang drillthrough, "Set as landing page" (research R14); còn chưa quan sát xoá trang có nút `PageNavigation` nên vẫn chặn.* Quan sát bổ sung (R1 chưa quan sát): xoá trang có nút `PageNavigation` trỏ tới, mở lại file đã xoá trang trong Desktop, nhân bản trang `d4_chinhanh`, "Set as landing page", tên mặc định khi "Page 1" đã đổi tên; cập nhật `research.md` R1 và mở khoá hoặc chỉnh luật chặn xoá (T025). Chưa có thì giữ chặn và ghi vào `STATE.md`.

## Giai đoạn 7: Câu chuyện 5 (P2): hoàn tác chung một lịch sử

**Mục tiêu**: thao tác trang xen kẽ với D1 đến D3 trong một ngăn xếp.

**Kiểm thử độc lập**: chuỗi hỗn hợp, hoàn tác từng bước rồi làm lại.

- [X] T034 [US5] Mở rộng `PageUndoTests.swift`: chuỗi hỗn hợp (thêm trang, kéo visual, thả trường, thêm visual, đổi loại, nhân bản trang, xoá trang) hoàn tác và làm lại từng bước đúng thứ tự ngược; hoàn tác về trạng thái đã lưu thì `isDirty` false; gộp bước kéo 0,5 s của D1 không nuốt thao tác trang; sau hoàn tác, mã trang và mã visual đã dùng không bị dùng lại; sửa mã nếu test trượt.
- [X] T035 [US5] Kiểm giới hạn lịch sử 200 bước và `cleanMark` khi thao tác trang làm tràn ngăn xếp (test nhỏ trong `PageUndoTests.swift`).

## Giai đoạn 8: Hoàn thiện

- [X] T036 Chạy lại `swift test` và golden nặng `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D5Nhom6|EditNhom6|BatchedSerial"`: không test nào trượt thêm; ghi số và thời gian (SC-001, SC-003) vào `measurements.md`.
- [X] T037 Cập nhật `docs/STATE.md`, `docs/BIPRO_BUILD_PLAN.md` (D5), `docs/phase-d-ownership.tsv` (các file mới), `research.md` R13 (kết quả T001, T002), `README.md` của `docs/phase-d-evidence/vm-d5/`; không commit nếu người dùng chưa bảo.
- [X] T038 Chạy `/speckit-converge` trên `specs/005-d5-quan-ly-trang/` và xử lý việc nó thêm vào.

## Phụ thuộc và thứ tự

- Giai đoạn 1 → 2 (T011 là cổng) → 3 → 4 → 5 → 6 → 7 → 8. US2, US3 dùng `makeChanges` và `PageTabs` đã mở rộng ở US1; US4 gom phần kiểm và kiểm thử nặng.
- T015 phụ thuộc T001; T016 phụ thuộc T002; nguồn bookmark của editor (closure `bookmarks`) chỉ có từ T025 nên xoá trang chưa dọn bookmark trước đó.
- T032, T033 phụ thuộc T031 và quyền điều khiển VM; không chặn T034 đến T038.

## Phủ yêu cầu

| Yêu cầu | Việc |
|---|---|
| FR-001 | T012, T013, T015 |
| FR-002 | T012, T013, T015 |
| FR-003 | T012, T013, T015 |
| FR-004 | T019, T020, T022 |
| FR-005 | T024, T025, T027 |
| FR-006 | T024, T025, T026, T033 |
| FR-007 | T009, T034, T035 |
| FR-008 | T004, T005, T006, T014, T021, T026, T029 |
| FR-009 | T030, T032 |
| FR-010 | T012, T015 |
| FR-011 | T014, T030 |
| FR-012 | T030, T036 |
| SC-001 | T030, T036 |
| SC-002 | T034 |
| SC-003 | T030, T036 |
| SC-004 | T031, T032 |
| SC-005 | T026, T029 |
| SC-006 | T036 |

## Chiến lược

- **MVP**: giai đoạn 1 đến 3 (thêm, đổi tên, đổi thứ tự, lưu) đã dùng được; nhân bản và xoá làm tiếp theo thứ tự.
- Phần cần VM (T032, T033) không chặn MVP; điều chưa quan sát giữ phương án thận trọng (chặn xoá khi có nút `PageNavigation`, bản sao không mang `pageBinding`).

## Giai đoạn 9: Hội tụ (Convergence)

- [X] T039 Bấm thử trong BI Pro (chụp riêng cửa sổ app) "Nhân bản" và "Xoá…" ở menu chuột phải tab, ở chế độ Sửa, trên bản sao của `Nhom6_work.pbix`: nhân bản D1 ra "Duplicate of …", xoá có hộp xác nhận, ⌘Z phục hồi; ghi kết quả vào `docs/phase-d-evidence/vm-d5/` và `docs/STATE.md`, per FR-004, FR-005, US2/AC1, US3/AC1 (partial)
- [X] T040 Đồng bộ `specs/005-d5-quan-ly-trang/plan.md` mục "Mã nguồn" với thực tế: bỏ các lệnh phụ `pbix-dump` (add-page, rename-page, move-page, dup-page, remove-page) vì đã thay bằng `D5Nhom6Tests` (T017, T023, T028), per plan: cấu trúc mã nguồn (partial)
- [X] T041 Ghi vào `specs/005-d5-quan-ly-trang/research.md` lý do giữ phần ngoài phạm vi nhưng cần cho FR-012: `ReportInteraction.visualFilters(of:)` sửa bộ lọc cấp visual của visual mã mới (lỗi có từ D1) và `pageFilters(of:)` áp bộ lọc cấp trang cho trang nhân bản; xác nhận cả hai có test (`D5Nhom6Tests.banSaoTrangDrillthroughApDungBoLocCapTrang`), per FR-012 (unrequested)
