# Đặc tả tính năng: D3, thêm visual mới và đổi loại visual, lưu `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng)

**Ngày tạo**: 2026-11-10

**Trạng thái**: Nháp, chờ duyệt

**Đầu vào**: "D3-them-visual-doi-loai: lát cắt thứ ba của Phase D (`docs/BIPRO_BUILD_PLAN.md` mục Phase D, sau D1 ở `specs/002-d1-canvas-luu-t1/` và D2 ở `specs/003-d2-build-pane-field-well/`): thêm visual mới vào trang và đổi loại visual đã có, rồi lưu `.pbix` tầng T1."

Cấp trên: `docs/BIPRO_BUILD_PLAN.md` (Phase D), `specs/002-d1-canvas-luu-t1/` (bố cục, lưu T1, hoàn tác, nhân bản), `specs/003-d2-build-pane-field-well/` (Build pane, ô trường, `PBIRQueryPatch`). Mâu thuẫn thì sửa `docs/` trước.

## Quan sát Power BI

Mục nào là [SUY ĐOÁN] thì chưa có quan sát hoặc tài liệu; phải kiểm ở bước plan hoặc bằng buổi quan sát trên VM (VM-D3) trước khi code phần đó.

**Đã quan sát trong file thật** (`Nhom6_work.pbix`, định dạng PBIR, 134 `visual.json`):

- Một visual là một phần `Report/definition/pages/<trang>/visuals/<mã 20 ký tự hex>/visual.json`. Mọi visual có khoá gốc `$schema`, `name` (trùng mã thư mục), `position` (`x`, `y`, `z`, `height`, `width`, `tabOrder`) và `visual`. Chỉ có thêm `isHidden` (3 visual) và `filterConfig` (1 visual).
- Trong `visual`: `visualType` (mọi visual), `visualContainerObjects` (134/134), `objects` (128/134), `query.queryState` (89/134, chỉ visual có dữ liệu), `drillFilterOtherVisuals` (52/134), `expansionStates` (1).
- Loại visual có trong Nhom6: card 50, image 30, slicer 17, textbox 7, actionButton 5, pageNavigator 3, và 12 biểu đồ (combo cột + đường nhóm 4, thanh nhóm 4, đường 3, donut 3, combo cột xếp chồng + đường 3, cột 100% 1, treemap 1, matrix `pivotTable` 2, bản đồ hình `shapeMap` 1).
- Kích thước thường gặp: card 302×108, slicer 364×64, thanh nhóm 616×380, hộp văn bản trải cả bề ngang trang. Đây là cỡ do tác giả đặt, chưa phải cỡ mặc định của Desktop.
- Hộp văn bản (`textbox`) không có `query`; nội dung nằm ở `visual.objects.general[0].properties.paragraphs[].textRuns[].value` cùng kiểu chữ.
- BI Pro đã có thư viện biểu tượng visual và bảng ô trường theo loại (`VisualCatalog`, `WellRules` của D2). Thư viện hiện chỉ hiển thị: chọn loại khác ghi "đổi loại visual: Phase D". Ribbon đã có nút "Visual mới" và "Hộp văn bản" (đang mờ, ghi "Phase D").
- BI Pro hiện vẽ bằng engine: card, slicer, matrix, các biểu đồ trục XY, donut, treemap, bản đồ hình. Từ D1: nhân bản visual, hoàn tác theo ảnh chụp trang, lưu T1 bằng thêm/bớt phần và ghép byte, bỏ `SecurityBindings`. Từ D2: ô trường, thêm/bỏ/đổi thứ tự trường, `PBIRQueryPatch` ghép byte `queryState`.

**Hành vi chuẩn của Power BI Desktop cần theo (kiến thức chung, chưa quan sát trên VM)**:

