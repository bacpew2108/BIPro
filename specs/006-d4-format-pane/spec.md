# Đặc tả tính năng: D4, Format pane sửa được và lưu `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng)

**Ngày tạo**: 2026-11-10

**Trạng thái**: Nháp, chờ duyệt

**Đầu vào**: "D4-format-pane: lát cắt thứ sáu của Phase D (`docs/BIPRO_BUILD_PLAN.md` mục Phase D, sau D1 `specs/002-d1-canvas-luu-t1/`, D2 `specs/003-d2-build-pane-field-well/`, D3 `specs/004-d3-them-visual-doi-loai/`, D5 `specs/005-d5-quan-ly-trang/`): biến Format pane (tab "Định dạng" của Trực quan hóa) từ chỉ-đọc thành sửa được, ghi vào `.pbix` tầng T1."

Cấp trên: `docs/BIPRO_BUILD_PLAN.md` (Phase D), `specs/002-d1-canvas-luu-t1/` (lưu T1, hoàn tác, bỏ `SecurityBindings` ở R13), `specs/003-d2-build-pane-field-well/` (`PBIRQueryPatch`, ghép byte trong `visual.json`), `specs/004-d3-them-visual-doi-loai/` (R16: Desktop giữ hay bỏ khoá `objects` khi đổi loại). Mâu thuẫn thì sửa `docs/` trước.

## Quan sát Power BI

Mục nào là [SUY ĐOÁN] thì chưa có quan sát; phải kiểm bằng buổi quan sát VM-D4 trước khi code phần đó (Claude điều khiển VM khi người dùng cho phép lần đó, hoặc người dùng làm tay).

**Hiện trạng trong BI Pro** (đọc từ mã, `Sources/BIPro/Panes/ReportPanes.swift`, `FormatCard`): tab "Định dạng" có hai phạm vi, "Visual" (khoá `objects`) và "Chung" (khoá `visualContainerObjects`). Pane chỉ liệt kê thẻ và thuộc tính đang CÓ trong `visual.json` của visual đang chọn; mỗi thẻ là một khoá, mỗi thuộc tính hiện giá trị (công tắc `show`, màu, số, chuỗi) nhưng không sửa được; pane không biết thuộc tính nào còn thêm được. Visual chưa có khoá nào hiện "Đang dùng định dạng mặc định của theme". Đường vẽ (engine) đã đọc nhiều thuộc tính này để vẽ visual (màu, cỡ chữ, nền, viền, bóng, legend, nhãn).

**Đã quan sát trong file thật** (`Nhom6_work.pbix`, định dạng PBIR; thống kê bằng script trên 134 `visual.json` của 4 trang, 2026-11-10):

- Loại visual: card 50, image 30, slicer 17, textbox 7, actionButton 5, clusteredBarChart 4, lineClusteredColumnComboChart 4, lineStackedColumnComboChart 3, donutChart 3, lineChart 3, pageNavigator 3, pivotTable 2, hundredPercentStackedColumnChart 1, treemap 1, shapeMap 1.
- `visual.objects` có 25 khoá khác nhau, tổng 72 tên thuộc tính. Số visual dùng từng khoá: `labels` 62, `categoryLabels` 50, `general` 38, `imageScaling` 30, `data` 17, `header` 17, `dataPoint` 11, `valueAxis` 7, `legend` 6, `icon` 5, `text` 5, `fill` 5, `outline` 4, `categoryAxis` 3; còn lại (`value`, `values`, `columnHeaders`, `rowHeaders`, `grid`, `columnWidth`, `shape`, `defaultColors`, `trend`, `forecast`, `subTotals`) mỗi khoá 1 đến 2 visual.
- `visual.visualContainerObjects` có 7 khoá: `title` 134 (mọi visual), `padding` 78, `subTitle` 76, `background` 64, `border` 64, `dropShadow` 30, `visualLink` 5.
- Mỗi khoá là mảng các mục `{selector?, properties}`. Trong 750 mục, 706 không có `selector` (giá trị chung); 44 có selector: `{id:"default"}` (13 mục, và 1 mục `{id:"1"}`), `{metadata:"Bảng.Cột"}` (định dạng riêng của một trường, 7 mục), `{data:[…]}` (điểm dữ liệu, 17 mục), tổ hợp `data+metadata` (6).
- Kiểu giá trị (số lần gặp): biểu thức `{expr:{Literal:{Value:"…"}}}` 406 (bool `true`/`false`, số có đuôi `D` hoặc `L`, chuỗi trong nháy đơn, cỡ chữ `'12pt'`); màu `{solid:{color:…}}` 140 (màu hex hoặc `ThemeDataColor{ColorId, Percent}`); ảnh `ResourcePackageItem` 30; và vài giá trị đặc biệt mỗi loại 1 lần (`geoJson`, `layout`, `algorithm`).
- Visual do Desktop thêm mới không có `objects` (VM-D3 mục A). Bỏ hết trường của visual thì `visual.json` về dạng trống (VM-D3 mục B). Đổi loại visual: Desktop giữ mọi khoá `objects` trừ khoá chỉ có ở loại cũ như `forecast` (VM-D3 mục C, `TypeChange.keepsObjectKey`).
- Hiện `PBIRPatch` (D2, D3) đã ghép byte được vào `visual.query` và `visual.visualType`; chưa có bộ ghép cho `visual.objects` và `visual.visualContainerObjects`.

