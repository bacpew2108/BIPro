# BI Pro: trạng thái làm việc

Cập nhật: 2026-11-11. **Phase C xong phần chính (commit `710daaf`). Phase D xong bảy lát: D1, D2, D3, D5, D4 (đã commit, D5 và D4 ở `98198d7`), D6 (bookmark và bộ lọc ghi vào file) và D7 (căn lề, phân bố, dán giữa trang, nhóm visual, sửa bố cục báo cáo định dạng cũ); D6 và D7 xong phần code, chưa commit. `swift test` 1345 qua; golden nặng 93 qua.** Mở được trong Power BI Desktop: `Nhom6_d3.pbix` đến `Nhom6_d7.pbix`, `Nhom2_d7.pbix` (kết quả ở `docs/phase-d-evidence/vm-d*/`). Việc tiếp: xem "Việc tiếp theo" ở cuối.

## Mục tiêu và tiến độ

- **Phase B (DAX engine + DAX Query View):** xong. 30/30 golden khớp Power BI.
- **Phase C (report có số liệu và tương tác):** đang làm. Kế hoạch ở `docs/PHASE_C_PLAN.md`, quan sát Power BI ở `docs/phase-c-evidence/C1.md`.
  - **Đợt 0** xong: hợp đồng `Sources/BIPro/Visuals/`, `dax-run profile`.
  - **Buổi C1** xong: 64 truy vấn Performance Analyzer, kết quả, ảnh, trong `docs/phase-c-evidence/observe-c1/`.
  - **Đợt 1** xong và đã merge vào `main`:
    - E1, engine chạy được 72/72 truy vấn visual thật;
    - E2, định dạng động `_<M> FormatString`;
    - Q, bộ sinh truy vấn trùng văn bản Power BI ở 43/44 visual, cùng mapper và loader;
    - R1, biểu đồ trục XY;
    - R2, card, slicer, matrix.
  - **Đợt 2** xong (2026-11-04):
    - R3 (donut, treemap, shape map, tooltip) và I (logic tương tác): agy xong, đã review và merge vào `main`;
    - E3 (hiệu năng engine): xong phần chính. Đo ở `phase-c-evidence/C1.md` §1.5: combo thấu chi 34 s → 3,7 s, matrix Giờ × Thứ 5,5–8 s → 1,7–2,2 s, matrix mở nút 9 s → 1,1–1,5 s, combo kênh 12,7 s → 0,7 s; golden 57/57, kết quả khớp byte. Chưa đạt ngưỡng 1 s ở combo thấu chi và matrix Giờ × Thứ (đã đạt ở E3-cấu-trúc, dưới đây);
    - **E3-cấu-trúc xong (2026-11-09, commit `e5907a2`, Spec Kit `specs/001-e3-cau-truc/`)**: combo thấu chi 2,15 → 0,54 s, matrix Giờ × Thứ 1,72 → 0,41 s, combo kênh 0,73 → 0,10 s, trang D1 song song 3,32 → 1,04 s; khớp byte, khớp 66 truy vấn visual giữa đường gộp và đường cũ. Gồm đường tính gộp theo nhóm cho `SUMX/AVERAGEX/MINX/MAXX` (công tắc `BIPRO_BATCH=0`), và các sửa nghẽn thật: `FilterContext.values`, `RelationshipIndex.manyRows`, `SummarizeColumns.groupCombinations`, `Aggregation.extremeOfColumn`. Đo và chẩn đoán: `specs/001-e3-cau-truc/measurements.md`, `research.md` R9, `phase-c-evidence/C1.md` §1.5. File Nhom6 gốc không còn ở `~/Downloads`: `DAXFixtures.nhom6` và `e3-loop.sh` dùng `~/Downloads/bipro-golden/Nhom6_work.pbix` hoặc `BIPRO_NHOM6`.
    - G (ghép): `Report/ReportInteraction.swift` + `Report/LiveVisual.swift`. Card, slicer, matrix, cột/bar/line/combo, donut, treemap, shape map chạy số thật; slicer, lọc chéo, tô sáng chéo (3 golden khớp `interact/xf-*.dax`), drill down/up (nút góc trên phải, chế độ drill, chuột phải), drillthrough (chuột phải → trang đích, tham số đọc từ `pageBinding`), tooltip khi rê chuột. Engine chạy được cả 16 truy vấn trong `observe-c1/interact/` (agy báo thiếu là sai). Bạn đã bấm thử slicer và lọc chéo: ổn. Chưa tự kiểm bấm drill, drillthrough, tô sáng trên app.
    - Mở nút: slicer hierarchy (`expansionStates` trong file + bấm mũi tên) và matrix cột (bấm +/−) đã làm, có golden (`D1-slicer-nam`, `interact/matrix-expand`); mới hỗ trợ mở một cấp ở cấp gốc. `DropdownSlicer` đã dùng `SlicerNode.formatString`.
    - Chưa làm (để sau): drill cho donut chưa có golden; Edit interactions (người dùng đổi lọc/tô sáng giữa hai visual) chưa có giao diện; matrix mở nút theo hàng; mở nút nhiều cấp.

  - **Phase D, lát D1 xong phần code, đã commit `42f3c41` + `e01f208` (2026-11-09, Spec Kit `specs/002-d1-canvas-luu-t1/`)**: ⌘E bật chế độ Sửa trên canvas (Xem giữ nguyên lọc chéo/drill): chọn một/nhiều (Shift, khung chọn), kéo di chuyển, 8 tay nắm đổi cỡ (khung bóng), bám lưới 8 px (giữ Option bỏ bám), phím mũi tên, Delete, ⌘D nhân bản, ⌘C/⌘V, ⌘Z/⇧⌘Z. Lưu: ⌘S, ⇧⌘S ghi **tầng T1** bằng ghép byte (`PBIRLayoutPatch`, `PBIXWriter` thêm/bớt phần), dựng+kiểm trong bộ nhớ → file tạm → mở lại → thay; bản sao lưu ở `~/Library/Application Support/BI Pro/Backups/`; file dưới `~/Downloads` buộc Lưu thành; hỏi lưu khi đóng/thoát; app là Editor của `.pbix`. Lưu Nhom6 mất 0,22–0,26 s (SC-004); kéo/đổi cỡ 10–32 ms mỗi khung. Visual trong nhóm (`parentGroupName`) chưa sửa được; báo cáo định dạng cũ (`Report/Layout`) chưa sửa được. Chi tiết ở `specs/002-d1-canvas-luu-t1/` (`measurements.md`, `research.md` R2), ảnh ở `docs/phase-d-evidence/`. **Sửa 2026-11-10:** bản đầu bị Power BI Desktop từ chối ("file is corrupted"); nguyên nhân là `SecurityBindings` không còn khớp phần báo cáo đã sửa, nay `PBIXWriter` bỏ nó khi sửa phần báo cáo (research R13); đã dựng lại `Nhom6_d1.pbix`, `Nhom6_pre.pbix`; **VM-D1-mở đạt hết** (2026-11-10, `CHECKLIST.md`: Power BI Desktop mở, dữ liệu, bố cục D1, bản nhân bản, matrix đã xoá, bookmark). VM-D1 quan sát đã xong (`docs/phase-d-evidence/vm-d1/QUAN-SAT.md`, research R14): xoá visual chỉ bỏ khỏi `visualContainers` của bookmark (đã sửa theo); lưới Desktop ≈ ô nhỏ 19,2 (không bám khi kéo), BI Pro giữ 8 có chủ ý; bookmark xoá/không xoá đều mở được.

  - **Phase D, lát D2 (Build pane + field well, 2026-11-10, Spec Kit `specs/003-d2-build-pane-field-well/`)** xong phần code (D2a), đã commit `960437b`: trong Sửa (⌘E) chọn một visual thì Build pane sửa được trường: kéo từ pane Dữ liệu (hoặc ô tick, hoặc menu "+ Thêm field") vào ô, nút bỏ, kéo đổi thứ tự trong ô và chuyển ô, menu chuột phải (đổi tên cho visual này, lên/xuống, chuyển sang ô, bỏ), vẽ lại đúng visual đó, hoàn tác chung với D1 (một lần thả một bước), ⌘S lưu T1 (`PBIRQueryPatch` ghép byte `queryState`; phần tử cũ chép nguyên byte). Chỉ cho thêm vào ô đã quan sát trong Nhom6 (30 tổ hợp, `WellRules`); ô khác hiện "(chưa kiểm)"; bỏ trường còn dùng ở sắp xếp/bộ lọc/định dạng riêng bị chặn kèm lý do. Số đo: lưu 0,18 s (riêng) và vẽ lại 24–104 ms (lần nạp đầu của phiên 255 ms vì khởi động engine); số card sau khi đổi measure khớp DAX viết tay (3 measure). `swift test` 968 qua; golden nặng 84 qua (30 golden Phase B giữ nguyên). Kéo thả dùng `NSItemProvider` (`.draggable`/`Transferable` không chạy, research R9). **Chờ bạn:** (1) mở `build/d-out/D2/Nhom6_d2.pbix` trong Power BI Desktop (`CHECKLIST.md`; bản `Nhom6_d2_pre.pbix` + `CHECKLIST-pre.md` nếu trượt); (2) buổi VM-D2 (`build/d-out/D2/VM-D2-QUAN-SAT.md`, kết quả vào `docs/phase-d-evidence/vm-d2/`). **Còn chặn bởi VM-D2 (T031–T034):** phép gộp (D2b: cột số vào ô giá trị, Sum/Average/…), bỏ trường còn dùng ở sắp xếp/bộ lọc/định dạng, nâng các ô "(chưa kiểm)" lên được thêm, truy vấn khớp mẫu Performance Analyzer của Desktop (FR-017).

  - **Phase D, lát D3 (thêm visual mới, đổi loại visual, 2026-11-10, Spec Kit `specs/004-d3-them-visual-doi-loai/`)** xong phần code (bản đầu), đã commit `49ef4dc`: ở Sửa (⌘E) không chọn visual thì bấm biểu tượng trong thư viện của Build pane (hoặc nút "Visual mới"/"Hộp văn bản" ở ribbon Trang chủ và Chèn) để thêm visual trống ở giữa phần trang đang nhìn thấy, chọn sẵn, nhận trường bằng Build pane của D2; chọn một visual rồi bấm biểu tượng khác thì đổi loại (giữ vị trí, cỡ, `z`; trường sang ô cùng vai trò, trường không có chỗ bị bỏ và báo, chặn nếu còn dùng ở sắp xếp/bộ lọc/định dạng; định dạng `objects` chỉ giữ khoá thấy trên visual cùng loại đích trong báo cáo); hộp văn bản sửa chữ ở ô "Nội dung" (giữ kiểu chữ); hoàn tác chung; lưu T1 (`PBIRNewVisual`, `PBIRVisualPatch`, `PBIRQueryPatch` tạo `query.queryState`). Loại thêm được: card, slicer, thanh nhóm, cột 100%, đường, hai loại combo, donut, treemap, matrix, bản đồ hình, hộp văn bản (loại có ô đã quan sát; cột nhóm, xếp chồng, vùng chờ VM-D3). `swift test` 1034 qua; golden nặng 85 qua (30 golden Phase B giữ nguyên). **Chờ bạn:** (1) mở `build/d-out/D3/Nhom6_d3.pbix` trong Power BI Desktop (`CHECKLIST.md`; `Nhom6_d3_pre.pbix` + `CHECKLIST-pre.md` nếu trượt); (2) buổi VM-D3 (`build/d-out/D3/VM-D3-QUAN-SAT.md`, kết quả vào `docs/phase-d-evidence/vm-d3/`). **Còn chặn bởi VM-D3 (T033–T035):** khoá `visual.json` mới Desktop ghi, `queryState` rỗng, cỡ và vị trí mặc định, ánh xạ ô khi đổi loại, giữ hay bỏ `objects`, mở thêm loại cột/thanh/vùng.

  - **Đợt 3 (gói P)** xong phần code (2026-11-05), lead tự làm, không dùng worker (git chưa sạch để tách worktree, phần UI nhỏ và dùng ngay model mới):
    - `PBIXKit/ReportFilters.swift`: `ReportBookmark` đọc thêm `suppressData`, `suppressActiveSection`, `activeSection`, `targetVisualNames`, `hidden` (id visual → ẩn); `ReportVisual` có init public;
    - `Report/ViewState.swift`: `VisibilityState` (ẩn/hiện do Selection pane và bookmark, ghi đè giá trị trong file), `UserFilter` + `UserFilterKey` (bộ lọc Basic In/Not In người dùng sửa);
    - `ReportInteraction`: `visibility`, `userFilters`, `applyBookmark`, `toggleHidden`, `distinctValues`, `mergeStatics` (thay bộ lọc tĩnh tại chỗ, thẻ ngầm thêm vào cuối nhóm cấp của nó); `VisualDataLoader.distinctValues`;
    - canvas bỏ visual ẩn theo `interaction.isHidden`, nút action kiểu Bookmark áp bookmark, `LiveVisualView` nạp lại khi `userFilters` đổi;
    - `Panes/FilterEditor.swift` (editor Basic filter: tìm kiếm, chọn nhiều, là/không phải, chọn tất cả, đặt lại) và `ReportPanes.swift` (thẻ mở được, mắt ẩn/hiện trong Selection pane, bấm bookmark trong Bookmarks pane);
    - test: `Tests/BIProTests/Panes/` (15 test thường, 3 test nặng trên Nhom6, đều qua; `swift test` 770 qua).
    - Chưa làm: bookmark không `suppressData` (khôi phục slicer/bộ lọc), thêm/xoá bộ lọc ở Filters pane, Advanced filter, Top N, thẻ bộ lọc cho hierarchy; bookmark ghi vào file (Add/Update/Delete). Chưa bấm thử giao diện (xem `VM-TODO-P.md` phần "tự bấm thử").

  - **Đợt 3 + đợt A + C2 (2026-11-05 đến 2026-11-07)** xong, kết quả đối chiếu Power BI ở `docs/phase-c-oracle/VM-TODO-C2.md`:
    - **Filters pane** làm lại như Power BI: thẻ, Basic (Select all ba trạng thái), Advanced (chữ, số, Và/Hoặc), Top N (cấp visual), thêm/bỏ thẻ, thẻ measure của visual (Advanced số, văn bản `__ValueFilterDM0` khớp Power BI); engine thêm `SEARCH`, `CONTAINSSTRING`, `LEFT`.
    - **Bookmark:** đọc bookmark có Data (slicer ở `objects.merge.general`, test bằng file thật), thêm/cập nhật/đổi tên/xoá, tuỳ chọn Data/Display/Current page (sống trong phiên, chưa ghi lại .pbix).
    - **Matrix mở nút nhiều cấp** Vùng › Bang › Chi nhánh có +/−, truy vấn khớp byte `b5-1`/`b5-2`; tiêu đề cột gộp ô, góc trái ghi tên cấp; cuộn bằng con lăn và trackpad.
    - **Biểu đồ:** định dạng giá trị theo cột (giờ, ngày), trục chữ cuộn được, dự báo line (dải tin cậy rộng khớp, từng tháng chưa khớp) và tooltip vùng dự báo, nhãn donut không chồng, % làm tròn 2 số, tooltip lật gần mép, nét line 3.
    - **Tương tác:** bấm ra ngoài bỏ chọn; mặc định lọc/tô sáng khớp Power BI (card, bản đồ, matrix lọc; donut, 100%, combo tô sáng).