- [SUY ĐOÁN] Bấm một biểu tượng trong thư viện visual khi không chọn visual nào thì Desktop thêm visual mới của loại đó vào trang, chọn sẵn, trống, ở vị trí và cỡ mặc định theo loại (không trùng đúng visual đang có).
- [SUY ĐOÁN] Cấu trúc `visual.json` của visual mới do Desktop ghi: `$schema`, `name`, `position`, `visual.visualType`, thường kèm `visual.drillFilterOtherVisuals` hoặc khoá tương tự và, khi đã có trường, `visual.query.queryState`; chưa rõ `objects` và `visualContainerObjects` mới có được ghi hay để trống.
- [SUY ĐOÁN] `z` và `tabOrder` của visual mới là số lớn nhất của trang cộng một (D1 đã quan sát khi dán: `z` = lớn nhất + 1, `tabOrder` = `z`).
- [SUY ĐOÁN] Đổi loại visual đã chọn bằng thư viện thì Desktop giữ vị trí và cỡ, thay `visualType`, và chuyển các trường sang ô cùng vai trò của loại mới (ví dụ ô trục X sang ô trục X, ô giá trị sang ô giá trị), bỏ trường không có chỗ. Định dạng riêng (`objects`) của visual cũ được giữ cho phần loại mới còn có.
- [SUY ĐOÁN] Hộp văn bản mới có một đoạn văn bản mặc định hoặc trống; Desktop ghi `paragraphs` ngay khi có nội dung.

**Cần buổi quan sát trên VM** (bạn làm tay, ngắn, ghi vào `docs/phase-d-evidence/vm-d3/`; mình chuẩn bị file và danh sách việc như VM-D1, VM-D2): (1) thêm từng loại visual (card, biểu đồ cột nhóm, thanh, đường, combo, donut, treemap, matrix, slicer, hộp văn bản, bản đồ hình) vào trang trống rồi lưu: xem `visual.json` mới có những khoá nào, cỡ mặc định, `z`; (2) đổi loại: cột sang thanh, cột sang đường, cột sang donut, card sang slicer (có trường): xem trường đi về ô nào và trường nào bị bỏ, `objects` còn gì; (3) thêm visual vào trang đã có visual: vị trí đặt ở đâu; (4) thêm visual khi trang đang cuộn hoặc thu phóng khác: có khác không. Nếu chưa có quan sát, bản đầu chỉ làm phần theo cấu trúc đã quan sát trong Nhom6 (khoá của card, slicer, biểu đồ có dữ liệu, hộp văn bản) và ghi rõ chỗ còn đoán.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1 — Thêm một visual mới từ thư viện (Ưu tiên: P1)

Người dùng bỏ chọn mọi visual, bấm một biểu tượng trong thư viện visual của Build pane (hoặc nút "Visual mới" ở ribbon). Một visual trống của loại đó xuất hiện trên trang, đang được chọn; Build pane hiện các ô trường của nó để thả trường vào bằng cách của D2.

**Vì sao P1**: không thêm được visual thì D2 chỉ sửa được cái có sẵn; thêm visual là nửa còn lại của "tạo báo cáo".

**Kiểm thử độc lập**: mở Nhom6, ở chế độ Sửa bỏ chọn, bấm biểu tượng card, thấy một card trống nằm trên cùng, chọn sẵn; thả measure `Net_Cashflow` vào ô Field, card hiện số. Chưa cần lưu.

**Kịch bản chấp nhận**:

1. **Cho** chế độ Sửa và không chọn visual nào, **Khi** bấm một biểu tượng loại hỗ trợ trong thư viện, **Thì** một visual mới của loại đó được thêm vào trang đang mở với mã mới (không trùng mã nào trong báo cáo), cỡ mặc định theo loại, nằm trong phạm vi trang và trên cùng mọi visual, và đang là visual được chọn.
2. **Cho** một visual mới vừa thêm, **Khi** xem Build pane, **Thì** hiện các ô trường đúng loại (như D2), mọi ô trống, và visual hiện trạng thái trống ("Thêm trường để vẽ").
3. **Cho** một visual mới, **Khi** thả trường vào ô hợp lệ, **Thì** visual vẽ lại bằng engine như D2; ô tick của pane Dữ liệu thêm trường vào ô mặc định.
4. **Cho** trang đã có nhiều visual, **Khi** thêm visual mới, **Thì** vị trí đặt ở giữa phần trang đang nhìn thấy và không chồng khít lên visual vừa thêm trước đó (mỗi lần thêm lệch một bậc nếu ô giữa đã bị chiếm).
5. **Cho** chế độ Xem (không phải Sửa), **Khi** bấm biểu tượng trong thư viện, **Thì** không thêm gì; thư viện cho biết cần bật chế độ Sửa.
6. **Cho** loại visual chưa hỗ trợ ở lát này (scatter, gauge, KPI, table, python/R…), **Khi** bấm biểu tượng, **Thì** không thêm, và thông báo rõ loại đó chưa hỗ trợ.

