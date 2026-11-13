# Đặc tả tính năng: D5, quản lý trang (thêm, đổi tên, đổi thứ tự, nhân bản, xoá) và lưu `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng)

**Ngày tạo**: 2026-11-10

**Trạng thái**: Nháp, chờ duyệt

**Đầu vào**: "D5-quan-ly-trang: lát cắt thứ năm của Phase D (`docs/BIPRO_BUILD_PLAN.md` mục Phase D, sau D1 canvas ở `specs/002-d1-canvas-luu-t1/`, D2 ở `specs/003-d2-build-pane-field-well/`, D3 ở `specs/004-d3-them-visual-doi-loai/`; D4 Format pane làm sau): thêm, xoá, đổi tên, nhân bản và đổi thứ tự trang của báo cáo, rồi lưu `.pbix` tầng T1."

Cấp trên: `docs/BIPRO_BUILD_PLAN.md` (Phase D), `specs/002-d1-canvas-luu-t1/` (lưu T1, hoàn tác theo ảnh chụp, nhân bản visual, bỏ `SecurityBindings` ở R13), `specs/004-d3-them-visual-doi-loai/` (thêm visual mới, mã mới). Mâu thuẫn thì sửa `docs/` trước.

## Quan sát Power BI

Mục nào là [SUY ĐOÁN] thì chưa có quan sát; phải kiểm bằng buổi quan sát VM-D5 trước khi code phần đó (Claude điều khiển VM khi người dùng cho phép, hoặc người dùng làm tay).

**Đã quan sát trong file thật** (`Nhom6_work.pbix`, định dạng PBIR, 4 trang):

- `Report/definition/pages/pages.json` có `pageOrder` (mảng mã trang, thứ tự tab) và `activePageName` (trang mở khi mở file). Nhom6: `["d1_giaodich","d2_khoanvay","d3_cskh","d4_chinhanh"]`, trang đang mở `d3_cskh`.
- Mỗi trang là thư mục `pages/<mã>/` với `page.json` và `visuals/`. `page.json` có `$schema` (2.1.0), `name` (trùng mã thư mục), `displayName`, `displayOption` (`FitToPage`), `height` (1080), `width` (1920), `objects.background`; trang `d4_chinhanh` có thêm `filterConfig` (4 thẻ lọc) và `pageBinding` loại `Drillthrough` (trang drillthrough, hiện biểu tượng ẩn ở tab). Mã trang của Nhom6 là chữ thường và gạch dưới do tác giả đặt; Desktop tự đặt mã 20 ký tự hex ở các trang BI Pro và Desktop thêm (quan sát khi VM-D3 thêm trang: `e75937a6c80a498eb90d`, tên hiển thị "Page 1", `displayOption` `FitToPage`, 1920×1080, không có `objects`).
- Bookmark là `bookmarks/<tên>.bookmark.json` với `displayName`, `name`, `options`, và `explorationState` có `activeSection` (mã trang) cùng `sections.<mã trang>` (trạng thái của từng trang); `bookmarks/bookmarks.json` liệt kê bookmark theo `name`. Cả 2 bookmark của Nhom6 có `activeSection` và `sections` chỉ gồm `d1_giaodich`.
- Nút điều hướng: trong Nhom6 các nút action dùng `visualLink` loại `Back` hoặc `Bookmark` (trỏ tên bookmark); `pageNavigator` là visual tự liệt kê trang (không lưu mã trang). Nhom6 không có nút loại `PageNavigation`.
- Mô hình trong bộ nhớ: `ReportPage` (id, tên, cỡ, ẩn, `objects`, `visuals`). Từ D1: hoàn tác theo ảnh chụp trang, lưu T1 bằng thêm/bớt part và ghép byte, bỏ `SecurityBindings`. Hiện thanh tab dưới cùng chỉ chọn trang, nút "+" và menu tab chưa làm gì.

**Đã quan sát ở VM-D5 (2026-11-10, `docs/phase-d-evidence/vm-d5/QUAN-SAT.md`)**: thêm trang đặt ở cuối `pageOrder`, mã 20 hex, tên "Page N", thành trang đang mở; đổi tên chỉ sửa `displayName`; kéo tab chỉ sửa `pageOrder`; nhân bản đặt tên "Duplicate of <tên>" ở cuối dãy, mọi visual có mã mới; xoá trang bỏ cả thư mục, **không sửa bookmark** (bookmark mồ côi bấm không làm gì, không lỗi); `activePageName` là trang đang mở khi lưu; menu tab có Duplicate, Rename, Delete, Move to (không có Sang trái/phải). Hai điểm lệch với bản nháp đầu của spec (nhân bản ngay sau trang gốc, tên "<tên> (2)") đã sửa bên dưới theo Desktop.

