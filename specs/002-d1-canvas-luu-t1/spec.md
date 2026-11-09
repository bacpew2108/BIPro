# Đặc tả tính năng: D1, sửa bố cục trang trên canvas và lưu `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng)

**Ngày tạo**: 2026-11-09

**Trạng thái**: Nháp, chờ duyệt

**Đầu vào**: "D1-canvas-luu-t1: lát cắt đầu tiên của Phase D (`docs/BIPRO_BUILD_PLAN.md` mục Phase D): sửa bố cục trang report trên canvas rồi lưu `.pbix` tầng T1 mà Power BI Desktop vẫn mở được."

Cấp trên: `docs/BIPRO_BUILD_PLAN.md` (Phase D), `docs/PHASE_W_PLAN.md` (đường ghi `.pbix`). Mâu thuẫn thì sửa `docs/` trước.

## Quan sát Power BI

Phần này là nền cho các yêu cầu bên dưới. Mục nào là [SUY ĐOÁN] thì chưa có quan sát hoặc tài liệu, phải kiểm ở bước plan hoặc bằng buổi test tay trên VM.

**Đã quan sát trong file thật** (`Nhom6_work.pbix`, định dạng PBIR):

- Mỗi trang là một thư mục `Report/definition/pages/<tên trang>/` có `page.json` (kích thước trang 1920 × 1080, kiểu hiển thị `FitToPage`) và thư mục `visuals/<mã 20 ký tự hex>/visual.json`.
- Vị trí và kích thước của một visual nằm trong `position` của `visual.json`: `x`, `y`, `z`, `width`, `height`, `tabOrder`; đơn vị là điểm ảnh của trang. Ví dụ: một thẻ card nằm ở x = 1594, y = 176, rộng 302, cao 108, z = 24000.
- Thứ tự trang và trang đang mở nằm trong `pages/pages.json` (`pageOrder`, `activePageName`).
- Nhom6 có 2 bookmark. Bookmark có thể nhắc tới visual theo mã (`targetVisualNames`, `hidden`), nên xoá visual có thể để lại tham chiếu treo.
- Từ Phase W: Power BI Desktop mở được file do BI Pro ghi lại không đổi (gate W1, bạn xác nhận) và ghi tầng T1 chỉ thay các phần PBIR, còn `DataModel` chép nguyên byte.

**Hành vi chuẩn của Power BI Desktop cần theo (kiến thức chung, chưa quan sát lại trên VM)**:

- [SUY ĐOÁN] Kéo visual trên canvas thì chỉ đổi `x`, `y`; kéo tay nắm thì đổi `width`, `height` (và `x`, `y` nếu kéo cạnh trái hoặc trên). Có đường gióng và lưới bám khi bật Snap to grid; lưới mặc định của Power BI Desktop có thể không phải 8 px. Giá trị 8 px lấy từ kế hoạch của dự án.
- [SUY ĐOÁN] Visual mới do Cmd+C / Cmd+V hoặc Ctrl+D tạo ra có mã mới, nằm lệch một chút so với bản gốc, và được đặt lên trên cùng.
- [SUY ĐOÁN] Xoá visual bằng phím Delete; Cmd+Z / Cmd+Shift+Z (Ctrl+Z / Ctrl+Y) hoàn tác và làm lại; mỗi thao tác kéo là một bước undo.
- [SUY ĐOÁN] Khi sửa xong, tiêu đề cửa sổ hiện dấu "đã sửa"; đóng cửa sổ hoặc thoát app thì hỏi lưu.

**Cần buổi quan sát trên VM** (bạn làm tay, ngắn, ghi vào `docs/phase-d-evidence/`): (1) kéo, đổi cỡ, nhân bản, xoá một visual rồi lưu: so `visual.json` trước/sau để biết Power BI Desktop đổi những trường nào (đặc biệt `z`, `tabOrder`, tên visual nhân bản, bookmark sau khi xoá visual); (2) lưới và đường gióng mặc định. Nếu chưa có quan sát, bản đầu theo các [SUY ĐOÁN] trên và ghi lại trong file bằng chứng.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1 — Chọn, di chuyển, đổi cỡ visual trên canvas (Ưu tiên: P1)

Người dùng mở báo cáo Nhom6, chọn một visual (hoặc nhiều visual) trên trang, kéo đến chỗ khác, kéo tay nắm để đổi cỡ. Vị trí và kích thước bám vào lưới 8 px.

