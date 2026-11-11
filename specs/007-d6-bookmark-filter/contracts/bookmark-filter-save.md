# Hợp đồng lưu: bookmark và bộ lọc

Lưu đi qua `DocumentSaver.save` như D1; `LayoutEditor.makeChanges` thêm các thay đổi sau (so với bytes trên đĩa, chỉ ghi khi khác).

## Part ghi

| Thay đổi | Part | Cách ghi |
|---|---|---|
| Thêm bookmark | `bookmarks/<name>.bookmark.json` (thêm), `bookmarks/bookmarks.json` | file mới dựng theo mẫu Desktop (R2a–c, R2f); thêm `{name}` ở cuối `items` bằng ghép byte; nếu `bookmarks.json` chưa có thì tạo theo mẫu |
| Cập nhật | `<name>.bookmark.json` | dựng lại cả file, giữ `name`, `displayName`, tuỳ chọn |
| Đổi tên | `<name>.bookmark.json` | chỉ `displayName` (ghép byte) |
| Xoá | file bookmark (bỏ), `bookmarks.json` | bỏ item (`PBIRPagePatch.bookmarkItemsRemoving`); bookmark cuối: theo R2e |
| Đổi thứ tự | `bookmarks.json` | sắp lại `items` bằng ghép byte |
| Thẻ lọc | `report.json`, `pages/<p>/page.json`, `visuals/<v>/visual.json` | thêm, thay, bỏ thẻ trong `filterConfig.filters`; tạo `filterConfig` khi chưa có; bỏ khi rỗng theo R2g; thẻ khác nguyên byte |

## Kiểm trong bộ nhớ (`verifyLayout`)

1. Mọi item `bookmarks.json` có file và mọi file có item (đã có từ D5).
2. Với bookmark BI Pro ghi (thêm hoặc cập nhật): khoá `visualContainers` chỉ trỏ visual tồn tại ở đúng trang; mọi bookmark: `activeSection` và khoá `sections` chỉ trỏ trang tồn tại.
3. Mọi thẻ lọc ở `report.json`, `page.json`, `visual.json` parse lại được, và thẻ đã đổi khớp thẻ mong muốn.
4. `displayName` của bookmark khớp tên đang sửa.
5. Part không đổi khớp byte (so với bản gốc).
Sai một điều: ném `verificationFailed`, file đích nguyên vẹn.

## Phối hợp

- Xoá visual: gỡ khỏi `visualContainers` (D1); `targetVisualNames` của bookmark có sẵn giữ nguyên như Desktop (R14 của D1).
- Xoá trang: gỡ bookmark (kể cả bản thêm trong phiên) và thay đổi lọc cấp trang hoặc cấp visual của trang đó.
- Báo cáo định dạng cũ (`Report/Layout`): không ghi; pane báo lý do.