---

### Câu chuyện 2 — Lưu visual mới và mở lại được trong Power BI Desktop (Ưu tiên: P1)

Người dùng bấm Cmd+S sau khi thêm visual và thả trường. File ghi ra mở lại trong BI Pro thấy đúng visual mới và trường của nó, và mở trong Power BI Desktop cũng thấy đúng visual đó, vẽ cùng số, mô hình dữ liệu không đổi.

**Vì sao P1**: Phase D chỉ "xong" khi file lưu ra dùng được ở cả hai nơi (như D1, D2).

**Kiểm thử độc lập**: thêm một card và một biểu đồ thanh nhóm vào trang D1 của Nhom6, thả trường, Cmd+S, mở lại: giữ nguyên. Bạn mở file trong Power BI Desktop trên VM theo `CHECKLIST.md`.

**Kịch bản chấp nhận**:

1. **Cho** visual mới chưa lưu, **Khi** Cmd+S, **Thì** file có thêm một phần `visual.json` cho mỗi visual mới (đặt ngay sau `visual.json` cuối của cùng trang), mọi phần khác giữ nguyên từng byte, trừ `SecurityBindings` và dòng liên quan trong `[Content_Types].xml` (xem D1, R13).
2. **Cho** file đã lưu, **Khi** mở lại trong BI Pro, **Thì** visual mới có đúng loại, vị trí, cỡ, thứ tự `z`, các ô và trường.
3. **Cho** file đã lưu, **Khi** mở trong Power BI Desktop, **Thì** không báo lỗi, visual mới hiện đúng loại ở đúng chỗ, các trường đúng ô, và số liệu khớp với BI Pro.
4. **Cho** visual mới được thêm rồi xoá trước khi lưu, **Khi** lưu, **Thì** file không chứa visual đó.
5. **Cho** visual mới chưa có trường nào, **Khi** lưu, **Thì** file vẫn ghi visual đó (visual trống hợp lệ mở được trong Desktop), không ghi ô rỗng.

---

### Câu chuyện 3 — Đổi loại visual đã chọn, giữ trường (Ưu tiên: P1)

Người dùng chọn một visual (ví dụ biểu đồ đường) và bấm biểu tượng khác trong thư viện (ví dụ biểu đồ thanh nhóm hoặc cột 100%). Visual đổi loại tại chỗ: vị trí và cỡ giữ nguyên, các trường chuyển sang ô tương ứng, trường không có chỗ được bỏ qua và báo rõ.

**Vì sao P1**: đổi loại là thao tác rất hay dùng và là phần "đổi loại visual" đã hứa ở D2.

**Kiểm thử độc lập**: chọn biểu đồ đường có Trục X, Trục Y và Chú thích công cụ ở trang D1 của Nhom6, bấm biểu tượng biểu đồ thanh nhóm: biểu đồ thành thanh, các trường vẫn ở ô tương ứng, số khớp truy vấn của loại mới. Các biến thể cột nhóm, cột và thanh xếp chồng, vùng chưa có luật ô quan sát được từ Nhom6; chúng mở sau buổi VM-D3 (xem Giả định).

**Kịch bản chấp nhận**:

