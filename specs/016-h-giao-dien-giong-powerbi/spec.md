# Đặc tả tính năng: v1.3 (Phase H) — Giao diện BI Pro giống Power BI Desktop

**Thư mục spec:** `specs/016-h-giao-dien-giong-powerbi/`
**Nhánh:** `main` (không tạo nhánh riêng; việc giao cho agy chạy trong worktree riêng theo `CLAUDE.md`)
**Ngày lập:** 2026-11-21
**Trạng thái:** Đã duyệt (Q1–Q6) · đã qua analyze và sửa · sẵn sàng giao agy
**Đầu vào:** v1.3 Giao diện giống Power BI Desktop (Phase H): đưa giao diện BI Pro về giống Power BI Desktop 2.159, trọng tâm là thanh Ribbon, rồi khung cửa sổ, pane, thanh trang/trạng thái, màn hình khởi động/File/Options và các view DAX/TMDL/Model/Table.
**Tài liệu cấp trên:** [`docs/PHASE_H_UI_PARITY.md`](../../docs/PHASE_H_UI_PARITY.md) (mã yêu cầu `UI-A1` … `UI-G4`, đã duyệt Q1–Q6 ngày 2026-11-21). Mâu thuẫn thì sửa tài liệu đó trước.
**Bằng chứng:** `docs/phase-ui-evidence/vm-ui/` (Power BI Desktop 2.159, ảnh đã che tên tài khoản) và `docs/phase-ui-evidence/bipro-truoc/` (BI Pro trước khi sửa).

## Quan sát Power BI *(bắt buộc theo hiến pháp, nguyên tắc I)*

Đã quan sát trên Power BI Desktop 2.159 (VM Windows 11) trong hai buổi VM-UI và VM-UI2 ngày 2026-11-21, có người dùng cho phép agent bấm chuột Mac thật vào VM (ngoại lệ ghi tại đây theo hiến pháp: chỉ cho Phase H; ảnh cắt che tên tài khoản; dọn thư mục VM sau mỗi buổi). Chi tiết từng tab, nhóm, nút, menu thả xuống, số đo và màu nằm trong `docs/PHASE_H_UI_PARITY.md` mục 3. Tóm tắt phần ảnh hưởng thiết kế:

- **Bộ tab theo view.** Report: File · Home · Insert · Modeling · Design · View · Optimize · Help, thêm tab ngữ cảnh **Format** và **Data / Drill** khi chọn visual. Table view: File · Home · Help + **Table tools**, **Column tools**. Model, DAX query, TMDL: File · Home · Help.
- **Kiểu Ribbon.** Panel trắng nổi trên nền chrome `#F5F5F5`, nhãn nhóm chữ thường nằm dưới nhóm, nút lớn (biểu tượng + nhãn 1–2 dòng) và nút nhỏ (xếp dọc tối đa 3), nút có menu thả xuống mang mũi tên ▾, nút vô hiệu mờ; tab đang chọn gạch chân màu xanh lục, tab ngữ cảnh chữ xanh lục.
- **Khung cửa sổ.** Rail 5 biểu tượng (Report, Table, Model, DAX query, TMDL) có vạch chọn xanh lục và tooltip; Filters là dải dọc thu gọn; Visualizations và Data là hai pane phải; thanh trang có nút `+` xanh lục; thanh trạng thái có "Page n of m" và zoom.
- **Màu nhấn** xanh lục teal (≈ `#117865`), nền canvas quanh trang `#E6E6E6`.
- Phần chưa quan sát được ghi `[CHƯA QUAN SÁT]` trong tài liệu cấp trên (menu Recent sources/Transform data/More visuals/Sensitivity/Optimization presets/Language/Linguistic schema/Groups/Align/Group, hộp Customize theme, hover/pressed, ribbon thu gọn, Mobile layout); các chỗ đó làm theo suy luận hợp lý và đánh dấu `[SUY ĐOÁN]` trong code.

## Clarifications

### Session 2026-11-21

Không hỏi người dùng thêm câu nào: các điểm mơ hồ dưới đây trả lời được từ `docs/PHASE_H_UI_PARITY.md` và hiện trạng ứng dụng, nên được quyết theo tài liệu (quy ước "quyết theo design") và ghi lại.

