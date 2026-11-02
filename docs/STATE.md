# BI Pro: trạng thái làm việc

Cập nhật: 2026-11-02, sau review và merge đợt 1 của Phase C.

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
  - **Đợt 2** chưa bắt đầu, gồm:
    - R3: donut, treemap, shape map, tooltip;
    - I: tương tác (slicer, lọc chéo, tô sáng);
    - E3 (lead): hiệu năng engine;
    - G (lead): ghép visual thật vào canvas, drill, drillthrough.

## Worktree / worker

| Worktree | Nhánh | Việc | Trạng thái |
|---|---|---|---|
| `c1-e1-engine` | `Bacpew/c1-e1-engine` | E1 engine hàm visual | đã merge; chưa xoá worktree (chờ bạn) |
| `c1-r1-charts` | `Bacpew/c1-r1-charts` | R1 biểu đồ | đã merge; chưa xoá |
| `c1-r2-cards` | `Bacpew/c1-r2-cards` | R2 card/slicer/matrix | đã merge; chưa xoá |
| `ui4-editor` | `Bacpew/ui4-editor` | UI4 Phase B | đã merge từ trước; chưa xoá |

Mô tả việc của từng worker nằm trong `docs/tasks/`.

## Quyết định đã chốt

- Visual sinh **văn bản DAX giống Performance Analyzer**, rồi chạy qua engine. So golden sau khi chuẩn hoá khoảng trắng.
- Renderer chỉ đọc `DataView` và `VisualFormat`, không biết DAX.
- Số hiển thị: đơn vị tự động; độ chính xác mặc định theo định dạng của measure.
- Tên cột kết quả:
  - ký tự không phải chữ hoặc số → `_`;
  - tên không bắt đầu bằng chữ cái thì thêm `v` ở đầu;
  - trùng tên cột của model thì thêm `2`.
- Dự báo (forecast) chỉ làm gần đúng; đường xu hướng làm đúng.

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

1. **Đợt 2:** giao R3 ‖ I cho worker. Lead làm E3 (3 truy vấn chậm: combo thấu chi 36 s, matrix Giờ × Thứ 5,5 s, matrix mở nút 9 s) và G (ghép vào canvas).
2. Bộ sinh truy vấn: slicer hierarchy đang mở nút (`expansionStates` → ROLLUP + NONVISUAL), và các khuôn tương tác ở C1.md §2.2.
3. **Hợp đồng:** `SlicerNode` chưa có `formatString`; R2 đã nêu.
4. **Ảnh xuất thử** ở `build/c-out/visuals/`. Renderer có tham số `interactive:`/`scrollable:` để `ImageRenderer` vẽ được.
5. **Chờ bạn:**
   - đồng ý xoá 4 worktree đã merge;
   - copy văn bản "Define new measure" của Power BI (Phase B);
   - buổi C2 trên VM (sau đợt 2).
