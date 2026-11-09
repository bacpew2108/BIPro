# Mô hình dữ liệu: D1

Các thực thể (khớp mục "Thực thể chính" của spec). Kiểu viết ở mức khái niệm; tên Swift là dự kiến.

## EditableVisual (dùng lại `ReportVisual`)

Không tạo kiểu mới. Trường dùng: `id` (20 hex), `x`, `y`, `z`, `width`, `height` (số nguyên), `isHidden`, `raw` (JSON gốc của `visual.json`).

Ràng buộc khi sửa:
- `0 ≤ x`, `0 ≤ y`, `x + width ≤ page.width`, `y + height ≤ page.height`
- `width ≥ 16`, `height ≥ 16`
- `z` duy nhất trong trang; `tabOrder` của bản ghi luôn bằng `z` khi do BI Pro tạo (nhân bản). Visual có sẵn giữ nguyên `tabOrder` cũ.

## PageLayout

Danh sách `[ReportVisual]` đã sắp theo `z` của một trang. Chỉ tồn tại cho trang đã bị sửa; trang chưa sửa không có bản sao (và không được ghi lại khi lưu: FR-018).

## LayoutEditor (@MainActor, @Observable)

| Trường | Ý nghĩa |
|---|---|
| `edited: [pageID: [ReportVisual]]` | bố cục sửa được, chỉ trang đã đụng tới |
| `selection: Set<String>` | mã visual đang chọn (trang hiện tại) |
| `primary: String?` | visual chọn cuối, nối với `DocumentState.visualID` |
| `undo: [LayoutSnapshot]`, `redo: [LayoutSnapshot]` | ngăn xếp |
| `cleanMark: Int` | độ sâu `undo` tại lần lưu gần nhất; `isDirty = undo.count != cleanMark` (tính cả khi redo/undo quay về) |
| `deletedByPage: [pageID: Set<String>]` | mã đã xoá khỏi bản gốc, cần bỏ phần khi lưu |
| `addedByPage: [pageID: [String: Data]]` | `visual.json` mới (bản sao) cần thêm khi lưu |

Phép toán: `move(ids, dx, dy)`, `resize(id, handle, to:)`, `delete(ids)`, `duplicate(ids)`, `select(...)`, `undo()`, `redo()`, `markSaved()`, `makeChanges() -> PBIXChanges`.

Mỗi phép toán sửa bố cục gọi `commit(page:)` đúng một lần: đẩy snapshot trước vào `undo`, xoá `redo`.

## LayoutSnapshot

`{ pageID, visuals: [ReportVisual], selection: Set<String>, deleted: Set<String>, added: [String: Data] }`. Một snapshot là toàn bộ trạng thái sửa của một trang trước thao tác. Hoàn tác = đổi chỗ snapshot với trạng thái hiện tại rồi đẩy vào `redo`.

## EditSession (trong DocumentState)

| Trường | Ý nghĩa |
|---|---|
| `fileURL: URL?` | file đang mở (nil nếu không biết) |
| `openedStamp: FileStamp` | ngày sửa + kích thước lúc mở hoặc lần lưu gần nhất |
| `mode: .view / .edit` | chế độ |
| `layout: LayoutEditor` | |

## PBIXChanges (mở rộng, `Contracts.swift`)

| Trường | Ý nghĩa |
|---|---|
| `reportParts` | (có sẵn) thay phần đã có |
| `addedParts: [String: Data]` | mới: thêm phần chưa có; đặt cạnh phần cùng trang |
| `removedParts: Set<String>` | mới: bỏ phần |
| `measures` | (có sẵn, T2) |

`tier` vẫn là `.report` khi chỉ có ba trường đầu.

## Mã phần ZIP

- `visual.json` của trang `P`, mã `V`: `Report/definition/pages/P/visuals/V/visual.json`
- `page.json`: `Report/definition/pages/P/page.json` (chỉ sửa nếu có `visualInteractions` nhắc visual bị xoá)
- bookmark: `Report/definition/bookmarks/<tên>.bookmark.json`

## Chuyển trạng thái

`đã mở (sạch)` → thao tác sửa → `chưa lưu` → ⌘S → `sạch` (cleanMark = undo.count, openedStamp mới) → hoàn tác → `chưa lưu` (vì khác cleanMark); hoàn tác tiếp/làm lại về đúng cleanMark → `sạch`.