- Q: Khi cửa sổ hẹp hơn tổng bề rộng các nhóm nút thì Ribbon xử lý thế nào? → A: Cuộn ngang trong panel (giữ cơ chế hiện có), không gom nhóm vào menu; nhãn nhóm và nút không bị cắt cụt.
- Q: Bánh răng ở thanh tiêu đề và Options and settings ▸ Options trong File khác nhau ra sao? → A: Bánh răng mở cửa sổ Cài đặt ứng dụng hiện có (`⌘,`: ngôn ngữ, giao diện, hướng dẫn); Options mở hộp GLOBAL / CURRENT FILE dùng lại các tuỳ chọn tệp hiện có; mục chưa có tính năng hiện vô hiệu. Hai nơi không lặp mục.
- Q: Danh sách Recent ở màn hình khởi động và trang Home của File lấy từ đâu? → A: Danh sách tài liệu gần đây của macOS (cùng nguồn "Mở gần đây"); cột Opened là lần mở gần nhất; tệp không còn tồn tại hiện mờ và không mở được.
- Q: Chế độ Sửa/chỉ xem lưu theo tài liệu hay theo ứng dụng? → A: Theo ứng dụng (tuỳ chọn người dùng), mặc định Sửa; đổi ở menu View, không ghi gì vào `.pbix`.

## Kịch bản người dùng & kiểm thử *(bắt buộc)*

Người dùng chính: người đã quen Power BI Desktop, mở BI Pro trên macOS để xem và sửa báo cáo `.pbix`. Mọi story chỉ đổi giao diện; không đổi số liệu, engine hay byte `.pbix`.

### User Story 1 — Khung Ribbon và bộ tab giống Power BI Desktop (Ưu tiên: P1)

Người dùng mở một báo cáo và thấy hàng tab, panel Ribbon, kiểu nút, tab ngữ cảnh và nút Share đúng như Power BI Desktop.

**Vì sao P1:** Ribbon là trọng tâm yêu cầu của người dùng và là mặt tiền quyết định cảm giác "giống". Các story sau dựng nội dung lên khung này.

**Kiểm thử độc lập:** Mở cùng một `.pbix` ở từng view, đếm và so tên/thứ tự tab với bảng tab của Power BI Desktop; kiểm kiểu tab đang chọn, tab ngữ cảnh, nút thu gọn, kiểu nút lớn/nhỏ/▾ bằng ảnh đối chiếu.

**Kịch bản chấp nhận:**

1. **Cho** báo cáo mở ở Report view, **Khi** xem hàng tab, **Thì** thấy File · Home · Insert · Modeling · Design · View · Optimize · Help theo đúng thứ tự, chữ thường, tab đang chọn đậm có gạch chân màu nhấn.
2. **Cho** Table / Model / DAX query / TMDL view, **Khi** xem hàng tab, **Thì** chỉ thấy File · Home · Help (Table view thêm Table tools và Column tools).
3. **Cho** đang chọn một visual, **Khi** xem hàng tab, **Thì** thấy thêm tab Format và Data / Drill chữ màu nhấn, không có vạch phân cách; bỏ chọn visual thì hai tab biến mất và tab đang xem trở về Home nếu nó vừa biến mất.
4. **Cho** panel Ribbon, **Khi** bấm nút `^` góc dưới phải, **Thì** Ribbon thu gọn chỉ còn hàng tab và trạng thái này được nhớ cho lần mở sau.
5. **Cho** tab File, **Khi** bấm, **Thì** mở màn hình File (story 7) thay vì hiện Ribbon.
6. **Cho** nút Share ở mép phải hàng tab, **Khi** rê chuột, **Thì** nút hiện vô hiệu kèm tooltip nêu BI Pro chưa hỗ trợ chia sẻ.

---

### User Story 2 — Nội dung Ribbon Report view khớp từng nhóm và nút (Ưu tiên: P1)

Mỗi tab Home, Insert, Modeling, Design, View, Optimize, Help có đúng các nhóm và nút của Power BI Desktop, theo đúng thứ tự, kiểu nút và trạng thái bật/tắt theo ngữ cảnh.

**Vì sao P1:** Người dùng đòi giống ở mức nút; nút nào đang chạy được vẫn phải chạy, nút chưa có tính năng phải hiện đúng chỗ.

**Kiểm thử độc lập:** Với từng tab, so danh sách nhóm → nút (tên, thứ tự, kiểu, trạng thái) với bảng chuẩn trong `docs/PHASE_H_UI_PARITY.md` mục 3.5 và 3.10 bằng test dữ liệu Ribbon và ảnh đối chiếu; bấm thử các nút đang chạy được.

**Kịch bản chấp nhận:**

