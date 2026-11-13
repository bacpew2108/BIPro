# Hợp đồng hành vi: sửa bộ lọc ở Filters pane

Ở chế độ Xem Filters pane chỉ để đọc: mọi thao tác sửa dưới đây bị mờ kèm lý do.

| Thao tác | Ở Sửa | Hoàn tác |
|---|---|---|
| Thêm thẻ Basic (chọn giá trị) | `edits.filters[key] = .set(UserFilter)` ở cấp báo cáo, trang hoặc visual | một bước; chọn giá trị liên tiếp trong cùng thẻ gộp một bước |
| Sửa thẻ (đổi giá trị, là ↔ không phải) | `.set` thay thế | một bước (gộp như trên) |
| Bỏ thẻ của file | `.remove` | một bước |
| Bỏ thẻ do người dùng thêm | xoá mục `.set` | một bước |
| Advanced, Top N, thẻ measure | như trên về mặt trạng thái. Ghi vào file (sửa 2026-11-13 theo VM-D8): Advanced chữ và số với một hoặc hai điều kiện nối Và/Hoặc (chứa, bắt đầu bằng, là, không phải, so sánh thứ tự, trống, không trống), Top N và Bottom N, thẻ Advanced của measure ở cấp visual. Còn `sessionOnly`: Basic có giá trị kiểu ngày hoặc tiền tệ | |

**Đọc lại** (2026-11-13): thẻ Top N/Bottom N và thẻ measure trong file được đọc thành `UserFilter` (`UserFilter.from`) và áp vào truy vấn khi mở file, để lưu xong mở lại không mất điều kiện.

**Hiệu lực**: bộ lọc hiệu lực = bộ lọc file, rồi `edits.filters`, rồi lớp phiên. Mọi visual nạp lại khi giá trị gộp đổi (cache theo văn bản DAX như hiện nay).

**Chỉ trong phiên**: thẻ `sessionOnly` hiện nhãn "chưa lưu được vào file: <lý do>" trên thẻ; vẫn lọc số liệu như hiện nay.

**Thẻ chưa chọn giá trị (Tất cả)**: không đổi file nếu Desktop không ghi dạng đó (R2g); chưa quan sát thì không ghi gì cho thẻ mới.