**[SUY ĐOÁN] còn lại, cần quan sát thêm**:

- Mở lại file đã xoá trang trong Desktop (bookmark mồ côi): trong phiên Desktop không lỗi; chưa kiểm sau khi mở lại.
- Khi Desktop xoá trang mà một nút `PageNavigation` trỏ tới: để nguyên liên kết hỏng, xoá liên kết hay đổi `visualLink`.
- Nhân bản trang có `filterConfig` hoặc `pageBinding` (trang D4): chưa nhân bản thử.
- "Set as landing page" ghi vào đâu.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1 — Thêm, đổi tên, đổi thứ tự trang (Ưu tiên: P1)

Người dùng ở chế độ Sửa (⌘E) muốn thêm một trang trống, đặt tên lại cho nó và kéo nó tới đúng chỗ trong dãy tab.

**Vì sao P1**: không thêm được trang thì không dựng được báo cáo mới; Phase D chỉ "xong" khi sửa được cả trang.

**Kiểm thử độc lập**: mở Nhom6, thêm trang, đổi tên, kéo sang đầu dãy; thứ tự tab và tên hiện đúng, trang mới mở sẵn và trống, hoàn tác từng bước đưa về trạng thái trước.

**Kịch bản chấp nhận**:

1. **Cho** chế độ Sửa đang bật, **khi** bấm nút "+" ở thanh tab, **thì** thêm một trang trống tên "Page N", cỡ 1920×1080 `FitToPage`, ở cuối dãy tab (như Desktop), trang đó thành trang đang mở.
2. **Cho** một trang, **khi** bấm đúp tab (hoặc "Đổi tên" ở menu chuột phải) rồi nhập tên mới và Enter, **thì** tab hiện tên mới, mã trang không đổi; tên rỗng hoặc chỉ có khoảng trắng bị từ chối và giữ tên cũ.
3. **Cho** nhiều trang, **khi** kéo một tab sang vị trí khác (hoặc "Sang trái"/"Sang phải"), **thì** thứ tự tab đổi theo ngay.
4. **Cho** ở chế độ Xem, **thì** các thao tác trên báo cáo không làm đổi trang nào (như D1: ⌘E mới cho sửa), và nút "+" cùng menu sửa bị mờ kèm lý do.

---

### Câu chuyện 2 — Nhân bản trang (Ưu tiên: P1)

Người dùng muốn bắt đầu từ một trang có sẵn: nhân bản trang kèm mọi visual để sửa tiếp.

**Vì sao P1**: cách nhanh nhất để dựng trang mới giống trang cũ, và kiểm lại bộ máy sao visual của D1.

**Kiểm thử độc lập**: nhân bản trang D1 của Nhom6: trang mới có đủ visual cùng vị trí, loại, trường, định dạng, mã visual mới không trùng; số liệu vẽ ra bằng trang gốc.

**Kịch bản chấp nhận**:

1. **Cho** trang D1, **khi** chọn "Nhân bản trang", **thì** có trang mới "Duplicate of D1 · Giao dịch" ở cuối dãy tab với từng visual của trang gốc (mã visual mới), mở sẵn; trang gốc không đổi.
2. **Cho** trang nhân bản, **khi** xem, **thì** số liệu từng visual bằng trang gốc với cùng bộ lọc; nút `Bookmark` trong trang nhân bản vẫn trỏ bookmark của báo cáo (bookmark không được sao).
3. **Cho** trang có `pageBinding` (drillthrough), **khi** nhân bản, **thì** bản sao không mang `pageBinding` (một trang drillthrough thứ hai ở ngoài phạm vi) và báo rõ cho người dùng. [SUY ĐOÁN] Desktop cũng bỏ hay giữ: kiểm ở VM-D5.

---

### Câu chuyện 3 — Xoá trang và dọn chỗ nhắc tới nó (Ưu tiên: P1)

Người dùng xoá một trang không cần nữa; báo cáo không được còn chỗ nào trỏ tới trang đã mất.

**Vì sao P1**: bài học D1, ghi sai (tham chiếu treo) làm Desktop từ chối cả file; xoá trang là chỗ dễ để lại tham chiếu treo nhất.