1. **Cho** tab Home, **Khi** xem, **Thì** thấy đủ nhóm Clipboard · Data · Queries · Insert · Calculations · Sensitivity · Share · Copilot với đúng nút của Power BI Desktop; nút chưa có tính năng thật (OneLake catalog, Dataverse, Sensitivity, Publish, Prep data for AI, Copilot, New visual calculation) hiện vô hiệu có tooltip nêu lý do.
2. **Cho** báo cáo trống, **Khi** xem Home, **Thì** các nút cần dữ liệu hoặc lựa chọn (Cut, Copy, Format painter, Refresh, New measure, Quick measure…) vô hiệu y như Power BI Desktop; khi đã có dữ liệu thì bật.
3. **Cho** tab Insert, **Khi** xem, **Thì** thấy nhóm Pages · Visuals · AI visuals · Power Platform · Elements · Sparklines; Buttons ▾ và Shapes ▾ mở đúng danh sách ở mục 3.10; New page ▾ có New page và Duplicate page.
4. **Cho** tab Modeling, **Khi** xem, **Thì** thấy Relationships · Calculations · Calendars (Mark as date table) · Page refresh · Parameters · Security · Q&A; nút chưa có tính năng vô hiệu có tooltip.
5. **Cho** tab Design, **Khi** xem, **Thì** thấy thư viện ô mẫu theme, Theme gallery, Customize theme, Download theme, Import theme, Page size, Page background, Wallpaper; menu Themes ▾ có banner, "This report", "Power BI" và Theme gallery; chọn một theme áp dụng được và hoàn tác được như hiện nay.
6. **Cho** tab View, **Khi** xem, **Thì** thấy Page view ▾ (Fit to page / Fit to width / Actual size), Mobile layout (vô hiệu), ba hộp kiểm Gridlines · Snap to grid · Lock objects, và nhóm Show panes (Filters, Bookmarks, Selection, Performance analyzer, Sync slicers) mà không còn nút bật/tắt Data hay Visualizations.
7. **Cho** tab Optimize và Help, **Khi** xem, **Thì** thấy đúng các nhóm và nút ở mục 3.5; Help ▸ About mở hộp Giới thiệu hiện có.
8. **Cho** Refresh ▾, **Khi** mở, **Thì** có ba mục Schema and data · Schema · Data (mục BI Pro chưa tách riêng thì vô hiệu có tooltip).

---

### User Story 3 — Tab ngữ cảnh và Ribbon của Table, Model, DAX, TMDL (Ưu tiên: P1)

Chọn visual, bảng, cột, hoặc chuyển view thì Ribbon đổi đúng như Power BI Desktop.

**Vì sao P1:** Đây là phần Ribbon người dùng chạm nhiều nhất khi tác giả hoá báo cáo và mô hình.

**Kiểm thử độc lập:** Chọn visual → kiểm Format và Data / Drill; vào Table view chọn cột → kiểm Table tools và Column tools; vào Model, DAX, TMDL → kiểm Home.

**Kịch bản chấp nhận:**

1. **Cho** đang chọn một visual, **Khi** mở tab Format, **Thì** thấy Interactions (Edit interactions, ô "Apply drill down filters to") và Arrange (Bring forward ▾, Send backward ▾, Selection, Align ▾, Group ▾); các thao tác Group/Ungroup/Merge hiện có vẫn dùng được qua menu Group ▾.
2. **Cho** đang chọn một visual, **Khi** mở tab Data / Drill, **Thì** thấy Show · Interactions · Drill actions · Data groups · AI với đúng nút; Drill up/down, Expand, Show as a table (Visual table) vẫn chạy như hiện nay.
3. **Cho** Table view, **Khi** chọn bảng rồi cột, **Thì** Table tools có Structure (Name) · Relationships · Calculations · Calendars, Column tools có Structure (Name, Data type) · Formatting · Properties · Sort · Groups · Relationships · Calculations; đổi tên, kiểu dữ liệu, định dạng, tóm tắt, danh mục, sắp xếp theo cột vẫn chạy và hoàn tác được.
4. **Cho** Model view, **Khi** xem Home, **Thì** thấy Calculations có thêm Calculation group, nhóm Parameters và Q&A (vô hiệu nếu chưa có tính năng) và không có Quick measure.
5. **Cho** DAX query view và TMDL view, **Khi** xem Home, **Thì** thấy Clipboard + Editing (Format, Comment/Uncomment cho DAX, Find, Replace, Command palette) đúng bảng 3.6; các nút Run / Update model with changes (DAX) và Apply / Preview (TMDL) nằm phía trên trình soạn thảo và vẫn chạy như hiện nay.

---

### User Story 4 — Khung cửa sổ, thanh tiêu đề, rail và màu sắc (Ưu tiên: P2)