**Đã quan sát ở VM-D4 (2026-11-10, `docs/phase-d-evidence/vm-d4/QUAN-SAT.md`)**: bật thuộc tính hoặc thẻ chưa có thêm khoá ở **cuối** `objects`/`visualContainerObjects` (thuộc tính mới ở cuối `properties`), tắt công tắc của thẻ đã có sửa `show` tại chỗ; số ghi dạng `"16D"` (không đơn vị), số nguyên `"1L"`, chọn từ danh sách là chuỗi trong nháy đơn hoặc số `D`, chuỗi gấp đôi nháy đơn, màu theme là `ThemeDataColor{ColorId, Percent}` và màu tự chọn là hex viết hoa; "Reset to default" của thẻ xoá cả khoá, của một thuộc tính màu chỉ bỏ thuộc tính; tên thẻ trong giao diện không trùng tên khoá (Callout value = `labels`, Shade area = `lineStyles.areaShow`, thẻ Values của slicer = `items`); visual chưa có trường thì Format pane của Desktop trống; Desktop chuẩn hoá lại toàn bộ `visual.json` khi lưu (nâng `$schema` lên 2.14.0). Chưa quan sát: matrix/bảng, `dataPoint` và `selector` theo trường, font family, màu viền/nền/bóng, khoảng giá trị của ô số.

**[SUY ĐOÁN] ban đầu** (phần lớn đã trả lời ở trên; phần còn lại ở `QUAN-SAT.md` mục 7, giữ chỉ-đọc cho tới khi quan sát; đọc diff `visual.json` sau mỗi thay đổi một thuộc tính trong Format pane của Desktop):

- Bật `show` của một thẻ chưa có trong file (ví dụ legend, tiêu đề trục) ghi khoá nào, mục có `selector` hay không, thứ tự khoá và thụt dòng.
- Đổi một thuộc tính đã có: chỉ sửa giá trị tại chỗ, hay ghi lại cả mục.
- Đặt lại về mặc định ("Revert to default") theo thuộc tính và theo thẻ: Desktop xoá thuộc tính, bỏ mục rỗng, bỏ cả khoá `objects` rỗng, hay ghi giá trị mặc định.
- Màu: màu theme ghi `ThemeDataColor{ColorId, Percent}`, màu tự chọn ghi hex chữ hoa hay thường, có kèm độ trong suốt không.
- Cỡ chữ, độ rộng, bán kính: Desktop ghi đơn vị nào (`'12pt'` hay số có đuôi `D`/`L`), giới hạn nhỏ nhất và lớn nhất.
- Tiêu đề visual: bật, đổi chữ, `titleWrap`, căn lề; visual chưa có `visualContainerObjects`.
- Nền, viền, bóng, padding của visual (`visualContainerObjects`): khoá và giá trị.
- Trục (`categoryAxis`, `valueAxis`): bật/tắt trục, tiêu đề trục, đơn vị hiển thị, khoảng.
- Legend, nhãn dữ liệu (`labels`), `dataPoint` màu từng điểm (chỉ để đọc; ghi ở lát này nếu chốt được).
- Thuộc tính phụ thuộc nhau: tắt `show` có làm Desktop giữ hay bỏ các thuộc tính con.
- Visual có `objects` nhưng thuộc tính tắt (`show:false`) vẫn nằm trong file hay bị bỏ.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1 — Sửa định dạng đã có của visual (Ưu tiên: P1)

