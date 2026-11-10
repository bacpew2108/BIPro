# Đặc tả tính năng: D2, sửa trường dữ liệu của visual bằng Build pane và lưu `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng)

**Ngày tạo**: 2026-11-10

**Trạng thái**: Nháp, chờ duyệt

**Đầu vào**: "D2-build-pane-field-well: lát cắt thứ hai của Phase D (`docs/BIPRO_BUILD_PLAN.md` mục Phase D, sau D1 ở `specs/002-d1-canvas-luu-t1/`): sửa dữ liệu của visual đã có trên trang (không tạo visual mới) bằng Build pane."

Cấp trên: `docs/BIPRO_BUILD_PLAN.md` (Phase D), `docs/PHASE_C_PLAN.md` (engine và truy vấn visual), `specs/002-d1-canvas-luu-t1/` (lưu T1, hoàn tác, chế độ Sửa). Mâu thuẫn thì sửa `docs/` trước.

## Quan sát Power BI

Mục nào là [SUY ĐOÁN] thì chưa có quan sát hoặc tài liệu; phải kiểm ở bước plan hoặc bằng buổi quan sát trên VM (VM-D2) trước khi code phần đó.

**Đã quan sát trong file thật** (`Nhom6_work.pbix`, định dạng PBIR, 171 trường trong các visual):

- Trường của một visual nằm ở `visual.query.queryState.<tên ô>.projections[]`. Tên ô trong Nhom6: `Values` (card, slicer, pivotTable, treemap), `Category`, `Y`, `Y2`, `Series`, `Tooltips` (biểu đồ), `Rows`, `Columns` (matrix), `Group` (treemap).
- Mỗi phần tử `projections[]` có `field` (kiểu `Column`, `Measure` hoặc `HierarchyLevel`, trỏ tới bảng và tên), `queryRef` (dạng `<Bảng>.<Tên>`; hierarchy là `<Bảng>.<Hierarchy>.<Cấp>`), `nativeQueryRef` (tên ngắn), có thể có `displayName` (tên đổi riêng cho visual) và `active`.
- Trong Nhom6 **không có** trường nào dùng phép gộp (không có `Aggregation`): mọi trường số đã là measure. Cách Power BI Desktop ghi một cột số được thả vào ô giá trị (Sum, Average…) chưa quan sát được.
- Bố cục ô đã được BI Pro biết cho từng loại visual (nhãn ô tiếng Việt trong `VisualCatalog`); Build pane hiện tại chỉ hiển thị, chưa sửa được.
- Từ D1: BI Pro lưu T1 bằng ghép byte, bỏ `SecurityBindings` khi sửa phần báo cáo (Power BI Desktop từ chối file nếu giữ nó: `specs/002-d1-canvas-luu-t1/research.md` R13); hoàn tác theo ảnh chụp `LayoutEditor`; Power BI Desktop ghi toạ độ số thực và tự nâng `$schema` của visual khi sửa, và vẫn mở file do BI Pro ghi (R14).

**Hành vi chuẩn của Power BI Desktop cần theo (kiến thức chung, chưa quan sát trên VM)**:

- [SUY ĐOÁN] Thả cột số vào ô giá trị tạo trường có phép gộp mặc định là Sum; cột văn bản thả vào ô giá trị mặc định Count (hoặc Count distinct); measure không có phép gộp. Cột ngày vào ô giá trị mặc định Earliest/Latest, và vào ô trục thì có cấp ngày.
- [SUY ĐOÁN] Cấu trúc ghi cho trường có phép gộp: `field` kiểu `Aggregation` (có `Expression` là cột và `Function` là mã số), `queryRef` dạng `Sum(Bảng.Cột)`, `nativeQueryRef` dạng `Sum of Cột`. Mã số của từng phép gộp phải xác nhận.
- [SUY ĐOÁN] Đổi tên trong visual ("Rename for this visual") chỉ thêm hoặc đổi `displayName` của trường; không đổi `queryRef`.
- [SUY ĐOÁN] Bỏ một trường khỏi ô thì visual vẽ lại với trường còn lại; nếu trường đó còn được nhắc ở nơi khác trong `visual.json` (sắp xếp `query.sortDefinition`, bộ lọc cấp visual trong `filterConfig`, định dạng có điều kiện trong `objects`) thì Desktop xử lý các nơi đó theo quy tắc riêng.
- [SUY ĐOÁN] Mỗi ô chỉ nhận loại trường phù hợp (ví dụ ô Chú giải không nhận measure, ô giá trị nhận measure và cột có phép gộp); một số ô chỉ nhận một trường (ví dụ slicer, ô Chú giải của biểu đồ).