Cửa sổ có thanh tiêu đề, rail 5 biểu tượng, màu nhấn xanh lục và nền canvas giống Power BI Desktop nhưng vẫn là cửa sổ macOS.

**Vì sao P2:** Làm sau Ribbon; không có nó Ribbon mới vẫn dùng được nhưng nhìn tổng thể chưa giống.

**Kiểm thử độc lập:** Chụp cửa sổ ở Light/Dark, đối chiếu số đo và màu với mục 3.1; bấm từng biểu tượng rail.

**Kịch bản chấp nhận:**

1. **Cho** cửa sổ tài liệu, **Khi** xem thanh tiêu đề, **Thì** thấy traffic lights macOS, rồi Lưu · Hoàn tác · Làm lại · tên tệp kèm "Last saved" có menu ▾, ô Search ở giữa, bánh răng Cài đặt, nút chuyển sáng/tối và nút Share; không còn nút Export riêng (Export nằm trong File).
2. **Cho** rail bên trái, **Khi** xem, **Thì** luôn có 5 biểu tượng (Report, Table, Model, DAX query, TMDL) rộng ≈ 42 pt, mục đang chọn có vạch dọc màu nhấn, rê chuột hiện tooltip tên view, không có bánh răng ở đáy rail.
3. **Cho** màu nhấn, **Khi** xem tab, nút Share, nút `+` thêm trang, công tắc bật, **Thì** dùng màu xanh lục teal; màu chủ đề biểu đồ của báo cáo giữ nguyên.
4. **Cho** nền quanh trang báo cáo, **Khi** xem ở chế độ sáng, **Thì** là xám trung tính `#E6E6E6`, giấy trang báo cáo vẫn trắng/đúng màu tác giả; Dark Mode vẫn đủ tương phản.
5. **Cho** tài liệu vừa mở, **Khi** chưa đổi chế độ, **Thì** ở chế độ Sửa như Power BI Desktop; chế độ "chỉ xem" vẫn có trong menu View như một lựa chọn bảo vệ tệp.

---

### User Story 5 — Các pane Filters, Visualizations, Data (Ưu tiên: P2)

Pane giống Power BI Desktop về bố cục, thứ tự và cách thu gọn.

**Vì sao P2:** Người dùng thao tác hằng ngày nhưng nội dung đã có, chỉ cần sắp lại và đổi kiểu.

**Kiểm thử độc lập:** Mở báo cáo, chọn visual, so từng pane với ảnh `p_format.png`, `o_now.png`, `v_tmdl_2.png`.

**Kịch bản chấp nhận:**

1. **Cho** Report view, **Khi** mới mở, **Thì** Filters là dải dọc thu gọn rộng ≈ 31 pt (mũi tên «, biểu tượng phễu, chữ xoay dọc) và mở rộng khi bấm hoặc khi chọn visual.
2. **Cho** pane Visualizations, **Khi** xem, **Thì** có tiêu đề + `»`, nhãn "Build visual", hàng ba biểu tượng (Build, Format, Analytics), lưới 6 cột theo thứ tự của Power BI Desktop, các well có khung nét đứt "Add data fields here", cuối pane là Drill through (Cross-report, Keep all filters).
3. **Cho** đang chọn visual và mở Format, **Khi** xem, **Thì** có ô Search, hai tab Visual / General và danh sách thẻ gập có công tắc On/Off khi áp dụng.
4. **Cho** pane Data, **Khi** xem, **Thì** có ô Search, cây bảng, ô tích màu nhấn cho trường đang dùng; ở Model/DAX/TMDL view có hai tab Tables / Model với cây "Semantic model" có số lượng từng loại; pane không còn thanh trạng thái riêng.

---

### User Story 6 — Thanh trang và thanh trạng thái (Ưu tiên: P2)

Thanh trang và thanh trạng thái toàn cửa sổ giống Power BI Desktop.

**Vì sao P2:** Chi tiết nhỏ nhưng xuất hiện ở mọi view.

**Kiểm thử độc lập:** Mở báo cáo nhiều trang, thêm/đổi trang, kéo thanh zoom; đối chiếu ảnh `o_now.png` và `t_colsel.png`.

**Kịch bản chấp nhận:**

1. **Cho** thanh trang, **Khi** xem, **Thì** có biểu tượng Desktop/Phone layout (Phone vô hiệu), mũi tên ◂ ▸, tab trang chữ thường (tab chọn nền trắng, gạch dưới màu nhấn, trang ẩn có biểu tượng mắt gạch), nút `+` vuông màu nhấn; thêm, đổi tên, xoá, ẩn trang hiện có vẫn chạy.
2. **Cho** thanh trạng thái, **Khi** xem ở Report view, **Thì** trái là "Page n of m", phải là thanh trượt zoom với `−`/`+`, phần trăm và nút fit page; ở Table view là "Table: … (n rows) Column: … (n distinct values)", ở DAX/TMDL là "Query n of m"/"Script n of m".

