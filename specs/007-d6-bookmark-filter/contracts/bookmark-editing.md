# Hợp đồng hành vi: sửa bookmark

Ở chế độ Xem mọi thao tác sửa dưới đây bị mờ kèm lý do (chỉ áp bookmark được).

| Thao tác | Ở Sửa | Hoàn tác |
|---|---|---|
| Thêm | chụp trạng thái (trang, hiển thị, bộ lọc, slicer, drill) vào `edits.bookmarks.added`; tên mặc định "Bookmark N" | một bước |
| Cập nhật | chụp lại, giữ mã, tên, tuỳ chọn; bookmark của file vào `updated` | một bước |
| Đổi tên | `renamed` (file) hoặc sửa tên bản thêm; rỗng hoặc chỉ khoảng trắng bị từ chối, giữ tên cũ | một bước |
| Xoá | `deleted` (file) hoặc bỏ bản thêm; cảnh báo nếu nút action `Bookmark` trỏ tới nó | một bước, phục hồi đúng vị trí |
| Đổi thứ tự | `order` | một bước |
| Đổi tuỳ chọn Data/Display/Current page | sửa bản thêm hoặc đã cập nhật (bookmark của file chưa cập nhật không có tuỳ chọn để đổi) | một bước |

**Chỉ trong phiên.** Bookmark mà `BookmarkExport` trả `sessionOnly` (Data có lựa chọn điểm dữ liệu, drill, mở nút, slicer nhiều cấp; hoặc trang không còn) vẫn dùng được trong phiên (áp, đổi tên, xoá), Bookmarks pane gắn nhãn "chưa lưu được vào file: <lý do>"; ⌘S ghi phần còn lại và báo số bookmark bỏ qua. Không bao giờ ghi dạng đoán.

**Áp bookmark** (bấm): hành vi hiện có (Phase C) không đổi, trên giá trị gộp. Chuyển trang theo `currentPage`.

**Không gian tên**: mã bookmark mới 20 hex không trùng mã nào trong file hoặc trong phiên.
