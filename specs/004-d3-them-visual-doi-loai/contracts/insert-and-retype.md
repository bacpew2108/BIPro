# Hợp đồng: thêm visual, đổi loại, sửa văn bản hộp văn bản

## Điều kiện chung

- Chế độ Sửa (⌘E), báo cáo PBIR (không phải `Report/Layout`), visual không thuộc nhóm. Ngược lại: thư viện và nút ribbon mờ, `.help` nêu lý do, bấm vào đặt `LayoutEditor.notice` (không đổi gì).
- Mọi thao tác dưới đây là đúng một `commit` (một bước hoàn tác). Thao tác không đổi gì thì không tạo bước.

## Thêm visual (`insertVisual`)

Điều kiện: không chọn visual nào (hoặc gọi từ ribbon: thêm bất kể vùng chọn, rồi chọn visual mới).

| Bước | Hành vi |
|---|---|
| Loại | Phải là loại `isSupported` (R2); không thì từ chối kèm lý do, không thêm |
| Mã | `makeVisualName(avoiding: usedIDs)`; thêm vào `usedIDs` và `createdIDs[trang]` |
| Cỡ | Mặc định theo loại, kẹp vừa trang |
| Vị trí | Tâm trùng tâm `visibleRect`, lưới 8; trùng ≥ 90% với một visual đã có thì lệch +16 mỗi lần, tối đa 10 lần (R5) |
| `z`, `tabOrder` | z lớn nhất của trang + 1000; `tabOrder` = `z` |
| Nội dung | `PBIRNewVisual.makeJSON` (R3); visual dữ liệu chưa có trường: `fields` rỗng, hiện "Thêm trường để vẽ" |
| Sau | Chọn visual mới; `notice` và `fieldRefusal` cũ bị xoá |

## Đổi loại (`changeType`)

Điều kiện: đúng một visual được chọn, có trong trang hiện tại, loại đích `isSupported` và khác loại hiện tại.

1. `TypeChange.plan` (R7, R8). `blocked != nil` → từ chối, không đổi gì.
2. Ngược lại: đổi `visualType`, tỉa `objects`, ghi ô mới. Giữ vị trí, cỡ, `z`.
3. `notice` liệt kê trường bị bỏ (và khoá `objects` bị bỏ), ví dụ "Đã bỏ 2 trường không có ô trong loại mới: Y2 Net, Tooltips Avg".
4. ⌘Z trả lại loại cũ, đủ trường, đủ `objects`.
5. Đổi sang chính loại hiện tại: không đổi, không bước.

## Hộp văn bản (`setText`)

Điều kiện: visual `textbox`. Nội dung nhập: văn bản thuần, nhiều dòng; mỗi dòng là một đoạn (R9). Một lần xong chỉnh là một bước. Rỗng hoàn toàn: giữ một đoạn rỗng. Kiểu chữ có sẵn giữ nguyên (R9).

## Bất biến

- Visual không đụng tới giữ nguyên từng byte khi lưu.
- Phần ngoài `visualType`, `objects` (khoá bị bỏ), `query.queryState` (ô đổi), `objects.general…paragraphs` (hộp văn bản) và `position` của một visual đã sửa giữ nguyên từng byte.
- Mã visual không bao giờ dùng lại (kể cả mã của visual mới đã xoá hoặc hoàn tác).
- File lưu không chứa trường tham chiếu treo (sắp xếp, bộ lọc, định dạng theo trường).