---

### User Story 7 — Màn hình khởi động, File, Options, báo cáo trống (Ưu tiên: P3)

Khi chưa mở tệp và khi bấm File, người dùng thấy màn hình giống Power BI Desktop; hộp Options có cùng cấu trúc.

**Vì sao P3:** Chạm ít hơn Ribbon nhưng là ấn tượng đầu tiên và điểm vào quen thuộc.

**Kiểm thử độc lập:** Mở app không tệp; mở tệp rồi bấm File; bấm Options and settings ▸ Options; đối chiếu với ảnh hai ảnh người dùng gửi và `f_file.png`, `dd_options_dialog.png`.

**Kịch bản chấp nhận:**

1. **Cho** app mở không tệp, **Khi** xem, **Thì** thấy rail Home/Open + Sign out/Options and settings/About, khối "Select a data source or start with a blank report" với 6 thẻ (Blank report, OneLake catalog [vô hiệu], Excel workbook, SQL Server, Learn with sample data [vô hiệu], Get data from other sources) và danh sách Recent (Name / Location / Opened).
2. **Cho** tab File, **Khi** mở, **Thì** có mũi tên quay lại và các mục Home · Open — Save · Save as · Share · Get data · Import · Export · Publish — Sign out · Options and settings · About; mục chưa có tính năng vô hiệu, mục có tính năng (Open, Save, Save as, Get data, Export PDF/PNG/CSV, About, Options) chạy như hiện nay.
3. **Cho** Options and settings ▸ Options, **Khi** mở, **Thì** có cột GLOBAL / CURRENT FILE đúng danh sách mục ở mục 3.10, nội dung Data Load (Type Detection, Time intelligence, DAX Behavior…) nối vào các tuỳ chọn tệp hiện có, nút OK/Cancel.
4. **Cho** báo cáo chưa có dữ liệu, **Khi** xem canvas, **Thì** thấy "Add data to your report", dòng phụ có chữ **Data** đậm, bốn thẻ có nửa trên tô màu nhạt (xanh lục, xanh dương, vàng, xám) và liên kết "Get data from another source →".

---

### User Story 8 — Hoàn thiện view DAX, TMDL, Model, Table (Ưu tiên: P3)

Bố cục trong các view mã và mô hình giống Power BI Desktop.

**Vì sao P3:** Phần ruột các view đã chạy; chỉ cần khung quanh giống.

**Kiểm thử độc lập:** Vào từng view và đối chiếu `v_dax_1.png`, `v_tmdl_2.png`, `v_model_1.png`, `t_colsel.png`.

**Kịch bản chấp nhận:**

1. **Cho** DAX query view, **Khi** xem, **Thì** có dải thông báo "DAX queries will be saved to your model…" đóng được, hàng nút Run (màu nhấn) + Update model with changes (n), khu Results có trạng thái trống minh hoạ, tab "Query n" và `+`.
2. **Cho** TMDL view, **Khi** xem, **Thì** có hàng Apply / Preview, khu dưới Problems (n) / Output, tab "Script n" và `+`; lần đầu mở hiện hộp giới thiệu có thể đóng và không hiện lại.
3. **Cho** Model view, **Khi** xem, **Thì** có pane Properties (nhóm Cards với ba công tắc) giữa canvas và pane Data, tab dưới "All tables" và `+`, và thanh trạng thái có nút đặt lại bố cục (Sắp xếp lại) và fit (Vừa màn hình) cùng thanh zoom.
4. **Cho** Table view, **Khi** xem, **Thì** vẫn có thanh công thức và lưới như hiện nay, cộng chân trạng thái ở Story 6.

---

### Trường hợp biên

- Cửa sổ hẹp: Ribbon cuộn ngang trong panel, không gom nhóm vào menu và không cắt cụt nhãn nhóm làm mất nút.
- Đổi view khi đang ở tab chỉ tồn tại ở view cũ (ví dụ Insert sang Table view): tự về Home.
- Tab ngữ cảnh đang chọn mà lựa chọn biến mất: tự về Home.
- Chế độ tiếng Anh: nhãn dùng đúng chữ của Power BI Desktop; tiếng Việt: giữ bản dịch hiện có.
- Dark Mode: chrome, Ribbon, pane đủ tương phản; giấy trang báo cáo giữ nguyên màu tác giả.
- Tệp không có mô hình hoặc chế độ chỉ xem: nút cần mô hình/sửa vô hiệu kèm lý do trong tooltip, không báo lỗi.
- VoiceOver: mọi nút, tab, mục rail có nhãn đọc được; tab đang chọn và nút bật/tắt báo đúng trạng thái.
- Tooltip và phím tắt macOS hiện có (⌘Z, ⇧⌘R, ⌘,…) giữ nguyên; không thêm phím gợi ý kiểu Alt của Windows.

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

