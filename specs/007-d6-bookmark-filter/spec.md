# Đặc tả tính năng: D6, bookmark và bộ lọc người dùng ghi vào `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng)

**Ngày tạo**: 2026-11-11

**Trạng thái**: Nháp, chờ duyệt

**Đầu vào**: "D6-bookmark-filter: lát cắt thứ bảy của Phase D (`docs/BIPRO_BUILD_PLAN.md` mục Phase D, sau D1 `specs/002-d1-canvas-luu-t1/`, D2 `specs/003-d2-build-pane-field-well/`, D3 `specs/004-d3-them-visual-doi-loai/`, D5 `specs/005-d5-quan-ly-trang/`, D4 `specs/006-d4-format-pane/`): ghi vào `.pbix` tầng T1 hai thứ hiện chỉ sống trong phiên: (A) bookmark người dùng thêm, cập nhật, đổi tên, xoá; (B) bộ lọc người dùng sửa ở Filters pane."

Cấp trên: `docs/BIPRO_BUILD_PLAN.md` (Phase D), `specs/002-d1-canvas-luu-t1/` (lưu T1, hoàn tác theo ảnh chụp, bỏ `SecurityBindings` ở R13, xoá visual bỏ khỏi bookmark ở R14), `specs/005-d5-quan-ly-trang/` (xoá trang gỡ bookmark trỏ tới), `specs/003-d2-build-pane-field-well/` (ghép byte vào `visual.json`). Mâu thuẫn thì sửa `docs/` trước.

## Quan sát Power BI

Mục nào là [SUY ĐOÁN] thì chưa có quan sát; phải kiểm bằng buổi quan sát VM-D6 trước khi code phần đó (Claude điều khiển VM khi người dùng cho phép lần đó, hoặc người dùng làm tay). Không dịch ngược; chỉ đọc file Desktop ghi và nhìn giao diện.

**Hiện trạng trong BI Pro** (đọc từ mã): `Report/UserBookmark.swift` giữ bookmark người dùng trong phiên (`UserBookmark`: tên, tuỳ chọn Data/Display/Current page, ảnh chụp gồm bộ lọc người dùng, bộ lọc đã bỏ, lựa chọn slicer, độ sâu drill, mở nút slicer và matrix, ẩn/hiện). `addBookmark`, `updateBookmark`, `renameBookmark`, `deleteBookmark`, `setBookmarkOption` chỉ đổi trạng thái trong `ReportInteraction`. Bookmark trong file được đọc bởi `PBIXKit/ReportFilters.swift` (`ReportBookmark.parse`, `loadBookmarks`: tên, trang, `suppressData`, `suppressActiveSection`, `targetVisualNames`, ẩn/hiện, và bộ lọc/lựa chọn slicer khi có Data). Bộ lọc người dùng (`UserFilter`: Basic là/không phải, Advanced, Top N, thẻ measure ở cấp visual) cũng chỉ nằm trong `ReportInteraction`. Từ D1 đến D5: lưu T1 bằng ghép byte (`DocumentSaver`), hoàn tác theo ảnh chụp (`LayoutEditor`), xoá visual đã bỏ khỏi `visualContainers` của bookmark, xoá trang đã gỡ bookmark trỏ trang đó.

**Đã quan sát trong file thật** (`Nhom6_work.pbix`, định dạng PBIR; và `bookmark-data.pbix` Desktop ghi ở buổi VM-C2, `~/Downloads/C2_A/`):