**Kiểm thử độc lập**: xoá `d1_giaodich` của Nhom6 (có 2 bookmark trỏ tới): lưu, mở lại ở BI Pro và Desktop; không bookmark nào trỏ trang đã mất, Desktop không báo lỗi.

**Kịch bản chấp nhận**:

1. **Cho** nhiều hơn một trang, **khi** chọn "Xoá trang" và xác nhận, **thì** trang và mọi visual của nó biến khỏi báo cáo, trang liền kề (ưu tiên trang bên phải) thành trang đang mở.
2. **Cho** trang cuối cùng của báo cáo, **khi** chọn xoá, **thì** bị từ chối kèm lý do (báo cáo phải còn ít nhất một trang).
3. **Cho** bookmark có `activeSection` hoặc `sections` trỏ tới trang bị xoá, **khi** xoá trang, **thì** bookmark đó bị gỡ khỏi báo cáo (nếu `activeSection` là trang đó; khác Desktop, vốn để bookmark mồ côi không làm gì) hoặc chỉ bỏ phần của trang (nếu chỉ `sections` nhắc tới); danh sách bookmark của báo cáo khớp với file bookmark còn lại; người dùng được báo bookmark nào đã gỡ.
4. **Cho** nút điều hướng (`visualLink` loại `PageNavigation`) trỏ tới trang bị xoá, **khi** xoá, **thì** trang được xoá, nút giữ nguyên (trỏ treo như Desktop, VM-D8) và thông báo kể tên các nút đó. (Sửa 2026-11-13; trước đó thao tác bị chặn vì chưa quan sát.)
5. **Cho** xoá nhầm, **khi** hoàn tác (⌘Z), **thì** trang trở lại đủ visual cùng các bookmark đã gỡ, đúng vị trí cũ trong dãy tab và đúng trang đang mở trước đó.

---

### Câu chuyện 4 — Lưu và mở lại được trong Power BI Desktop (Ưu tiên: P1)

Người dùng lưu báo cáo đã sửa trang và mở lại ở BI Pro và Power BI Desktop.

**Vì sao P1**: tiêu chí xong của cả Phase D là file lưu ra dùng được ở hai nơi (như D1, D2, D3).

**Kiểm thử độc lập**: kịch bản Nhom6 (thêm trang, đổi tên, kéo, nhân bản D1, xoá một trang có bookmark) rồi ⌘S; mở lại bằng `PBIXFile`, so `pageOrder`, tên, số visual; người dùng hoặc Claude (khi được phép) mở file trong Desktop.

**Kịch bản chấp nhận**:

1. **Cho** trang mới, **khi** lưu, **thì** `pages.json` có mã trang trong `pageOrder`, có thư mục `pages/<mã>/page.json` (và `visuals/` của trang nhân bản), các phần khác khớp từng byte (trừ `SecurityBindings` và `[Content_Types].xml` như D1).
2. **Cho** trang bị xoá, **khi** lưu, **thì** thư mục trang không còn trong file, `pageOrder` và `activePageName` không nhắc mã đó, bookmark đã dọn khớp.
3. **Cho** đổi tên hoặc đổi thứ tự, **khi** lưu, **thì** chỉ `page.json` (tên) hoặc `pages.json` (thứ tự) đổi, bằng ghép byte.
4. **Cho** file đã lưu, **khi** mở ở Desktop, **thì** không báo lỗi, tab đúng thứ tự và tên, bookmark còn lại bấm được, trang nhân bản vẽ cùng nội dung.
5. **Cho** file gốc dưới `~/Downloads`, **khi** lưu, **thì** buộc "Lưu thành" (như D1) và file gốc không đổi.

---

### Câu chuyện 5 — Hoàn tác chung một lịch sử (Ưu tiên: P2)

Mỗi thao tác trang là đúng một bước hoàn tác, chung ngăn xếp với kéo/đổi cỡ (D1), trường (D2), visual (D3).

**Vì sao P2**: chạy đúng nhờ bộ máy hoàn tác có sẵn, nhưng phải kiểm với thao tác ở mức báo cáo (thêm/xoá cả trang).

**Kiểm thử độc lập**: xen kẽ thêm trang, kéo visual, thả trường, xoá trang, rồi ⌘Z/⇧⌘Z lần lượt: mỗi bước đảo đúng một thao tác theo thứ tự ngược.