**Ribbon (nhóm A)**

- **FR-001**: Hệ thống PHẢI hiển thị bộ tab theo view đúng bảng ở mục "Quan sát Power BI" (thêm File, Design, Optimize; Table/Model/DAX/TMDL chỉ còn File · Home · Help và tab công cụ ngữ cảnh). *(UI-A1)*
- **FR-002**: Hàng tab PHẢI dùng chữ thường, tab đang chọn đậm có gạch chân màu nhấn, tab ngữ cảnh chữ màu nhấn không có vạch phân cách, nút Share neo mép phải ở trạng thái vô hiệu kèm tooltip. *(UI-A2)*
- **FR-003**: Panel Ribbon PHẢI là nền trắng nổi trên chrome, cao ≈ 98 pt, nhãn nhóm chữ thường nằm dưới nhóm, có vạch dọc mảnh giữa nhóm và nút `^` thu gọn có nhớ trạng thái. *(UI-A3)*
- **FR-004**: Nút Ribbon PHẢI có hai cỡ (lớn: biểu tượng + nhãn tối đa 2 dòng; nhỏ: xếp dọc tối đa 3 hàng), có kiểu ▾ cho nút có menu, và trạng thái vô hiệu mờ đồng nhất; mọi nút vô hiệu PHẢI có tooltip nêu lý do. *(UI-A4, UI-A13)*
- **FR-005**: Tab Home (Report) PHẢI có đúng 8 nhóm và thứ tự nút của bảng 3.5; nhóm Arrange chuyển sang tab Format. *(UI-A5)*
- **FR-006**: Tab Insert PHẢI có 6 nhóm; Buttons ▾, Shapes ▾, New page ▾, More visuals ▾ PHẢI mở đúng nội dung ghi ở mục 3.5/3.10. *(UI-A6)*
- **FR-007**: Tab Modeling PHẢI có 7 nhóm; Mark as date table nằm ở nhóm Calendars. *(UI-A7)*
- **FR-008**: Tab Design PHẢI có nhóm Themes (thư viện ô mẫu + Theme gallery + Customize/Download/Import theme), Customize page và Help; menu Themes ▾ theo mục 3.10; bỏ Themes khỏi tab View. *(UI-A8)*
- **FR-009**: Tab View PHẢI có Scale to fit (Page view ▾ 3 mục), Mobile layout, Page options (3 hộp kiểm) và Show panes; không có nút bật/tắt Data hay Visualizations. Tab Optimize PHẢI có 5 nút ở bảng 3.5. *(UI-A9)*
- **FR-010**: Tab Format và Data / Drill PHẢI theo bảng 3.5; Group/Ungroup/Merge dùng qua menu Group ▾. *(UI-A10)*
- **FR-011**: Table view PHẢI có Home theo 3.6, Table tools và Column tools theo 3.6, giữ nguyên hành vi đổi tên, kiểu, định dạng, tóm tắt, danh mục, sắp xếp. *(UI-A11)*
- **FR-012**: Model Home PHẢI có Calculation group, Parameters, Q&A (vô hiệu nếu chưa có tính năng); DAX Home và TMDL Home PHẢI theo 3.6, với Run/Update model/Apply/Preview chuyển xuống thanh phía trên trình soạn thảo. *(UI-A12, UI-G1, UI-G2)*
- **FR-013**: Nút Windows-only hoặc cloud (Copilot, Publish, Share, Dataverse, OneLake, Power Apps, Power Automate, Q&A, Sensitivity, Prep data for AI) PHẢI hiện đúng vị trí ở trạng thái vô hiệu có tooltip, không ẩn. *(Q4)*
- **FR-014**: Mọi nút đang chạy được ở phiên bản 1.2 PHẢI vẫn chạy với hành vi cũ (kể cả hoàn tác) sau khi chuyển vị trí, kể cả nút không có trong Power BI Desktop: *Sắp xếp lại* và *Vừa màn hình* của Model view (chuyển thành nút đặt lại/fit trên thanh trạng thái Model view), *Xuất TMDL* (chuyển vào File ▸ Export) và *Sao chép* của TMDL view (nút Copy ở Clipboard). *(Hồi quy)*

