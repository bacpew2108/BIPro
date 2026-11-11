# Hợp đồng hành vi: sửa bộ lọc ở Filters pane

Ở chế độ Xem Filters pane chỉ để đọc: mọi thao tác sửa dưới đây bị mờ kèm lý do.

| Thao tác | Ở Sửa | Hoàn tác |
|---|---|---|
| Thêm thẻ Basic (chọn giá trị) | `edits.filters[key] = .set(UserFilter)` ở cấp báo cáo, trang hoặc visual | một bước; chọn giá trị liên tiếp trong cùng thẻ gộp một bước |
| Sửa thẻ (đổi giá trị, là ↔ không phải) | `.set` thay thế | một bước (gộp như trên) |
| Bỏ thẻ của file | `.remove` | một bước |
| Bỏ thẻ do người dùng thêm | xoá mục `.set` | một bước |
| Advanced, Top N, thẻ measure | như trên về mặt trạng thái; `FilterExport` trả `sessionOnly` đến khi VM-D6 chốt | |

**Hiệu lực**: bộ lọc hiệu lực = bộ lọc file, rồi `edits.filters`, rồi lớp phiên. Mọi visual nạp lại khi giá trị gộp đổi (cache theo văn bản DAX như hiện nay).

**Chỉ trong phiên**: thẻ `sessionOnly` hiện nhãn "chưa lưu được vào file: <lý do>" trên thẻ; vẫn lọc số liệu như hiện nay.

**Thẻ chưa chọn giá trị (Tất cả)**: không đổi file nếu Desktop không ghi dạng đó (R2g); chưa quan sát thì không ghi gì cho thẻ mới.