- `Report/definition/bookmarks/bookmarks.json`: `$schema` (`bookmarksMetadata/1.0.0`) và `items` là mảng `{name}` theo thứ tự hiện ở Bookmarks pane (có thể có nhóm kèm `children`). Bookmark Desktop thêm mới nằm **cuối** mảng và có tên file/`name` là 20 ký tự hex (`a75f6610730ae7536ee0`), `displayName` "Bookmark 3" (số theo thứ tự).
- Bookmark chỉ có Display (Nhom6, 2 file, tác giả đặt `name` tay): `$schema` `bookmark/2.1.0`; khoá theo thứ tự `displayName`, `name`, `options`, `explorationState`. `options`: `applyOnlyToTargetVisuals: true`, `targetVisualNames` (mảng mã visual), `suppressActiveSection: true`, `suppressData: true`. `explorationState`: `version "1.0"`, `activeSection`, `sections.<mã trang>.visualContainers.<mã visual>.singleVisual` chỉ có `visualType` và `display:{mode:"hidden"}` cho visual ẩn.
- Bookmark có Data (mặc định của Desktop, `bookmark-data.pbix`, 20 KB): `options` chỉ có `targetVisualNames` (một visual) và `preserveNewVisualVisibility: true`; `explorationState.version "1.3"`, `activeSection`, `filters.byExpr` (bộ lọc cấp báo cáo: thẻ không đổi chỉ có `name`, `type`, `expression`, `howCreated`, không có `filter`), và với mỗi visual của trang `filters.byExpr` + `singleVisual` có `visualType`, `objects` (lựa chọn slicer ở `objects.merge.general[0].properties.filter.filter`, slicer ở "Tất cả" thì không có), `activeProjections`… Tức Data ghi **trạng thái cả trang**, nhiều hơn mọi thứ BI Pro đang giữ.
- Bộ lọc người dùng nằm ở `filterConfig.filters` của `report.json` (2 thẻ), `page.json` (1 thẻ, trang `d4_chinhanh`), `visual.json` (1 thẻ). Thẻ Categorical Nhom6: `{name, field, type:"Categorical", filter:{Version:2, From:[{Name,Entity,Type:0}], Where:[{Condition:{Not:{Expression:{In:{Expressions:[…], Values:[[{Literal:{Value:"9999L"}}]]}}}}}]}}`; chưa có mẫu Desktop ghi cho Advanced, Top N, hoặc thẻ chưa có giá trị chọn.

**[SUY ĐOÁN], phải quan sát ở VM-D6** (đọc diff `bookmarks.json`, `*.bookmark.json`, `report.json`, `page.json`, `visual.json` sau mỗi thao tác Desktop rồi lưu):

- Thêm bookmark với từng tổ hợp tuỳ chọn Data, Display, Current page (mặc định bật cả ba; tắt từng cái; "All visuals" và "Selected visuals"): `options` và `explorationState` ghi gì, `version` nào, bộ lọc nào được ghi, visual nào có mặt trong `visualContainers`.
- Cập nhật (Update): ghi lại cả file, giữ `name`, giữ `displayName`; tuỳ chọn có giữ không.
- Đổi tên: chỉ `displayName`. Xoá: bỏ item và xoá file, bookmark cuối cùng thì xoá `bookmarks.json` hay để `items` rỗng.
- Đổi thứ tự (kéo), nhóm bookmark (Group): ghi `children`?
- Filters pane: thêm Basic ở cấp visual, trang, báo cáo; Advanced chữ và số (Và/Hoặc); Top N; bỏ thẻ; "Clear filter" (bỏ `filter` hay xoá thẻ); Lock/Hide thẻ (`isLockedInViewMode`, `isHiddenInViewMode`); vị trí thẻ mới trong `filterConfig.filters`; tên thẻ Desktop sinh (20 hex hay `Filter…`); `howCreated`.
- Desktop ghi lại cả `bookmarks/` khi lưu hay giữ nguyên byte của bookmark không đổi (đã thấy với `visual.json`: Desktop chuẩn hoá cả file khi lưu).
- Áp bookmark có Data trong Desktop: bộ lọc nằm ngoài bookmark có bị đặt lại không.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1 — Thêm bookmark hiển thị/trang và lưu vào file (Ưu tiên: P1)

Người dùng ẩn vài visual (Selection pane), bấm "Thêm bookmark" (tắt Data), lưu; mở lại ở BI Pro hoặc Power BI Desktop thì bookmark còn đó và bấm vào áp đúng hiển thị.

**Vì sao P1**: đây là dạng bookmark Nhom6 thật đã dùng (nút chuyển Giờ × Thứ / Tháng trong năm), cấu trúc đã quan sát; không có bước này thì bookmark thêm trong phiên mất khi đóng app.

**Kiểm thử độc lập**: mở Nhom6, ẩn một visual, thêm bookmark với Data tắt, Display và Current page bật, ⌘S, mở lại: bookmark có trong danh sách, bấm vào ẩn đúng visual và (nếu bật Current page) chuyển đúng trang.