**Khung cửa sổ (nhóm B)**

- **FR-015**: Thanh tiêu đề PHẢI giữ traffic lights macOS và có Lưu, Hoàn tác, Làm lại, tên tệp + "Last saved" kèm menu, ô Search, Cài đặt, chuyển sáng/tối, Share; nút Export riêng bị bỏ và Export nằm trong File. *(UI-B1)*
- **FR-016**: Rail PHẢI luôn có 5 biểu tượng rộng ≈ 42 pt, vạch chọn dọc màu nhấn, tooltip tên view, không bánh răng ở đáy. Khi tài liệu chưa có mô hình, chọn Table/Model/DAX/TMDL PHẢI hiện trạng thái trống song ngữ "Chưa có dữ liệu. Thêm dữ liệu để dùng chế độ này." / "No data yet. Add data to use this view.", không lỗi. *(UI-B2)*
- **FR-017**: Màu nhấn PHẢI là teal `#117865` (chế độ sáng) và biến thể sáng hơn cho Dark Mode; nền canvas quanh trang `#E6E6E6` (sáng); chrome `#F5F5F5` (sáng). *(UI-B3, UI-F1, UI-F2)*
- **FR-018**: Tài liệu mở mặc định ở chế độ Sửa **với điều kiện** bấm một điểm dữ liệu ở chế độ Sửa vẫn lọc chéo như hiện nay (kiểm ở tác vụ T052); nếu điều kiện không đạt, giữ mặc định Xem hiện tại và chỉ chuyển công tắc Xem/Sửa vào menu View, kèm ghi chú cho người dùng. Chế độ chỉ xem là lựa chọn của người dùng trong menu View, lưu theo ứng dụng, không ghi vào `.pbix`. *(Q2, R-02)*
- **FR-019**: Số đo khung (thanh tiêu đề, hàng tab, panel Ribbon, rail, thanh trang, thanh trạng thái, pane) PHẢI lệch ≤ 2 pt so với bảng ở mục 3.1 của tài liệu cấp trên. *(UI-F2)*

**Pane, thanh trang, trạng thái (nhóm C, D)**

- **FR-020**: Filters PHẢI thu gọn mặc định thành dải dọc ≈ 31 pt và mở rộng khi bấm hoặc khi chọn visual; Visualizations và Data khi thu gọn bằng `»` PHẢI thành dải dọc ≈ 31 pt (chữ xoay dọc, mũi tên «) và bấm vào để mở lại, vì tab View không còn nút bật/tắt hai pane này. *(UI-C1)*
- **FR-021**: Visualizations PHẢI có hàng 3 biểu tượng tab, lưới 6 cột theo thứ tự ở `contracts/visual-gallery.md` (visual BI Pro chưa hỗ trợ hiện mờ kèm tooltip, không ẩn), well khung nét đứt, và Drill through ở cuối; Format có ô Search, tab Visual/General, thẻ gập. *(UI-C2, C3, C4)*
- **FR-022**: Data PHẢI có ô tích màu nhấn cho trường đang dùng và, ở Model/DAX/TMDL view, hai tab Tables/Model với cây "Semantic model"; thanh trạng thái riêng của từng pane bị bỏ. *(UI-C5, C6)*
- **FR-023**: Thanh trang và thanh trạng thái toàn cửa sổ PHẢI theo mô tả Story 6. *(UI-D1, D2)*

**File, khởi động, view mã (nhóm E, G)**

- **FR-024**: Màn hình khởi động, File backstage, hộp Options và báo cáo trống PHẢI theo Story 7; mục chưa có tính năng vô hiệu. *(UI-E1 … E4)*
- **FR-025**: DAX/TMDL/Model/Table view PHẢI có các thành phần bố cục ở Story 8. *(UI-G1 … G4)*

**Ràng buộc chung**

- **FR-026**: Thay đổi PHẢI không đổi byte `.pbix` khi mở rồi lưu, không đổi kết quả DAX/M, không thêm thư viện ngoài.
- **FR-027**: Mọi nhãn mới PHẢI có cả tiếng Việt và tiếng Anh (tiếng Anh dùng đúng chữ của Power BI Desktop), hỗ trợ Dark Mode và có nhãn VoiceOver; tab ngữ cảnh và nút bật/tắt báo đúng trạng thái.
- **FR-028**: Phần chưa quan sát được PHẢI đánh dấu `[SUY ĐOÁN]` trong code (mỗi mục `observed == false` có `note` không rỗng) và ghi trong tệp bằng chứng.