Người dùng ở chế độ Sửa (⌘E) chọn một visual, mở tab "Định dạng" và đổi một thuộc tính đang hiện: bật hay tắt, đổi số, chọn từ danh sách, đổi màu, đổi chữ. Visual trên canvas đổi ngay.

**Vì sao P1**: Format pane chỉ đọc làm Phase D không "xong" (tiêu chí xong nêu rõ đổi tiêu đề, màu nền, legend, nhãn, cỡ chữ); sửa giá trị đã có là phần ít rủi ro nhất vì cấu trúc đã quan sát trong Nhom6.

**Kiểm thử độc lập**: mở Nhom6, chọn một card ở trang D3 (có `labels`, `categoryLabels`, tiêu đề), đổi cỡ chữ nhãn và màu nền; card vẽ lại ngay; hoàn tác từng bước trả về đúng giá trị cũ. Chưa cần lưu.

**Kịch bản chấp nhận**:

1. **Cho** chế độ Sửa và một visual được chọn, **khi** đổi giá trị một thuộc tính bằng điều khiển hợp kiểu (công tắc cho bool, ô số cho số, ô chọn cho giá trị cố định, bảng màu cho màu, ô chữ cho chuỗi), **thì** giá trị ghi vào đúng thuộc tính của đúng khoá và visual vẽ lại ngay trên canvas bằng đường vẽ có sẵn.
2. **Cho** thuộc tính số, **khi** nhập giá trị ngoài khoảng cho phép hoặc không phải số, **thì** bị từ chối kèm lý do và giữ giá trị cũ, không ghi gì.
3. **Cho** chế độ Xem, **thì** mọi điều khiển trong Format pane mờ kèm lý do ("bật chế độ Sửa"), không đổi gì.
4. **Cho** nhiều visual được chọn cùng lúc, **thì** Format pane hiện thông báo chọn một visual (như Build pane), không sửa hàng loạt ở lát này.
5. **Cho** thuộc tính có kiểu giá trị chưa hỗ trợ (`geoJson`, `layout`, `algorithm`, ảnh, biểu thức không phải `Literal` hoặc `solid`), **thì** hiện chỉ-đọc kèm lý do và giữ nguyên byte khi lưu.

---

### Câu chuyện 2 — Thêm thuộc tính chưa có và đặt lại về mặc định (Ưu tiên: P1)

Người dùng bật legend hoặc tiêu đề trục chưa có trong file, thêm tiêu đề cho visual chưa có, rồi đổi ý và đặt lại thuộc tính hay cả thẻ về mặc định.

**Vì sao P1**: phần lớn visual Desktop thêm mới không có `objects`; không thêm được thuộc tính thì chỉ sửa được báo cáo mẫu của người khác.

**Kiểm thử độc lập**: thêm một visual cột nhóm mới (D3), bật legend và tiêu đề, đổi chữ tiêu đề, rồi "Đặt lại" thẻ legend: `visual.json` trong bộ nhớ quay về y như trước khi bật.

**Kịch bản chấp nhận**:

1. **Cho** thẻ chưa có trong file mà danh mục của loại visual đó có, **khi** bật hoặc đặt giá trị, **thì** thẻ hiện trong pane ở dạng tắt/mặc định và thêm khoá (mục, thuộc tính) đúng cách Desktop ghi (cấu trúc, thứ tự khoá, thụt dòng đã quan sát ở VM-D4).
2. **Cho** thuộc tính hoặc thẻ có trong file, **khi** bấm "Đặt lại về mặc định", **thì** thuộc tính (hoặc cả thẻ) bị bỏ theo cách Desktop làm; mục rỗng và khoá `objects` rỗng bị bỏ; nếu Desktop không bỏ thì làm theo Desktop.
3. **Cho** thuộc tính không nằm trong danh mục đã quan sát của loại visual (khoá lạ có sẵn trong file, hoặc khoá chưa quan sát), **thì** hiện chỉ-đọc kèm lý do ("chưa quan sát ở Power BI Desktop"), không có nút thêm, và lưu giữ nguyên.
4. **Cho** thuộc tính phụ thuộc thuộc tính khác (ví dụ chỉ có nghĩa khi `show` bật), **khi** tắt thuộc tính chính, **thì** các thuộc tính con mờ nhưng giá trị giữ nguyên (theo quan sát VM-D4; chưa quan sát thì giữ nguyên, không xoá).

---

### Câu chuyện 3 — Định dạng chung của khung visual (Ưu tiên: P1)

Người dùng đổi tiêu đề, phụ đề, nền, viền, bóng, khoảng đệm của khung visual ở phạm vi "Chung" (`visualContainerObjects`).