## Worktree / worker

Không có worker nào đang chạy. Worktree `c2-r3`, `c2-i` đã merge và xoá (2026-11-04). Báo cáo của agy ở `docs/tasks/c2-r3-report.md`, `c2-i-report.md`.

## Quyết định đã chốt

- Visual sinh **văn bản DAX giống Performance Analyzer**, rồi chạy qua engine. So golden sau khi chuẩn hoá khoảng trắng.
- Renderer chỉ đọc `DataView` và `VisualFormat`, không biết DAX.
- Số hiển thị: đơn vị tự động; độ chính xác mặc định theo định dạng của measure.
- Tên cột kết quả:
  - ký tự không phải chữ hoặc số → `_`;
  - tên không bắt đầu bằng chữ cái thì thêm `v` ở đầu;
  - trùng tên cột của model thì thêm `2`.
- Dự báo (forecast) chỉ làm gần đúng; đường xu hướng làm đúng.
- Spec Kit (2026-11-03): lead tự dùng khi bắt đầu phase hoặc tính năng mới (từ Phase D), dừng cho bạn duyệt sau spec, plan, tasks; quy tắc ở mục "Spec Kit" trong `CLAUDE.md`, nguyên tắc ở `.specify/memory/constitution.md`.
- Skill (2026-11-04): Spec Kit là quy trình chính; chỉ dùng 3 skill mattpocock (`/writing-for-agents`, `/tdd`, `/diagnosing-bugs`); Superpowers đã gỡ.
- Tương tác (đợt 2): mặc định theo loại visual, Nhom6 không có `visualInteractions`. Card, shape map bị lọc; combo, donut, cột 100% bị tô sáng; các chỗ khác ghi [SUY ĐOÁN] trong C1.md §2.6, kiểm ở buổi C2.

