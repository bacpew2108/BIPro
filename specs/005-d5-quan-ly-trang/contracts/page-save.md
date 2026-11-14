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
| Trang của file đã xoá, đã lưu, rồi hoàn tác (sửa 2026-11-13) | `addedParts` = mọi part dưới `pages/<mã>/` lấy từ file lúc mở, có áp phần sửa trong phiên (visual đã xoá trong phiên không ghi lại); bookmark lúc mở có nhắc trang đó lấy lại từ byte lúc mở, bỏ trang và visual hiện vẫn đang xoá, rồi mới áp sửa bookmark của D6; `bookmarks.json` dựng từ bản lúc mở (mục về đúng chỗ, đúng nhóm), bookmark tạo trong phiên thêm ở cuối |
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
4. Không còn tham chiếu tới trang đã xoá ở những chỗ là tham chiếu (SC-005): part dưới `pages/<mã>/`, `pageOrder` và `activePageName` của `pages.json`, `activeSection` và `sections` của bookmark, nút `PageNavigation` trong `visual.json`. Chuỗi trùng mã trang ở chỗ khác (tên hiển thị, chữ trong visual) không phải tham chiếu và không chặn lưu (sửa 2026-11-13; trước đó tìm chuỗi trong mọi file nên có thể chặn nhầm, và không bắt được nút điều hướng vì mã nằm trong dấu nháy đơn). Sửa lần hai 2026-11-13 (VM-D8): nút `PageNavigation` trỏ trang đã xoá **không** tính là lỗi; Desktop để nguyên nút, BI Pro giữ part của nút từng byte.

Lỗi ở bước nào thì `SaveError.verificationFailed`, file đích còn nguyên.

## Dọn tài nguyên khi xoá trang (bổ sung 2026-11-14, VM-D12 mục 2)

Desktop bỏ mục `ShapeMap` (`SharedResources`) và `Image` (`RegisteredResources`) khỏi `report.json` > `resourcePackages`, cùng file của nó ở `Report/StaticResources/<gói>/<path>`, khi **mọi** trang nhắc tới nó (`"ItemName":"<tên>"` trong part của trang) đã xoá; còn một trang nhắc tới thì giữ; theme không đụng.

- `LayoutEditor.addResourceChanges` (cuối `addReportChanges`, sau bộ lọc, trên `report.json` hiện có trong `changes`): so với `report.json` lúc mở (`openedParts`), mục bị bỏ = mục mà các trang của file lúc mở nhắc tới, không trang nào còn trong thứ tự trang nhắc, và không part nào còn lại của báo cáo nhắc. Ghép byte `items` bằng `PBIRResourcePatch.settingItems` (mục bỏ chỉ trong `items`, phần khác nguyên byte, kiểm lại bằng so cấu trúc).
- Tính lại từ đầu mỗi lần lưu: hoàn tác xoá trang sau khi đã lưu đưa mục và file (byte lúc mở) trở lại; lưu lần hai không ghi gì; không trang nào xoá và file đủ mục thì không làm gì.
- Mục không trang nào nhắc tới lúc mở (và mọi loại khác `ShapeMap`/`Image`) không đụng.