**Kịch bản chấp nhận**:

1. **Cho** chế độ Sửa, **khi** thêm bookmark rồi ⌘S, **thì** `bookmarks.json` có thêm item ở cuối, có file `<name>.bookmark.json` mới với `displayName`, `name` (20 hex), `options` và `explorationState` đúng dạng Desktop ghi cho tổ hợp tuỳ chọn đó; các part khác khớp từng byte.
2. **Cho** bookmark vừa lưu, **khi** mở lại ở BI Pro, **thì** bấm bookmark ẩn/hiện đúng visual (các visual có trong `visualContainers`) và chuyển trang khi không có `suppressActiveSection`.
3. **Cho** bookmark vừa lưu, **khi** mở bằng Power BI Desktop, **thì** không báo lỗi và bookmark áp cho cùng kết quả như BI Pro.

---

### Câu chuyện 2 — Cập nhật, đổi tên, xoá bookmark (Ưu tiên: P1)

Người dùng đổi tên một bookmark, cập nhật nó theo trạng thái hiện tại, xoá một bookmark có sẵn của file, rồi lưu.

**Kiểm thử độc lập**: trên Nhom6 xoá `Bookmark_Q13_MuaVu`, đổi tên `Bookmark_Q13_GioThu`, lưu: file bookmark bị xoá và item bỏ khỏi index, bookmark còn lại có `displayName` mới còn mọi khoá khác như cũ.

**Kịch bản chấp nhận**:

1. **Cho** một bookmark của file, **khi** đổi tên rồi lưu, **thì** chỉ `displayName` đổi trong file đó; `name` (mã) và tên file không đổi.
2. **Cho** một bookmark, **khi** xoá rồi lưu, **thì** file `<name>.bookmark.json` và item trong `bookmarks.json` biến mất; nút action `Bookmark` còn trỏ tới nó giữ nguyên (như Desktop, [SUY ĐOÁN] cần VM-D6) và hiện cảnh báo trước khi xoá.
3. **Cho** một bookmark, **khi** Cập nhật rồi lưu, **thì** file được ghi lại theo trạng thái hiện tại, giữ `name`, `displayName`, tuỳ chọn.
4. **Cho** nhiều bookmark, **khi** kéo đổi thứ tự rồi lưu, **thì** thứ tự `items` trong `bookmarks.json` đổi theo.

---

### Câu chuyện 3 — Bộ lọc người dùng ghi vào file (Ưu tiên: P1)

Người dùng thêm một bộ lọc ở Filters pane (cấp báo cáo, trang hoặc visual), sửa một bộ lọc có sẵn, hoặc bỏ thẻ; lưu; mở lại thì bộ lọc còn và áp số liệu đúng.

**Vì sao P1**: bộ lọc Basic (là/không phải) ở cả ba cấp đã có mẫu Desktop trong Nhom6; thiếu bước ghi thì mọi thao tác Filters pane mất khi đóng app.

**Kiểm thử độc lập**: trên Nhom6 thêm Basic "là" cho một cột ở cấp trang, sửa bộ lọc `fNoUnknownYear` thành NOT IN thêm một giá trị, bỏ một thẻ ở cấp visual, lưu, mở lại: số liệu các visual khớp bản trước khi lưu và `filterConfig` ở `page.json`/`report.json`/`visual.json` đổi đúng một chỗ mỗi file.

**Kịch bản chấp nhận**:

1. **Cho** thẻ Basic mới, **khi** lưu, **thì** `filterConfig.filters` của đúng part (report, page, visual) có thêm thẻ `{name, field, type:"Categorical", filter}` đúng cấu trúc Desktop; thẻ có sẵn không đổi được chép nguyên byte.
2. **Cho** thẻ Advanced hoặc Top N, **khi** lưu, **thì** ghi đúng cấu trúc Desktop nếu đã quan sát ở VM-D6; nếu chưa, bộ lọc đó chỉ sống trong phiên, Filters pane báo "chưa lưu được vào file" và lần lưu vẫn ghi phần còn lại.
3. **Cho** thẻ bị bỏ hoặc "Clear filter", **khi** lưu, **thì** file phản ánh đúng cách Desktop làm (xoá thẻ, hoặc bỏ `filter`).
4. **Cho** file đã lưu, **khi** mở lại ở BI Pro và Power BI Desktop, **thì** không báo lỗi và số liệu cùng bộ lọc khớp nhau.

