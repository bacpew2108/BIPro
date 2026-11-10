# Kết quả mở `Nhom6_d4.pbix` trong Power BI Desktop (2026-11-10)

Claude điều khiển VM theo lời cho phép của người dùng cho lát D4. File: `build/d-out/D4/Nhom6_d4.pbix` (BI Pro lưu, do `D4Nhom6Tests`). Power BI Desktop 2.159.x.

| Mục | Kết quả |
|---|---|
| Mở file | Mở được, không báo lỗi |
| Trang D3, card đầu (Tổng khách hàng) | Giá trị chữ lớn hơn (28), không còn nhãn danh mục dưới số (đúng `labels.fontSize`, `categoryLabels.show=false`) |
| Trang D3, slicer đầu | Mất tiêu đề (`header.show=false`) |
| Trang D3, biểu đồ cột + đường Q3.4 | Tiêu đề "Tiêu đề 'thử' · Việt" màu cam cỡ 16, chú giải ở trên, nhãn dữ liệu hiện |
| Trang D3, card mới | Hiện số $197M, không có tiêu đề (`title.show=false`) |
| Trang D1, matrix | Tiêu đề cột (Monday, Tuesday…) cỡ lớn hơn bản gốc (`columnHeaders.fontSize 14`) |

Ảnh: `checklist-d4-trang-d3.png`, `checklist-d4-trang-d1.png`. Chưa mở Format pane của Desktop trên từng visual để đối chiếu từng giá trị (nhìn bằng mắt trên canvas).
