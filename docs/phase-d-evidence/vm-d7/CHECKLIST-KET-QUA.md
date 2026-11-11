# VM-D7 vòng 2: kết quả mở file BI Pro ghi trong Power BI Desktop

Ngày: 2026-11-11 (Claude điều khiển VM theo lời cho phép của người dùng: "Ok, có thể điều khiển VM"). Desktop 2.159, Windows 11. File: `build/d-out/D7/Nhom6_d7.pbix`, `Nhom2_d7.pbix` do `D7Nhom6Tests` ghi (bản sao Nhom6 và Nhóm 2, không đụng file gốc).

| Mục | Kết quả |
|---|---|
| `Nhom6_d7.pbix` mở trong Desktop | Đạt, không báo lỗi, dữ liệu nạp |
| Trang D3: ba biểu đồ hàng dưới là một nhóm (Selection pane: "Group 1" có ba con); nhóm kéo 16 điểm | Đạt (`desktop-d7-nhom-selection.png`); vị trí các con đúng |
| Trang D3: căn trái hàng giữa (x = 24), phân bố ngang ba thẻ hàng trên | Đạt (hiện đúng bố cục) |
| Trang D1: thẻ dán từ D3 nằm trên cùng, lệch (10, 10) | Đạt (`desktop-d7-dan-d1.png`) |
| `Nhom2_d7.pbix` (định dạng cũ `Report/Layout`, bỏ `SecurityBindings`) mở trong Desktop | Đạt, không báo "corrupted", bố cục hiện (`desktop-d7-nhom2-dinh-dang-cu.png`) |
| Xoá nhóm (Delete) có xoá con | **Chưa quan sát**: phím Delete gửi qua `cliclick` không tới Desktop. BI Pro xoá cả nhóm và con (hoàn tác được) |
| Co dọc của nhóm | Chưa quan sát; BI Pro co tỷ lệ cả hai chiều |

Dọn: tiến trình Desktop đã tắt, `C:\Users\bacpew\vmd7` và `~/Desktop/vmd7out` đã xoá.