---

### Câu chuyện 4 — Bookmark có Data (Ưu tiên: P2)

Người dùng đổi slicer và bộ lọc rồi thêm bookmark với Data bật (mặc định của Power BI); bấm bookmark thì khôi phục đúng lựa chọn.

**Vì sao P2**: Data của Desktop ghi trạng thái cả trang (`explorationState` 1.3, bộ lọc từng visual, `activeProjections`, `objects` slicer); chưa biết phần nào bắt buộc nên chỉ làm khi VM-D6 chốt dạng tối thiểu Desktop chấp nhận.

**Kiểm thử độc lập**: đối chiếu với `bookmark-data.pbix`: sau khi chọn trans_type = Credit và năm = 2016, thêm bookmark Data, lưu, mở lại: slicer về đúng lựa chọn khi bấm bookmark ở BI Pro; Desktop áp cho cùng kết quả.

**Kịch bản chấp nhận**:

1. **Cho** bookmark Data, **khi** lưu, **thì** ghi `explorationState` đúng dạng quan sát (bộ lọc cấp báo cáo/visual, lựa chọn slicer ở `objects.merge.general`), hoặc, nếu dạng chưa quan sát đủ, từ chối ghi và giữ bookmark trong phiên kèm thông báo; không bao giờ ghi một dạng đoán.
2. **Cho** bookmark Data đã lưu, **khi** bấm nó, **thì** lựa chọn slicer và bộ lọc khôi phục như lúc thêm, ở cả BI Pro và Desktop.

---

### Câu chuyện 5 — Lưu và mở lại được trong Power BI Desktop (Ưu tiên: P1)

Cả file (bookmark, bộ lọc, các sửa D1 đến D5) lưu một lần bằng ⌘S, kiểm trong bộ nhớ trước khi ghi, mở lại được ở BI Pro và Desktop.

**Kiểm thử độc lập**: xuất `Nhom6_d6.pbix` từ bản sao Nhom6 theo tiêu chí xong; mở trong Power BI Desktop trên VM theo checklist: không báo lỗi, bookmark áp đúng, bộ lọc đúng.

**Kịch bản chấp nhận**:

1. **Cho** bookmark và bộ lọc đã sửa, **khi** ⌘S, **thì** chỉ các part đổi (`bookmarks.json`, `*.bookmark.json`, `report.json`, `page.json`, `visual.json`) được ghi; phần khác khớp từng byte; `SecurityBindings` bỏ như D1 (R13).
2. **Cho** trạng thái sai (bookmark trong index không có file, `targetVisualNames` hay `visualContainers` trỏ visual không có, `activeSection` trỏ trang không có, bộ lọc không parse lại được), **khi** lưu, **thì** kiểm trong bộ nhớ từ chối và file trên đĩa không đổi.
3. **Cho** file dưới `~/Downloads`, **thì** vẫn chỉ đọc (buộc Lưu thành), như D1.

---

### Câu chuyện 6 — Hoàn tác chung một lịch sử (Ưu tiên: P2)

Mỗi thao tác bookmark (thêm, cập nhật, đổi tên, xoá, đổi thứ tự, đổi tuỳ chọn) và mỗi lần sửa bộ lọc là đúng một bước ⌘Z/⇧⌘Z, chung lịch sử với D1 đến D5.

**Kiểm thử độc lập**: xoá một bookmark rồi sửa một bộ lọc rồi di chuyển một visual; ⌘Z ba lần đưa về trạng thái ban đầu theo đúng thứ tự; ⌘S sau đó không thay đổi file.

**Kịch bản chấp nhận**:

1. **Cho** thao tác bookmark hoặc bộ lọc, **khi** ⌘Z, **thì** về đúng trạng thái trước; ⇧⌘Z làm lại.
2. **Cho** xoá bookmark rồi ⌘Z, **thì** bookmark hiện lại ở đúng vị trí; lưu rồi ghi lại như trước khi xoá.