**Vì sao P1**: đây là phần cốt lõi của "sửa báo cáo"; không có nó thì lưu không có gì để lưu.

**Kiểm thử độc lập**: mở Nhom6, kéo một thẻ card sang phải 40 px, đổi cỡ một biểu đồ; trên màn hình visual ở đúng chỗ mới, số liệu và lọc chéo vẫn chạy như trước. Chưa cần lưu.

**Kịch bản chấp nhận**:

1. **Cho** báo cáo đang mở ở chế độ sửa, **Khi** bấm một visual, **Thì** visual được chọn, hiện khung và 8 tay nắm.
2. **Cho** một visual được chọn, **Khi** kéo thân visual, **Thì** nó di chuyển theo con trỏ, toạ độ x, y làm tròn về bội số của 8, và không rời khỏi trang.
3. **Cho** một visual được chọn, **Khi** kéo một tay nắm, **Thì** chiều rộng và chiều cao đổi theo, bám lưới 8 px, và không nhỏ hơn cỡ tối thiểu.
4. **Cho** nhiều visual được chọn (Shift-bấm hoặc kéo khung chọn), **Khi** kéo, **Thì** cả nhóm di chuyển cùng lúc, giữ nguyên vị trí tương đối.
5. **Cho** đang ở chế độ sửa, **Khi** bấm vùng trống của trang, **Thì** bỏ chọn. Ở chế độ xem (đọc), bấm visual vẫn lọc chéo như hiện nay.

---

### Câu chuyện 2 — Lưu thay đổi và mở lại được trong Power BI Desktop (Ưu tiên: P1)

Người dùng bấm Cmd+S. Báo cáo được ghi vào file `.pbix`; mở lại trong BI Pro thấy đúng bố cục đã sửa, và mở trong Power BI Desktop cũng thấy đúng bố cục đó, mô hình dữ liệu không đổi.

**Vì sao P1**: Phase D chỉ "xong" khi file lưu ra dùng được ở cả hai nơi.

**Kiểm thử độc lập**: sửa bố cục một trang Nhom6, Cmd+S, thoát app, mở lại: bố cục giữ nguyên. Bạn mở file trong Power BI Desktop trên VM theo `CHECKLIST.md`.

**Kịch bản chấp nhận**:

1. **Cho** báo cáo có thay đổi chưa lưu, **Khi** bấm Cmd+S, **Thì** chỉ các phần report thay đổi được ghi (tầng T1); mô hình dữ liệu (`DataModel`) và mọi phần không đổi giữ nguyên từng byte.
2. **Cho** báo cáo vừa ghi xong, **Khi** hệ thống đọc lại file vừa ghi, **Thì** nội dung phải khớp với trạng thái trong bộ nhớ; chỉ khi khớp mới thay file đích. Không khớp thì file đích còn nguyên và người dùng thấy thông báo lỗi.
3. **Cho** file đích là file có sẵn, **Khi** lưu, **Thì** phiên bản trước được giữ lại thành bản sao lưu ở nơi người dùng tìm được (xem Giả định) trước khi thay.
4. **Cho** báo cáo mở từ `~/Downloads`, **Khi** người dùng bấm lưu, **Thì** app không ghi vào file gốc trong `~/Downloads` mà yêu cầu "Lưu thành" bản mới (xem Giả định về quy tắc file gốc).
5. **Cho** tên file mới ở Save As, **Khi** lưu xong, **Thì** cửa sổ chuyển sang file mới, file cũ không bị đổi.
6. **Cho** có thay đổi chưa lưu, **Khi** đóng cửa sổ hoặc thoát app, **Thì** hỏi Lưu / Không lưu / Huỷ; tiêu đề cửa sổ cho biết có thay đổi chưa lưu.

---

### Câu chuyện 3 — Hoàn tác và làm lại (Ưu tiên: P1)

**Vì sao P1**: kéo thả dễ nhầm; sửa mà không hoàn tác được thì không dùng nổi.

**Kiểm thử độc lập**: kéo một visual, xoá một visual, Cmd+Z hai lần: về đúng trạng thái ban đầu; Cmd+Shift+Z hai lần: về trạng thái sau cùng.

**Kịch bản chấp nhận**:

1. **Cho** vừa làm một thao tác sửa bố cục, **Khi** bấm Cmd+Z, **Thì** trạng thái trở lại như trước thao tác đó, kể cả vùng chọn hợp lý.
2. **Cho** vừa hoàn tác, **Khi** bấm Cmd+Shift+Z, **Thì** thao tác được làm lại.
3. **Cho** một lần kéo thả liên tục, **Khi** thả chuột, **Thì** chỉ tạo đúng một bước hoàn tác.
4. **Cho** hoàn tác về đúng trạng thái đã lưu, **Thì** dấu "chưa lưu" mất.
5. **Cho** sau khi hoàn tác rồi làm thao tác mới, **Thì** các bước làm lại cũ bị bỏ.

---

### Câu chuyện 4 — Xoá và nhân bản visual (Ưu tiên: P2)

**Vì sao P2**: cần để sửa trang trọn vẹn, nhưng di chuyển + lưu đã cho giá trị trước.

**Kiểm thử độc lập**: chọn một thẻ card, nhân bản, thấy bản sao cạnh bản gốc và chạy số thật; xoá bản sao; lưu; mở lại.

**Kịch bản chấp nhận**:

1. **Cho** một hoặc nhiều visual được chọn, **Khi** bấm Delete, **Thì** chúng biến khỏi trang; khi lưu, các phần của chúng bị bỏ khỏi file.
2. **Cho** một hoặc nhiều visual được chọn, **Khi** nhân bản (Cmd+D hoặc Cmd+C rồi Cmd+V), **Thì** bản sao có mã mới (không trùng bất kỳ visual nào trong cùng trang), cùng cấu hình và cùng dữ liệu, lệch vị trí một chút, nằm trên cùng, và được chọn.
3. **Cho** visual bị xoá được bookmark nhắc tới, **Khi** lưu, **Thì** file vẫn hợp lệ: tham chiếu treo tới visual đã xoá được xử lý theo cách Power BI Desktop làm (xem Quan sát); ít nhất phải mở được trong cả hai app.
4. **Cho** hoàn tác sau khi xoá, **Thì** visual trở lại đúng vị trí, đúng thứ tự lớp.

---

### Câu chuyện 5 — App là trình sửa `.pbix` (Ưu tiên: P3)

Người dùng bấm đúp hoặc "Mở bằng" một file `.pbix` trong Finder thì BI Pro mở được và nhận là trình sửa (không chỉ trình xem), nên Cmd+S và Save As có tác dụng.

**Vì sao P3**: chức năng đã dùng được qua Open trong app; đăng ký với hệ thống là phần hoàn thiện.

**Kiểm thử độc lập**: sau khi cài app, "Mở bằng → BI Pro" từ Finder mở đúng file; menu Lưu bật sáng.

**Kịch bản chấp nhận**:

1. **Cho** file `.pbix` trong Finder, **Khi** mở bằng BI Pro, **Thì** file mở và có thể sửa/lưu.
2. **Cho** app vẫn xử lý `.pbix` với mức ưu tiên như hiện nay, **Thì** việc đổi từ Viewer sang Editor không đổi cách Finder chọn app mặc định.

---

### Trường hợp biên

- Sửa xong chưa lưu rồi đổi sang trang khác hoặc đổi chế độ xem: thay đổi vẫn giữ trong phiên và vẫn hoàn tác được.
- Ghi file bị gián đoạn (đĩa đầy, mất quyền, app sập giữa chừng): file đích cũ phải còn nguyên; không để lại file hỏng; file tạm được dọn.
- File đích đã bị đổi bởi chương trình khác kể từ khi mở (ví dụ Power BI Desktop trên thư mục chia sẻ): phải cảnh báo trước khi ghi đè, không im lặng ghi đè.
- Kéo visual ra ngoài trang, hoặc đổi cỡ về âm hoặc 0: bị kẹp trong trang và cỡ tối thiểu.
- Visual bị khoá hoặc ẩn: ẩn thì vẫn chọn được qua Selection pane nếu có; xử lý cụ thể ghi ở plan (xem Giả định).
- Visual nằm trong nhóm (`parentGroupName`): di chuyển nhóm thì con đi theo; nếu chưa hỗ trợ nhóm thì không được làm hỏng nhóm khi lưu.
- Nhân bản nhiều lần liên tiếp: mã không bao giờ trùng, kể cả sau khi hoàn tác rồi làm lại.
- Báo cáo có nhiều trang: chỉ ghi lại các phần của trang đã sửa; trang chưa sửa giữ nguyên từng byte.
- File mở từ một vị trí không ghi được (chỉ đọc): Lưu chuyển sang Save As.
- Không có thay đổi mà bấm Cmd+S: không ghi lại file (hoặc ghi lại nguyên văn; không thay đổi nội dung).

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