**Vì sao P1**: tiêu đề, nền, viền là thứ người dùng đổi đầu tiên; Nhom6 có đủ ví dụ (tiêu đề ở cả 134 visual).

**Kiểm thử độc lập**: chọn một biểu đồ thanh ở D3, đổi chữ tiêu đề, bật viền và đổi màu nền; lưu, mở lại: giữ nguyên.

**Kịch bản chấp nhận**:

1. **Cho** phạm vi "Chung", **khi** sửa `title` (bật, chữ, cỡ chữ, màu, căn lề), `subTitle`, `background` (màu, độ trong suốt), `border` (màu, độ rộng, bán kính), `dropShadow`, `padding`, **thì** ghi vào `visualContainerObjects` đúng cấu trúc Nhom6 và Desktop ghi; visual vẽ lại ngay.
2. **Cho** visual chưa có `visualContainerObjects` (visual mới ở D3), **khi** bật tiêu đề, **thì** tạo khoá `visualContainerObjects` đúng thứ tự khoá trong `visual` như Desktop.
3. **Cho** khoá `visualLink` (nút điều hướng) trong `visualContainerObjects`, **thì** chỉ-đọc ở lát này (liên kết trang/bookmark thuộc D6 và sau đó).

---

### Câu chuyện 4 — Lưu và mở lại được trong Power BI Desktop (Ưu tiên: P1)

Người dùng ⌘S sau khi sửa định dạng. File ghi ra mở lại ở BI Pro và Power BI Desktop giữ đúng định dạng, không báo lỗi.

**Vì sao P1**: tiêu chí xong của cả Phase D (như D1 đến D5).

**Kiểm thử độc lập**: kịch bản Nhom6 (xem tiêu chí xong) rồi ⌘S; mở lại bằng `PBIXFile`, so khoá `objects` và `visualContainerObjects`; người dùng hoặc Claude (khi được phép) mở file ở Desktop theo `CHECKLIST.md`.

**Kịch bản chấp nhận**:

1. **Cho** visual đã sửa định dạng, **khi** lưu, **thì** chỉ `visual.json` của visual đó đổi, ghép byte vào chỗ của khoá `objects` hoặc `visualContainerObjects` (phần còn lại của file và của visual khớp từng byte, trừ `SecurityBindings` và `[Content_Types].xml` như D1).
2. **Cho** file đã lưu, **khi** mở ở BI Pro, **thì** Format pane hiện đúng giá trị đã đặt; visual vẽ đúng.
3. **Cho** file đã lưu, **khi** mở ở Desktop, **thì** không báo lỗi và Desktop vẽ cùng định dạng (màu, cỡ chữ, tiêu đề, legend…) như BI Pro.
4. **Cho** khoá hoặc giá trị Desktop không nhận, **thì** `DocumentSaver.verify` từ chối khi lưu (không ghi file hỏng), kèm lý do.
5. **Cho** file gốc dưới `~/Downloads`, **thì** buộc "Lưu thành" (như D1) và file gốc không đổi.

---

### Câu chuyện 5 — Hoàn tác chung một lịch sử (Ưu tiên: P2)

Mỗi lần sửa định dạng là một bước hoàn tác chung ngăn xếp với kéo/đổi cỡ (D1), trường (D2), thêm/đổi loại visual (D3), thao tác trang (D5).

**Vì sao P2**: chạy đúng nhờ bộ máy hoàn tác có sẵn, nhưng thao tác liên tục (kéo thanh trượt, gõ chữ) phải gộp thành một bước.

**Kiểm thử độc lập**: xen kẽ kéo visual, đổi màu nền, thả trường, đổi cỡ chữ, rồi ⌘Z/⇧⌘Z lần lượt: mỗi bước đảo đúng một thao tác theo thứ tự ngược.

**Kịch bản chấp nhận**:

1. **Cho** chuỗi thao tác hỗn hợp, **khi** hoàn tác từng bước, **thì** từng lần sửa định dạng được đảo đúng một bước; làm lại đưa về đúng trạng thái.
2. **Cho** gõ chữ hoặc kéo giá trị liên tiếp trên cùng một thuộc tính, **thì** gộp thành một bước (như kéo visual ở D1).
3. **Cho** hoàn tác về trước khi có sửa, **thì** `isDirty` về false và ⌘S không còn việc.

---

### Trường hợp biên