## Lệnh build/test

- `swift build`; `swift test` (1034 test).
- Golden Nhom6:
  ```
  BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS"
  ```
  85 test (lệnh lọc thêm `|D2Nhom6|D3Nhom6|EditNhom6|BatchedSerial`), gồm 30 golden Phase B, 72 truy vấn visual và các test sửa/lưu D1, D2, D3. Test `huyTruyVanNangDungNhanh` (huỷ trong 100 ms) chập chờn khi chạy cùng test nặng khác.
- `zsh scripts/e3-loop.sh`: đo ba truy vấn chậm trên Nhom6 và so byte với `build/e3-base/` (tạo bản chuẩn trước khi sửa engine).
- `zsh scripts/build-app.sh` (đóng gói `build/BI Pro.app`).
- `dax-run profile <pbix> --filter "<DAX>"`: đo thời gian truy vấn của từng visual.
- Test sập SIGBUS sau khi đổi struct dùng chung giữa các module: xoá `.build` rồi build lại.

## D4 và D5: trạng thái khi chốt phiên (2026-11-10)

- **Đã commit `98198d7`** (D5 và D4 cùng một commit vì chung `LayoutEditor`, `DocumentState`, `ReportPanes`; file `docs/phase-d-evidence/**/*.pbix` để ngoài git). Cây làm việc sạch.
- **D5** (`specs/005-d5-quan-ly-trang/`): tasks T001 đến T041 xong; đã bấm thử trong app Thêm, Đổi tên, Kéo, Nhân bản, Xoá, ⌘Z, ⌘S. Chưa quan sát: xoá trang có nút `PageNavigation` trỏ tới (BI Pro đang chặn).
- **D4** (`specs/006-d4-format-pane/`): tasks T001 đến T034 xong, kể cả `/code-review` và `/speckit-converge`. VM-D4 hai vòng (`docs/phase-d-evidence/vm-d4/QUAN-SAT.md`); đã bấm thử trong app (đổi cỡ chữ card, tắt nhãn danh mục, phạm vi Chung). ⌘Z chưa thử bằng tay vì ô số còn giữ focus (có test).
- **Review còn lại, chưa sửa (D5):** (a) `verifyPages` tìm mã trang đã xoá như chuỗi trong mọi file `definition/`, có thể chặn lưu nếu chỗ lạ nhắc mã (chỉ báo lỗi, không ghi hỏng); (b) hoàn tác sau khi lưu việc xoá trang: trang về dãy nhưng file đã mất thư mục, lần lưu sau bị `verify` chặn; (c) thả tab nhận mọi chuỗi `page:`; (d) `removePage` và `LayoutEditor.pages` tính lại nhiều khi báo cáo lớn.
- **Danh mục D4 chưa phủ:** matrix thêm mới (`subTotals`), `dataPoint` và định dạng theo trường (`selector`), phông, màu nền và bóng, khoảng giá trị của ô số, reset thẻ cuối làm `objects` rỗng. Nhom6 còn 33 cặp chưa phủ (`specs/006-d4-format-pane/measurements.md`).
- **Khác biệt có chủ ý so với Desktop:** xoá trang thì BI Pro gỡ bookmark trỏ tới (Desktop để mồ côi); nhân bản trang drillthrough bỏ `pageBinding` (có báo).
- Mẹo chụp app khi VM đang chạy: ẩn Parallels (`osascript -e 'tell application "System Events" to set visible of process "Parallels Desktop" to false'`) rồi mở app; cửa sổ Parallels che app thì bấm chuột rơi vào Windows. Nhập Enter vào ô văn bản của app: dùng `osascript -e 'tell application "System Events" to key code 36'` (cliclick `kp:return` đôi khi không tới).