### Trường hợp biên

- Bookmark trỏ trang đã xoá (D5 gỡ khi xoá trang); bookmark có `targetVisualNames` chứa visual đã xoá (D1 R14 đã bỏ khỏi `visualContainers`; `targetVisualNames` giữ nguyên như Desktop).
- Bookmark Display-only có `suppressActiveSection` hay không: theo tuỳ chọn Current page; "Selected visuals" (`applyOnlyToTargetVisuals`) chỉ tính nếu quan sát được.
- Xoá bookmark cuối cùng: `bookmarks.json` còn hay bị xoá ([SUY ĐOÁN], VM-D6).
- Bookmark nhóm (`children`) và bookmark mồ côi trên đĩa nhưng không có trong index: giữ nguyên, không đụng.
- Tên bookmark trùng, rỗng, hay quá dài: từ chối kèm lý do; mã bookmark mới (20 hex) không trùng mã nào có sẵn.
- Thẻ Basic mà bộ lọc chưa chọn giá trị (= Tất cả): không ghi `filter` nếu Desktop không ghi (kiểm VM-D6).
- Cột của bộ lọc đã bị bỏ khỏi mô hình, bộ lọc cấp visual của visual đã xoá, thẻ measure cấp visual không có chỗ ghi đã quan sát: từ chối ở khâu kiểm.
- Báo cáo định dạng cũ (`Report/Layout`): bookmark và bộ lọc chỉ-đọc, như D1.
- Chế độ Xem chỉ để xem (quyết định của người dùng 2026-11-11): thêm, cập nhật, đổi tên, xoá, đổi thứ tự bookmark và sửa bộ lọc ở Filters pane bị mờ kèm lý do; bấm bookmark để áp vẫn được (áp là xem, không đổi file); Filters pane vẫn hiện các thẻ để đọc. Chỉ khi bật Sửa (⌘E) mới dùng được các thao tác sửa.

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

- **FR-001**: Thêm bookmark (Data, Display, Current page tuỳ chọn) PHẢI được ghi khi lưu: thêm item vào cuối `bookmarks.json` và file `<name>.bookmark.json` mới đúng cấu trúc Desktop cho tổ hợp tuỳ chọn đó; mã 20 hex không trùng.
- **FR-002**: Đổi tên PHẢI chỉ đổi `displayName`; xoá PHẢI bỏ item và file; cập nhật PHẢI ghi lại file theo trạng thái hiện tại giữ `name`; đổi thứ tự PHẢI đổi thứ tự `items`.
- **FR-003**: Bookmark có Data chỉ được ghi khi dạng tối thiểu Desktop chấp nhận đã quan sát (VM-D6); nếu chưa, bookmark giữ trong phiên và báo rõ, không ghi đoán.
- **FR-004**: Bộ lọc Basic người dùng thêm, sửa, bỏ ở cấp báo cáo, trang, visual PHẢI ghi vào `filterConfig.filters` của part tương ứng bằng ghép byte; thẻ không đổi giữ nguyên byte.
- **FR-005**: Bộ lọc Advanced và Top N chỉ được ghi khi cấu trúc Desktop ghi đã quan sát (VM-D6); chưa quan sát thì giữ trong phiên và báo rõ.
- **FR-006**: Mọi thao tác bookmark và mỗi lần sửa bộ lọc PHẢI là đúng một bước hoàn tác, chung một lịch sử với D1 đến D5 (gộp sửa liên tiếp cùng một thẻ thành một bước).
- **FR-007**: Lưu (⌘S, ⇧⌘S) PHẢI đi qua đường lưu của D1: dựng và kiểm trong bộ nhớ (mọi bookmark trong index có file, mọi `targetVisualNames` và `visualContainers` trỏ visual có thật, `activeSection` trỏ trang có thật, mọi thẻ lọc parse lại được), ghi file tạm, mở lại, rồi thay; chỉ part đổi được ghi, phần khác khớp từng byte; `SecurityBindings` bỏ như D1.
- **FR-008**: Xoá visual (D1) PHẢI bỏ nó khỏi `visualContainers` của mọi bookmark (`targetVisualNames` của bookmark có sẵn giữ nguyên như Desktop, D1 R14; bookmark BI Pro ghi chỉ trỏ visual có thật); xoá trang (D5) tiếp tục gỡ bookmark trỏ trang đó; xoá bookmark không làm hỏng nút action `Bookmark` trỏ tới (giữ nguyên liên kết, như Desktop nếu VM-D6 xác nhận).
- **FR-009**: File đã lưu PHẢI mở lại được ở BI Pro (bookmark còn, áp đúng; bộ lọc còn, số liệu khớp) và ở Power BI Desktop (không báo lỗi, bookmark và bộ lọc áp giống BI Pro).
- **FR-010**: Báo cáo định dạng cũ: bookmark và bộ lọc không lưu được, báo lý do. Chế độ Xem: các thao tác sửa bookmark và bộ lọc bị mờ kèm lý do, chỉ áp bookmark được; chế độ Xem không bao giờ làm bẩn file.
- **FR-011**: Không file nào dưới `~/Downloads` bị ghi; golden Phase B/C và các test D1 đến D5 PHẢI vẫn qua.