- Giá trị trùng giá trị hiện có: không tạo bước hoàn tác, không ghi gì (như D5).
- Thuộc tính có ở nhiều mục (nhiều `selector`): lát này chỉ sửa mục không có selector hoặc `{id:"default"}`; mục có selector `metadata`/`data` chỉ-đọc, giữ nguyên khi lưu.
- Khoá `objects` có sẵn trong file nhưng không có trong danh mục của loại visual: hiện chỉ-đọc, giữ nguyên khi lưu.
- Đổi loại visual (D3) sau khi sửa định dạng: khoá được giữ hay bỏ theo `TypeChange.keepsObjectKey`; hoàn tác đưa về đủ.
- Nhân bản visual hay trang (D1, D5): định dạng đã sửa đi theo bản sao.
- Visual trong nhóm, visual ẩn, visual khoá: sửa định dạng được như visual thường.
- Báo cáo định dạng cũ (`Report/Layout`): chưa sửa được định dạng (như D1), điều khiển mờ kèm lý do.
- Màu theme: chọn màu theme ghi `ThemeDataColor` với `ColorId` và `Percent` như Nhom6; đổi theme báo cáo ngoài phạm vi.
- Tên thuộc tính tiếng Anh trong file hiển thị tên tiếng Việt qua `FormatNames`; thuộc tính chưa có tên Việt hiện tên khoá, không ẩn.
- Văn bản tiêu đề có dấu tiếng Việt, ký tự đặc biệt, nháy đơn: ghi đúng cách thoát (nháy đơn trong literal chuỗi là hai nháy đơn).

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

- **FR-001**: Ở chế độ Sửa, mỗi thuộc tính có trong danh mục đã quan sát PHẢI sửa được trong Format pane bằng điều khiển hợp kiểu (công tắc, ô số, ô chọn, bảng màu, ô chữ); kiểu giá trị chưa hỗ trợ hiện chỉ-đọc kèm lý do.
- **FR-002**: Sửa định dạng PHẢI ghi đúng cấu trúc Power BI Desktop ghi (khoá, mục, thứ tự khoá, kiểu giá trị), và visual PHẢI vẽ lại ngay bằng đường vẽ có sẵn.
- **FR-003**: Danh mục thuộc tính theo loại visual PHẢI chỉ gồm thuộc tính đã quan sát (Nhom6, các file Desktop ghi ở VM-D1 đến VM-D5, VM-D4); thuộc tính ngoài danh mục chỉ-đọc, không bịa khoá.
- **FR-004**: Thêm thuộc tính hoặc thẻ chưa có trong file PHẢI tạo khoá đúng cách Desktop ghi, kể cả khi visual chưa có `objects` hay `visualContainerObjects`.
- **FR-005**: "Đặt lại về mặc định" theo thuộc tính và theo thẻ PHẢI xoá khoá đúng cách Desktop làm; không để lại mục rỗng hay khoá `objects` rỗng nếu Desktop không để.
- **FR-006**: Phạm vi "Visual" (`objects`) và "Chung" (`visualContainerObjects`: `title`, `subTitle`, `background`, `border`, `dropShadow`, `padding`) PHẢI sửa được; `visualLink` chỉ-đọc.
- **FR-007**: Mục có `selector` kiểu `metadata`, `data` hoặc `id` khác `default` (định dạng riêng theo trường hoặc điểm dữ liệu) PHẢI chỉ-đọc và giữ nguyên byte, trừ khi VM-D4 chốt được cách ghi.
- **FR-008**: Mỗi lần sửa PHẢI là đúng một bước hoàn tác chung một lịch sử với D1, D2, D3, D5; sửa liên tiếp trên một thuộc tính gộp thành một bước; hoàn tác và làm lại khôi phục đúng.
- **FR-009**: Lưu (⌘S, ⇧⌘S) PHẢI ghi định dạng vào `.pbix` ở tầng T1 qua đường lưu của D1: chỉ `visual.json` đã sửa đổi, ghép byte vào đúng chỗ của khoá, phần còn lại khớp từng byte; `SecurityBindings` bỏ như D1 (R13); dựng và kiểm trong bộ nhớ trước khi ghi, file đích còn nguyên nếu lỗi.
- **FR-010**: File đã lưu PHẢI mở lại được ở BI Pro (Format pane và canvas đúng giá trị) và ở Power BI Desktop (không báo lỗi, vẽ cùng định dạng); `DocumentSaver.verify` PHẢI từ chối khoá hoặc giá trị Desktop không nhận.
- **FR-011**: Ở chế độ Xem, với báo cáo định dạng cũ và khi chọn nhiều visual, các điều khiển sửa PHẢI mờ kèm lý do; chế độ Xem không đổi gì.
- **FR-012**: Không file nào dưới `~/Downloads` bị ghi; phần chưa sửa khớp từng byte; golden Phase B/C và test D1 đến D5 giữ nguyên số qua; visual không sửa vẽ cùng số.