## D6 (bookmark và bộ lọc ghi vào file, 2026-11-11, chưa commit)

- **Spec Kit `specs/007-d6-bookmark-filter/`**: tasks T001 đến T040 xong. Quan sát VM-D6 (Claude điều khiển VM theo lời cho phép của bạn): `docs/phase-d-evidence/vm-d6/QUAN-SAT.md` (hai vòng) và `CHECKLIST-KET-QUA.md`.
- **Quyết định của bạn**: Xem chỉ để xem. Sửa bookmark và bộ lọc chỉ ở Sửa (⌘E); ở Xem các nút mờ kèm lý do, bấm bookmark để áp vẫn được. Hai lớp: lớp tài liệu (`ReportEdits` trong `LayoutEditor`, hoàn tác chung, lưu) và lớp phiên (do áp bookmark và slicer, không ghi).
- **Ghi vào file** (`PBIRBookmarkPatch`, `PBIRFilterPatch`, ghép byte, so với file trên đĩa; lưu nhiều lần chỉ ghi phần đổi): bookmark Display + Current page (dạng Nhom6), bookmark Data tối giản (lựa chọn slicer cột đơn, slicer khác về All, ẩn visual: Desktop áp đúng), đổi tên, cập nhật, xoá (xoá hết thì xoá `bookmarks.json`), đổi thứ tự (menu Chuyển lên/xuống); thẻ lọc Basic (là, không phải), Advanced chữ (`Contains`, `StartsWith`, `Not`, `And` hai điều kiện), Top N, ở cấp báo cáo, trang, visual. Hoàn tác sau khi lưu rồi lưu lại đưa bookmark thêm/xoá/đổi tên và thẻ lọc thêm về như cũ.
- **Chưa ghi, giữ trong phiên và hiện cảnh báo vàng kèm lý do**: Data có lựa chọn điểm dữ liệu, drill, mở nút, slicer nhiều cấp; Advanced số, "Hoặc", "là"/"không phải"; Bottom N; thẻ measure; nhóm bookmark. Bookmark Data không ghi thẻ lọc của Filters pane (thẻ lọc nằm riêng trong `filterConfig`).
- **Kiểm Desktop**: `Nhom6_d6.pbix` mở không lỗi, bookmark áp đúng, bộ lọc `sex = Female` đúng số liệu (card 5.369 → 2.645). Đã bấm thử trong app (thêm bộ lọc trang, chọn Female, thêm bookmark, ⌘S).
- **Review `/code-review` (medium)**, đã sửa: đổi tên bookmark có cập nhật chưa ghi được làm `verify` chặn lưu; cập nhật bookmark không có trong file bị bỏ im lặng (nay báo); bookmark phiên đã xoá còn hiện. **Còn lại, chấp nhận**: Cập nhật bookmark có sẵn viết lại cả file theo dạng tối giản (mất `targetVisualNames` và trang khác của bookmark tay); sửa thẻ lọc có sẵn rồi lưu rồi hoàn tác thì file giữ giá trị đã lưu (có ghi chú); ⌘Z bằng phím không tới khi con trỏ ở ô tìm kiếm trên cùng (menu Edit > Hoàn tác thì có); `effectiveUserFilters` tính lại mỗi lần đọc (chưa đo là chậm); chuyển bookmark lên/xuống không tôn trọng ranh giới nhóm.
- **Số đo**: `swift test` 1284 qua (1200 trước D6); golden nặng 91 qua; thao tác bookmark vài chục µs; lưu Nhom6 0,24 s.

