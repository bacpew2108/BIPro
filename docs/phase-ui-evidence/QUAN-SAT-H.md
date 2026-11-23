# Quan sát & Mục `[SUY ĐOÁN]` — Phase H (v1.3 UI Parity)

Ngày tổng hợp: 2026-11-21 · Nguồn ảnh VM chuẩn: `docs/phase-ui-evidence/vm-ui/` (Power BI Desktop 2.159, 2 phiên VM-UI và VM-UI2).

Tài liệu này liệt kê đầy đủ mọi mục có cờ `observed == false` (`[SUY ĐOÁN]`) trong mã nguồn Phase H và các thành phần giao diện chưa có ảnh chụp VM-UI, kèm cách BI Pro xử lý để người dùng quyết định có cần chụp VM bổ sung hay không.

## 1. Danh mục mục `observed == false` trong mã Ribbon (`Sources/BIPro/Shell/Ribbon/`)

| # | Tệp | Mục / Nhãn EN | Lý do chưa quan sát trên VM | Cách xử lý trong BI Pro v1.3.0 |
|---|---|---|---|---|
| 1 | `Catalog+Design.swift` | `Themes` gallery (`9` ô Power BI trong `dd_themes.png`) | Ảnh `dd_themes.png` hiển thị 9 ô màu nhưng chưa chụp hover để lấy tên từng theme mặc định | Gắn vào `ThemeCatalog.presets` hiện có + ô mặc định gạch chéo, bấm áp dụng thật + hoàn tác |
| 2 | `Catalog+Design.swift` | `Customize theme` | Hộp thoại Customize theme chưa mở chụp trên VM | Đặt `.pending` (vô hiệu kèm tooltip song ngữ) |
| 3 | `Catalog+Insert.swift` & `RibbonMenus.swift` | `Buttons ▾` → `Navigator ›` (`Page navigator`, `Bookmark navigator`) | Ảnh `dd_buttons.png` thấy 10 mục chính nhưng chưa bung menu con `Navigator ›` | Nối trực tiếp vào 2 lệnh có sẵn (`pageNavigator`, `bookmarkNavigator`) |
| 4 | `Catalog+ViewOptimizeHelp.swift` | `Mobile layout` | Chế độ thiết kế di động chưa mở trên VM | Đặt `.unsupported` (ngoài phạm vi Phase H, vô hiệu kèm tooltip) |
| 5 | `Catalog+ViewOptimizeHelp.swift` | `Optimization presets ▾` | Menu thả xuống chưa mở chụp trên VM | Đặt `.pending` (vô hiệu kèm tooltip song ngữ) |
| 6 | `Catalog+Modeling.swift` | `Language ▾` (nhóm Q&A) | Menu thả xuống chưa mở chụp trên VM | Đặt `.unsupported` (BI Pro không có Q&A, vô hiệu kèm tooltip) |
| 7 | `Catalog+Modeling.swift` | `Linguistic schema ▾` (nhóm Q&A) | Menu thả xuống chưa mở chụp trên VM | Đặt `.unsupported` (vô hiệu kèm tooltip) |
| 8 | `Catalog+Contextual.swift` | `Groups ▾` (Data/Drill → Data groups) | Menu thả xuống chưa mở chụp trên VM | Đặt `.pending` (binning/grouping chưa cài, vô hiệu kèm tooltip) |

## 2. Thành phần ngoài Ribbon chưa quan sát chi tiết trên VM

| # | Thành phần | Điểm `[SUY ĐOÁN]` | Cách xử lý trong BI Pro v1.3.0 |
|---|---|---|---|
| 1 | `VisualizationsPane` (`contracts/visual-gallery.md`) | Hàng 7 trong `o_now.png` có thêm dãy visual nhập riêng của file (`Nhom6_d15.pbix`) | Giữ 39 ô chuẩn Power BI Desktop (hàng 1–7 đến `…` Get more visuals); các ô BI Pro chưa hỗ trợ hiện mờ + tooltip |
| 2 | Menu `Recent sources ▾`, `Transform data ▾`, `More visuals ▾`, `Sensitivity ▾` | Nội dung menu thả xuống chưa chụp riêng trên VM | `Transform data` nối Query Editor; `More visuals` mở popover `VisualCatalog`; `Recent sources` và `Sensitivity` vô hiệu có tooltip |
| 3 | Menu `Align ▾`, `Group ▾`, `Bring forward ▾`, `Send backward ▾` | Biểu tượng chi tiết từng mục con trong menu thả xuống | Nối đầy đủ 8 lệnh Align, Group/Ungroup/Merge, Z-order hiện có của `LayoutEditor` |
| 4 | Trạng thái hover / pressed chi tiết & Ribbon khi thu gọn (`^`) | Không chụp từng trạng thái con trỏ trên VM | Dùng nền `DS.Palette.selectionSoft` / `controlFill`, thu gọn lưu `AppPreferences.shared.ribbonCollapsed` |
| 5 | Hộp thoại `Get Data` (cột danh mục bên trái và chân hộp thoại) | `dd_getdata.png` chụp danh sách nguồn All, không thấy chân hộp | Giữ `GetDataDialog` đã chạy đầy đủ ở Phase F |

## 3. Đề xuất cho người dùng

- Toàn bộ 15 thanh Ribbon (tên tab, nhóm, thứ tự nút, kiểu L/S/▾) và 6 màn hình chính đều **đã có ảnh VM đối chiếu trực tiếp** (`observed == true`).
- Các mục ở bảng trên chủ yếu là tính năng cloud/chưa cài đặt (đang vô hiệu có tooltip) hoặc menu con nối vào hành động đã có. Không bắt buộc chụp VM bổ sung cho cổng v1.3.0; nếu cần chuẩn hoá tên 9 theme hoặc menu `Buttons ▸ Navigator`, chỉ cần chụp bổ sung 2 ảnh VM sau.