1. **Cho** một visual đang chọn, **Khi** bấm biểu tượng loại hỗ trợ khác, **Thì** `visualType` đổi, vị trí, cỡ và `z` giữ nguyên, và visual vẽ lại theo loại mới.
2. **Cho** visual đổi loại, **Khi** loại mới có ô cùng vai trò (Trục X/Category, Trục Y/Y, Chú giải/Series, Chú thích công cụ/Tooltips…), **Thì** trường chuyển sang ô đó theo đúng thứ tự cũ.
3. **Cho** một trường không có ô nhận trong loại mới (loại không nhận hoặc ô đã đủ), **Khi** đổi loại, **Thì** trường đó bị bỏ khỏi visual và danh sách các trường bị bỏ được báo cho người dùng ngay sau thao tác; một lần ⌘Z trả lại visual cũ cùng đủ trường.
4. **Cho** visual có tham chiếu tới trường ở nơi khác trong `visual.json` (sắp xếp, bộ lọc cấp visual, định dạng theo trường) mà trường bị bỏ khi đổi loại, **Khi** đổi loại, **Thì** thao tác bị chặn và nêu lý do (như D2), không để tham chiếu treo trong file.
5. **Cho** định dạng riêng (`objects`) của visual cũ, **Khi** đổi loại, **Thì** chỉ giữ những phần dùng được cho loại mới; phần không dùng được bị bỏ (hoặc giữ nguyên nếu Desktop giữ: theo quan sát VM-D3).
6. **Cho** chế độ Xem, nhiều visual đang chọn, visual trong nhóm, hoặc loại đích chưa hỗ trợ, **Khi** bấm biểu tượng, **Thì** không đổi gì và nêu lý do.

---

### Câu chuyện 4 — Hộp văn bản và các nút ở ribbon Chèn (Ưu tiên: P2)

Nút "Hộp văn bản" và "Visual mới" ở ribbon Chèn thêm visual cùng cách với thư viện. Hộp văn bản mới có thể gõ nội dung ngắn; nội dung được lưu.

**Vì sao P2**: tiện lợi và cần cho báo cáo hoàn chỉnh, nhưng không chặn việc thêm visual dữ liệu.

**Kiểm thử độc lập**: bấm "Hộp văn bản" ở ribbon, hộp xuất hiện, chọn sẵn; sửa nội dung thành "Tiêu đề"; lưu, mở lại thấy "Tiêu đề".

**Kịch bản chấp nhận**:

1. **Cho** chế độ Sửa, **Khi** bấm "Hộp văn bản", **Thì** một hộp văn bản mới được thêm như Câu chuyện 1 (có nội dung mặc định ngắn).
2. **Cho** hộp văn bản đang chọn, **Khi** sửa nội dung (chỉ văn bản thuần một hoặc nhiều đoạn, kiểu chữ mặc định), **Thì** nội dung đổi, hoàn tác được và lưu được.
3. **Cho** nút "Visual mới" ở ribbon, **Khi** bấm, **Thì** thêm một visual mặc định (card) như bấm biểu tượng card ở thư viện.
4. **Cho** chế độ Xem, **Khi** các nút này hiện, **Thì** chúng mờ và nêu cần bật chế độ Sửa.

---

### Câu chuyện 5 — Hoàn tác, xoá, nhân bản chung một lịch sử (Ưu tiên: P2)

Thêm visual, đổi loại, thả trường, kéo, xoá, nhân bản đều nằm trong một lịch sử hoàn tác; một lần thêm hoặc một lần đổi loại là một bước.

**Vì sao P2**: tính chất đã có ở D1 và D2, ở đây cần giữ nó đúng cho thao tác mới.

**Kiểm thử độc lập**: thêm card, thả trường, đổi sang slicer, dời, xoá; ⌘Z lần lượt về trạng thái đầu từng bước một.

**Kịch bản chấp nhận**:

1. **Cho** chuỗi thao tác D1, D2, D3 đan xen, **Khi** hoàn tác từng bước, **Thì** mỗi bước quay lại trạng thái ngay trước đó, và về trạng thái lúc mở thì không còn dấu "đã sửa".
2. **Cho** visual mới (đã thêm, chưa lưu), **Khi** nhân bản, xoá, dời, đổi cỡ, **Thì** chạy như visual thường của D1.
3. **Cho** visual mới đã lưu rồi sửa tiếp (thả thêm trường, đổi loại), **Khi** lưu lần hai, **Thì** ghi đúng thay đổi lần hai lên phần đã có trong file.

