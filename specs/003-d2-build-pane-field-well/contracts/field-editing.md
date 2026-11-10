# Hợp đồng: sửa trường của visual

## Điều kiện bật

- Chế độ Sửa (⌘E), đúng một visual được chọn, visual có `queryState` hoặc có ô trong `WellRules`, không thuộc nhóm (`parentGroupName`), báo cáo không phải định dạng cũ (`Report/Layout`).
- Ngược lại: Build pane hiện trường ở chế độ chỉ xem kèm lý do (chọn nhiều visual, visual trong nhóm, định dạng cũ, chế độ Xem).

## Thao tác

Mỗi thao tác là một `commit` (một bước hoàn tác). Thao tác không đổi gì thì không tạo bước.

| Thao tác | Hành vi | Từ chối khi |
|---|---|---|
| Thêm (kéo thả, menu ô, ô tick) | Thêm `Projection` mới vào cuối ô | ô không nhận loại trường (`accepts`) hoặc `status == unverified`; trùng `queryRef` trong ô; cột số vào ô giá trị (cần phép gộp: D2a) |
| Thêm vào ô chỉ nhận một trường | Thay trường cũ bằng trường mới | (không từ chối) |
| Bỏ | Bỏ `Projection` khỏi ô | còn được nhắc ở sắp xếp, bộ lọc, định dạng (`FieldReferences`) và không còn phần tử nào khác cùng `queryRef` |
| Đổi thứ tự | Đổi chỉ số trong ô | (không từ chối) |
| Chuyển ô | Bỏ khỏi ô cũ, thêm vào ô mới (đầu vào là phần tử đã có: giữ nguyên byte) | ô đích không nhận, trùng, hoặc ô cũ sẽ vi phạm quy tắc bỏ |
| Đổi tên hiển thị | Đặt hoặc đổi `displayName`; chuỗi rỗng hoặc bằng tên gốc: bỏ `displayName` | (không từ chối) |

Từ chối luôn đi kèm lý do tiếng Việt hiển thị cho người dùng; trạng thái visual và tài liệu không đổi.

## Ô và quy tắc nhận

Nguồn: `WellRules`. D2 chỉ cho thêm khi ô ở mức `observed`; bảng ban đầu lấy từ research R1. Ô `unverified` hiện ra nhưng từ chối thả. Hierarchy: không thêm; phần tử `HierarchyLevel` sẵn có được chép nguyên khi đổi thứ tự hoặc chuyển ô trong cùng loại ô, và được bỏ khi quy tắc bỏ thoả.

## Vẽ lại

Sau mỗi thao tác (kể cả hoàn tác), đúng visual đã sửa nạp lại truy vấn từ `ReportVisual.raw` mới. Visual có ô bắt buộc trống (không có `Values`/`Y`…) hiện trạng thái trống ("Thêm trường để vẽ"), không báo lỗi truy vấn.

## Hoàn tác

Chung ngăn xếp với D1. Ví dụ thứ tự: thêm trường → dời visual → bỏ trường; ⌘Z ba lần quay về đầu từng bước một. Một lần thả = một bước. Hoàn tác về trạng thái lúc mở thì `isDirty == false`.

## Bất biến

- Visual không bị sửa trường: `visual.json` giữ nguyên từng byte khi lưu.
- Phần ngoài `queryState` của một visual đã sửa giữ nguyên từng byte.
- `queryRef` của phần tử cũ không đổi (nên sắp xếp, bộ lọc, định dạng vẫn trỏ đúng sau thêm, đổi thứ tự, chuyển ô, đổi tên).
