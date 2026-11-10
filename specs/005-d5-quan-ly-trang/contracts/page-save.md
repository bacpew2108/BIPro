# Hợp đồng: ghi trang vào `.pbix` (D5)

Mở rộng `contracts/save-pipeline.md` của D1: cùng thứ tự (chặn Downloads, kiểm file nguồn, dựng và kiểm trong bộ nhớ, ghi tạm, mở lại, sao lưu, thay). `LayoutEditor.makeChanges` thêm phần trang; `DocumentSaver.verifyLayout` kiểm cấu trúc.

## Ghi gì (PBIXChanges)

| Thay đổi trong editor | Phần ghi |
|---|---|
| Trang tạo (thêm) | `addedParts[pages/<mã>/page.json]` = byte mẫu R6 |
| Trang tạo (nhân bản) | `addedParts[pages/<mã>/page.json]` = byte trang gốc, `name`/`displayName` thay, bỏ `pageBinding`, mã trong `visualInteractions` đổi; `addedParts[pages/<mã>/visuals/<mã visual>/visual.json]` cho từng visual (byte hiện tại, `name`/`parentGroupName` đổi, vị trí giữ nguyên chính xác) |
| Đổi tên trang của file | `reportParts[pages/<mã>/page.json]` = ghép byte `displayName` |
| Đổi tên trang tạo trong phiên | cập nhật `pageJSON` của `created` (chưa có part) |
| Thứ tự, thêm, xoá, trang mở | `reportParts[pages/pages.json]` = ghép byte `pageOrder` (và `activePageName` = trang đang mở nếu còn trong dãy, không thì trang đầu) |
| Trang của file bị xoá | `removedParts` = mọi part dưới `pages/<mã>/` có trong file; visual của nó tính vào `removedIDs` để dọn bookmark (D1) |
| Trang tạo bị xoá sau khi đã lưu trong phiên | `removedParts` = các part trong `savedPaths` |
| Bookmark gỡ (`activeSection` = trang xoá) | `removedParts[bookmarks/<tên>.bookmark.json]`; `reportParts[bookmarks/bookmarks.json]` bỏ mục `items[]` của nó |
| Bookmark chỉ nhắc trang xoá ở `sections` | `reportParts[bookmarks/<tên>.bookmark.json]` bỏ `sections.<mã>` |

Không có thay đổi cấu trúc thì không đụng `pages.json` (byte khớp). `activePageName` chỉ đổi khi cấu trúc trang đổi (R5).

## Mẫu `page.json` mới (một dòng, không BOM)

```
{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json","name":"<mã 20 hex>","displayName":"<tên>","displayOption":"FitToPage","height":1080,"width":1920}
```

`$schema` lấy theo `page.json` đầu tiên của báo cáo nếu có (như `PBIRNewVisual.schemaURL`), mặc định 2.1.0.

## `PBIRPagePatch` (PBIXKit, công khai)

```
setPageOrder(_ order: [String], activePage: String?, in pagesJSON: Data) -> Data
setPageDisplayName(_ name: String, in pageJSON: Data) -> Data
newPageJSON(id: String, displayName: String, schema: String?) -> Data
duplicatedPageJSON(_ source: Data, newName id: String, displayName: String, visualIDMap: [String: String]) -> Data   // bỏ pageBinding
renamedVisualJSON(_ json: Data, newName: String, parentGroupName: String?) -> Data                                      // chỉ name/parentGroupName
removingPageReferences(_ ids: Set<String>, fromBookmark json: Data) -> BookmarkOutcome                              // .unchanged | .trimmed(Data) | .remove
bookmarkItemsRemoving(_ names: Set<String>, from json: Data) -> Data                                                  // bookmarks.json
pageNavigationTargets(in visualJSON: Data) -> Set<String>                                                              // visualLink loại PageNavigation
```

Mỗi hàm ghép byte rồi phân tích lại và so với cấu trúc mong đợi (như `PBIRQueryPatch`); lỗi thì ném `WriteError` và editor không áp.

## Kiểm lúc lưu (`verifyLayout`, thêm)

1. Đọc lại bằng `PBIXFile.loadReport`: thứ tự trang và `displayName` khớp `editor.pages`.
2. Mọi trang trong `editor.pages` có đủ visual (tập mã, khung, `z`, loại, trường như D1 đến D3).
3. Mọi bookmark còn trong file có `activeSection` thuộc dãy trang; `bookmarks.json` khớp tập file bookmark.
4. Không mã trang đã xoá còn xuất hiện trong chuỗi byte của `Report/definition/` (SC-005).

Lỗi ở bước nào thì `SaveError.verificationFailed`, file đích còn nguyên.