---

### Trường hợp biên

- Thêm nhiều visual liên tiếp: mỗi visual có mã khác nhau, không trùng mã đã có trong báo cáo kể cả các mã đã dùng rồi bỏ (như D1).
- Trang nhỏ hơn cỡ mặc định của loại visual: cỡ được kẹp vừa trang.
- Đổi loại giữa hai loại có số ô tối đa khác nhau (ví dụ donut chỉ một Y): trường dư bị bỏ khỏi ô và được báo.
- Đổi loại visual có hierarchy hoặc cấp drill: giữ nếu loại mới nhận hierarchy ở ô tương ứng, nếu không thì bị bỏ và báo (hierarchy mới ngoài phạm vi).
- Đổi sang chính loại hiện tại: không làm gì, không tạo bước hoàn tác.
- Visual trong nhóm (`parentGroupName`) hoặc báo cáo định dạng cũ (`Report/Layout`): không thêm vào nhóm, không đổi loại; báo rõ (như D1).
- Hộp văn bản có nhiều đoạn hoặc kiểu chữ khác nhau: sửa nội dung thì giữ các đoạn và kiểu chữ không bị sửa; chỉ cho sửa văn bản.
- Loại `image`, `actionButton`, `pageNavigator`, `shape`: không thêm được ở lát này (cần tài nguyên hoặc cấu hình riêng); visual đã có thì đổi vị trí, xoá, nhân bản như D1 và không đổi loại.
- Bookmark: bookmark không nhắc visual mới (ghi bookmark là lát sau); xoá visual mới chưa lưu không đụng bookmark.
- Visual mới thêm khi Build pane đang hiện thông báo từ chối của D2: thông báo cũ được xoá.

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

**Thêm visual mới**

- **FR-001**: Ở chế độ Sửa, khi không chọn visual nào, bấm một biểu tượng loại hỗ trợ trong thư viện visual của Build pane PHẢI thêm một visual mới của loại đó vào trang đang mở và chọn nó.
- **FR-002**: Visual mới PHẢI có mã 20 ký tự hex không trùng mã nào trong báo cáo (kể cả mã đã dùng trong phiên), cỡ mặc định theo loại kẹp trong trang, vị trí ở giữa phần trang đang nhìn thấy (lệch một bậc nếu bị chiếm), và `z`, `tabOrder` lớn hơn mọi visual của trang.
- **FR-003**: Các nút "Visual mới" và "Hộp văn bản" ở ribbon (Trang chủ và Chèn) PHẢI thêm visual cùng cách (card mặc định và hộp văn bản); ở chế độ Xem PHẢI mờ và nêu lý do.
- **FR-004**: Loại hỗ trợ ở lát này gồm các loại vẽ được và có ô trong `WellRules` (bản đầu: card, thanh nhóm, cột 100%, đường, hai loại combo, donut, treemap, bản đồ hình, matrix, slicer; cột nhóm, cột và thanh xếp chồng, vùng và các biến thể cùng họ mở sau VM-D3) và hộp văn bản. Loại khác PHẢI bị từ chối kèm lý do, không thêm gì.
- **FR-005**: Visual mới chưa có trường PHẢI hiện trạng thái trống và dùng được các thao tác sửa trường của D2.

**Đổi loại**