**Cần buổi quan sát trên VM** (bạn làm tay, ngắn, ghi vào `docs/phase-d-evidence/vm-d2/`; mình chuẩn bị file và danh sách việc như VM-D1): (1) thả cột số, cột văn bản, cột ngày, measure vào ô giá trị của card và biểu đồ cột rồi lưu: xem `visual.json` ghi phép gộp, `queryRef`, `nativeQueryRef` ra sao; (2) đổi phép gộp qua menu của trường; (3) bỏ trường đang dùng làm sắp xếp, làm bộ lọc cấp visual: xem `sortDefinition` và `filterConfig` đổi thế nào; (4) đổi thứ tự trường trong ô và chuyển trường giữa hai ô; (5) đổi tên hiển thị trong visual. Nếu chưa có quan sát, bản đầu chỉ làm phần đã có dữ liệu (thêm, bỏ, đổi thứ tự, chuyển ô với measure và cột đã quan sát) và ghi rõ phần phép gộp chưa làm.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1 — Thêm và bỏ trường của visual (Ưu tiên: P1)

Người dùng chọn một visual trên trang (ở chế độ Sửa), mở Build pane, thấy các ô trường đúng với loại visual. Người dùng kéo một trường từ pane Dữ liệu vào một ô (hoặc dùng menu "Thêm trường" của ô), hoặc bỏ một trường khỏi ô; visual vẽ lại ngay với số liệu mới.

**Vì sao P1**: đây là lõi của "sửa dữ liệu của visual"; không có nó thì Build pane chỉ để xem.

**Kiểm thử độc lập**: mở Nhom6, chọn biểu đồ cột ở trang D1, thêm một measure vào ô Trục Y (hoặc bỏ một measure), thấy biểu đồ đổi theo và số khớp với truy vấn DAX tương ứng. Chưa cần lưu.

**Kịch bản chấp nhận**:

1. **Cho** một visual đang chọn, **Khi** mở Build pane, **Thì** các ô hiện đúng theo loại visual, mỗi ô liệt kê các trường hiện có theo thứ tự trong file, và ô trống có chỗ để thả hoặc thêm.
2. **Cho** một trường trong pane Dữ liệu, **Khi** kéo thả vào một ô hợp lệ của visual đang chọn, **Thì** trường được thêm vào cuối ô và visual vẽ lại ngay.
3. **Cho** một ô không nhận loại trường đó (ví dụ measure vào ô Chú giải), **Khi** thả, **Thì** không thêm, ô báo không nhận, trạng thái visual không đổi.
4. **Cho** một trường trong một ô, **Khi** bỏ nó (nút bỏ hoặc menu), **Thì** trường biến mất khỏi ô và visual vẽ lại; nếu ô bắt buộc không còn trường nào, visual hiện trạng thái trống thay vì sập.
5. **Cho** ô chỉ nhận một trường (ví dụ slicer), **Khi** thả trường thứ hai, **Thì** trường mới thay trường cũ.
6. **Cho** không chọn visual nào, **Khi** mở Build pane, **Thì** hiện thông báo chọn một visual và không thể thả trường.

---

### Câu chuyện 2 — Lưu thay đổi trường và mở lại được trong Power BI Desktop (Ưu tiên: P1)

