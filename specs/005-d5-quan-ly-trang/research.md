# Nghiên cứu D5: quản lý trang

Mỗi mục: quyết định, lý do, phương án đã loại. Mục [SUY ĐOÁN] là chỗ chưa quan sát; kiểm ở buổi VM-D5 bổ sung hoặc giữ phương án thận trọng.

## R1. Quan sát Power BI Desktop (VM-D5, 2026-11-10)

Nguồn: `docs/phase-d-evidence/vm-d5/QUAN-SAT.md`, file `R-D5-*.pbix`. Điều đã quan sát và dùng làm chuẩn:

- **Thêm trang**: mã 20 hex, thư mục `pages/<mã>/page.json` một dòng, không BOM: `{"$schema":".../page/2.1.0/schema.json","name":"<mã>","displayName":"Page 1","displayOption":"FitToPage","height":1080,"width":1920}`; mã vào **cuối** `pageOrder`; `activePageName` = trang mới. Trang thứ hai tên "Page 2".
- **Đổi tên**: chỉ `displayName` của `page.json`.
- **Đổi thứ tự**: chỉ `pageOrder`.
- **Nhân bản**: "Duplicate of <tên>", mã mới, cuối `pageOrder`, thành trang đang mở; `page.json` giữ mọi khoá của trang gốc trừ `name`, `displayName`; mọi visual có mã 20 hex mới (loại, vị trí, `z` giữ), nút `Bookmark` vẫn trỏ bookmark cũ.
- **Xoá**: bỏ cả thư mục (page.json, 36 visual), bỏ khỏi `pageOrder`; bookmark và `bookmarks.json` **không đổi**; trong phiên bấm bookmark mồ côi không làm gì, không lỗi.
- `activePageName` luôn là trang đang mở lúc lưu.
- Menu chuột phải tab: Set as landing page, Duplicate page, Rename, Delete (hộp thoại xác nhận), Hide, Move to.
- Mẫu pages.json của Nhom6 một dòng, không BOM (`pageOrder`, `activePageName` ở cuối).

Chưa quan sát [SUY ĐOÁN]: xoá trang có nút `PageNavigation`; mở lại file sau khi xoá trang (bookmark mồ côi); nhân bản trang có `filterConfig` hoặc `pageBinding`; "Set as landing page" ghi vào đâu (nhiều khả năng `activePageName`); tên mặc định khi "Page 1" đã bị xoá hay đổi tên.

## R2. Trạng thái sửa: `PageStructure` và ảnh chụp toàn trạng thái

**Quyết định**: `LayoutEditor` có thêm `structure: PageStructure` (thứ tự tab, tên đổi, trang tạo trong phiên, trang đã xoá của file, bookmark gỡ, ghi nhớ mã đã dùng). `LayoutSnapshot` chuyển thành `{ edited, structure, currentPageID, selection, primary }`. `undo`/`redo` hoán đổi snapshot hiện tại với snapshot trên ngăn xếp.

**Lý do**: lịch sử là tuyến tính, nên ảnh chụp toàn trạng thái tương đương ảnh chụp theo trang của D1; `edited` là từ điển giá trị nên chụp rẻ (copy-on-write). Thao tác thêm/xoá cả trang thành một bước tự nhiên; hoàn tác xoá phục hồi cả `edited[trang]` lẫn bookmark đã gỡ.

**Loại**: giữ ảnh chụp theo trang và thêm cơ chế riêng cho cấu trúc: hai ngăn xếp, xen kẽ với D1 đến D3 dễ sai.

**Giữ nguyên hành vi D1**: gộp bước kéo trong 0,5 s (`coalesce`), `cleanMark`, giới hạn 200 bước.

## R3. Trang tạo trong phiên dùng lại `PageEdit`

**Quyết định**: trang mới (thêm hoặc nhân bản) nằm trong `structure.created[mã]` (tên, cỡ, nội dung `page.json` gốc nếu nhân bản) và có `edited[mã]` bình thường. Hàm tra cứu "trang cơ sở" (`basePage(id)`) trả trang của `baseline` hoặc một `ReportPage` rỗng tạo từ `created`. Visual của trang nhân bản nằm trong `edited[mã].visuals` và `edited[mã].added[mã visual]` (byte `visual.json` đã đổi mã), nên kéo, thả trường, thêm visual, xoá visual chạy y như D1 đến D3.

