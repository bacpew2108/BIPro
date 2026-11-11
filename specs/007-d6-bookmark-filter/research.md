# Nghiên cứu D6: bookmark và bộ lọc ghi vào file

Nguồn: `Nhom6_work.pbix`, `~/Downloads/C2_A/bookmark-data.pbix` (Desktop ghi, buổi VM-C2), mã `ReportFilters.swift`, `UserBookmark.swift`, `ReportInteraction.swift`, `DocumentSaver.swift`, `PBIRPagePatch.swift`. Mục [SUY ĐOÁN] chờ buổi VM-D6.

## R1. Cấu trúc đã quan sát

- `bookmarks/bookmarks.json`: `$schema` (`bookmarksMetadata/1.0.0`), `items` mảng `{name}`; bookmark Desktop thêm mới đứng **cuối**; tên và tên file là 20 hex (`a75f6610730ae7536ee0`); `displayName` "Bookmark N" (N theo số bookmark).
- File chỉ-Display (Nhom6, tác giả đặt): khoá `displayName`, `name`, `options{applyOnlyToTargetVisuals, targetVisualNames, suppressActiveSection, suppressData}`, `explorationState{version "1.0", activeSection, sections.<trang>.visualContainers.<visual>.singleVisual{visualType, display{mode hidden}?}}`.
- File Data mặc định (Desktop): `options{targetVisualNames:[1 visual], preserveNewVisualVisibility:true}`; `explorationState{version "1.3", activeSection, filters.byExpr, sections.<trang>.visualContainers.<visual>{filters.byExpr, singleVisual{visualType, objects, activeProjections}}}`. Lựa chọn slicer ở `singleVisual.objects.merge.general[0].properties.filter.filter`. Thẻ lọc không đổi chỉ có `name`, `type`, `expression`, `howCreated`. Kích thước 20 KB cho một bookmark: Data ghi trạng thái cả trang.
- Bộ lọc cố định: `filterConfig.filters` mảng thẻ `{name, field, type, filter?, howCreated?, isHiddenInViewMode?, isLockedInViewMode?}` ở `report.json` (2 thẻ Nhom6), `page.json` (1), `visual.json` (1). Thẻ Categorical: `filter{Version:2, From:[{Name,Entity,Type:0}], Where:[{Condition:{In|Not{In}}}]}`.

## R2. Kết quả VM-D6 (2026-11-11, `docs/phase-d-evidence/vm-d6/QUAN-SAT.md`)

Đã quan sát. Tóm tắt (chi tiết và JSON ở `QUAN-SAT.md`, `json/`):

| # | Câu hỏi | Kết quả |
|---|---|---|
| a | Add mặc định | `options{targetVisualNames:[],preserveNewVisualVisibility:true}`; `explorationState` version 1.3 chụp **cả trang** (32 visual, `filters.byExpr`, `objects`); thêm cuối `items` của `bookmarks.json`; mã 20 hex |
| b | Tắt Current page | thêm `suppressActiveSection:true`; `activeSection` vẫn ghi |
| c | Tắt Data, Display | thêm `suppressData:true`, `suppressDisplay:true`; state không đổi |
| d | All/Selected visuals, Update | `applyOnlyToTargetVisuals:true`; `targetVisualNames` = mã visual đang chọn khi Update; Update ghi lại cả file, giữ `name`, `displayName`, tuỳ chọn |
| e | Rename, Delete, đổi thứ tự, bookmark cuối | Rename chỉ `displayName`; Delete xoá file và item; bookmark cuối: **xoá luôn `bookmarks.json`**; thêm lại tạo `bookmarks.json` mới; đổi thứ tự chỉ đổi `items` |
| h | Desktop chuẩn hoá bookmark không đổi | **Không**: byte giữ nguyên |
| i | Nút `Bookmark` trỏ bookmark đã xoá | Chưa quan sát (nút không bị đụng, như D5 với bookmark mồ côi) |
| g | Filters pane | Thêm: Page/Report-level qua chuột phải trường; thẻ Basic chưa chọn không có `filter`; Basic In có `filter` trước `howCreated:"User"`, bí danh `From` = chữ cái đầu bảng viết thường; Advanced `StartsWith`, `Contains`, `Not`, `And`; TopN có `From` subquery; `filterConfig` của `page.json` chèn sau `width`; xoá thẻ cuối bỏ `filterConfig` (`page.json` về đúng byte cũ); visual ghi mọi thẻ Filters pane khi chạm tới |
| f | Data tối thiểu | **Chưa quan sát**; chỉ biết dạng đầy đủ. Quyết định ở R6 |

Chưa quan sát (nên `sessionOnly`): Lock/Hide thẻ; Advanced "is", "is not", "is blank", số (`Comparison`), `Or`; Bottom N; Group bookmark.

## R3. Hai lớp trạng thái (quyết định)

- **Quyết định** (người dùng chốt 2026-11-11: Xem chỉ để xem): sửa bookmark và bộ lọc chỉ ở chế độ Sửa, vào lớp tài liệu `ReportEdits` trong `LayoutEditor`. Ở Xem các thao tác sửa mờ kèm lý do; áp bookmark vẫn được. Lớp phiên của `ReportInteraction` giữ lại chỉ cho trạng thái do áp bookmark và slicer (không ghi).
- **Lý do**: D1 chốt Xem không đổi file (không hỏi lưu khi chỉ xem). Hoàn tác và dấu chưa lưu đã nằm ở `LayoutEditor` (ảnh chụp giá trị); thêm một trường vào ảnh chụp rẻ và an toàn.
- **Đọc gộp**: bộ lọc hiệu lực = bộ lọc file, rồi thay đổi tài liệu, rồi lớp phiên; bookmark hiển thị = file (trừ xoá/đổi tên), rồi tài liệu, rồi phiên. Mọi chỗ đọc `userFilters` / `removedFilters` / `bookmarkRows` đổi sang giá trị gộp (liệt kê ở plan).
- **Loại**: một lớp chung (áp bookmark sẽ làm bẩn file, hoặc bị đè khi lưu); cho phép sửa ở Xem (người dùng đã bác).