## D7 (căn lề, phân bố, dán, nhóm, định dạng cũ; 2026-11-11, chưa commit)

- **Spec Kit `specs/008-d7-nhom-can-le-cu/`**: tasks T001 đến T034 xong. Quan sát VM-D7 (Claude điều khiển VM theo lời cho phép của bạn): `docs/phase-d-evidence/vm-d7/QUAN-SAT.md`, `CHECKLIST-KET-QUA.md`.
- **Căn lề và phân bố** (ribbon "Sắp xếp", menu Sửa, chuột phải trên canvas): căn trái/phải/trên/dưới theo mép vùng chọn, giữa theo **trung bình các tâm**, phân bố từ 3 visual, kẹp trong trang (con của nhóm: trong khung nhóm); một bước hoàn tác.
- **Dán** (cùng trang hoặc trang khác): vị trí nguồn +10 mỗi lần dán, `z` = lớn nhất + 1 (Desktop); nhân bản ⌘D giữ quy tắc D1 (+16).
- **Nhóm** (⌘G, ⇧⌘G, ribbon): container `visualGroup` và `parentGroupName` đúng dạng Desktop (con toạ độ tương đối, mô hình dùng tuyệt đối; bộ đọc đã sửa theo, trước đó con của nhóm bị vẽ sai chỗ). Di chuyển, đổi cỡ (co tỷ lệ hai chiều), xoá, nhân bản, chép nhóm; con sửa được, kẹp trong khung nhóm; Selection pane có cây nhóm. Từ chối: nhóm lồng nhau.
- **Định dạng cũ `Report/Layout`**: ở Sửa chạy di chuyển, đổi cỡ, căn, xoá, nhân bản, chép dán (`LegacyLayoutPatch`, ghép byte UTF-16LE, toạ độ ở cả container và `config`); Build, Format, trang, bookmark, bộ lọc, nhóm vẫn chặn kèm lý do; visual trong nhóm cũ bị khoá. `Nhom2_d7.pbix` mở được trong Desktop.
- **Kiểm Desktop**: `Nhom6_d7.pbix` (nhóm hiện trong Selection pane, thẻ dán ở D1) và `Nhom2_d7.pbix` mở không lỗi. Bấm thử trong app: chọn ba visual, Nhóm, ⌘S (file ghi giống hệt dạng Desktop), ⌘Z.
- **Số đo** (`specs/008-.../measurements.md`): căn, phân bố, nhóm dưới 1 ms, dán 1,4 ms, lưu Nhom6 0,19 s, lưu Nhóm 2 (định dạng cũ) 0,42 s.
- **Chưa quan sát ở Desktop (BI Pro theo phương án an toàn, hoàn tác được)**: Delete trên nhóm có xoá con hay không (BI Pro xoá cả nhóm và con); co theo chiều dọc của nhóm; nhóm lồng nhau; dán/nhân bản cùng trang. Phím Delete và Ctrl gửi qua `cliclick` không tới Desktop, dùng nút và biểu tượng.
- **Hạn chế đã biết**: dán nút điều hướng/bookmark mà đích đã bị xoá sau khi chép không bị bỏ kèm báo (T031, chưa biết dạng tham chiếu); làm tròn về điểm nguyên (Desktop giữ số thập phân, lệch tối đa 0,5 điểm); mắt ẩn nhóm trong Selection pane áp lên từng con, không ghi `visualGroup.display`.
- **Review `/code-review` (medium) đã sửa**: con chép/dán riêng lẻ không còn bị khoá, con của nhóm trong file sau Bỏ nhóm sửa được, con co không nhỏ hơn 1 điểm, `z` nhóm không trùng visual khác, phân bố dùng mép phải xa nhất, căn trong nhóm theo khung nhóm, kiểm `verifyGroups` chỉ với phần đã đổi, bộ ghép định dạng cũ chịu container không có tên và tên trùng.

