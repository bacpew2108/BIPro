# Mô hình dữ liệu D6

## Giá trị thuần ở `BIPro`

- **`ReportEdits`** (trong `LayoutSnapshot`): thay đổi cấp tài liệu so với file lúc mở.
  - `bookmarks`: `added: [UserBookmark]` (theo thứ tự thêm), `updated: [String: UserBookmark]` (mã file → bản mới), `renamed: [String: String]`, `deleted: Set<String>`, `order: [String]?` (thứ tự hiển thị mong muốn, nil = thứ tự file).
  - `filters`: `[UserFilterKey: FilterChange]`, `FilterChange` = `.set(UserFilter)` (thêm hoặc thay) hoặc `.remove` (bỏ thẻ của file).
- **`ExportResult<T>`**: `.writable(T)` hoặc `.sessionOnly(reason: String)`.
- **Giá trị gộp** (hàm thuần): `effectiveFilters(file, edits, session)`, `effectiveBookmarks(file, edits, session)`.

## Giá trị thuần ở `PBIXKit`

- **`BookmarkSpec`**: xem research R6.
- **`FilterCardSpec`**: `name`, `field` (entity, property, kind), `type`, `values`/`exclude` (Basic), điều kiện (Advanced/TopN sau VM-D6), `howCreated`.

## Quan hệ

- `LayoutSnapshot.edits` thêm vào `edited` và `structure`; `isDirty` theo `cleanMark` của ngăn xếp hoàn tác như D1 đến D5 (`edits` nằm trong ảnh chụp nên không cần dấu riêng).
- Mỗi `UserBookmark.pageID` phải là trang còn tồn tại lúc lưu; trang bị xoá thì bookmark bị bỏ khỏi `added`/`updated` (xem contracts).
- `UserFilterKey.scope` trỏ trang hoặc visual còn tồn tại lúc lưu; không thì thay đổi lọc tương ứng bị bỏ.

## Chuyển trạng thái

- Thao tác ở Sửa: `LayoutEditor` chụp ảnh trước, rồi đổi `edits` (một bước). Gộp liên tiếp: sửa cùng một thẻ lọc liên tiếp (gõ, chọn giá trị) cùng khoá gộp thì một bước.
- Chuyển Xem ⇄ Sửa: lớp phiên và lớp tài liệu giữ nguyên, giá trị gộp đổi theo.
- Lưu: `makeChanges` so giá trị mong muốn với bytes trên đĩa; `markSaved` đặt `cleanMark` như D1 đến D5.
