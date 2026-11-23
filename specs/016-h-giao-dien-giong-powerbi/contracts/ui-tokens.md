# Hợp đồng: số đo và màu giao diện

Giá trị chuẩn lấy từ ảnh Power BI Desktop 2.159 (`docs/PHASE_H_UI_PARITY.md` mục 3.1; đơn vị pt, ảnh VM 1867 pt rộng). Dung sai kiểm tra: số đo ±2 pt, màu ±3% độ sáng.

## Số đo (`UIMetrics`)

| Token | Giá trị | Hiện tại | Ghi chú |
|---|---|---|---|
| `titleBar` | 36 | 52 | cao thanh tiêu đề (gồm traffic lights) |
| `tabRow` | 32 | ≈ 34 (tab 26 + đệm) | hàng tab Ribbon |
| `ribbonPanel` | 98 | 88 | panel trắng, gồm nhãn nhóm |
| `rail` | 42 | 56 | rộng rail |
| `railIconHit` | 40 | 38 | cao mỗi biểu tượng rail |
| `pageTabs` | 35 | 34 | thanh trang |
| `statusBar` | 23 | 28 | thanh trạng thái toàn cửa sổ |
| `pane` | 181 | 260 | rộng pane Visualizations và Data |
| `collapsedPane` | 31 | 30 | dải dọc thu gọn (Filters) |
| `ribbonIcon` | 28 | 17 | biểu tượng nút lớn |
| `ribbonCorner` | 6 | 6 | bo panel |
| `tabUnderline` | 2 | — | gạch chân tab |

Pane Visualizations/Data rộng 181 pt có thể chật cho cây bảng của BI Pro; cho phép kéo rộng đến 320 pt, **mặc định 181**.

## Màu (`DS.Palette`)

| Token | Sáng | Tối | Dùng cho |
|---|---|---|---|
| `accent` | `#5B4BDB` (đổi 2026-11-23, trước là teal `#117865`) | `#9A8EFF` | gạch chân tab, vạch rail, nút Share, `+` thêm trang, công tắc On, liên kết, chọn |
| `accentPressed` | `#0E6655` | `#35A088` | trạng thái nhấn |
| `chrome` | `#F5F5F5` | giữ `#242426` | tiêu đề, hàng tab, rail, pane Data, thanh trạng thái |
| `ribbonPanel` | `#FFFFFF` | giữ `#2C2C2E` | nền panel Ribbon (= `canvas`) |
| `canvasWell` | `#E6E6E6` | `#1C1C1E` | nền quanh trang báo cáo |
| `paper*` | giữ nguyên | giữ nguyên | nhãn/thẻ vẽ trên giấy báo cáo (đã có) |
| `series` | giữ nguyên | giữ nguyên | màu biểu đồ mặc định, **không đổi** |

`DS.Palette.selectionSoft` đổi theo `accent` (alpha 0,12 sáng / 0,24 tối). `DS.Palette.success` (`#34C759`) giữ cho trạng thái thành công, không dùng làm màu nhấn.

## Chữ

SF Pro (hệ thống). Tab 13 · nhãn nút 11 · nhãn nhóm 10 (chữ thường, xám, không viết hoa) · nội dung pane 12 · tiêu đề pane 15 đậm. Không nhúng Segoe UI.

## Kiểm thử

- `UIMetricsTests`: từng token bằng giá trị bảng (±2).
- `TokensColorTests`: từng màu sáng/tối bằng bảng (±3% độ sáng), `series` không đổi so với v1.2.
- `ShellLayoutTests`: dựng `ShellView` ở kích thước 1600×1000 pt, đo chiều cao hàng tab, panel, rail, thanh trang, thanh trạng thái (qua tên nhận dạng khung) và so với bảng.
