# Hợp đồng: thao tác trang (D5)

Phạm vi: `LayoutEditor` (và `DocumentState` bọc lại). Mọi thao tác trả `String?` (lý do từ chối, ghi vào `fieldRefusal`) hoặc nil khi thành công; thành công là đúng một bước hoàn tác; từ chối hay không đổi gì thì không tạo bước.

## Điều kiện chung

- Chỉ ở chế độ Sửa và với báo cáo PBIR (`canEditLayout`); ngoài ra mờ kèm lý do ("Bật chế độ Sửa (⌘E)…", "Báo cáo định dạng cũ chưa sửa được trang").
- Sau mỗi thao tác: `currentPageID` và vùng chọn theo bảng dưới; `notice` mang thông báo (nếu có).

## Các thao tác

| Thao tác | Điều kiện / từ chối | Kết quả |
|---|---|---|
| `addPage()` | không | trang trống "Page N" (R4), cỡ 1920×1080, cuối `order`, thành trang đang mở, vùng chọn rỗng |
| `renamePage(id, to:)` | tên cắt khoảng trắng rỗng → "Tên trang không được để trống."; dài hơn 100 ký tự → "Tên trang tối đa 100 ký tự."; không đổi → không bước | tên mới; mã không đổi; tên trùng trang khác được phép |
| `movePage(id, to index:)` | chỉ số ngoài khoảng → từ chối; cùng chỗ → không bước | `order` đổi; trang đang mở giữ nguyên |
| `duplicatePage(id)` | không | trang mới "Duplicate of <tên>" cuối `order`, mọi visual mã mới (kể cả visual trong nhóm, `parentGroupName` theo bảng mã), vị trí và `z` giữ, thành trang đang mở; trang gốc có `pageBinding`: bản sao không có, `notice` = "Bản sao không mang cấu hình drillthrough." |
| `removePage(id)` | chỉ còn một trang → "Báo cáo phải còn ít nhất một trang."; còn nút `PageNavigation` trỏ tới → "Chưa xoá được: nút … trỏ tới trang này (chưa kiểm với Power BI Desktop)." kèm tên nút | trang biến; trang liền kề (phải, hoặc trái nếu cuối) thành trang đang mở; bookmark theo R7 gỡ; `notice` = "Đã xoá trang \"…\" và gỡ N bookmark: …" khi có gỡ |

## Hoàn tác

- ⌘Z đảo đúng một thao tác trang; ⇧⌘Z làm lại. Hoàn tác `removePage` phục hồi trang, mọi visual (kể cả sửa chưa lưu), bookmark đã gỡ, vị trí trong `order` và trang đang mở trước đó.
- Xen kẽ với kéo/đổi cỡ, thả trường, thêm visual (D1 đến D3) trong một ngăn xếp; `isDirty` về false khi hoàn tác tới trạng thái đã lưu.

## Giao diện (`PageTabs`)

- "+" = `addPage`; bấm đúp tab hoặc menu "Đổi tên…" mở hộp nhập; menu chuột phải: Đổi tên, Nhân bản, Xoá (hộp xác nhận "Xoá trang \"…\"? Có thể hoàn tác bằng ⌘Z."), Sang trái, Sang phải (mờ ở đầu/cuối); kéo tab thả lên tab khác = `movePage`.
- Thao tác từ chối hiện `fieldRefusal` ở thanh trạng thái như D2/D3.

## Bất biến sau mỗi thao tác

`order` không rỗng, không trùng mã; mọi trang có `PageBounds`; `currentPageID ∈ order`; không bookmark còn lại trỏ trang không có trong `order`.