- **FR-006**: Khi chọn đúng một visual ở chế độ Sửa, bấm biểu tượng loại hỗ trợ khác PHẢI đổi `visualType`, giữ vị trí, cỡ, `z`, và chuyển các trường sang ô cùng vai trò của loại mới theo thứ tự cũ.
- **FR-007**: Trường không có ô nhận trong loại mới PHẢI bị bỏ kèm thông báo liệt kê rõ các trường đó ngay sau thao tác; thao tác PHẢI hoàn tác được một bước, trả lại đủ trường.
- **FR-008**: Đổi loại PHẢI bị chặn (nêu lý do) khi nó làm mất một trường còn được nhắc ở sắp xếp, bộ lọc cấp visual hoặc định dạng theo trường (cùng quy tắc chặn của D2), cho tới khi quan sát được cách Desktop xử lý.
- **FR-009**: Định dạng riêng của visual cũ PHẢI được giữ hoặc bỏ theo quan sát Power BI Desktop (VM-D3); không để định dạng không hợp lệ với loại mới nằm trong file.
- **FR-010**: Không đổi gì và không tạo bước hoàn tác khi bấm biểu tượng của chính loại hiện tại; không đổi gì khi chế độ Xem, nhiều visual được chọn, visual trong nhóm, báo cáo định dạng cũ, hoặc loại đích chưa hỗ trợ.

**Hộp văn bản**

- **FR-011**: Hộp văn bản PHẢI sửa được nội dung văn bản (đoạn, dòng) mà giữ nguyên kiểu chữ của các đoạn không sửa; nội dung hoàn tác được và lưu được.

**Hoàn tác, xoá, nhân bản**

- **FR-012**: Thêm visual, đổi loại và mọi thao tác D1, D2 PHẢI chung một lịch sử hoàn tác; một lần thêm hoặc một lần đổi loại là một bước.
- **FR-013**: Xoá, nhân bản, dời, đổi cỡ của D1 PHẢI dùng được trên visual mới (kể cả chưa lưu và đã lưu).

**Lưu (tầng T1)**

- **FR-014**: Khi lưu, hệ thống PHẢI thêm một phần `visual.json` cho mỗi visual mới theo đúng cấu trúc Power BI Desktop ghi cho visual mới (theo quan sát Nhom6 và VM-D3), đặt ngay sau `visual.json` cuối của cùng trang; đổi loại PHẢI ghi lại `visualType` và `queryState` bằng ghép byte, giữ nguyên mọi byte khác.
- **FR-015**: Visual mới chưa lưu mà đã xoá PHẢI không có mặt trong file; visual đã lưu rồi bị xoá thì bỏ khỏi file như D1.
- **FR-016**: Đường lưu an toàn của D1 (kiểm trong bộ nhớ, ghi tạm, mở lại, sao lưu, chặn ghi `~/Downloads`, bỏ `SecurityBindings`) PHẢI áp nguyên cho thay đổi D3, và bước đọc lại PHẢI kiểm cả loại, vị trí và trường của visual mới và visual đã đổi loại.
- **FR-017**: Phần không sửa của file (trang không sửa, visual không đổi, mô hình dữ liệu) PHẢI giữ nguyên từng byte.

**Chất lượng**

- **FR-018**: Golden Phase B/C PHẢI vẫn khớp; truy vấn sinh ra cho visual chưa sửa PHẢI không đổi; số liệu của visual mới và visual đã đổi loại đến từ cùng engine và bộ sinh truy vấn (không có đường tính thứ hai).

### Thực thể chính

