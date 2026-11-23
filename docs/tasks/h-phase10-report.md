# Báo cáo Phase 10 (H5 / US8 — View DAX, TMDL, Model, Table)

Ngày hoàn tất: 2026-11-21 · Phạm vi: `T075`–`T079` trong `specs/016-h-giao-dien-giong-powerbi/tasks.md`.

## 1. Tóm tắt thay đổi

- **T075 (`Tests/BIProTests/UIParity/CodeViewChromeTests.swift`):** kiểm dải thông báo DAX, chuỗi trống khu Results, tab "Query n" / "Script n", tab `Problems (n)` / `Output`, hộp giới thiệu TMDL lần đầu lưu qua `AppPreferences.tmdlIntroSeen`, pane `ModelPropertiesPanel` với 3 công tắc mặc định (`No` / `Yes` / `No`), và xác nhận 4 workspace không còn thanh trạng thái lồng.
- **T076 (`Sources/BIPro/Query/CodeActionBar.swift`, `Sources/BIPro/Query/QueryWorkspaces.swift`):**
  - DAX Query view: thêm `DAXInfoBanner` đóng được theo phiên, `DAXEmptyResultsIllustration` ("Your query results will show up here") khi chưa chạy truy vấn, thanh tab đáy `Query n` + nút `+` vuông `accentTeal`, bỏ thanh trạng thái lồng.
  - TMDL view: thêm vùng đáy `Problems (n)` / `Output`, thanh kịch bản `Script n` + `+`, hộp giới thiệu lần đầu "Edit your model with TMDL" ghi `tmdlIntroSeen`, gắn `DataPane` tab `Model` thu gọn được, bỏ thanh trạng thái lồng.
- **T077 (`Sources/BIPro/Model/ModelPropertiesPanel.swift`, `Sources/BIPro/Model/ModelWorkspace.swift`):** tạo `ModelPropertiesPanel` (nhóm "Cards" với 3 công tắc `No` / `Yes` / `No`) đặt giữa sơ đồ và `DataPane` (cả hai thu gọn thành dải 31 pt); chuẩn hoá thanh tab đáy "All tables" + nút `+` vuông `accentTeal`; gỡ thanh trạng thái lồng và cụm zoom/reset trùng (đã chuyển sang `WindowStatusBar`).
- **T078 (`Sources/BIPro/Table/TableWorkspace.swift`):** giữ thanh công thức và lưới `NSTableView`, thêm ký hiệu lọc `▾` ở hàng tiêu đề cột, gỡ thanh trạng thái lồng (dùng `WindowStatusBar` / `StatusLine`).

## 2. Kiểm chứng tự động

- **TDD RED → GREEN:** `CodeViewChromeTests` thất bại đỏ trước cài đặt, sau đó xanh 4/4 test (tổng `UIParity`: 51/51 passed).
- **Toàn repo (`swift test --no-parallel`):** **2.533 / 2.533 passed** (0 failures).
- **Heavy Golden (`BIPRO_HEAVY=1 swift test -c release ...`):** **119 / 119 passed** (0 regressions).

## 3. Kiểm tra ảnh chụp (`build/h-out/us8/`)

| Tệp | Kích thước | Nhận xét thị giác |
|---|---|---|
| `build/h-out/us8/dax-view-light.png` | 186,492 bytes | Dải thông báo DAX, nút Run teal + Update model (0), Results trống "Your query results will show up here", Data Tables/Model, `Query 1 of 1`; khớp `v_dax_1.png` |
| `build/h-out/us8/tmdl-view-light.png` | 199,811 bytes | Apply/Preview, `Problems (0)` / `Output`, Data tab `Model` với cây `Semantic model`, `Script 1 of 3`; khớp `v_tmdl_2.png` |
| `build/h-out/us8/model-view-light.png` | 243,225 bytes | Sơ đồ bảng, pane `Properties` (Cards No/Yes/No) giữa canvas và Data, thanh trạng thái `1 tables · 0 relationships` + reset + zoom; khớp `v_model_1.png` |
| `build/h-out/us8/table-view-light.png` | 183,020 bytes | Ribbon Column tools, FormulaBar, tiêu đề cột có `▾`, Data pane, `Table: Sales (2 rows) Column: Amount (2 distinct values)`; khớp `t_colsel.png` |

## 4. Quyền sở hữu tệp

Toàn bộ tệp sửa/tạo nằm trong `docs/phase-h-ownership.tsv`.