## R4. So với file trên đĩa, không với ảnh gốc (quyết định)

`makeChanges` dựng thay đổi bằng cách so trạng thái mong muốn với bytes trong `archive` đang mở (như D5), không dựa vào "đã lưu hay chưa". Sau lưu `markSaved` đặt lại ảnh gốc; lưu lần hai không ghi lại phần đã khớp. Hệ quả: hoàn tác sau khi lưu rồi lưu lại ghi đúng trạng thái mới (không như D5 mục (b) còn tồn đọng cho xoá trang).

Khi bookmark cuối bị xoá, xoá cả `bookmarks.json` (R2e); thêm bookmark khi chưa có tạo `bookmarks.json` mới.

## R5. Sinh mã bookmark

Mã mới là 20 hex ngẫu nhiên (cùng bộ sinh với trang và visual: `PBIRLayoutPatch.makePageName(avoiding:)`), tránh trùng mọi `name` có trong `bookmarks.json` và trên đĩa. Tên hiển thị mặc định "Bookmark N" như Desktop (đã có trong `addBookmark`).

## R6. Mô hình bookmark ghi được (quyết định sau VM-D6)

`BookmarkSpec` (giá trị thuần, `PBIXKit`): `name`, `displayName`, `activePage`, `suppressActiveSection`, `suppressData`, `suppressDisplay`, `targetVisualNames`, `hidden: [page: [visual: (type, hidden)]]`, `data?`.

- **Ghi dạng tối giản Nhom6** (Desktop đã mở: VM-D1; Desktop không ghi lại): `options{applyOnlyToTargetVisuals:true, targetVisualNames:[mọi visual của trang], suppressActiveSection?, suppressData:true, suppressDisplay?}`, `explorationState{version:"1.0", activeSection, sections.<trang>.visualContainers.<visual>.singleVisual{visualType, display{mode:"hidden"}?}}`. Không bắt chước dạng toàn trạng thái 1.3 (cần `activeProjections`, thẻ lọc từng visual: không có đủ thông tin trong BI Pro, dễ ghi sai).
- **Bookmark có Data**: `sessionOnly("Data cần dạng Desktop chấp nhận")` cho tới khi US4 (T030, T031) thử: BI Pro ghi dạng tối giản có `filters.byExpr` và `objects.merge.general.filter`, mở trong Desktop, bấm bookmark; áp đúng thì mở, không thì giữ `sessionOnly`.
- Tuỳ chọn của `UserBookmark` → cờ: Data bật → không ghi `suppressData` (nhưng chưa ghi được: xem trên); Data tắt → `suppressData:true`; Display tắt → `suppressDisplay:true`, không ghi `display`; Current page tắt → `suppressActiveSection:true`. Thứ tự khoá `options`: `applyOnlyToTargetVisuals`, `targetVisualNames`, `suppressActiveSection`, `suppressData`, `suppressDisplay`.

## R7. Chọn thẻ lọc ghi được (quyết định sau VM-D6)

Ghi được (dạng đã quan sát): Basic `In` và `Not In` (Nhom6 cho `Not In` do tác giả đặt, Desktop hiện "is not"; kiểm lại ở T035), Advanced chữ với `StartsWith`, `Contains`, `Not{StartsWith|Contains}`, `And` của hai điều kiện đã quan sát; TopN (một thẻ theo mẫu quan sát). Thẻ mới: `name` 20 hex ngẫu nhiên, `field` Column, `type`, `filter` trước `howCreated:"User"`, bí danh `From` = chữ cái đầu của bảng viết thường (trùng thì thêm số). `sessionOnly`: Advanced "is", "is not", rỗng, so sánh số, `Or`; Bottom N; thẻ measure Advanced (số); thẻ chưa chọn giá trị chưa có thì không ghi gì cho thẻ mới. Thẻ trong file không đổi: giữ nguyên byte.

## R8. Xoá dọn tham chiếu

- Xoá visual: bỏ khỏi `visualContainers` của bookmark (đã có, D1 R14) và `targetVisualNames` (mới); bộ lọc cấp visual đi cùng `visual.json` bị xoá.
- Xoá trang: gỡ bookmark trỏ tới (D5); bookmark mới tạo trong phiên trỏ trang đó cũng bỏ; bộ lọc cấp trang đi cùng `page.json`.
- Xoá bookmark: nút `Bookmark` trỏ tới giữ nguyên (R2i); không đụng `visual.json` của nút.

## R9. Hiệu năng

Mỗi thao tác sửa giá trị thuần, ghi sau ở lúc lưu: dưới 1 ms mỗi thao tác. Dựng 1 bookmark và vài thẻ lọc lúc lưu dưới 10 ms; phần lớn thời gian lưu là zip (0,18 s ở D2/D4).

## R10. Rủi ro

| Rủi ro | Giảm |
|---|---|
| Desktop chấp nhận khác dự kiến | Cổng VM-D6; không ghi dạng chưa quan sát; `verify` đọc lại bằng chính bộ đọc BI Pro |
| Bookmark Data thiếu phần Desktop cần | Chỉ làm khi R2f chốt; chưa thì `sessionOnly` |
| Hai lớp gây lệch giữa Xem và Sửa | Test chuyển chế độ giữa các thao tác; giá trị gộp là một hàm thuần có test |
