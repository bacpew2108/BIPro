# Hợp đồng: đường lưu T1

## Đầu vào

`DocumentSaver.save(editor, source: URL, destination: URL)`.

`LayoutEditor.makeChanges()` cho một `PBIXChanges` chứa:

- `reportParts[visualPath] = visual.json` đã ghép byte, cho visual **có sẵn** mà `position` đổi (chỉ các trường đổi).
- `addedParts[visualPath] = visual.json` mới, cho bản sao.
- `removedParts` = `visual.json` của visual bị xoá.
- `reportParts[bookmarkPath]`, `reportParts[pagePath]` = JSON đã dọn tham chiếu tới mã bị xoá (chỉ khi có tham chiếu).

Trang không sửa không xuất hiện trong ba trường trên (FR-018). `measures` luôn rỗng ở lát này.

## Thứ tự và điều kiện (mỗi bước lỗi thì dừng, đích còn nguyên)

1. **Chặn đường dẫn**: `destination` không được nằm dưới `~/Downloads` (giải liên kết). Vi phạm → lỗi `readOnlyOriginal`, giao diện đã chuyển sang Lưu thành trước đó.
2. **File đổi ngoài app**: nếu `destination` tồn tại và `FileStamp` khác `openedStamp` → hỏi người dùng (Ghi đè / Lưu thành / Huỷ). Lưu thành mới không kiểm bước này.
3. **Dựng**: `PBIXWriter.build(source:, changes:)` → `Result.data`. `source` luôn là file đã mở. Điều kiện: mọi phần trong `reportParts`/`removedParts` phải có trong nguồn; mọi phần trong `addedParts` phải chưa có.
4. **Kiểm trong bộ nhớ**:
   - `PBIXFile(data:)` mở được;
   - mọi `reportParts` và `addedParts` đọc lại bằng nội dung đã định; mọi `removedParts` không còn;
   - mọi thành viên khác (gồm `DataModel`) có CRC và nội dung giống nguồn, trừ `SecurityBindings` (bị bỏ, xem dưới) và `[Content_Types].xml` (mất dòng Override của `SecurityBindings`);
   - không còn `SecurityBindings` trong file mới, và `[Content_Types].xml` không nhắc tới nó;
   - `loadReport()` khớp `LayoutEditor` theo mục "Đọc lại" của `layout-editing.md`.
5. **Ghi tạm**: `.<tên>.<uuid>.tmp` cùng thư mục đích; mở lại bằng `PBIXFile(url:)`; lỗi thì xoá file tạm.
6. **Sao lưu**: nếu `destination` tồn tại, chép sang `~/Library/Application Support/BI Pro/Backups/<băm đường dẫn tuyệt đối>-<tên>.pbix` (ghi đè bản sao lưu cũ của cùng file); lỗi chép sao lưu = lỗi cả lưu.
7. **Thay**: `FileManager.replaceItemAt(destination, withItemAt: temp)` (hoặc `moveItem` nếu đích chưa có).
8. **Sau khi lưu**: `LayoutEditor.markSaved()`, cập nhật `openedStamp` bằng `FileStamp` của đích.

## Lưu thành

Hộp thoại `NSSavePanel` (đuôi `.pbix`). Xong bước 8 thì mở đích bằng `NSDocumentController` rồi đóng cửa sổ cũ không hỏi (trạng thái chưa lưu của nó đã nằm trong đích). Cửa sổ cũ không đổi file nguồn.

## Lỗi người dùng thấy

| Tình huống | Thông báo (tiếng Việt, ngắn) | Hành động |
|---|---|---|
| Đích chỉ đọc/không có quyền | "Không ghi được vào <vị trí>." | Đề nghị Lưu thành |
| Đích nằm dưới `~/Downloads` | "File trong Downloads là bản gốc, chỉ đọc. Hãy lưu thành bản mới." | Mở Lưu thành |
| File đổi ngoài app | "File đã bị thay đổi bởi chương trình khác." | Ghi đè / Lưu thành / Huỷ |
| Kiểm tra đọc lại không khớp | "File mới không qua kiểm tra, file cũ được giữ nguyên." + chi tiết ngắn | Đóng |
| Sao lưu lỗi | "Không tạo được bản sao lưu, chưa ghi gì." | Đóng |

## Không thay đổi

- `DataModel`, `Metadata`, `Settings`, `DiagramLayout`, tài nguyên tĩnh: `rawCopy` từng byte.
- **`SecurityBindings` bị bỏ** (cùng dòng Override của nó trong `[Content_Types].xml`, phần còn lại của file này giữ nguyên byte) mỗi khi save có đổi, thêm hoặc xoá phần báo cáo. Power BI Desktop từ chối file nếu giữ nó (research R13).
- Thứ tự thành viên ZIP của phần giữ lại: giữ nguyên. Phần thêm đặt ngay sau phần `visual.json` cuối cùng của cùng trang. Phần xoá chỉ bị bỏ.
- Chế độ: `tier == .report`. Số thành viên mới = nguồn + phần thêm − phần xoá − 1 (SecurityBindings, nếu nguồn có).