**Chọn và sửa bố cục**

- **FR-001**: Hệ thống PHẢI cho chọn một visual bằng cách bấm, và chọn nhiều visual bằng Shift-bấm hoặc kéo khung chọn, ở chế độ sửa.
- **FR-002**: Hệ thống PHẢI cho di chuyển visual đã chọn (một hoặc nhiều) bằng chuột và bằng phím mũi tên (1 bước lưới hoặc 1 px), giữ vị trí tương đối của nhóm chọn.
- **FR-003**: Hệ thống PHẢI cho đổi cỡ một visual bằng 8 tay nắm, có cỡ tối thiểu, và giữ visual trong phạm vi trang.
- **FR-004**: Vị trí và cỡ PHẢI bám lưới 8 px khi kéo; có cách tạm bỏ bám (giữ phím Option) [SUY ĐOÁN: theo Power BI cần xác nhận].
- **FR-005**: Hệ thống PHẢI cho xoá visual đã chọn bằng phím Delete.
- **FR-006**: Hệ thống PHẢI cho nhân bản visual đã chọn; bản sao có mã mới, không trùng trong cùng trang, và giữ nguyên cấu hình dữ liệu và định dạng.
- **FR-007**: Chế độ xem (lọc chéo, drill, slicer như hiện nay) PHẢI không bị ảnh hưởng ở chế độ không sửa; việc chuyển giữa chế độ xem và chế độ sửa PHẢI rõ ràng với người dùng.

**Hoàn tác và làm lại**

- **FR-008**: Hệ thống PHẢI có hoàn tác (Cmd+Z) và làm lại (Cmd+Shift+Z) cho mọi thao tác sửa bố cục ở trên; mỗi cử chỉ liên tục là một bước.
- **FR-009**: Lịch sử hoàn tác PHẢI nằm trong phiên làm việc và theo từng tài liệu; không cần giữ sau khi đóng tài liệu.

**Lưu**

- **FR-010**: Hệ thống PHẢI cho lưu (Cmd+S) và lưu thành (Cmd+Shift+S); tiêu đề cửa sổ và menu PHẢI cho biết có thay đổi chưa lưu.
- **FR-011**: Khi lưu, hệ thống PHẢI chỉ ghi tầng T1: các phần report thay đổi được thay; mọi phần khác của `.pbix`, gồm `DataModel`, được giữ nguyên từng byte.
- **FR-012**: Trước khi thay file đích, hệ thống PHẢI ghi ra file tạm, đọc lại, và kiểm tra khớp với trạng thái cần lưu; không khớp thì giữ nguyên file đích và báo lỗi.
- **FR-013**: Trước khi ghi đè một file có sẵn, hệ thống PHẢI giữ lại bản sao lưu của phiên bản trước.
- **FR-014**: Hệ thống KHÔNG ĐƯỢC ghi vào file gốc nằm trong `~/Downloads` (Hiến pháp IV); lưu từ file như vậy PHẢI chuyển sang "Lưu thành" tới một vị trí khác.
- **FR-015**: Hệ thống PHẢI hỏi lưu khi đóng tài liệu hoặc thoát app lúc còn thay đổi chưa lưu.
- **FR-016**: Hệ thống PHẢI cảnh báo trước khi ghi đè nếu file đích đã đổi sau lúc mở.
- **FR-017**: Visual bị xoá PHẢI được bỏ khỏi file; tham chiếu tới nó trong bookmark và các nơi khác PHẢI được xử lý để Power BI Desktop mở được file.
- **FR-018**: Trang không sửa PHẢI giữ nguyên từng byte sau khi lưu.

**Tích hợp hệ thống**

- **FR-019**: App PHẢI đăng ký là trình sửa (Editor) cho `.pbix`, trong khi vẫn là ứng dụng xử lý mặc định như hiện nay.

**Chất lượng và an toàn**

