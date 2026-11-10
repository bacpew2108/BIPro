# VM-D1: kết quả quan sát Power BI Desktop (2026-11-10, bản 2.159.1231.0)

Nguồn: bốn file `R-D1-a-move`, `-b-resize`, `-c-copy`, `-d-delete` (mỗi file chỉ đổi một thứ từ `Nhom6_work.pbix`), ảnh `5E.png`, ghi chú `ghichu.txt`. So sánh bằng `visual.json`, bookmark, `page.json`. Mọi file Desktop lưu đều đổi `DataModel`, `SecurityBindings` và `pages.json` (trang đang mở); phần này không bàn tới.

## Điều đo được

| Bước | Quan sát | So với điều BI Pro đang làm |
|---|---|---|
| A, dời bằng chuột | `position.x/y` thành số thực (x = 247.7419…, y = 175.953…); `z`, `tabOrder`, `width`, `height` không đổi. `$schema` của visual đổi 2.13.0 → 2.14.0. Phần còn lại của `visual.json` giữ nguyên | BI Pro ghi số nguyên, giữ `$schema`. Desktop mở được cả hai (D1 đã đạt). Không cần đổi |
| B, đổi cỡ | `width`, `height`, và `x`/`y` đều thành số thực (23.93, 540.53, 353.31); `z`, `tabOrder` không đổi | Như A |
| C, Ctrl+C / Ctrl+V | Bản sao: tên mới 20 ký tự hex, **`z` = z lớn nhất của trang + 1 (37001)**, `tabOrder` = `z`, cỡ giữ nguyên, **vị trí không lệch cố định** (đặt ở (304.05, 299.82) so với gốc (24, 176)); mọi phần khác của `visual.json` giống gốc trừ `$schema`. `page.json` không đổi | BI Pro: `z` = max + 1000, lệch +16/+16. Cả hai hợp lệ; giữ nguyên lệch +16 (không có quy tắc để bắt chước) |
| D, xoá visual có trong bookmark | Visual bị bỏ; `page.json` không đổi. Trong cả hai bookmark Q1.3, visual **chỉ bị bỏ khỏi `explorationState.sections.<trang>.visualContainers`; `options.targetVisualNames` vẫn giữ tên đã xoá**. Bookmark không báo lỗi khi bấm (theo bạn) | BI Pro trước đây bỏ cả hai nơi. **Đã sửa theo Desktop** (chỉ `visualContainers`) |
| E, lưới | Chấm lưới cách nhau 136 px trên ảnh (đo từ `5E.png`) = khoảng 96–97 đơn vị của trang ở tỷ lệ hiển thị này (1,40 px mỗi đơn vị: đo từ banner 1920 rộng và thẻ 302 rộng). Theo bạn, "một ô lớn có 5 ô nhỏ", tức ô nhỏ khoảng 19,3 đơn vị | BI Pro bám lưới 8. **Chưa khớp**; xem "Việc còn mở" |
| F, cỡ nhỏ nhất | Khoảng một ô nhỏ của lưới (≈ 19) | BI Pro: 16 |
| G, phím mũi tên | Mũi tên: 1 px. Shift + mũi tên: một ô nhỏ | BI Pro: 1 và 8 |

## Điều bất ngờ

- **Desktop không bám lưới khi kéo mặc định**: toạ độ ra số thực dài (7680/31…), nên kéo tự do. Việc bám lưới 8 px của BI Pro là lựa chọn của mình (Option để tắt), không phải bắt chước Desktop. Giữ nguyên theo yêu cầu "snap 8 px" của người dùng, ghi rõ ở đây.
- Desktop đọc và ghi toạ độ số thực. Visual nào Desktop đã đặt ở toạ độ thực thì BI Pro đọc làm tròn khi sửa; visual không đụng tới thì không bị ghi lại.

## Lưới, chốt (sau khi người dùng bật lưới trên VM)

Người dùng mô tả: lưới chia trang thành các ô vuông, mỗi cạnh chia 5 ô nhỏ; mũi tên nhích rất ít (khoảng 1/10 ô nhỏ); Shift + mũi tên nhích đúng một ô nhỏ. Đo lại ảnh `5E.png`: banner 1920 rộng = 2716 px ảnh (tỷ lệ 1,4146), chấm lưới cách nhau 136 px ảnh = **≈ 96 đơn vị trang** mỗi ô vuông, nên **ô nhỏ ≈ 19,2 = 1/100 chiều rộng trang** (suy ra, trên trang 1920; chưa kiểm trên trang cỡ khác). Mũi tên ≈ 1,9 đơn vị.

**Quyết định cho BI Pro:** giữ lưới 8, cỡ nhỏ nhất 16, mũi tên 1, Shift + mũi tên 8. Lý do: Desktop không bám lưới khi kéo mặc định (toạ độ thực), nên không có hành vi để bắt chước ở đây; các số của mình là lựa chọn có chủ ý, sát cỡ Desktop (ô nhỏ ≈ 19) và là số nguyên. Đổi sau nếu người dùng muốn giống hẳn.

## Việc còn mở

- `visualInteractions` của trang khi xoá visual: Nhom6 không có, chưa quan sát.