Người dùng bấm Cmd+S sau khi sửa trường. File ghi ra mở lại trong BI Pro thấy đúng các trường và số liệu đã sửa, và mở trong Power BI Desktop cũng vẽ cùng số.

**Vì sao P1**: Phase D chỉ "xong" khi file lưu ra dùng được ở cả hai nơi (như D1).

**Kiểm thử độc lập**: sửa trường của một visual trên trang Nhom6, Cmd+S, mở lại: các trường giữ nguyên. Bạn mở file trong Power BI Desktop trên VM theo `CHECKLIST.md`.

**Kịch bản chấp nhận**:

1. **Cho** thay đổi trường chưa lưu, **Khi** Cmd+S, **Thì** chỉ `visual.json` của các visual đã sửa đổi nội dung; mọi phần khác giữ nguyên từng byte, trừ `SecurityBindings` và dòng liên quan trong `[Content_Types].xml` (xem D1, R13).
2. **Cho** file đã lưu, **Khi** mở lại trong BI Pro, **Thì** các ô có đúng các trường, thứ tự và tên hiển thị như trước lúc lưu.
3. **Cho** file đã lưu, **Khi** mở trong Power BI Desktop, **Thì** không báo lỗi, các ô hiện đúng trường, và số liệu visual khớp với số trong BI Pro.
4. **Cho** một visual không bị sửa, **Khi** lưu, **Thì** `visual.json` của nó giữ nguyên từng byte.
5. **Cho** thay đổi trường kết hợp với thay đổi bố cục của D1 trong cùng phiên, **Khi** lưu, **Thì** cả hai ghi đúng.

---

### Câu chuyện 3 — Hoàn tác và làm lại chung với D1 (Ưu tiên: P1)

Cmd+Z và Cmd+Shift+Z hoàn tác và làm lại mọi thao tác sửa trường, chung một lịch sử với thao tác bố cục của D1, theo thứ tự đã làm.

**Vì sao P1**: sửa mà không hoàn tác được thì không dùng được.

**Kiểm thử độc lập**: thêm một trường, dời một visual, bỏ một trường, rồi Cmd+Z ba lần: về đúng trạng thái đầu, mỗi lần một bước; Cmd+Shift+Z đi lại đúng.

**Kịch bản chấp nhận**:

1. **Cho** nhiều thao tác sửa trường và bố cục đan xen, **Khi** hoàn tác từng bước, **Thì** từng bước quay lại trạng thái ngay trước đó, visual vẽ lại đúng.
2. **Cho** đã hoàn tác về trạng thái lúc mở, **Khi** xem tiêu đề cửa sổ, **Thì** không còn dấu "đã sửa" (như D1).
3. **Cho** một thao tác kéo thả trường, **Khi** hoàn tác, **Thì** một lần Cmd+Z hoàn tác cả thao tác (một bước, không nhiều).

---

### Câu chuyện 4 — Đổi thứ tự trường và chuyển trường giữa các ô (Ưu tiên: P2)

Người dùng kéo một trường lên xuống trong cùng ô để đổi thứ tự, hoặc kéo sang một ô khác của cùng visual (ví dụ từ ô Trục Y sang ô Trục Y phụ).

**Vì sao P2**: hay dùng nhưng không chặn việc thêm/bỏ.

**Kiểm thử độc lập**: trên biểu đồ combo của Nhom6, chuyển một measure từ ô cột sang ô đường; biểu đồ vẽ lại đúng (measure thành đường).

**Kịch bản chấp nhận**:

1. **Cho** ô có từ hai trường trở lên, **Khi** kéo một trường lên hoặc xuống, **Thì** thứ tự đổi và visual vẽ lại theo thứ tự đó (thứ tự cột, màu, hàng).
2. **Cho** một trường trong ô này, **Khi** kéo sang ô khác hợp lệ, **Thì** nó rời ô cũ, vào ô mới, visual vẽ lại.
3. **Cho** ô đích không nhận loại trường đó, **Khi** thả, **Thì** trường trở về chỗ cũ, không mất.