## Việc tiếp theo

**Chờ bạn (theo thứ tự nên làm):**
- **VM-D2 đã đọc 2026-11-10** (`docs/phase-d-evidence/vm-d2/QUAN-SAT.md`, `specs/003-.../research.md` R16) và đã áp vào mã (D2b, T033): bỏ trường thì dọn định dạng riêng của nó và giữ bộ lọc (chỉ chặn khi có sắp xếp tường minh), thêm trùng measure được, đổi tên ghi cả `nativeQueryRef`. **Phép gộp (T032) đã có kết luận**: Nhom6 bật `DiscourageImplicitMeasures` nên Desktop từ chối cột số ở ô giá trị (không có Aggregation để ghi); BI Pro từ chối đúng lý do đó. Ô "chưa kiểm" của loại cũ (T034) cũng chưa có quan sát.
- **VM-D3 đã xong 2026-11-10 (Claude điều khiển VM theo lời cho phép một lần của bạn):** `docs/phase-d-evidence/vm-d3/QUAN-SAT.md` và `CHECKLIST-KET-QUA.md`; `Nhom6_d3.pbix` mở được trong Power BI Desktop (mục 10 và 11 của checklist chưa làm). **D3b đã sửa một phần (2026-11-10, chưa commit):** ô `Y2` của `lineChart` và giữ Y2 khi đổi sang đường, donut/treemap giữ nhiều cấp, `objects` chỉ bỏ khoá không hợp lệ (`TypeChange.keepsObjectKey`). **Chưa sửa:** `cardVisual` (BI Pro thêm `card` cũ, Desktop mở được), `sortDefinition` mặc định, `active:true` cho cột mới, cỡ/vị trí mặc định (giữ thiết kế riêng), loại thanh xếp chồng/vùng… (BI Pro chưa vẽ). Đã thêm cột nhóm `clusteredColumnChart` và cột xếp chồng `columnChart` (Desktop ghi tên này). Điểm khác ban đầu (`research.md` R16): thư viện Card ghi `cardVisual` (ô `Data`), `lineChart` có ô `Y2`, combo→đường giữ `Y2`, donut→treemap giữ cả 3 cấp (`Category`→`Group`), chỉ bỏ khoá `objects` không hợp lệ, `sortDefinition` mặc định, vị trí thêm (100,100) 300×300, `active:true` cho cột. Điều khiển VM: `prlctl exec --current-user`, `cliclick` lên cửa sổ Parallels; quy tắc "agent không điều khiển VM" của hiến pháp vẫn giữ, lần này là ngoại lệ do bạn cho phép.
- **D3 trong app:** bấm thử đã làm (thêm card, thả measure bằng menu, đổi đường→thanh, ⌘S, lưu mở được, bỏ `SecurityBindings`); số card Net_Cashflow khớp $197M.
- **D2:** mở `build/d-out/D2/Nhom6_d2.pbix` trong Power BI Desktop (`CHECKLIST.md`); bấm thử kéo trường từ pane Dữ liệu vào Build pane (kéo thả chưa tự thử được bằng script).
- **D1:** (VM mở file và buổi quan sát đã xong 2026-11-10; D1 chốt); bấm thử chế độ Sửa trong app (⌘E).
- Bấm thử bản mới (`zsh scripts/build-app.sh`): bookmark (menu chuột phải chưa kiểm), thẻ measure, matrix nhiều cấp, tốc độ cuộn (hằng số 100 và 2,5 ở `MatrixVisual.swift` nếu cần chỉnh).
- Hệ quả E3-cấu-trúc: các visual đã nhanh nên có thể bấm thử lọc/đổi slicer ở trang D1 để cảm nhận (mục tiêu mỗi visual dưới 1 s).
- Chỉ trường nào "chưa add được bộ lọc" ở trang nào (menu "Thêm field" mới có 77 cột nhìn thấy, chưa có measure, cấp hierarchy).