### Thực thể chính

- **Mô hình Ribbon**: danh sách có thứ tự gồm tab → nhóm → nút; mỗi nút có tên song ngữ, cỡ (lớn/nhỏ), có menu hay không, điều kiện bật, lý do vô hiệu. Là nguồn sự thật duy nhất cho cả hiển thị và kiểm thử đối chiếu.
- **Tab ngữ cảnh**: tab chỉ hiện khi có lựa chọn phù hợp (visual, bảng, cột).
- **Bảng số đo và màu giao diện**: tập số đo (pt) và màu (sáng/tối) dùng chung cho mọi thành phần khung.
- **Trạng thái giao diện lưu giữ**: Ribbon thu gọn/mở, chế độ Sửa/chỉ xem, đã xem hộp giới thiệu TMDL.

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: 100% tab, nhóm và nút ở 15 Ribbon cần đối chiếu (Report: Home, Insert, Modeling, Design, View, Optimize, Help, Format, Data/Drill; Table view: Home, Table tools, Column tools; Model, DAX, TMDL Home) khớp danh mục trong tài liệu cấp trên về tên, thứ tự, kiểu nút và trạng thái; kiểm bằng test tự động trên mô hình Ribbon và bằng ảnh đối chiếu cạnh nhau.
- **SC-002**: Mọi số đo khung lệch ≤ 2 pt và màu nhấn/chrome/canvas lệch ≤ 3% độ sáng so với Power BI Desktop; kiểm bằng ảnh chụp cùng kích thước.
- **SC-003**: 0 hồi quy: 100% test đơn vị và golden nặng đang xanh ở v1.2 (2 478 và 124) vẫn xanh; mở rồi lưu `.pbix` không đổi byte so với trước thay đổi.
- **SC-004**: Người quen Power BI Desktop tìm đúng vị trí 10 lệnh thường dùng (Get data, New visual, New measure, Manage relationships, Format painter, Themes, Page view, Mark as date table, Manage roles, Export) ở lần bấm đầu tiên trong ≥ 9/10 lệnh khi thử với bản dựng (người dùng tự thử, ghi vào checklist).
- **SC-005**: Cổng ảnh Desktop: ảnh BI Pro và Power BI Desktop của cùng một `.pbix` được đặt cạnh nhau cho từng tab/view ở mục SC-001; người dùng duyệt "giống bố cục và nhận diện" cho toàn bộ.
- **SC-006**: 100% nhãn mới có bản Việt/Anh và đạt kiểm tương phản ở Dark Mode; 100% nút/tab mới có nhãn VoiceOver (kiểm bằng test và rà bằng tay).
- **SC-007**: Dựng lại `build/BI Pro.app` v1.3.0, `codesign --verify --deep --strict` đạt, mở được trên macOS 15 và tệp mẫu `Nhom6` hiển thị đủ như trước.

## Giả định

- Chuẩn so sánh là Power BI Desktop 2.159 trên Windows 11; Windows-only (Copilot, Publish, Dataverse, OneLake…) không có tính năng thật trong BI Pro.
- Biểu tượng Ribbon dùng bộ SF Symbols hai màu ở lần này (quyết định Q3); thay bằng bộ tự vẽ giống Fluent để sau, ngoài phạm vi.
- Phông chữ giữ SF Pro, không nhúng Segoe UI; cỡ chữ theo bảng ở tài liệu cấp trên.
- Quyết định Q1–Q6 đã duyệt ngày 2026-11-21; Q1 (màu nhấn teal) và Q4 (nút AI/cloud hiện vô hiệu thay vì ẩn) sửa hiến pháp mục "Ràng buộc sản phẩm" từ phiên bản 1.2.0 của hiến pháp.
- Phần ngoài phạm vi: engine DAX/M, định dạng `.pbix`, thêm tính năng thật cho các nút đang vô hiệu, Mobile layout, bộ biểu tượng Fluent tự vẽ, ribbon thu gọn kiểu Windows nâng cao, nhúng phông Segoe UI.
- Cổng cuối (H6) có thể cần một buổi VM để chụp đối chiếu; người dùng đã cho phép lái VM cho Phase H theo cách ghi ở mục Quan sát.
- Giao việc cho agy theo `CLAUDE.md` và skill `agy-delegation` (worktree riêng, bảng sở hữu file, báo cáo ở `docs/tasks/`); Ribbon và bảng màu/số đo là phần dùng chung của mọi pha nên các pha H1–H3 chạy tuần tự, chỉ H4–H5 (pane, khởi động) có thể song song nếu bảng sở hữu file không giao nhau.
