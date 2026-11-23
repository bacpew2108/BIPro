# Báo cáo Phase 7 (H4 / US5 — Pane Filters, Visualizations, Data)

Ngày hoàn tất: 2026-11-21 · Phạm vi: `T054`–`T060` trong `specs/016-h-giao-dien-giong-powerbi/tasks.md`.

## 1. Tóm tắt thay đổi

- **T054 (`Tests/BIProTests/UIParity/PaneParityTests.swift`):** kiểm Filters thu gọn mặc định (`filtersCollapsed == true`), bề rộng pane mặc định `UIMetrics.pane` (181 pt) kéo giãn tối đa 320 pt, thu gọn/mở lại Visualizations và Data; Visualizations có đủ 3 tab biểu tượng (`build`, `format`, `analytics`) và lưới 6 cột 39 ô đúng thứ tự `contracts/visual-gallery.md` (ô chưa hỗ trợ mờ + tooltip, ô hỗ trợ gọi `insertVisual`); Format có Search + Visual/General; Data ở Model/DAX/TMDL hiện tab Tables/Model và cây "Semantic model" đủ 9 nhóm kèm số lượng; bỏ toàn bộ chân trạng thái riêng của pane.
- **T055 (`Sources/BIPro/Panes/ReportPanes.swift`, `Sources/BIPro/DesignSystem/Components.swift`, `Sources/BIPro/Report/ReportWorkspace.swift`):**
  - `CollapsedPaneStrip`: rộng `UIMetrics.collapsedPane` (31 pt), mũi tên `«`, biểu tượng phễu/biểu đồ/dữ liệu, tiêu đề chữ thường xoay 90°; bấm để mở lại.
  - `FiltersPane`: thu gọn mặc định, tự mở khi bấm hoặc chọn visual; bỏ `PaneFooter`.
  - `VisualizationsPane`: tiêu đề + `»`, nhãn phụ "Build visual" / "Format visual" / "Add further analyses", thanh 3 biểu tượng tab có gạch chân `accentTeal`, lưới 6 cột 39 ô (`VisualGallerySlot`, đối chiếu `o_now.png` — hàng 1–6 khớp 100%, hàng 7 có Power Automate, ArcGIS Maps, `…` Get more visuals; 4 visual tuỳ chỉnh nhập riêng của file trong `o_now.png` không có trong tài liệu trống nên giữ đúng 39 ô theo hợp đồng), vùng **Drill through** ở cuối (Cross-report Off, Keep all filters On, ô nét đứt "Add drill-through fields here"); bỏ `PaneFooter`.
- **T056 (`Sources/BIPro/Panes/BuildWells.swift`):** ô trống viền nét đứt với nhãn `"Add data fields here"` / `"Thêm trường dữ liệu vào đây"`; thẻ trường có nút menu `▾` và nút bỏ `×`.
- **T057 (`Sources/BIPro/Panes/FormatPane.swift`):** thêm ô Search lọc theo tên thẻ và thuộc tính; giữ 2 tab `Visual` / `General` gạch chân teal (chuyển Analytics lên tab biểu tượng thứ 3 ở `VisualizationsPane`); giữ thẻ gập `›` kèm công tắc On/Off bên phải.
- **T058 (`Sources/BIPro/Panes/DataPane.swift`, `Sources/BIPro/Panes/ModelTree.swift`):** ô tích màu `accentTeal`; hiện tab **Tables / Model** ở cả Model, DAX và TMDL view (`DataPane.showsModelTabs`); song ngữ hoá cây "Semantic model" và 9 nhóm con (`Calculation groups`, `Cultures`, `Expressions`, `Functions`, `Measures`, `Perspectives`, `Relationships`, `Roles`, `Tables`) kèm số lượng từ `ModelMetadata`; bỏ `PaneFooter`.
- **T059 (`Sources/BIPro/DocumentState.swift`):** thêm `filtersCollapsed = true`, `visualizationsCollapsed`, `dataCollapsed`, `paneWidth(for:)` / `setPaneWidth(_:for:)` (mặc định `UIMetrics.pane` = 181 pt, kẹp 160–320 pt), mở rộng `VisualizationsTab` thêm `.analytics`.

## 2. Kiểm chứng tự động

- **TDD RED → GREEN:** `PaneParityTests` thất bại đỏ trước cài đặt, sau đó xanh 3/3 test (tổng `UIParity`: 38/38 passed).
- **Toàn repo (`swift test --no-parallel`):** **2.519 / 2.519 passed** (0 failures).

## 3. Kiểm tra ảnh chụp (`build/h-out/us5/`)

Trong lần chụp đầu, kiểm tra ảnh bằng mắt phát hiện biển cấm vàng `ImageRenderer` từ `Menu`/`.onDrop` trong `BuildWells` và `leftContextMenu` trong `DataPane`/`ModelTree`. Đã thêm guard `isSnapshotRender` (`snapshotSafeDrop`, `snapshotSafeLeftContextMenu`) và xuất lại:

| Tệp | Kích thước | Nhận xét thị giác |
|---|---|---|
| `build/h-out/us5/panes-build-light.png` | 123,168 bytes | Filters thu gọn 31 pt (`«`, phễu, chữ dọc), Visualizations lưới 6 cột sắc nét + 4 well nét đứt "Add data fields here" + Drill through, Data có Search và bảng `Sales`; không biển cấm |
| `build/h-out/us5/panes-build-dark.png` | 121,848 bytes | Dark Mode tương phản cao, màu nhấn teal `#3FB59B` rõ trên tab và nút chọn visual |
| `build/h-out/us5/panes-format-light.png` | 66,956 bytes | Tab Format visual có ô Search + Visual/General gạch chân teal, khớp `p_format.png` |
| `build/h-out/us5/pane-data-model-light.png` | 70,443 bytes | Tab Tables/Model và cây `Semantic model` đủ 9 nhóm + số lượng, khớp `v_tmdl_2.png` |

## 4. Quyền sở hữu tệp (`git status`)

Toàn bộ tệp nằm trong `docs/phase-h-ownership.tsv`.