**Backlog Phase C (chưa có yêu cầu):**
- Matrix: đọc nút đã mở lưu trong file (`expansionStates`), mở nút theo hàng, ô "Nhóm tuổi" (tên trường hàng) đang bị thay bằng tên cấp theo yêu cầu.
- Drill cho donut chưa có golden; Edit interactions chưa có giao diện; thêm measure/hierarchy vào Filters pane; kéo field từ pane Dữ liệu; Advanced cho cột ngày; Top N khớp văn bản Power BI (`TOPN` nửa nối).
- Trục Y line "$0bn" của Power BI (đơn vị tự động) chưa biết quy tắc; dự báo từng tháng chưa khớp.
- Ghi bookmark vào .pbix; test `huyTruyVanNangDungNhanh` nay lặp truy vấn đến khi bị huỷ (truy vấn golden đều xong dưới 0,6 s), vẫn có thể chập chờn khi máy tải cao.

**Phase D tiếp (kế hoạch, theo Spec Kit, mỗi lát dừng cho bạn duyệt sau spec, plan, tasks):**
1. **D2b và D3b** (chờ VM-D2, VM-D3; mỗi cái khoảng nửa tuần): phép gộp Sum/Average/… và ghi đúng cấu trúc `Aggregation`; nâng các ô "(chưa kiểm)" lên được thêm; xử lý sắp xếp/bộ lọc/định dạng khi bỏ trường hoặc đổi loại theo cách Desktop làm; thêm cột nhóm, cột/thanh xếp chồng, vùng; chốt khoá `visual.json` mới, cỡ mặc định, ánh xạ ô khi đổi loại. Trong lúc chờ có thể làm D4 hoặc D5.
2. **D4 Format pane (xong 2026-11-10, Spec Kit `specs/006-d4-format-pane/`)**: ở Sửa, tab Định dạng sửa được: công tắc, ô số, danh sách, bảng màu (lưới theme 6 hàng + ô hex + "Đặt lại"), ô chữ; hai phạm vi Visual (`objects`) và Chung (`visualContainerObjects`); thẻ theo danh mục đã quan sát (`FormatCatalog`), thuộc tính chưa quan sát chỉ-đọc; thêm thuộc tính chưa có, đặt lại thẻ hoặc thuộc tính; hoàn tác chung với D1 đến D5 (sửa liên tiếp một thuộc tính gộp một bước); lưu T1 bằng ghép byte (`PBIRFormatPatch`), `verifyLayout` so định dạng. Bằng chứng: `docs/phase-d-evidence/vm-d4/` (`QUAN-SAT.md` hai vòng, `CHECKLIST-KET-QUA.md`: `Nhom6_d4.pbix` mở được ở Desktop, hiện đúng); ảnh app `app-d4-*.png`. Số: `swift test` 1200 qua, golden nặng 89 qua; mỗi nhóm sửa 1 đến 19 ms, lưu 0,18 s. Chưa quan sát: matrix thêm mới (`subTotals`), `dataPoint`/mục theo trường, phông, màu nền/bóng, khoảng ô số, reset thẻ cuối làm `objects` rỗng (danh mục Nhom6 chưa phủ 33 cặp, xem `measurements.md`). `/speckit-converge` và `/code-review` đã chạy và xử lý (sửa: lỗi áp định dạng không còn bị nuốt khi nhân bản, chỉ xoá thư mục trang đã biết, nhóm bookmark mất con khi xoá trang). **Review còn lại, chưa sửa (D5):** (a) `verifyPages` tìm mã trang đã xoá như chuỗi trong mọi file `definition/`, có thể chặn lưu nếu chỗ lạ nhắc mã (chỉ báo lỗi, không ghi hỏng); (b) hoàn tác sau khi lưu việc xoá trang: trang về dãy nhưng file đã mất thư mục, lần lưu sau bị `verify` chặn; (c) thả tab nhận mọi chuỗi `page:`; (d) `removePage` và `LayoutEditor.pages` tính lại nhiều khi báo cáo lớn.
3. **D5 Quản lý trang (xong 2026-11-10, Spec Kit `specs/005-d5-quan-ly-trang/`)**: ở Sửa (⌘E) thanh tab có "+", bấm đúp đổi tên, kéo tab đổi thứ tự, chuột phải: Đổi tên, Nhân bản ("Duplicate of …" ở cuối), Sang trái/phải, Xoá (xác nhận; gỡ bookmark trỏ trang, báo bookmark nào; chặn khi có nút `PageNavigation` trỏ tới hoặc chỉ còn một trang); hoàn tác chung; lưu T1 so với file trên đĩa (`makeChanges`), `verifyLayout` kiểm thứ tự, tên, bookmark, tham chiếu treo. Số đo: nhân bản D1 (36 visual) 90 đến 113 ms, xoá 150 đến 175 ms, lưu 0,19 đến 0,27 s. VM: `Nhom6_d5.pbix` mở được trong Desktop (`docs/phase-d-evidence/vm-d5/CHECKLIST-KET-QUA.md`). Khác Desktop có chủ ý: gỡ bookmark mồ côi; nhân bản trang drillthrough không sao `pageBinding` (Desktop sao). Chưa quan sát: xoá trang có nút `PageNavigation`; chưa tự bấm Nhân bản/Xoá trong app (có test). Sửa kèm: bộ lọc cấp visual của visual mã mới (bản sao) nay được áp (`ReportInteraction.visualFilters(of:)`).
4. **D6 Bookmark và bộ lọc ghi vào file: xong** (2026-11-11, xem mục D6 ở trên).
5. **D7 xong** (2026-11-11, xem mục D7 ở trên): nhóm visual, sửa bố cục báo cáo định dạng cũ, chép dán giữa các trang, căn lề và phân bố. Phase D còn lại: các mục tồn đọng (D5 review (a)–(d), danh mục D4, quan sát Desktop thêm).

Phase D xong khi sửa trang Nhom6 trong BI Pro (bố cục, trường, loại, định dạng, trang), lưu, rồi mở lại được cả trong BI Pro lẫn Power BI Desktop. Phase W đã được bạn xác nhận ổn.