### Thực thể chính

- **Định dạng của visual**: hai khoá gốc `objects` và `visualContainerObjects` trong `visual.json`; mỗi khoá là danh sách thẻ (tên khoá), mỗi thẻ là danh sách mục `{selector?, properties}`, mỗi thuộc tính có tên, kiểu giá trị (bool, số, chuỗi, màu, danh sách cố định) và giá trị.
- **Danh mục thuộc tính**: theo loại visual và theo phạm vi (Visual/Chung), gồm thẻ, thuộc tính, kiểu điều khiển, khoảng/giá trị cho phép, tên hiển thị tiếng Việt, và nguồn quan sát; chỉ gồm thuộc tính đã quan sát.
- **Bước sửa định dạng**: một lần đổi (hoặc đặt lại) thuộc tính hay thẻ của một visual, một bước hoàn tác, gộp được khi cùng thuộc tính liên tiếp.

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: Trên Nhom6 chọn một card, một slicer, một biểu đồ cột/đường và một matrix, ở mỗi cái đổi tiêu đề, màu nền, cỡ chữ, bật/tắt legend hoặc nhãn dữ liệu (nơi có): mỗi lần sửa thấy trên canvas trong dưới 0,5 giây.
- **SC-002**: Hoàn tác từng bước của chuỗi trên đưa lại đúng giá trị trước (so `objects`/`visualContainerObjects` của từng visual), làm lại đưa về đúng giá trị sau; "Đặt lại về mặc định" đưa `visual.json` về đúng nội dung trước khi thêm thuộc tính; không bước nào hỏng.
- **SC-003**: Lưu báo cáo sau chuỗi trên mất dưới 1 giây (như D1 đến D5); file lưu mở lại ở BI Pro có đúng giá trị định dạng; mọi phần không sửa khớp từng byte (trừ `SecurityBindings`, `[Content_Types].xml`).
- **SC-004**: File mở được ở Power BI Desktop (người dùng kiểm hoặc Claude khi được phép): không báo lỗi, định dạng của các visual đã sửa hiện như BI Pro (tiêu đề, màu nền, cỡ chữ, legend, nhãn).
- **SC-005**: 0 khoá bịa: mọi khoá và kiểu giá trị BI Pro ghi đều có trong Nhom6 hoặc trong file Desktop đã ghi (kiểm bằng test so danh mục với `docs/phase-d-evidence/`).
- **SC-006**: Golden nặng Phase B/C và các test D1 đến D5 giữ nguyên số qua; file gốc dưới `~/Downloads` không đổi.

## Giả định

- Chỉ dùng khoá và kiểu giá trị đã quan sát trong Nhom6 và trong các file Desktop ghi ở VM-D1 đến VM-D5; phần chưa quan sát (mục [SUY ĐOÁN]) giữ chỉ-đọc cho tới buổi VM-D4.
- Danh mục thuộc tính dựng từ quan sát (không tải schema JSON từ mạng, không dịch ngược Power BI Desktop); ưu tiên thuộc tính nhiều visual dùng nhất ở Nhom6: `title`, `background`, `border`, `labels`, `categoryLabels`, `legend`, `valueAxis`, `categoryAxis`, `dataPoint` (đọc).
- Lát này không đổi cách vẽ: chỉ sửa giá trị mà đường vẽ đã đọc; thuộc tính mà đường vẽ chưa đọc vẫn ghi được (và Desktop vẽ) nhưng BI Pro ghi chú "BI Pro chưa vẽ thuộc tính này" ở điều khiển.
- Phạm vi: không làm định dạng trang (nền, cỡ trang, ẩn trang), không đổi theme báo cáo, không điều kiện định dạng (quy tắc, field value), không định dạng riêng theo trường hay điểm dữ liệu nếu VM-D4 chưa chốt, không Edit interactions, không bookmark (D6), không nhóm visual, tooltip page, tầng T2/T3.
- Tiếp tục theo quy tắc: hiến pháp (agent không điều khiển VM, trừ khi người dùng cho phép lần đó), không thư viện ngoài, không ghi `~/Downloads`.