**Lý do**: không viết lại thao tác visual; `makeChanges` đã biết ghi `added` thành part mới.

**Loại**: nhân bản trang thành "trang cơ sở" có sẵn visual trong `baseline`: baseline bất biến theo thiết kế.

## R4. Mã trang và tên mặc định

**Quyết định**: mã trang mới là 20 hex ngẫu nhiên từ cùng bộ sinh với mã visual (`PBIRLayoutPatch.makeVisualName` đổi tên chung `makeObjectName`, giữ tên cũ làm bí danh), tránh mọi mã trang đã có hoặc đã sinh trong phiên (kể cả trang đã xoá, phòng hoàn tác). Tên mặc định "Page N" với N = (số lớn nhất của các tên dạng `Page <số>` đang có) + 1, tối thiểu 1. Nhân bản: "Duplicate of " + tên trang gốc.

**Lý do**: khớp quan sát VM-D5 (Page 1, Page 2; Duplicate of …). Quy tắc N khi có khoảng trống chưa quan sát [SUY ĐOÁN]; chọn số lớn nhất cộng một vì không bao giờ trùng tên mặc định.

## R5. Ghi `pages.json`

**Quyết định**: chỉ ghi khi cấu trúc đổi (thêm, bớt, đổi thứ tự, hoặc đổi trang đang mở cùng lúc có thao tác trang): thay mảng `pageOrder` bằng thứ tự mới (một dòng, cùng kiểu phân cách mảng cũ) và `activePageName` bằng trang đang mở khi lưu (nếu trang đó còn trong dãy; không thì trang đầu). Không đổi gì về trang thì không đụng `pages.json` (D1 đến D3 giữ nguyên byte).

**Lý do**: đúng quan sát (`R-D5-*`): Desktop chỉ đổi hai khoá này. `activePageName` khớp trang đang mở như Desktop.

**Loại**: luôn ghi `activePageName` theo tab đang mở mỗi lần lưu: làm đổi `pages.json` cả khi chỉ kéo visual (phá "phần không sửa khớp byte").

## R6. Ghi `page.json`

- **Trang mới**: một dòng đúng như R1, `displayName` đã escape; part mới đặt sau thành viên cuối của `pages/` (mở rộng `PBIXWriter.insertionIndex`: trang mới chưa có thư mục thì ra sau thành viên cuối dưới `Report/definition/pages/`).
- **Đổi tên**: ghép byte giá trị `displayName` (như `setVisualTitle` của D1); trang vừa tạo trong phiên chưa có part nên cập nhật nội dung `created`.
- **Nhân bản**: byte `page.json` của trang gốc (đã áp đổi tên nếu có) với `name`, `displayName` thay, **bỏ `pageBinding`** (bản nhân bản không thành trang drillthrough thứ hai; có báo), và mã visual trong `visualInteractions` (nếu có) đổi theo bảng mã cũ → mới.
- **Visual của trang nhân bản**: byte `visual.json` hiện tại (đã áp sửa của D1 đến D3) với `name` đổi, `parentGroupName` đổi theo bảng mã nếu có; `position` giữ nguyên chính xác (không làm tròn).

## R7. Xoá trang

**Quyết định**:

1. Chặn nếu chỉ còn một trang; chặn nếu có nút `visualLink` loại `PageNavigation` trỏ tới trang (đọc từ `visual.json` của mọi trang còn lại) [SUY ĐOÁN về cách Desktop xử lý] kèm danh sách nút.
2. Trang của file: ghi vào `structure.removed`; khi lưu `removedParts` mọi part dưới `pages/<mã>/`. Trang tạo trong phiên: bỏ khỏi `created` và `edited`; nếu `created` đã có part trong file đang mở (đã lưu lần trước trong phiên) thì cũng `removedParts` (như `createdIDs` của D1).
3. Bookmark: bookmark có `activeSection` = trang xoá thì gỡ cả file và mục trong `bookmarks.json`; bookmark có `sections.<mã>` mà `activeSection` khác thì chỉ bỏ phần `sections.<mã>`. Danh sách bookmark gỡ nằm trong `structure.removedBookmarks` để hoàn tác phục hồi và để báo người dùng. Khác Desktop (để mồ côi), có chủ ý: R-D5 xác nhận Desktop không lỗi, nên cả hai cách đều mở được; ta chọn không để tham chiếu treo (SC-005).
4. Visual của trang xoá được tính là visual bị xoá để dọn `targetVisualNames` và `explorationState.sections.<trang>.visualContainers` ở bookmark còn lại (cùng đường dọn của D1).
5. Trang liền kề (bên phải, hoặc bên trái nếu là trang cuối) thành trang đang mở; hoàn tác trả đúng trang đang mở cũ.

