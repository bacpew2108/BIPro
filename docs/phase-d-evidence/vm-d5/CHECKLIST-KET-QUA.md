# Kết quả kiểm `Nhom6_d5.pbix` trên VM (2026-11-10)

Claude điều khiển VM theo lời cho phép của người dùng; Power BI Desktop 2.159.x; file chép vào `C:\Users\bacpew\vmd6\`. Không mở trực tiếp từ thư mục Mac.

| Mục | Kết quả | Ghi chú |
|---|---|---|
| 1. Mở file | Đạt | Không hộp thoại lỗi, không "repair". Mở vào trang D2 (đúng `activePageName` = trang đang mở lúc lưu) |
| 2. 5 tab đúng thứ tự và tên | Đạt | Trang thử · tổng hợp, D2, D3, Chi tiết chi nhánh (ẩn), Duplicate of D1 · Giao dịch; `pageNavigator` tự liệt kê đúng |
| 3. Trang nhân bản vẽ như D1 | Đạt | Tiêu đề, 6 card, 5 slicer, biểu đồ, matrix cùng số ($3bn, $197M, 1,056,320…) |
| 4. Bộ lọc cấp visual của matrix | Đạt | Matrix "Giờ × Thứ" trên bản sao chỉ có giờ 08 đến 16 (giờ 17 bị bỏ như trang gốc) |
| 5. Bookmarks pane trống | Đạt | "Use bookmarks to capture key data…" |
| 6. Nút trỏ bookmark đã gỡ | Không kết luận | Mở và chọn nút không báo lỗi; Ctrl+bấm không thấy thay đổi hay thông báo |
| 7. D2, D3, Chi tiết chi nhánh | Đạt | Giống file gốc; trang Chi tiết giữ biểu tượng ẩn |
| 8. Save trong Desktop | Đạt | Không báo lỗi; file trong VM đổi giờ lưu |
| 9. Số liệu khớp BI Pro | Đạt (qua test) | `D5Nhom6` so truy vấn từng visual của bản sao với trang gốc: khớp 20+ visual |

Ảnh: `checklist-d5-mo-file.png`, `checklist-d5-trang-nhan-ban.png`, `checklist-d5-bookmark-trong.png`, `checklist-d5-sau-save.png`.