**Kịch bản chấp nhận**:

1. **Cho** chuỗi thao tác hỗn hợp, **khi** hoàn tác từng bước, **thì** từng thao tác (kể cả thêm và xoá trang) được đảo đúng một bước; làm lại đưa về đúng trạng thái.
2. **Cho** hoàn tác về trước khi có sửa, **thì** `isDirty` về false và ⌘S không còn việc.

---

### Trường hợp biên

- Xoá trang đang mở: chọn trang liền kề; `activePageName` chỉ lưu khi người dùng thật sự có đổi trang (không ép).
- Tên trang trùng tên trang khác: cho phép (Desktop cho); chỉ mã là duy nhất.
- Tên trang có ký tự đặc biệt và chữ Việt có dấu, dài tới 100 ký tự: giữ nguyên (dài hơn: từ chối).
- Mã trang mới không bao giờ trùng mã đã có, kể cả mã trang đã xoá trong phiên (phòng khi hoàn tác).
- Trang có bookmark có thể trỏ tới nhiều trang (`sections` nhiều mục): chỉ bỏ phần của trang bị xoá.
- Báo cáo định dạng cũ (`Report/Layout`): chưa sửa được trang (như D1), thao tác trang bị mờ kèm lý do.
- Trang ẩn (`visibility`) và trang drillthrough: xoá, đổi tên, đổi thứ tự được như trang thường.
- Lưu ngay sau thêm trang trống chưa có visual: vẫn ghi `page.json` hợp lệ.
- Mở ở chế độ Xem: không thao tác nào đổi trang.

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

- **FR-001**: Ở chế độ Sửa, người dùng PHẢI thêm được trang trống mới ("Page N", 1920×1080, `FitToPage`) bằng nút "+" ở thanh tab hoặc menu chuột phải tab; trang mới thành trang đang mở.
- **FR-002**: Người dùng PHẢI đổi được tên hiển thị của trang (bấm đúp tab hoặc menu chuột phải); mã trang không đổi; tên rỗng hoặc quá dài bị từ chối kèm lý do.
- **FR-003**: Người dùng PHẢI đổi được thứ tự trang bằng kéo tab hoặc "Sang trái"/"Sang phải" ở menu chuột phải (Desktop chỉ có kéo tab và "Move to"); thứ tự mới là thứ tự tab ngay lập tức.
- **FR-004**: Người dùng PHẢI nhân bản được một trang kèm mọi visual (mã visual mới, vị trí, loại, trường, định dạng giữ nguyên); trang mới có mã mới, tên "Duplicate of <tên>" như Desktop, đặt ở cuối dãy tab; bookmark không được sao; `pageBinding` không được sao và có báo.
- **FR-005**: Người dùng PHẢI xoá được trang (có hỏi xác nhận), trừ trang cuối cùng; sau khi xoá, trang liền kề thành trang đang mở.
- **FR-006**: Xoá trang PHẢI dọn mọi chỗ nhắc tới mã trang: bookmark trỏ trang đó (`activeSection`, `sections`) và `bookmarks.json`; nút `PageNavigation` trỏ tới trang đó chặn thao tác kèm danh sách (cho tới khi VM-D5 chốt cách Desktop xử lý). Sửa 2026-11-13 (VM-D8): Desktop không cảnh báo và để nguyên nút; BI Pro không chặn nữa, chỉ báo nút nào còn trỏ tới trang đã xoá.
- **FR-007**: Mọi thao tác trang PHẢI là đúng một bước hoàn tác, chung một lịch sử với D1, D2, D3; hoàn tác xoá trang phục hồi trang, visual, bookmark và vị trí tab.
- **FR-008**: Lưu (⌘S, ⇧⌘S) PHẢI ghi các thay đổi trang vào `.pbix` ở tầng T1 qua đường lưu của D1: thêm/bớt part trang, sửa `pages.json`, `page.json`, bookmark bằng ghép byte, giữ nguyên mọi phần khác; `SecurityBindings` bỏ như D1 (R13); dựng và kiểm trong bộ nhớ trước khi ghi, file đích còn nguyên nếu lỗi.
- **FR-009**: File đã lưu PHẢI mở lại được ở BI Pro (đủ trang, đúng thứ tự, tên, số visual) và ở Power BI Desktop (không báo lỗi, bookmark còn lại bấm được).
- **FR-010**: Ở chế độ Xem, và với báo cáo định dạng cũ, các thao tác sửa trang PHẢI bị mờ kèm lý do; chế độ Xem không đổi trang nào.
- **FR-011**: Không file nào dưới `~/Downloads` bị ghi; phần chưa sửa của file khớp từng byte.
- **FR-012**: Số liệu và truy vấn của các trang không sửa (golden Phase B/C) PHẢI giữ nguyên; trang nhân bản vẽ cùng số với trang gốc.