**Loại**: không gỡ bookmark: để lại bookmark vô dụng và tham chiếu treo.

## R8. Hoàn tác

Mỗi thao tác trang là một `commit` cấp cấu trúc: tạo một snapshot, không gộp theo thời gian. Thao tác không đổi gì (đổi tên trùng tên cũ, kéo về chỗ cũ) không tạo bước. `isDirty` vẫn là `undoStack.count != cleanMark`.

## R9. Giao diện thanh tab

**Quyết định**: `PageTabs` đọc `state.pages` (trang đã sửa, theo thứ tự). Chế độ Sửa: nút "+" bật; menu chuột phải gồm Đổi tên (hộp `alert` có `TextField`, như đổi tên trường D2), Nhân bản, Xoá (hộp xác nhận), Sang trái, Sang phải; bấm đúp tab mở đổi tên; kéo tab bằng `onDrag`/`onDrop` với `NSItemProvider` (D2 R9: `draggable`/`Transferable` không chạy trong `DocumentGroup`). Chế độ Xem hoặc báo cáo định dạng cũ: nút và mục menu mờ kèm `help`. Trang ẩn giữ biểu tượng mắt gạch.

**Thử trước**: T001 của D5 thử kéo tab đổi thứ tự; không chạy thì chỉ còn Sang trái/Sang phải và báo.

## R10. Rà soát nơi đọc danh sách trang

Mọi chỗ đọc `workspace.report.pages` hoặc `workspace.page(id:)` phải thấy bản đã sửa:

| Nơi | Đọc | Quyết định |
|---|---|---|
| `PageTabs` | danh sách và tên | `state.pages` |
| `DocumentState.init` | trang mở đầu | giữ (lúc mở chưa có sửa) |
| `ShellView` tìm kiếm | tên trang | `state.pages` |
| `Workspace.drillthroughPages` | trang có `pageBinding` (baseline, lazy) | lọc bỏ trang đã xoá; trang nhân bản không có `pageBinding` nên không thêm |
| `ReportCanvas`/`pageNavigator` | liệt kê trang (nếu có) | `state.pages` ẩn trang ẩn |
| `ReportInteraction` điều hướng (nút `Back`, `PageNavigation`, drillthrough) | mã trang đích | bỏ qua đích đã xoá |
| `DocumentSaver.verifyLayout` | `editor.baseline.pages` | `editor.pages` (cấu trúc mới) |

## R11. Lưu và kiểm

`makeChanges` thêm các bước, theo thứ tự: (1) trang tạo: `page.json` mới và `visual.json` của từng visual (`addedParts`); (2) trang đổi tên: `reportParts[page.json]`; (3) trang xoá: `removedParts` toàn bộ part của trang; (4) `pages.json`: `reportParts`; (5) bookmark: gỡ file (`removedParts`) hoặc sửa (`reportParts`) và sửa `bookmarks.json`. `PBIXWriter.build` đã kiểm: mọi part ghi đọc lại đúng, part không chạm khớp CRC, số thành viên đúng. `verifyLayout` kiểm thêm: thứ tự và tên trang khớp `editor.pages`, mọi trang tạo có đủ visual, không bookmark nào trỏ trang không còn, không mã trang đã xoá còn xuất hiện trong `definition/` (SC-005).

## R12. Gói thử tay và quan sát bổ sung

