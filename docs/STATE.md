# BI Pro: trạng thái làm việc

Cập nhật: 2026-11-04, đợt 2: R3, I đã merge; E3 xong phần chính; G đã ghép số thật vào canvas (chưa có drill, drillthrough, tô sáng).

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
  - **Đợt 2** (2026-11-04) làm gần xong, còn các phần ghi bên dưới:
    - R3 (donut, treemap, shape map, tooltip) và I (logic tương tác): agy xong, đã review và merge vào `main`;
    - E3 (hiệu năng engine): xong phần chính. Đo ở `phase-c-evidence/C1.md` §1.5: combo thấu chi 34 s → 3,7 s, matrix Giờ × Thứ 5,5–8 s → 1,7–2,2 s, matrix mở nút 9 s → 1,1–1,5 s, combo kênh 12,7 s → 0,7 s; golden 57/57, kết quả khớp byte. Chưa đạt ngưỡng 1 s ở combo thấu chi và matrix Giờ × Thứ;
    - G (ghép): `Report/ReportInteraction.swift` + `Report/LiveVisual.swift`. Card, slicer, matrix, cột/bar/line/combo, donut, treemap, shape map chạy số thật; slicer và lọc chéo đi qua `FilterTranslator.assemble`. Đã mở trang D2 của Nhom6 trong app: đủ 6 card, 3 chart, donut, 100%, bản đồ, bar, combo. Chưa làm: tô sáng chéo (tạm áp như lọc chéo), drill down/up, drillthrough, slicer phân cấp mở nút, tooltip, chuột phải; chưa tự kiểm bấm chuột (chỉ logic thuần có test).

## Worktree / worker

Worktree của đợt 1 và `ui4-editor` đã xoá (2026-11-03). Mô tả việc của từng worker nằm trong `docs/tasks/`. Gốc của cả hai nhánh: `main` ở `61adc89` (chưa push).

| Worker | Nhánh | Worktree | Brief → báo cáo | jsonl | Trạng thái |
|---|---|---|---|---|---|
| R3 | `bacpew2108/c2-r3` | `~/orca/workspaces/PowerBINative/c2-r3` | `docs/tasks/c2-r3.md` → `c2-r3-report.md` | `/private/tmp/claude-501/-Users-macprom114-Desktop-PowerBINative/39e5fdc8-d27c-46a2-b750-47ff2adaa733/scratchpad/runs/c2-r3.jsonl` | đã merge vào `main` (2026-11-04); worktree còn đó, chờ bạn cho xoá |
| I | `bacpew2108/c2-i` | `~/orca/workspaces/PowerBINative/c2-i` | `docs/tasks/c2-i.md` → `c2-i-report.md` | `…/scratchpad/runs/c2-i.jsonl` (cùng thư mục) | đã merge vào `main` (2026-11-04); worktree còn đó, chờ bạn cho xoá |

Allow-list quyền của agy: `…/scratchpad/c2-allow.json` (ngoài repo). Một lệnh nền chờ cả hai jsonl có `"event":"result"`; nếu phiên đóng mà chưa xong thì mở phiên mới, kiểm hai file jsonl rồi review.

**Review cần làm khi xong** (CLAUDE.md "Khi review"):
- `git diff --stat main` mỗi nhánh: chỉ file trong danh sách được giao (R3: Charts/{Donut,Treemap}, Map, Tooltip, Tests/{Donut,Treemap,Map}; I: Interaction/{FilterState,SelectionState,FilterTranslator,InteractionRules}, Tests/Interaction; cộng file báo cáo).
- Đọc báo cáo và diff; chạy `swift build`, `swift test`. Soi các lỗi agy hay mắc: `@objc(selector:)` thiếu, `isReleasedWhenClosed`, popover sáng, kết quả viết cứng cho test qua.
- R3: mở 6 ảnh `build/c-out/visuals/{donut,donutHighlight,treemap,treemapOneLevel,shapeMap,tooltip}.png` trong worktree, kiểm khác dung lượng và đúng hình.
- I: kiểm 7 test golden đọc văn bản từ `observe-c1/interact/*.dax`; xem danh sách [SUY ĐOÁN] trong báo cáo.
- Chưa đạt thì giao lại MỘT lần; vẫn chưa đạt thì báo bạn. Không tự merge, không tự xoá worktree.

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

- `swift build`; `swift test` (717 test).
- Golden Nhom6:
  ```
  BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS"
  ```
  57 test, gồm 30 golden Phase B và 72 truy vấn visual.
- `zsh scripts/build-app.sh` (đóng gói `build/BI Pro.app`).
- `dax-run profile <pbix> --filter "<DAX>"`: đo thời gian truy vấn của từng visual.
- Test sập SIGBUS sau khi đổi struct dùng chung giữa các module: xoá `.build` rồi build lại.

## Việc tiếp theo

1. **G còn lại (lead):** tô sáng chéo (thêm `highlight` cho `VisualQuerySpec`, `VAR __H0FilterTable` + cột `CALCULATE(<measure>, KEEPFILTERS(__H0FilterTable))` theo C1.md §2.2); drill down/up (`Drill.swift`), drillthrough, slicer phân cấp mở nút (`expansionStates` → ROLLUP + NONVISUAL); tooltip và chuột phải; kiểm engine chạy được các truy vấn tương tác trong `observe-c1/interact/*.dax` (có tuple IN, `KEEPFILTERS(SUMMARIZE …)`: agy báo engine chưa chạy, mình chưa kiểm). Bấm thử trong app (slicer, lọc chéo) chưa ai làm.
2. **E3 còn lại:** hạ combo thấu chi và matrix Giờ × Thứ dưới 1 s. Hướng: gộp context transition theo nhóm (một lần quét thay vì mỗi tài khoản hai CALCULATE), giảm cấp phát ở đường nóng (8 luồng chỉ nhanh hơn 1 luồng khoảng 2,2 lần).
3. **Hợp đồng:** `SlicerNode.formatString` đã thêm (2026-11-04); `DropdownSlicer` chưa dùng (năm có thể hiện "2,016").
4. **Ảnh xuất thử** ở `build/c-out/visuals/`. Renderer có tham số `interactive:`/`scrollable:` để `ImageRenderer` vẽ được.
5. **Chờ bạn:**
   - copy văn bản "Define new measure" của Power BI (Phase B);
   - duyệt cho xoá worktree `c2-r3`, `c2-i` (đã merge);
   - buổi C2 trên VM (sau đợt 2) và bấm thử app.
