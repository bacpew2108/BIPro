# BI Pro: trạng thái làm việc

Cập nhật: 2026-11-09. **Phase C xong phần chính (commit `710daaf`). Phase D lát D1 (sửa bố cục canvas, lưu `.pbix` T1) xong phần code, chưa commit; `swift test` 911 qua, golden nặng 81 qua.** Việc tiếp: xem "Việc tiếp theo" ở cuối.

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

  - **Phase D, lát D1 xong phần code (2026-11-09, Spec Kit `specs/002-d1-canvas-luu-t1/`, chưa commit)**: ⌘E bật chế độ Sửa trên canvas (Xem giữ nguyên lọc chéo/drill): chọn một/nhiều (Shift, khung chọn), kéo di chuyển, 8 tay nắm đổi cỡ (khung bóng), bám lưới 8 px (giữ Option bỏ bám), phím mũi tên, Delete, ⌘D nhân bản, ⌘C/⌘V, ⌘Z/⇧⌘Z. Lưu: ⌘S, ⇧⌘S ghi **tầng T1** bằng ghép byte (`PBIRLayoutPatch`, `PBIXWriter` thêm/bớt phần), dựng+kiểm trong bộ nhớ → file tạm → mở lại → thay; bản sao lưu ở `~/Library/Application Support/BI Pro/Backups/`; file dưới `~/Downloads` buộc Lưu thành; hỏi lưu khi đóng/thoát; app là Editor của `.pbix`. Lưu Nhom6 mất 0,22–0,26 s (SC-004); kéo/đổi cỡ 10–32 ms mỗi khung. Visual trong nhóm (`parentGroupName`) chưa sửa được; báo cáo định dạng cũ (`Report/Layout`) chưa sửa được. Chi tiết ở `specs/002-d1-canvas-luu-t1/` (`measurements.md`, `research.md` R2), ảnh ở `docs/phase-d-evidence/`. Chờ bạn: VM-D1-mở (mở `build/d-out/D1/Nhom6_d1.pbix` trong Power BI Desktop, `CHECKLIST.md`; và `Nhom6_pre.pbix` + `CHECKLIST-pre.md`), VM-D1 quan sát (`VM-D1-QUAN-SAT.md`).

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

- `swift build`; `swift test` (798 test).
- Golden Nhom6:
  ```
  BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS"
  ```
  60 test, gồm 30 golden Phase B và 72 truy vấn visual. Test `huyTruyVanNangDungNhanh` (huỷ trong 100 ms) chập chờn khi chạy cùng test nặng khác.
- `zsh scripts/e3-loop.sh`: đo ba truy vấn chậm trên Nhom6 và so byte với `build/e3-base/` (tạo bản chuẩn trước khi sửa engine).
- `zsh scripts/build-app.sh` (đóng gói `build/BI Pro.app`).
- `dax-run profile <pbix> --filter "<DAX>"`: đo thời gian truy vấn của từng visual.
- Test sập SIGBUS sau khi đổi struct dùng chung giữa các module: xoá `.build` rồi build lại.

## Việc tiếp theo

**Chờ bạn:**
- **D1:** mở `build/d-out/D1/Nhom6_d1.pbix` và `Nhom6_pre.pbix` trong Power BI Desktop (VM) theo `CHECKLIST.md` / `CHECKLIST-pre.md`; làm buổi quan sát `VM-D1-QUAN-SAT.md` (chốt các [SUY ĐOÁN] về lưới, nhân bản, bookmark khi xoá visual); bấm thử chế độ Sửa trong app (⌘E).
- Bấm thử bản mới (`zsh scripts/build-app.sh`): bookmark (menu chuột phải chưa kiểm), thẻ measure, matrix nhiều cấp, tốc độ cuộn (hằng số 100 và 2,5 ở `MatrixVisual.swift` nếu cần chỉnh).
- Hệ quả E3-cấu-trúc: các visual đã nhanh nên có thể bấm thử lọc/đổi slicer ở trang D1 để cảm nhận (mục tiêu mỗi visual dưới 1 s).
- Chỉ trường nào "chưa add được bộ lọc" ở trang nào (menu "Thêm field" mới có 77 cột nhìn thấy, chưa có measure, cấp hierarchy).

**Backlog Phase C (chưa có yêu cầu):**
- Matrix: đọc nút đã mở lưu trong file (`expansionStates`), mở nút theo hàng, ô "Nhóm tuổi" (tên trường hàng) đang bị thay bằng tên cấp theo yêu cầu.
- Drill cho donut chưa có golden; Edit interactions chưa có giao diện; thêm measure/hierarchy vào Filters pane; kéo field từ pane Dữ liệu; Advanced cho cột ngày; Top N khớp văn bản Power BI (`TOPN` nửa nối).
- Trục Y line "$0bn" của Power BI (đơn vị tự động) chưa biết quy tắc; dự báo từng tháng chưa khớp.
- Ghi bookmark vào .pbix; test `huyTruyVanNangDungNhanh` nay lặp truy vấn đến khi bị huỷ (truy vấn golden đều xong dưới 0,6 s), vẫn có thể chập chờn khi máy tải cao.

**Phase D tiếp:** các lát sau theo Spec Kit: Build pane + field well, Format pane, ribbon Insert, thêm/xoá/đổi tên trang, ghi bookmark và bộ lọc người dùng vào file. Phase W đã được bạn xác nhận ổn.