`pbix-dump` thêm `add-page`, `rename-page`, `move-page`, `dup-page`, `remove-page` (như D2, D3) để dựng `build/d-out/D5/Nhom6_d5.pbix` và `Nhom6_d5_pre.pbix` (chia đôi nếu Desktop từ chối) cùng `CHECKLIST.md`. Buổi VM-D5 bổ sung (nếu người dùng cho phép): xoá trang có nút `PageNavigation`, mở lại file đã xoá trang, nhân bản trang `d4_chinhanh`, "Set as landing page".

## R13. Kết quả rà soát và thử (2026-11-10)

- **T001 kéo tab**: `NSItemProvider` với `onDrag`/`onDrop` chạy được trong app; tab dùng cử chỉ chạm (không dùng `Button`, vì Button nuốt thao tác kéo như D2). Thử trên bản sao Nhom6: kéo "Trang moi" lên trước D1 đổi `pageOrder` đúng, lưu và hoàn tác ba bước (thêm, đổi tên, kéo) đúng.
- **T002 nơi đọc danh sách trang**: `PageTabs` và `ShellView` dùng `DocumentState.pages`; `ReportInteraction.pages` (đặt bởi `DocumentState`) cho `PageNavigatorVisual`, đích drillthrough còn sống và trang của bookmark; danh sách bookmark ẩn bookmark đã gỡ do xoá trang (`removedBookmarksProvider`); `DocumentState.init` giữ trang mở đầu từ file.
- **Ghi**: `makeChanges` so với file trên đĩa nên không cần theo dõi trạng thái "đã lưu" (lưu lần hai không ghi gì); không dùng `NewPage.savedPaths` (đã bỏ khỏi thiết kế).

## R14. Quan sát bổ sung và quyết định sau khi làm (2026-11-10)

- **Mở lại file đã xoá trang**: Desktop mở được file có bookmark mồ côi (`R-D5-e`); vậy cả hai cách (để mồ côi hoặc gỡ) mở được. BI Pro vẫn gỡ (R7).
- **Nút `Bookmark` trỏ bookmark đã gỡ**: khi xoá trang có bookmark, nút trên trang khác (ví dụ bản nhân bản D1) vẫn tham chiếu bookmark theo tên. Desktop mở file không lỗi và chọn nút không báo gì (`CHECKLIST-KET-QUA.md` mục 6); Ctrl+bấm không thấy tác dụng. Giữ nguyên nút, không dọn.
- **`landingPageName`** ("Set as landing page"): khoá mới của `pages.json`. `PBIRPagePatch.setPageOrder` giữ khoá khi trang còn, bỏ khoá khi trang landing bị xoá (tránh tham chiếu treo; chưa quan sát cách Desktop làm).
- **Nhân bản trang drillthrough**: Desktop sao cả `pageBinding`; BI Pro không sao (có báo) vì tạo trang drillthrough mới thuộc ngoài phạm vi D5. Khác biệt có chủ ý.
- **Nhóm visual (`visualGroup`)** không được nạp thành `ReportVisual` nên nhân bản trang sao chúng riêng qua `PageEdit.extraParts` và `containerSource`, đổi `parentGroupName` theo bảng mã (phát hiện khi viết test).
- **Bộ lọc cấp visual của visual mã mới** (bản sao visual hoặc trang): `ReportInteraction.visualFilters(of:)` đọc từ `filterConfig` của chính visual khi mã không có trong `workspace.visualFilters`, nên bản sao vẽ cùng dữ liệu như gốc (sửa luôn lỗi cũ của D1 với visual nhân bản; `D5Nhom6` so 20+ truy vấn).

- **Bộ lọc cấp trang của trang nhân bản** (2026-11-10, theo converge T041): `ReportInteraction.pageFilters(of:)` đọc `filterConfig` từ `page.json` của trang nhân bản (qua `pageJSONProvider` do `DocumentState` đặt) vì `workspace` chỉ biết bộ lọc của trang có sẵn. Cùng `visualFilters(of:)` ở trên, hai chỗ này ngoài phạm vi liệt kê của D5 nhưng cần cho FR-012 (trang nhân bản vẽ cùng số với trang gốc; D1 để lọt lỗi với visual mã mới). Có test: `D5Nhom6Tests.banSaoTrangDrillthroughApDungBoLocCapTrang` (golden nặng 88 qua).