---

### Câu chuyện 5 — Phép gộp và đổi tên hiển thị (Ưu tiên: P2)

Người dùng thả một cột số vào ô giá trị: trường có phép gộp mặc định. Mở menu của trường đổi phép gộp (Sum, Average, Min, Max, Count, Count distinct). Người dùng cũng đổi tên hiển thị của một trường riêng cho visual đó.

**Vì sao P2**: cần để dùng cột số trực tiếp (không phải tạo measure), nhưng Nhom6 không có mẫu nên cần quan sát trước (VM-D2).

**Kiểm thử độc lập**: thả một cột số của bảng `Fact_Transaction` vào card, thấy tổng; đổi sang Average, thấy số đổi và khớp với truy vấn DAX (`AVERAGE`). Đổi tên hiển thị, thấy tiêu đề đổi trong visual.

**Kịch bản chấp nhận**:

1. **Cho** cột số được thả vào ô giá trị, **Khi** thả, **Thì** trường có phép gộp mặc định theo quan sát Desktop, nhãn trường hiện tên phép gộp, và visual vẽ lại bằng giá trị đã gộp.
2. **Cho** trường có phép gộp, **Khi** đổi sang phép gộp khác trong danh sách hợp lệ cho kiểu dữ liệu, **Thì** visual vẽ lại; phép gộp không hợp lệ với kiểu (ví dụ Sum của văn bản) không hiện trong menu.
3. **Cho** measure, **Khi** mở menu trường, **Thì** không có mục phép gộp.
4. **Cho** một trường, **Khi** đổi tên hiển thị, **Thì** tên mới hiện trong visual và Build pane, và được lưu; bỏ trống tên thì quay về tên gốc.

---

### Trường hợp biên

- Trường bị bỏ khỏi ô nhưng còn được nhắc ở nơi khác trong `visual.json` (sắp xếp, bộ lọc cấp visual, định dạng có điều kiện): file lưu ra KHÔNG ĐƯỢC chứa tham chiếu tới trường không còn tồn tại (Power BI Desktop có thể từ chối); cách xử lý từng loại tham chiếu theo quan sát Desktop (VM-D2), trước đó thì chặn việc bỏ và báo rõ lý do.
- Visual có trường hierarchy hoặc cấp drill: giữ nguyên, chỉ cho bỏ hoặc đổi thứ tự cả trường, chưa cho thêm hierarchy mới (ngoài phạm vi).
- Trường trỏ tới bảng hoặc cột không còn trong mô hình: hiện ở trạng thái lỗi, không làm sập; vẫn bỏ được.
- Thêm cùng một trường hai lần vào một ô: theo quy tắc của Desktop (cho phép hoặc báo trùng), quan sát ở VM-D2.
- Nhiều visual được chọn cùng lúc: Build pane chỉ sửa khi chọn đúng một visual; chọn nhiều thì thông báo.
- Hoàn tác sau khi đã lưu: vẫn hoàn tác được trong phiên; lưu lại ghi trạng thái mới (như D1).
- Visual trong nhóm (`parentGroupName`) hoặc báo cáo định dạng cũ (`Report/Layout`): chưa sửa được trường, báo rõ (như D1).
- Visual kiểu chưa hỗ trợ vẽ trong BI Pro: Build pane vẫn sửa được trường theo bố cục ô nếu biết loại; nếu không biết, chỉ hiển thị và báo chưa sửa được.
- Bookmark nhắc tới visual đã đổi trường: bookmark không bị đổi (ghi bookmark là lát sau).

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

**Build pane**