### Thực thể chính

- **Trang (`ReportPage`)**: mã (20 hex cho trang mới), tên hiển thị, cỡ, ẩn/không, định dạng nền, danh sách visual, thẻ lọc cấp trang, `pageBinding` (chỉ đọc); vị trí trong dãy tab.
- **Dãy trang (`pageOrder`)** và **trang đang mở (`activePageName`)**: ở `pages.json`.
- **Bookmark**: `activeSection`, `sections.<mã trang>`, mục trong `bookmarks.json`; phụ thuộc trang.
- **Thao tác trang**: thêm, đổi tên, đổi thứ tự, nhân bản, xoá; mỗi cái là một bước hoàn tác.

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: Trên Nhom6 thực hiện đủ chuỗi: thêm 1 trang, đổi tên, kéo lên đầu, nhân bản D1, xoá một trang có 2 bookmark trỏ tới; mỗi thao tác xong trong dưới 1 giây (nhân bản trang 36 visual dưới 1 giây) và thấy ngay trên thanh tab.
- **SC-002**: Hoàn tác từng bước của chuỗi trên đưa lại đúng trạng thái trước (so sánh trang, thứ tự, bookmark), làm lại đưa về đúng trạng thái sau; không bước nào hỏng.
- **SC-003**: Lưu báo cáo sau chuỗi trên mất dưới 1 giây (như D1 đến D3); file lưu mở lại ở BI Pro có đủ trang đúng thứ tự, đúng tên và số visual; mọi phần không sửa khớp byte (trừ `SecurityBindings`, `[Content_Types].xml`).
- **SC-004**: File mở được ở Power BI Desktop (người dùng kiểm hoặc Claude khi được phép): không báo lỗi, đúng thứ tự và tên tab, bookmark còn lại bấm được, trang nhân bản vẽ cùng nội dung như gốc.
- **SC-005**: 0 tham chiếu treo: sau khi xoá trang, không còn tham chiếu tới mã trang đã xoá trong `definition/` (thư mục trang, `pages.json`, bookmark, nút điều hướng trang). Sửa 2026-11-13: chỉ tính chỗ là tham chiếu; chuỗi trùng mã trang ở chỗ khác (tên hiển thị, chữ trong visual) không tính. Sửa lần hai 2026-11-13 (VM-D8): nút điều hướng trỏ trang đã xoá được để nguyên như Desktop, không tính là tham chiếu treo phải dọn.
- **SC-006**: Golden nặng Phase B/C và các test D1, D2, D3 giữ nguyên số qua; file gốc dưới `~/Downloads` không đổi.

## Giả định

- Chỉ dùng khoá đã quan sát trong Nhom6 và trong các file Desktop ghi ở VM-D1 đến VM-D3 (`page.json` 2.1.0, `pages.json` 1.1.0, bookmark 2.1.0); chỗ nào chưa quan sát (mục [SUY ĐOÁN]) thì giữ phương án thận trọng (chặn hoặc không sao chép) cho tới buổi VM-D5.
- Mã trang mới là 20 ký tự hex ngẫu nhiên, như Desktop ghi ở VM-D3 và VM-D5; trang thêm mới đặt ở cuối dãy.
- Trang nhân bản đặt ở cuối dãy và mang tên "Duplicate of <tên>", theo đúng quan sát ở VM-D5.
- Phạm vi: không làm định dạng trang (nền, cỡ, ẩn trang) vì thuộc D4; không tạo trang drillthrough hay `pageBinding` mới; không có tooltip page, nhóm trang; không ghi bookmark mới vào file (D6); Filters pane không ghi vào file; tầng T2/T3 ngoài phạm vi.
- Xoá trang chỉ dọn tham chiếu trong `definition/` (bookmark, `pages.json`); tên trang không được lưu ở nơi khác (`pageNavigator` tự liệt kê).
- Tiếp tục theo quy tắc: hiến pháp (agent không điều khiển VM, trừ khi người dùng cho phép), không thư viện ngoài, không ghi `~/Downloads`.
