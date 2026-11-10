# Mô hình dữ liệu D5

## `PageStructure` (BIPro, giá trị, thuộc `LayoutEditor`)

Cấu trúc trang đang sửa. Bản sạch (chưa sửa) có `order` bằng `pageOrder` của file, các tập còn lại rỗng.

| Trường | Ý nghĩa |
|---|---|
| `order: [String]` | mã trang theo thứ tự tab (gồm trang của file chưa xoá và trang tạo trong phiên) |
| `renamed: [String: String]` | mã trang của file → tên hiển thị mới (trang tạo trong phiên giữ tên trong `created`) |
| `created: [String: NewPage]` | trang tạo trong phiên |
| `removed: Set<String>` | mã trang của file đã xoá |
| `removedBookmarks: Set<String>` | tên bookmark đã gỡ khi xoá trang (để hoàn tác và báo) |
| `trimmedBookmarkSections: [String: Set<String>]` | tên bookmark → các mã trang đã bỏ khỏi `sections` |
| `usedPageIDs: Set<String>` | mã trang đã có hoặc đã sinh (không dùng lại), không hoàn tác |
| `activePageID: String?` | nil: không đổi; có: `activePageName` ghi lúc lưu khi cấu trúc đổi |

`usedPageIDs` nằm ngoài snapshot (như `usedIDs`, `createdIDs` của D1): hoàn tác không làm mã được dùng lại.

## `NewPage`

| Trường | Ý nghĩa |
|---|---|
| `id` | mã 20 hex |
| `displayName` | tên hiển thị hiện tại |
| `pageJSON: Data` | byte `page.json` sẽ ghi (mẫu Desktop hoặc nhân bản đã sửa `name`, `displayName`, bỏ `pageBinding`) |
| `sourcePage: String?` | trang được nhân bản (để báo `pageBinding` bị bỏ) |
| `width`, `height` | cỡ (1920 × 1080 hoặc của trang gốc) |

## `LayoutSnapshot` (đổi)

`{ edited: [String: PageEdit], structure: PageStructure, currentPageID: String?, selection: Set<String>, primary: String? }`. Hoán đổi toàn bộ khi `undo`/`redo`.

## Quan hệ và bất biến

- Mọi mã trong `order` là của file (không thuộc `removed`) hoặc trong `created`; không trùng; `order.count >= 1`.
- `created[id]` có `edited[id]` (có thể rỗng): `PageEdit.visuals` là danh sách visual của trang; `edit.added` chứa `visual.json` mọi visual của trang nhân bản.
- `removed` ∩ `order` = ∅; `removedBookmarks` chỉ chứa bookmark của file.
- Bookmark còn lại (không trong `removedBookmarks`) không có `activeSection` ∉ `order`.
- Trang xoá có thể là trang hoặc trang tạo; trang tạo bị xoá thì biến khỏi `created`, `edited`, `order` (nhưng mã vẫn trong `usedPageIDs`).

## Đọc ra cho giao diện

`LayoutEditor.pages: [ReportPage]`: theo `order`, mỗi trang là trang cơ sở (baseline hoặc từ `created`) với `displayName` đã đổi và `visuals` đã sửa. `DocumentState.pages` chuyển tiếp.

## Thực thể trong file (`.pbix`, PBIR)

| Part | Khoá D5 đụng tới |
|---|---|
| `Report/definition/pages/pages.json` | `pageOrder`, `activePageName` |
| `Report/definition/pages/<mã>/page.json` | `displayName` (đổi tên); mới: toàn bộ; nhân bản: `name`, `displayName`, bỏ `pageBinding`, mã trong `visualInteractions` |
| `Report/definition/pages/<mã>/visuals/<mã visual>/visual.json` | nhân bản: `name`, `parentGroupName`; xoá trang: bỏ part |
| `Report/definition/bookmarks/<tên>.bookmark.json` | bỏ file; hoặc bỏ `explorationState.sections.<mã>`; dọn visual đã xoá (D1) |
| `Report/definition/bookmarks/bookmarks.json` | bỏ mục `items[]` của bookmark đã gỡ |
