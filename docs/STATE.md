# BI Pro: trạng thái làm việc

Cập nhật: 2026-11-05, **đợt 3 (gói P) đã commit (88329f1), chờ bạn bấm thử; E3 vòng 2 xong**. Việc tiếp: buổi C2 trên VM (checklist ở `docs/phase-c-oracle/VM-TODO-P.md` cho phần P).

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
    - E3 (hiệu năng engine): xong phần chính. Đo ở `phase-c-evidence/C1.md` §1.5: combo thấu chi 34 s → 3,7 s, matrix Giờ × Thứ 5,5–8 s → 1,7–2,2 s, matrix mở nút 9 s → 1,1–1,5 s, combo kênh 12,7 s → 0,7 s; golden 57/57, kết quả khớp byte. Chưa đạt ngưỡng 1 s ở combo thấu chi và matrix Giờ × Thứ;
    - G (ghép): `Report/ReportInteraction.swift` + `Report/LiveVisual.swift`. Card, slicer, matrix, cột/bar/line/combo, donut, treemap, shape map chạy số thật; slicer, lọc chéo, tô sáng chéo (3 golden khớp `interact/xf-*.dax`), drill down/up (nút góc trên phải, chế độ drill, chuột phải), drillthrough (chuột phải → trang đích, tham số đọc từ `pageBinding`), tooltip khi rê chuột. Engine chạy được cả 16 truy vấn trong `observe-c1/interact/` (agy báo thiếu là sai). Bạn đã bấm thử slicer và lọc chéo: ổn. Chưa tự kiểm bấm drill, drillthrough, tô sáng trên app.
    - Mở nút: slicer hierarchy (`expansionStates` trong file + bấm mũi tên) và matrix cột (bấm +/−) đã làm, có golden (`D1-slicer-nam`, `interact/matrix-expand`); mới hỗ trợ mở một cấp ở cấp gốc. `DropdownSlicer` đã dùng `SlicerNode.formatString`.
    - Chưa làm (để sau): drill cho donut chưa có golden; Edit interactions (người dùng đổi lọc/tô sáng giữa hai visual) chưa có giao diện; matrix mở nút theo hàng; mở nút nhiều cấp.

  - **Đợt 3 (gói P)** xong phần code (2026-11-05), lead tự làm, không dùng worker (git chưa sạch để tách worktree, phần UI nhỏ và dùng ngay model mới):
    - `PBIXKit/ReportFilters.swift`: `ReportBookmark` đọc thêm `suppressData`, `suppressActiveSection`, `activeSection`, `targetVisualNames`, `hidden` (id visual → ẩn); `ReportVisual` có init public;
    - `Report/ViewState.swift`: `VisibilityState` (ẩn/hiện do Selection pane và bookmark, ghi đè giá trị trong file), `UserFilter` + `UserFilterKey` (bộ lọc Basic In/Not In người dùng sửa);
    - `ReportInteraction`: `visibility`, `userFilters`, `applyBookmark`, `toggleHidden`, `distinctValues`, `mergeStatics` (thay bộ lọc tĩnh tại chỗ, thẻ ngầm thêm vào cuối nhóm cấp của nó); `VisualDataLoader.distinctValues`;
    - canvas bỏ visual ẩn theo `interaction.isHidden`, nút action kiểu Bookmark áp bookmark, `LiveVisualView` nạp lại khi `userFilters` đổi;
    - `Panes/FilterEditor.swift` (editor Basic filter: tìm kiếm, chọn nhiều, là/không phải, chọn tất cả, đặt lại) và `ReportPanes.swift` (thẻ mở được, mắt ẩn/hiện trong Selection pane, bấm bookmark trong Bookmarks pane);
    - test: `Tests/BIProTests/Panes/` (15 test thường, 3 test nặng trên Nhom6, đều qua; `swift test` 770 qua).
    - Chưa làm: bookmark không `suppressData` (khôi phục slicer/bộ lọc), thêm/xoá bộ lọc ở Filters pane, Advanced filter, Top N, thẻ bộ lọc cho hierarchy; bookmark ghi vào file (Add/Update/Delete). Chưa bấm thử giao diện (xem `VM-TODO-P.md` phần "tự bấm thử").

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