- **FR-001**: Khi chọn đúng một visual ở chế độ Sửa, Build pane PHẢI hiện các ô trường theo loại visual (cùng bố cục ô như Power BI Desktop), mỗi ô liệt kê trường hiện có theo thứ tự trong file.
- **FR-002**: Hệ thống PHẢI cho thêm một trường vào ô bằng kéo thả từ pane Dữ liệu và bằng menu của ô; ô PHẢI từ chối loại trường không hợp lệ và báo lý do.
- **FR-003**: Hệ thống PHẢI cho bỏ một trường khỏi ô.
- **FR-004**: Hệ thống PHẢI cho đổi thứ tự trường trong ô và chuyển trường giữa các ô hợp lệ của cùng visual.
- **FR-005**: Ô chỉ nhận một trường PHẢI thay trường cũ khi thả trường mới.
- **FR-006**: Trường cột số thả vào ô giá trị PHẢI có phép gộp mặc định; người dùng PHẢI đổi được giữa các phép gộp hợp lệ cho kiểu dữ liệu (Sum, Average, Min, Max, Count, Count distinct). Measure PHẢI không có phép gộp. [SUY ĐOÁN: danh sách và mặc định theo kiến thức chung, xác nhận ở VM-D2; phần ghi phép gộp làm sau VM-D2 (D2b), xem Giả định]
- **FR-007**: Hệ thống PHẢI cho đổi tên hiển thị của một trường riêng cho visual đang chọn, và cho trả về tên gốc.

**Vẽ lại và hoàn tác**

- **FR-008**: Sau mỗi thay đổi trường, visual PHẢI vẽ lại bằng truy vấn sinh lại từ trường mới qua engine DAX hiện có (không thêm đường tính thứ hai).
- **FR-009**: Mọi thao tác sửa trường PHẢI hoàn tác và làm lại được, chung lịch sử với D1; một cử chỉ (một lần thả) là một bước.
- **FR-010**: Thay đổi chưa lưu PHẢI hiện trên tiêu đề cửa sổ và trong lời hỏi lưu lúc đóng, như D1.

**Lưu (tầng T1)**

- **FR-011**: Khi lưu, hệ thống PHẢI ghi lại `visual.query.queryState` của các visual đã sửa theo đúng cấu trúc Power BI Desktop ghi (`field`, `queryRef`, `nativeQueryRef`, `displayName`, `active`) và chỉ thay nội dung các `visual.json` đó; mọi phần khác giữ nguyên như D1 (kể cả việc bỏ `SecurityBindings`).
- **FR-012**: Phần của `visual.json` ngoài `queryState` mà không liên quan tới trường PHẢI giữ nguyên từng byte.
- **FR-013**: Hệ thống PHẢI cập nhật hoặc loại bỏ mọi tham chiếu trong `visual.json` tới trường đã bỏ (sắp xếp, bộ lọc cấp visual, định dạng có điều kiện) theo cách Power BI Desktop làm, để file lưu ra mở được. Chưa xác định cách làm của Desktop cho loại tham chiếu nào thì chặn việc bỏ trường đó và báo rõ.
- **FR-014**: Trước khi ghi, hệ thống PHẢI đọc lại file đã dựng và kiểm khớp (các ô, trường, thứ tự, tên hiển thị) với trạng thái trong bộ nhớ, rồi mới thay file đích; các bước an toàn khác (sao lưu, chặn ghi vào `~/Downloads`, hỏi khi file đích đã đổi) như D1.
- **FR-015**: Visual không đổi trường PHẢI giữ nguyên từng byte sau khi lưu.

**Chất lượng**

- **FR-016**: Golden Phase B/C PHẢI vẫn khớp; truy vấn sinh ra cho visual chưa sửa PHẢI không đổi.
- **FR-017**: Với visual đã sửa trường, truy vấn sinh ra PHẢI trùng văn bản truy vấn Power BI Desktop sinh cho cùng cấu hình khi đã có mẫu để so (golden của buổi VM-D2).

### Thực thể chính

