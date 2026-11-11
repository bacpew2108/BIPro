# Kết quả kiểm `Nhom6_d6.pbix` trong Power BI Desktop (2026-11-11, Claude điều khiển VM theo lời cho phép của người dùng)

File do BI Pro lưu từ bản sao Nhom6 (`build/d-out/D6/Nhom6_d6.pbix`, dựng bởi test nặng `D6Nhom6`).

| # | Kiểm | Kết quả |
|---|---|---|
| 1 | Power BI Desktop mở file, không báo lỗi | Đạt |
| 2 | Bookmarks pane: "Giờ × Thứ (D6)" (đã đổi tên), "Bookmark D6" (mới, cuối danh sách); "Q1.3 · Tháng trong năm" đã xoá không còn | Đạt (`checklist-d6-bookmarks-filters.png`) |
| 3 | Bấm "Bookmark D6": chuyển sang trang D1, ẩn card đã chọn | Đạt (`checklist-d6-bookmark-applied.png`) |
| 4 | Trang D3 có bộ lọc `sex = Female`: card "Tổng khách hàng" 5.369 → 2.645, legend chỉ còn Female | Đạt |
| 5 | Thẻ lọc cấp visual đã sửa (is ↔ is not) mở được, không báo lỗi | Đạt (chỉ kiểm mở; chưa nhìn số) |

Bookmark Data tối giản (BI Pro ghi thử, `QUAN-SAT.md` "Vòng 2"): Desktop áp đúng lựa chọn slicer (một và hai giá trị), đặt slicer về All khi không có `objects`, ẩn visual. Ảnh `checklist-d6-data-*.png`.

File VM (`C:\Users\bacpew\vmd6\`) và file thử ở `build/d-out/D6/exp-*` đã xoá.