### Thực thể chính

- **Bookmark (trong file)**: mã (`name`), tên hiển thị, tuỳ chọn (Data, Display, Current page, visual đích), `explorationState` (trang, bộ lọc, trạng thái visual).
- **Bản ghi bookmark người dùng**: `UserBookmark` (phiên), sẽ có "đã lưu / chưa lưu vào file" theo dạng ghi được.
- **Thẻ lọc**: cấp (báo cáo, trang, visual), tên, trường, loại (Categorical, Advanced, TopN), điều kiện; `UserFilter` trong phiên.
- **Bản thay đổi bookmark/lọc**: bước hoàn tác và phần ghép byte cho `bookmarks/`, `report.json`, `page.json`, `visual.json`.

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: Trên Nhom6 thêm một bookmark Display + Current page, đổi tên, xoá một bookmark có sẵn, thêm một bộ lọc cấp trang và sửa một bộ lọc cấp visual, hoàn tác từng bước, lưu: file mở lại ở BI Pro và Power BI Desktop không báo lỗi, bookmark áp đúng và bộ lọc cho cùng số liệu (kiểm bằng checklist VM).
- **SC-002**: Với mọi thao tác không đổi bookmark hay bộ lọc, 100% part khác khớp từng byte với file gốc; mỗi thao tác chỉ đổi đúng các part liên quan.
- **SC-003**: Lưu một báo cáo cỡ Nhom6 sau các thao tác trên trong dưới 1 giây (D1 đạt 0,22 s).
- **SC-004**: Mỗi thao tác bookmark và sửa bộ lọc ghi vào bộ nhớ trong dưới 100 ms (không kể truy vấn vẽ lại visual).
- **SC-005**: 0 trường hợp ghi một cấu trúc bookmark hay bộ lọc chưa quan sát: dạng chưa quan sát bị từ chối kèm lý do (kiểm bằng test cố ghi Advanced/Top N/Data khi chưa có mẫu).
- **SC-006**: Golden Phase B/C (30 + 72 truy vấn visual) và toàn bộ test D1 đến D5 vẫn qua.

## Giả định

- Làm theo quy trình D1 đến D5: Spec Kit với 3 chỗ dừng duyệt; một buổi quan sát VM-D6 chốt các [SUY ĐOÁN] trước khi code phần ghi tương ứng.
- Chỉ ghi những dạng đã quan sát: Display + Current page (mẫu Nhom6), Basic Categorical (mẫu Nhom6). Data, Advanced, Top N, nhóm bookmark, "Selected visuals" chờ VM-D6; trong lúc đó chúng sống trong phiên, có thông báo rõ.
- Hoàn tác dùng ảnh chụp như D1 đến D5; trạng thái bookmark và bộ lọc người dùng nhập vào ảnh chụp.
- Nút action `Bookmark` mới và Selection pane nhiều lớp ngoài phạm vi; chỉ áp bookmark có sẵn.
- Ngoài phạm vi: Edit interactions, nhóm bookmark (nếu VM-D6 chưa chốt), bookmark cho visual trong nhóm, theme, định dạng trang, báo cáo định dạng cũ (`Report/Layout`), tầng T2/T3, và mọi thuộc tính chưa quan sát.