0. **Đợt 3:** VM P1–P10 xong (2026-11-06), 9/10 khớp giả định, P9 khác nhưng giữ (xem cuối `VM-TODO-P.md`). Bấm thử 4/5 đạt; **lỗi mục 3**: bộ lọc cấp visual trong Filters pane không đổi visual và sau 1–2 lần bấm thì mọi biểu đồ đứng im. Engine đã kiểm ổn (test `boLocCapVisualTrenMoiThe`), cần tái hiện ở lớp giao diện (cần quyền Accessibility cho `cliclick` hoặc bước bấm cụ thể từ bạn). **Đã làm lại giao diện Filters pane theo Power BI (2026-11-06):** thẻ trắng/xám, tên đậm khi lọc hoặc mở, Filter type, tìm kiếm, Select all ba trạng thái, đánh dấu phần bù cho Not In, ô thả "Thêm field" (chưa kéo thả được); visual chỉ nạp lại khi bộ lọc của nó, trang hoặc báo cáo đổi (trước đây mọi visual nạp lại, nghi là nguyên nhân đứng im). Đã tự bấm thử bằng cliclick (2026-11-06): lọc cấp visual, lọc báo cáo, bấm liên tiếp đều ổn, không còn đứng im. Sau đó sửa tiếp: giá trị hiển thị theo `formatString` của cột (giờ `08:00`, ngày `MMM yyyy` qua `Visuals/Format/DateDisplay.swift`, nhãn năm trục liên tục lấy từ giá trị gốc), trục chữ quá dày thì cuộn ngang có thanh cuộn (như combo thấu chi của Power BI), bấm ra ngoài trang bỏ chọn visual và lựa chọn điểm dữ liệu. Thanh cuộn của trục chữ kéo được, bánh xe/trackpad cuộn được (lớp bắt cuộn nằm trên lớp chọn điểm); chọn điểm trên trục cuộn hỏi biểu đồ theo vị trí. Dự báo line chart vẽ dải tin cậy và đường dự báo (`Charts/Forecast.swift`, Holt-Winters cộng tính, mùa 12, cần ≥ 24 tháng; [SUY ĐOÁN] chỉ giống hình Power BI, chưa khớp số). **Đợt A (2026-11-06):** Advanced filter (1–2 điều kiện, And/Or; chữ: chứa/bắt đầu bằng/…; số: so sánh) và Top N (chỉ cấp visual) trong Filters pane, đọc được Advanced từ file; thêm thẻ bằng menu cột, bỏ thẻ bằng ×; bookmark không `suppressData` khôi phục bộ lọc và slicer ([SUY ĐOÁN] theo schema PBIR); engine thêm `CONTAINSSTRING`, `CONTAINSSTRINGEXACT`, `LEFT`; giá trị series cũng theo định dạng cột. Việc bạn tự làm ở `docs/phase-c-oracle/VM-TODO-C2.md`. Chưa làm: kéo field từ pane Dữ liệu vào Filters pane, Advanced cho cột ngày, Require single selection chỉ là hành vi giao diện. "Define new measure" (Phase B) = đúng chữ `Measure = ` bạn đã cho, xong. **Buổi C2 + đợt A đã đối chiếu (2026-11-07, `~/Downloads/C2_A/`, bảng ở cuối `VM-TODO-C2.md`):** Advanced "contains" của Power BI là `SEARCH("x", col, 1, 0) >= 1` (engine thêm `SEARCH`, văn bản đã đổi); Top N của Power BI là bảng nửa nối `TOPN(n, SUMMARIZECOLUMNS(col, "m", measure), [m], 0|1)` (BI Pro chỉ đúng kết quả, khác văn bản); bookmark thật ghi lựa chọn slicer ở `objects.merge.general` (đã sửa, slicer hierarchy Năm › Quý khôi phục đúng, test dùng chính `bookmark-data.pbix`). **Bookmark thêm/cập nhật/đổi tên/xoá** trong Bookmarks pane (nút +, menu chuột phải; tuỳ chọn Data/Display/Current page; `Report/UserBookmark.swift`), sống trong phiên vì BI Pro chưa ghi lại .pbix. Tooltip vùng dự báo như Power BI (tên dự báo, Upper/Lower bound; điểm neo thêm dòng dự báo), tooltip lật sang trái/lên khi gần mép. Dự báo: dải tin cậy rộng 42–51M so với 44,6–51,2M của Power BI nhưng từng tháng chưa khớp (Jan 188M so với 165M); ETS các dạng cũng không khớp, không chase thêm. Chưa làm: thêm measure/cấp hierarchy vào Filters pane (menu hiện đủ 77 cột nhìn thấy; bạn báo "một số trường ở một số dashboard chưa add được", cần bạn chỉ trường cụ thể), mở nút nhiều cấp (mẫu truy vấn đã có ở `b5-1/b5-2.dax`).

1. **Đợt 2 còn tồn:** kiểm tay drill, drillthrough, tô sáng, mở nút trên app ở buổi C2; Edit interactions; mở nút nhiều cấp.
2. **E3 còn lại (vòng 2 xong 2026-11-05):** combo thấu chi 3,6 → 2,15 s, matrix Giờ × Thứ 2,4 → 1,75 s, matrix mở nút 1,0 s, combo kênh 0,74 s; golden 60/60, khớp byte (chi tiết và chẩn đoán ở `C1.md` §1.5). Chưa dưới 1 s ở hai cái đầu: các sửa nhỏ hết lợi nhuận, còn lại cần đổi cấu trúc (gộp context transition theo nhóm cho `Avg_Account_Balance`, `FilterContext` ít cấp phát). **Quyết định (2026-11-07): mở đợt engine riêng cho E3-cấu-trúc** (gộp context transition theo nhóm cho `Avg_Account_Balance`, `FilterContext` ít cấp phát); chưa bắt đầu, vào Spec Kit khi bạn bảo bắt đầu. Test huỷ truy vấn (100 ms) chập chờn từ trước, không phải do E3.
4. **Ảnh xuất thử** ở `build/c-out/visuals/`. Renderer có tham số `interactive:`/`scrollable:` để `ImageRenderer` vẽ được.
5. **Chờ bạn:**
   - copy văn bản "Define new measure" của Power BI (Phase B);
   - buổi C2 trên VM (sau đợt 2) và bấm thử app.