- **Visual mới**: một visual vừa thêm trong phiên, chưa có trong file: loại, mã, vị trí, cỡ, các ô trường (ban đầu trống).
- **Loại visual hỗ trợ**: tập loại thêm được và đổi tới được (kèm cỡ mặc định theo loại và bố cục ô).
- **Ánh xạ ô khi đổi loại**: quy tắc đưa trường từ ô của loại cũ sang ô của loại mới (theo vai trò), kèm danh sách trường bị bỏ.
- **Hộp văn bản**: visual không có truy vấn, nội dung là các đoạn văn bản có kiểu chữ.

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: Trên Nhom6 thêm ít nhất 4 loại visual khác nhau (card, biểu đồ thanh nhóm, matrix, hộp văn bản), thả trường vào, và đổi loại ít nhất 3 cặp giữ được trường (đường sang thanh nhóm, combo sang đường, donut sang treemap): visual vẽ lại đúng và số liệu khớp với truy vấn DAX tương ứng ở 100% các lần thử.
- **SC-002**: Lưu rồi mở lại trong BI Pro: loại, vị trí, cỡ, thứ tự `z`, ô và trường của mọi visual mới và visual đã đổi loại giống hệt trước khi lưu.
- **SC-003**: File đã lưu mở được trong Power BI Desktop (bạn kiểm tay trên VM), visual mới và visual đã đổi loại hiện đúng loại ở đúng chỗ, và số liệu khớp với BI Pro.
- **SC-004**: Visual không sửa, trang không sửa và mô hình dữ liệu khớp từng byte với file gốc (ngoài `SecurityBindings` như D1).
- **SC-005**: Thêm một visual hoặc đổi loại cho thấy kết quả (bố cục ô, trạng thái trống) ngay lập tức và, khi đã có trường, vẽ xong dưới 150 ms với visual thường và dưới 1 giây với visual nặng; lưu sau khi thêm visual mất dưới 1 giây.
- **SC-006**: 30/30 golden Phase B và các golden Phase C vẫn khớp; `swift test` không có test nào trượt thêm.
- **SC-007**: Hoàn tác về trạng thái lúc mở sau một chuỗi tuỳ ý thao tác D1, D2, D3 luôn trả trang và file về đúng trạng thái đầu (kiểm bằng test tự động trên chuỗi ngẫu nhiên có cả thêm visual và đổi loại).
- **SC-008**: Người dùng làm được chuỗi "bỏ chọn → bấm biểu tượng card → thả một measure → lưu thành → mở lại trong Power BI Desktop" mà không phải đọc hướng dẫn.

## Giả định

- Loại thêm được và đổi tới được ở bản đầu là loại có ô đã quan sát trong Nhom6 (11 loại dữ liệu và hộp văn bản); các biến thể cột nhóm, cột và thanh xếp chồng, vùng chờ VM-D3 cho tên ô rồi mới mở (không đoán tên ô). Card và slicer không đổi qua lại giữ trường được (card nhận measure, slicer nhận cột): đổi giữa hai loại đó chỉ giữ visual, trường bị bỏ và báo.
- Chỉ thêm visual loại dữ liệu đã vẽ được và hộp văn bản; chưa Format pane và định dạng mới, chưa thêm/xoá/đổi tên trang, chưa ghi bookmark và bộ lọc người dùng vào file, chưa sửa Filters pane, chưa hierarchy và drill mới, chưa phép gộp (chờ VM-D2), chưa các loại visual chưa vẽ được hay cần tài nguyên (scatter, gauge, KPI, table, hình ảnh, nút, điều hướng trang, hình, python/R, custom), chưa nhóm visual, chưa tầng T2/T3.
- Cỡ mặc định theo loại ở bản đầu lấy từ cỡ thường gặp trong Nhom6 (card 302×108, slicer 364×64, biểu đồ 616×380, matrix 616×380, hộp văn bản 400×100); sẽ chỉnh theo quan sát VM-D3 nếu Power BI Desktop dùng cỡ khác.
- Cấu trúc `visual.json` mới ở bản đầu theo khoá quan sát được ở visual cùng loại trong Nhom6 (không ghi `objects` và `visualContainerObjects` trống nếu Nhom6 cho thấy loại đó không bắt buộc); chốt theo VM-D3.
- Ánh xạ ô khi đổi loại ở bản đầu: cùng tên ô (`Category`, `Y`, `Series`, `Tooltips`, `Values`, `Rows`, `Columns`…) thì chuyển nguyên; ô khác tên (Y2 của combo sang loại không có Y2) thì chuyển vào ô cùng loại trường nếu còn chỗ, nếu không thì bỏ và báo. Quy tắc đầy đủ chốt theo VM-D3.
- Thư viện visual và ô trường dùng lại `VisualCatalog`, `WellRules`, chế độ Sửa (⌘E), chọn visual, hoàn tác, lưu, sao lưu của D1 và D2; không làm lại.
- Test trên VM Windows 11 do bạn làm tay; mình chuẩn bị file trong `build/d-out/` và `CHECKLIST.md`.
- Không thêm thư viện ngoài.
