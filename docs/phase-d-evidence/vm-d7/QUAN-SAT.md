# VM-D7: quan sát Power BI Desktop (nhóm, căn lề, phân bố, dán)

Ngày: 2026-11-11. Claude điều khiển VM theo lời cho phép của người dùng ("Ok, có thể điều khiển VM"; ngoại lệ một lần của quy tắc "agent không điều khiển VM"). Desktop 2.159.x, Windows 11 (Parallels), file `Nhom6_work.pbix` bản sao ở `C:\Users\bacpew\vmd7\`, bản sao Mac ở `~/Desktop/vmd7out/` (đã xoá sau khi chép mẫu). Không dịch ngược: chỉ thao tác giao diện, lưu, đọc diff các part. Mẫu JSON: `json/`.

Trang thử: `d3_cskh` (D3 · Chăm sóc KH, 1920×1080). Ghi chú thao tác: phím tắt Ctrl+G, Ctrl+S qua `cliclick` không tới Desktop (⌘ thành phím Windows); dùng nút Group ở tab Format và biểu tượng Lưu.

## 1. Nhóm (Format > Group > Group, chọn 3 visual ở hàng dưới)

- Tạo **container nhóm** `visuals/<20 hex>/visual.json` (mã 70703ac9b8810b6162e7), mẫu `json/group-moi.visual.json`:
  `{"$schema": ".../visualContainer/2.14.0/schema.json", "name": "<id>", "position": {"x":24,"y":688,"z":33001,"height":380,"width":1872,"tabOrder":33001}, "visualGroup": {"displayName":"Group 1","groupMode":"ScaleMode"}}`.
  Khoá `position` theo thứ tự `x, y, z, height, width, tabOrder`. Vị trí nhóm = hộp bao của các con. `z` và `tabOrder` = `z` lớn nhất của con + 1. Tên mặc định "Group 1".
- Mỗi **con**: `position.x`, `position.y` đổi thành **toạ độ tương đối so với nhóm** (x−24, y−688); `z`, `tabOrder`, `width`, `height` giữ; thêm `"parentGroupName":"<id nhóm>"` làm khoá **cuối cùng** của đối tượng gốc (sau `visual`). Desktop chuẩn hoá lại cả file con (đổi `$schema` lên 2.14.0, đổi thứ tự `queryState`, đưa `active` lên trước, đổi chỗ `visualContainerObjects`) nhưng nội dung ngữ nghĩa như cũ. `page.json` không đổi (không có danh sách nhóm ở cấp trang).
- Không có part nào khác đổi; không có `bookmarks` đổi.

## 2. Đổi cỡ nhóm (Format pane > General > Size, Width 1872 → 936)

- `visualGroup` không đổi; `position.width` của nhóm đổi 1872 → 936.
- Các con **co theo tỷ lệ** (`groupMode: ScaleMode`): x tương đối và `width` nhân 0,5 (1256→628, 628→314, 616→308; x=0 giữ 0). Chiều cao không đổi vì không đổi `Height` (co theo y là tương tự, chưa tự thử).
- Desktop **bỏ khoá `tabOrder`** khỏi `position` của các con (nhóm vẫn giữ `tabOrder`).

## 3. Di chuyển nhóm (chọn nhóm, phím mũi tên phải 5 lần)

- Chỉ `position.x`, `position.y` của **nhóm** đổi (24→25,993…, 688→687,336…: Desktop ghi số thập phân). Các con không đổi (vì toạ độ tương đối).

## 4. Bỏ nhóm (Format > Group > Ungroup)

- Part của nhóm bị xoá. Mỗi con: bỏ `parentGroupName`; `position.x`, `position.y` về **toạ độ tuyệt đối** (tương đối + x,y của nhóm); `z` giữ; các khoá khác như cũ (Desktop vẫn chuẩn hoá `$schema` 2.14.0). Xem `json/con-sau-bo-nhom.visual.json`.

## 5. Căn lề và phân bố (Format > Align; chọn 2 hoặc 3 visual cùng trang)

Menu: Align left, Align center, Align right, Align top, Align middle, Align bottom, Distribute horizontally, Distribute vertically. Hai lệnh Distribute **mờ khi chỉ chọn 2 visual**, bật khi chọn 3.

Kết quả đọc từ file (kích thước không đổi ở mọi lệnh):
- **Left**: mọi `x` = `x` nhỏ nhất của vùng chọn (c1ed 1356 → 25,99 = x của e324).
- **Right**: mọi cạnh phải = cạnh phải lớn nhất (e324 x=83,99+w308 → x=232 để phải = 540 = phải của c1ed).
- **Bottom**: mọi cạnh dưới = cạnh dưới lớn nhất (y c1ed 296 → 687,34).
- **Center**: mọi **tâm** = **trung bình các tâm** (không phải tâm hộp bao). Thử hai lần: tâm 295,99 và 179,99 → 237,99 (kết quả bị kẹp, xem dưới); tâm 270 và 386 → 328 (c1ed x=58, e324 x=174).
- **Kẹp trong trang**: lần Center đầu tính được x = −32 cho visual rộng 540 thì Desktop ghi x = 0 (không âm).
- **Top** và **Middle**: các visual đã cùng y/tâm dọc nên không đổi; theo đối xứng với Bottom và Center (chưa thấy số khác).
- **Distribute horizontally** trên 3 thẻ x=24, 338, 1594 (rộng 302): thẻ giữa → x=809. Khoảng hở đều: (1896−24−3×302)/2 = 483 → 24+302+483 = 809. Hai thẻ ngoài giữ nguyên; chỉ part của thẻ đổi được ghi (kích thước byte không đổi).
- Số thập phân giữ nguyên (không làm tròn).

## 6. Chép dán sang trang khác (Home > Copy, chuyển trang, Home > Paste)

- Visual mới ở trang đích với mã mới (20 hex), mẫu `json/dan-sang-trang-khac.visual.json`. Nội dung như nguồn (query, objects, filterConfig, `visualContainerObjects`) trừ `name`, `position`, `$schema` (2.14.0) và thứ tự khoá `active`.
- `position.x`, `position.y` = nguồn **+10, +10** (24,176 → 34,186). Dán lần hai → +10 nữa (44,196). Không giữ nguyên toạ độ nguồn dù khác trang.
- `z` = `z` lớn nhất của trang đích + 1 (37000 → 37001 → 37002), `tabOrder` = `z`.
- Trang nguồn không đổi. `pages.json` đổi `activePageName` thành trang đang mở khi lưu (Desktop làm khi lưu; không phải do dán).

## Chưa quan sát

- Xoá nhóm (Delete) có xoá cả con hay không (thử chưa chạy được vì lệnh Group lần hai bị lệch chọn); BI Pro làm theo cách an toàn "xoá cả nhóm và con, hoàn tác được" và ghi trong chú thích.
- Nhóm lồng nhau, nhóm trong bookmark, co theo chiều dọc của nhóm, nhóm ở báo cáo định dạng cũ.
- Dán trong cùng trang (dự kiến cùng quy tắc +10).