- **FR-020**: Mọi truy vấn và số liệu của các visual sau khi sửa bố cục PHẢI không đổi; golden Phase B/C PHẢI vẫn qua.
- **FR-021**: File đã lưu PHẢI mở được trong BI Pro với bố cục đúng như đã sửa (kiểm bằng test tự động: lưu rồi đọc lại và so với bộ nhớ).

### Thực thể chính

- **Phiên sửa tài liệu**: tài liệu `.pbix` đang mở cùng trạng thái "đã sửa/chưa lưu", vị trí file, và thời điểm file đích lúc mở.
- **Bố cục trang**: danh sách visual của một trang, mỗi visual có mã, vị trí (x, y), lớp (z), cỡ (rộng, cao), thứ tự tab.
- **Vùng chọn**: tập các visual đang chọn trên trang đang xem.
- **Bước hoàn tác**: một thay đổi bố cục có thể đảo ngược và làm lại, kèm vùng chọn trước và sau.
- **Gói thay đổi để lưu**: tập các phần report cần thay, thêm hoặc bỏ khi lưu.

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: Sửa một trang Nhom6 (di chuyển ít nhất 3 visual, đổi cỡ ít nhất 1, xoá 1, nhân bản 1), lưu, rồi mở lại trong BI Pro: bố cục giống hệt trạng thái trước khi lưu, ở 100% các visual đã sửa.
- **SC-002**: File đã lưu mở được trong Power BI Desktop (bạn kiểm tay trên VM) với bố cục đúng, mô hình dữ liệu và số liệu không đổi so với file trước khi sửa.
- **SC-003**: Phần ngoài report (mô hình dữ liệu và mọi phần không đổi) của file đã lưu khớp từng byte với file gốc, và các trang không sửa khớp từng byte.
- **SC-004**: Lưu một thay đổi bố cục trên Nhom6 (90 MB) mất dưới 1 giây (chỉ tiêu của `docs/BIPRO_BUILD_PLAN.md` §6).
- **SC-005**: Kéo hoặc đổi cỡ visual phản hồi trong dưới 150 ms mỗi khung hình trên trang Nhom6 nặng nhất (chỉ tiêu tương tác của §6).
- **SC-006**: 30/30 golden Phase B và các golden Phase C hiện có vẫn khớp; `swift test` không có test nào trượt thêm.
- **SC-007**: Không lần thử nào trong bộ test lỗi giữa chừng (đĩa đầy, mất quyền, sập giả lập) để lại file đích hỏng; file đích còn nguyên 100% các lần.
- **SC-008**: Người dùng làm được chuỗi "mở Nhom6 → sửa bố cục → lưu thành → mở lại" mà không phải đọc hướng dẫn.

## Giả định

- Chỉ sửa bố cục các visual đã có; chưa thêm visual mới từ ribbon Insert, chưa sửa field/format, chưa thêm/xoá/đổi tên trang, chưa ghi bookmark/bộ lọc người dùng vào file, chưa tầng T2/T3 (thuộc các lát sau của Phase D và các Phase E, F).
- Mức lưới 8 px lấy từ kế hoạch của dự án; nếu quan sát Power BI cho thấy khác thì sửa theo quan sát.
- Mã visual mới dùng cùng dạng với Power BI Desktop (20 ký tự hex); xác nhận dạng này ở bước quan sát.
- Vị trí bản sao lưu: thư mục cùng cấp file, tên dạng `<tên>.bak.pbix`, giữ 1 bản gần nhất [quyết ở plan]. Không để bản sao lưu lọt vào `~/Downloads` (file gốc chỉ đọc), nên bản sao lưu của file lưu ở nơi khác dùng thư mục hỗ trợ của app.
- Quy tắc file gốc trong `~/Downloads`: coi mọi file dưới `~/Downloads` là gốc chỉ đọc; Lưu thành là cách duy nhất để lưu bản sửa. Người dùng làm việc với bản sao ở nơi khác (ví dụ `bipro-golden/` hoặc Desktop) thì Lưu ghi thẳng vào bản sao đó.
- Nhóm visual, visual bị khoá, visual ẩn: bản đầu xử lý để không làm hỏng file; hỗ trợ đầy đủ ghi ở plan nếu quan sát cho thấy cần.
- Các visual đang dùng nút action Bookmark và các tương tác khác không bị đổi khi sửa bố cục.
- Test trên VM Windows 11 do bạn làm tay; mình chuẩn bị file trong `build/d-out/` và `CHECKLIST.md`.
- Không thêm thư viện ngoài.