- **Trường (Field)**: tham chiếu tới cột, measure hoặc cấp hierarchy của mô hình, thuộc một ô của một visual, có thể có phép gộp (cột số) và tên hiển thị riêng.
- **Ô (Well)**: một ngăn của visual (Trục X, Giá trị, Chú giải…) có danh sách trường theo thứ tự, loại trường được nhận, và số trường tối đa.
- **Phép gộp (Aggregation)**: cách tính một cột số khi dùng làm giá trị (Sum, Average, Min, Max, Count, Count distinct).
- **Cấu hình trường của visual (queryState)**: tập hợp các ô và trường của một visual, phần đọc và ghi vào `visual.json`.

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: Trên Nhom6, thêm, bỏ, đổi thứ tự, chuyển ô và đổi tên hiển thị trên ít nhất 4 loại visual khác nhau (card, biểu đồ cột, biểu đồ combo, matrix): visual vẽ lại đúng và số liệu khớp với truy vấn DAX tương ứng ở 100% các lần thử.
- **SC-002**: Lưu rồi mở lại trong BI Pro: các ô, trường, thứ tự, tên hiển thị giống hệt trước khi lưu ở 100% visual đã sửa.
- **SC-003**: File đã lưu mở được trong Power BI Desktop (bạn kiểm tay trên VM), các ô hiện đúng trường, và số liệu của visual đã sửa khớp với BI Pro.
- **SC-004**: Visual không sửa, trang không sửa và mô hình dữ liệu khớp từng byte với file gốc (ngoài `SecurityBindings` như D1).
- **SC-005**: Thả hoặc bỏ một trường thì visual hiện trạng thái mới (bố cục ô, nhãn trường) ngay lập tức và vẽ lại xong dưới 150 ms với visual thường (card, slicer, biểu đồ đơn) và dưới 1 giây với visual nặng nhất của Nhom6 (mốc đo trước khi sửa: 426–514 ms nạp lạnh cho combo và matrix, xem `measurements.md`); lưu sau khi sửa trường mất dưới 1 giây.
- **SC-006**: 30/30 golden Phase B và các golden Phase C vẫn khớp; `swift test` không có test nào trượt thêm.
- **SC-007**: Hoàn tác về trạng thái lúc mở sau một chuỗi tuỳ ý thao tác sửa trường và bố cục luôn trả visual và file về đúng trạng thái đầu (kiểm bằng test tự động trên chuỗi ngẫu nhiên).
- **SC-008**: Người dùng làm được chuỗi "chọn visual → thêm một measure vào Trục Y → lưu thành → mở lại trong Power BI Desktop" mà không phải đọc hướng dẫn.

## Giả định

- Chỉ sửa trường của visual đã có; chưa tạo visual mới và ribbon Insert, chưa đổi loại visual, chưa Format pane, chưa thêm/xoá/đổi tên trang, chưa ghi bookmark và bộ lọc người dùng vào file, chưa sửa Filters pane, chưa hierarchy và drill mới, chưa tạo measure/cột mới, chưa tầng T2/T3 (các lát sau của Phase D, và Phase E, F).
- Bố cục ô theo loại visual lấy từ bảng ô đã có trong BI Pro; loại visual nào bảng chưa có thì Build pane chỉ hiển thị.
- Danh sách trường lấy từ pane Dữ liệu hiện có (mô hình đã nạp); bảng ẩn và trường ẩn theo hành vi hiện tại của pane.
- Chế độ Sửa (⌘E), chọn visual, lưu (Cmd+S, Lưu thành), sao lưu, hỏi lưu khi đóng, hoàn tác: dùng lại từ D1, không làm lại.
- Phép gộp và cấu trúc ghi của chúng là [SUY ĐOÁN] cho đến khi có mẫu từ VM-D2; chưa có mẫu thì chưa làm phần ghi phép gộp (FR-006 chỉ làm phần đã quan sát).
- Test trên VM Windows 11 do bạn làm tay; mình chuẩn bị file trong `build/d-out/` và `CHECKLIST.md`.
- Không thêm thư viện ngoài.
