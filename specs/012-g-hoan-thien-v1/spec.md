# Đặc tả tính năng: Phase G — Hoàn thiện ứng dụng (v1.0)

**Nhánh**: `main` (không tạo nhánh riêng)

**Ngày tạo**: 2026-11-21

**Trạng thái**: Đã duyệt (2026-11-21)

## Làm rõ

### Phiên 2026-11-21
- **Dark Mode trên Report Canvas**: giữ nguyên nền trang báo cáo của file `.pbix` (chỉ chuyển tối khung ứng dụng, backdrop, pane, hộp thoại và 4 workspace Table/Model/DAX/TMDL).
- **Phạm vi song ngữ**: dịch toàn bộ UI người dùng thấy (Title bar, Ribbon, Rail, Status bar, Panes, Settings, Onboarding, các hộp thoại chính, nhãn phép gộp); giữ nguyên chuỗi lỗi kỹ thuật tầng thấp trong `PBIXKit`/`DAXEngine`/`MEngine`.
- **Quick Look `.pbix`**: tự biên dịch & đóng gói `.appex` ký ad-hoc trực tiếp trong `scripts/build-app.sh`, spike kiểm chứng với `qlmanage` ngay Đợt 0.

**Đầu vào**: Mục "Phase G: Hoàn thiện (2–3 tuần) → **v1.0**" trong `docs/BIPRO_BUILD_PLAN.md`:
- Export PDF / PNG / CSV
- Quick Look cho `.pbix`
- Dark Mode
- VoiceOver (trợ năng)
- Song ngữ Tiếng Việt và Tiếng Anh
- Biểu tượng ứng dụng (App Icon)
- Cài đặt ứng dụng (Settings)
- Hướng dẫn lần đầu (Onboarding)

Cấp trên: `docs/BIPRO_BUILD_PLAN.md` (§1, §5 Phase G), `UIdesign/lumen_analytics_design_system/DESIGN.md`, `.specify/memory/constitution.md`, `docs/STATE.md`. Mâu thuẫn thì sửa `docs/` trước.

**Phạm vi**: hoàn thiện trải nghiệm ứng dụng native macOS cho mốc **v1.0** trên nền M1–M3 đã xong (Phase A–F và `specs/011` Phase 9). Không thay đổi ngữ nghĩa engine DAX, engine M hay định dạng ghi `.pbix` (T1/T2/T3). Không thêm AI/Copilot (theo quyết định đã chốt). Không thêm thư viện bên ngoài (Hiến pháp III).

## Quan sát Power BI

Ghi lại hành vi chuẩn của Power BI Desktop (kết hợp chuẩn HIG của macOS 15 Sequoia cho phần thuần macOS như Quick Look, Dark Mode, Settings, VoiceOver, App Icon). Không dịch ngược.

**Hiện trạng trong BI Pro** (đọc từ mã nguồn):
- **Menu Xuất** (`Sources/BIPro/Shell/ShellView.swift` L96–106): đã có nút `Xuất` trên Title bar với 3 mục bị vô hiệu hoá (`PDF…`, `Ảnh PNG của trang…`, `Dữ liệu visual ra CSV…`, tooltip *"Xuất PDF/PNG/CSV có ở Phase G"*). `QueryResultsView.swift` đã có mẫu xuất CSV bảng kết quả DAX; `Ribbon.swift` đã có mẫu xuất thư mục TMDL.
- **Nút Cài đặt** (`ShellView.swift` L233–238): đã có biểu tượng bánh răng ở đáy Rail trái, hiện bị vô hiệu hoá (*"Cài đặt (Phase G)"*). Hiện chỉ có `FileOptionsView` (tuỳ chọn theo từng file: Auto date/time, tự phát hiện quan hệ) và `UserDefaults["bipro.sqlite.odbcDriver"]` (driver ODBC SQLite).
- **Dark Mode**: `Sources/BIPro/DesignSystem/Tokens.swift` định nghĩa toàn bộ `DS.Palette` bằng mã hex cố định của chế độ sáng (`#EBEBF0`, `#F5F5F7`, `#FFFFFF`, `#1C1C1E`…); 10 vị trí trong `ShellView.swift`, `FileOptionsView.swift`, `ReportCanvas.swift`, `DropdownSlicer.swift`, `CodeEditor.swift`, `ResultGrid.swift`, `AppliedStepsView.swift`, `CompletionPopup.swift` ép `.environment(\.colorScheme, .light)`, và 5 cầu AppKit (`Treemap`, `DonutChart`, `ShapeMap`, `CodeEditor`, `ResultGrid`, `CompletionPopup`) ép `NSAppearance(named: .aqua)`.
- **Song ngữ**: toàn bộ chuỗi giao diện đang viết cứng tiếng Việt trong mã Swift; chưa có `Localizable.strings` hay cơ chế đổi ngôn ngữ.
- **Quick Look & App Icon**: `scripts/build-app.sh` đóng gói `build/BI Pro.app` từ SwiftPM không cần Xcode, đã khai báo `UTImportedTypeDeclarations` cho `com.microsoft.powerbi.pbix` (`.pbix`), nhưng chưa có `CFBundleIconFile` / `AppIcon.icns` và chưa có Quick Look extension (`.appex`).
- **VoiceOver**: hầu hết điều khiển biểu tượng (Rail, Ribbon, Zoom, nút thu gọn pane, visual tile trên canvas) chưa gắn nhãn/giá trị/mô tả trợ năng tường minh.
- **Hướng dẫn lần đầu**: chưa có màn giới thiệu khi mở app lần đầu (mới có `AddDataPanel` khi mở tài liệu trống).

**Hành vi Power BI Desktop & chuẩn macOS đối chiếu:**
- **Power BI Desktop — Export to PDF** (`File ▸ Export ▸ Export to PDF`):
  - Xuất từng trang báo cáo **hiển thị** (bỏ qua trang ẩn `visibility == hidden`) thành từng trang PDF theo đúng kích thước/tỉ lệ trang (mặc định 16:9 ngang), giữ nguyên trạng thái lọc/slicer/bookmark đang hiển thị trên màn hình.
  - Không dính viền chọn, tay nắm đổi cỡ hay biểu tượng di chuột lên visual.
  - `[SUY ĐOÁN]` BI Pro cho phép chọn xuất "Trang hiện tại" hoặc "Tất cả trang hiển thị" (mặc định tất cả trang hiển thị như Desktop).
- **Power BI Desktop — Export data (CSV)** (menu `⋯` của visual → `Export data` → *Summarized data*):
  - Xuất bảng dữ liệu tóm tắt đang hiện của visual (tuân theo mọi bộ lọc báo cáo/trang/visual, slicer, lọc chéo và cấp drill hiện tại).
  - Định dạng CSV chuẩn RFC 4180, mã hoá UTF-8 có BOM (`EF BB BF`) để Excel/Numbers mở không lỗi dấu tiếng Việt; dòng đầu là tên hiển thị của các trường (như tiêu đề cột/chuỗi của visual); giữ đúng thứ tự sắp xếp hiện tại của visual.
  - Card/KPI xuất 1 dòng giá trị; biểu đồ trục/donut/treemap/map xuất các cột danh mục + chuỗi + giá trị; matrix/bảng xuất các cột hàng/cột/giá trị đang mở.
- **Xuất ảnh PNG (tính năng bổ sung trên macOS thay cho Publish)**:
  - Xuất trang hiện tại ra PNG sắc nét (mặc định tỉ lệ 2× Retina, cho chọn 1× / 2×), giữ đúng nền trang, bố cục và dữ liệu hiện tại, không dính khung chọn Sửa.
- **Dark Mode, Quick Look, VoiceOver, Settings, App Icon, Onboarding**:
  - Thuần chuẩn macOS 15 Sequoia (Apple HIG), bám `UIdesign/lumen_analytics_design_system/DESIGN.md` (accent `#0A84FF`, bo góc 6–8 px, vibrancy, viền 1 px).
  - Power BI Desktop giữ nền trang báo cáo theo đúng định dạng file `.pbix` (không tự đảo màu biểu đồ/nền trang của tác giả) để số liệu và màu sắc không sai lệch; chỉ vỏ ứng dụng và các vùng dữ liệu/mã thích ứng Dark Mode.

**Chuẩn so khớp (Hiến pháp II)**:
- Dữ liệu CSV xuất từ visual của `Nhom6_work.pbix` PHẢI khớp 100% với bảng kết quả truy vấn DAX (golden Phase B/C) đang nuôi visual đó.
- Ảnh PNG và trang PDF xuất ra PHẢI khớp thị giác với trang đang hiển thị trong BI Pro (kiểm bằng ảnh xuất vào `build/g-out/` và đối chiếu kích thước/số trang/không rỗng).
- Đổi ngôn ngữ (Việt ↔ Anh) hoặc đổi chế độ Sáng/Tối KHÔNG ĐƯỢC làm thay đổi một byte nào của file `.pbix` khi lưu (cấu trúc PBIR, M, DAX, `queryRef` giữ nguyên như Desktop).
- Toàn bộ 30 golden DAX Phase B, 72 truy vấn visual và toàn bộ bộ test hiện có (2 387 test) PHẢI giữ nguyên qua 100%.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1 — Xuất báo cáo ra PDF, PNG và xuất dữ liệu visual ra CSV (Ưu tiên: P1)

Bạn đang xem một trang báo cáo (như `Nhom6_work.pbix` đã lọc theo slicer) và muốn gửi báo cáo cho đồng nghiệp hoặc lấy số liệu sang Excel. Bạn bấm nút **Xuất** trên thanh tiêu đề (hoặc menu `Tệp ▸ Xuất`) để xuất toàn bộ báo cáo (hoặc trang hiện tại) thành PDF, xuất trang hiện tại thành ảnh PNG 2×, hoặc chọn một visual rồi xuất bảng dữ liệu đang hiển thị của nó ra tệp CSV.

**Vì sao P1**: Đây là nút công khai nổi bật ngay trên thanh tiêu đề (`ShellView.swift`) đã được giữ chỗ từ Phase A (thay cho Publish) và mang lại giá trị sử dụng trực tiếp cao nhất cho bản v1.0.

**Kiểm độc lập**: Mở `Nhom6_work.pbix`, bật một slicer lọc (ví dụ năm 2018), xuất (1) PDF tất cả trang hiển thị, (2) PNG trang D1 ở 2×, (3) CSV của một biểu đồ cột, một card và một matrix → kiểm tra file PDF hợp lệ (đủ số trang không ẩn, kích thước đúng tỉ lệ trang), PNG hợp lệ đúng độ phân giải 2× và không rỗng, CSV đọc lại khớp từng ô với kết quả DAX của visual đó.

**Kịch bản chấp nhận**:
1. **Cho** một báo cáo đang mở ở chế độ Xem hoặc Sửa, **khi** chọn **Xuất ▸ PDF…**, **thì** hộp chọn cho phép chọn "Tất cả trang hiển thị" (mặc định) hoặc "Trang hiện tại", lưu ra tệp `.pdf` mở được bằng Preview.app, số trang khớp số trang không ẩn, kích thước mỗi trang đúng tỉ lệ `page.width × page.height`, số liệu khớp trạng thái slicer/bộ lọc hiện tại, và không có khung chọn hay tay nắm Sửa.
2. **Cho** một trang báo cáo đang mở, **khi** chọn **Xuất ▸ Ảnh PNG của trang…**, **thì** lưu ra tệp `.png` sắc nét (mặc định 2×, cho chọn 1×/2×), kích thước pixel bằng `round(page.width * scale) × round(page.height * scale)`, hiển thị đủ các visual đang hiện (bỏ visual ẩn) và không có khung chọn Sửa.
3. **Cho** một visual có dữ liệu đang được chọn (card, biểu đồ cột/đường/combo/donut/treemap/vùng/ruy-băng/thác nước/phễu/bản đồ hình, bảng/matrix), **khi** chọn **Xuất ▸ Dữ liệu visual ra CSV…** (hoặc từ menu chuột phải / `⋯` của visual), **thì** lưu tệp `.csv` UTF-8 có BOM, dòng tiêu đề là tên hiển thị của các trường, dữ liệu khớp 100% bảng kết quả đang hiển thị theo đúng bộ lọc/slicer/drill hiện hành.
4. **Cho** trạng thái chưa chọn visual hoặc visual đang chọn không có dữ liệu (hộp văn bản, hình ảnh, nút), **thì** mục "Dữ liệu visual ra CSV…" hiện mờ kèm lý do rõ ràng.
5. **Cho** thao tác xuất lỗi (ví dụ không có quyền ghi vào thư mục đích), **thì** báo lỗi rõ ràng bằng ngôn ngữ đang chọn, không làm treo hay sập ứng dụng.

---

### Câu chuyện 2 — Giao diện tối (Dark Mode) & Cài đặt ứng dụng (`⌘,`) (Ưu tiên: P1)

Bạn dùng macOS ở chế độ Tối vào buổi tối (hoặc muốn chủ động chọn Sáng/Tối/Theo hệ thống). Bạn bấm biểu tượng bánh răng ở đáy thanh trái (hoặc `BI Pro ▸ Cài đặt…`, phím tắt `⌘,`) để chỉnh chế độ giao diện, ngôn ngữ, lưới căn lề mặc định, driver ODBC SQLite mặc định, mở thư mục sao lưu hoặc xem lại hướng dẫn lần đầu. Toàn bộ khung ứng dụng và các không gian làm việc đổi màu mượt mà, độ tương phản rõ ràng, riêng trang báo cáo vẫn giữ đúng màu nền tài liệu `.pbix`.

**Vì sao P1**: Nút bánh răng đã hiển thị sẵn ở đáy Rail trái từ Phase A; Dark Mode là kỳ vọng cơ bản của ứng dụng native macOS và là nền tảng để các màn hình mới (Settings, Onboarding, Quick Look) xây dựng đúng hệ màu ngữ nghĩa ngay từ đầu.

**Kiểm độc lập**: Chuyển lần lượt Sáng → Tối → Theo hệ thống trong Cài đặt; chụp và kiểm tra tất cả 5 workspace (Report, Table, Model, DAX Query, TMDL) cùng các sheet (Get Data, Query Editor, File Options, Settings); đóng mở lại app xác nhận tuỳ chọn được lưu bền vững.

**Kịch bản chấp nhận**:
1. **Cho** ứng dụng đang chạy, **khi** bấm nút bánh răng ở Rail hoặc nhấn `⌘,`, **thì** cửa sổ Cài đặt mở ra với các nhóm rõ ràng: **Chung** (Giao diện Sáng/Tối/Theo hệ thống, Ngôn ngữ, Hiện hướng dẫn lần đầu), **Chỉnh sửa** (Bám lưới mặc định, Cỡ lưới 8/16 px), **Dữ liệu & Sao lưu** (Driver ODBC SQLite mặc định nối với `UserDefaults["bipro.sqlite.odbcDriver"]`, đường dẫn thư mục sao lưu và nút "Mở trong Finder").
2. **Cho** chế độ Giao diện chuyển sang **Tối** (hoặc **Theo hệ thống** khi macOS đang ở Dark Mode), **thì** Title bar, Ribbon, Rail, Status bar, mọi Pane (Filters, Visualizations, Data, Selection, Bookmarks), các hộp thoại (Get Data, Navigator, Enter Data, File Options, Query Editor, Settings) và 4 workspace dữ liệu/mã (Table, Model, DAX Query, TMDL — kể cả lưới AppKit và trình soạn thảo mã/gợi ý tự hoàn thành) chuyển sang nền tối tương phản đạt chuẩn, không còn chữ tối trên nền tối hay ô trắng chói bất thường.
3. **Cho** chế độ Tối đang bật ở Report Canvas, **thì** nền ngoài trang (`backdrop`) tối nhưng bản thân trang báo cáo giữ nguyên màu nền của tệp `.pbix` (mặc định trắng) và màu sắc visual không bị biến dạng.
4. **Cho** người dùng đổi bất kỳ tuỳ chọn nào trong Cài đặt, **khi** thoát và mở lại ứng dụng, **thì** mọi tuỳ chọn được khôi phục đúng như đã lưu.

---

### Câu chuyện 3 — Song ngữ Tiếng Việt và Tiếng Anh (Ưu tiên: P2)

Bạn muốn dùng BI Pro bằng Tiếng Việt (mặc định) hoặc chuyển sang English khi làm việc với đồng nghiệp quốc tế hoặc đối chiếu thuật ngữ Power BI. Bạn đổi ngôn ngữ trong Cài đặt; toàn bộ thanh công cụ, menu, pane, hộp thoại và nhãn phép gộp ngầm chuyển ngay sang ngôn ngữ mới, trong khi tệp `.pbix` khi lưu vẫn giữ đúng định dạng kỹ thuật của Power BI Desktop.

**Vì sao P2**: Là yêu cầu cốt lõi trong `BIPRO_BUILD_PLAN.md` Phase G; độc lập với Export và Quick Look, kết nối trực tiếp vào Cài đặt ở US2.

**Kiểm độc lập**: Đổi ngôn ngữ Tiếng Việt ↔ English trong Cài đặt; kiểm tra chuỗi hiển thị ở cả 5 workspace, Ribbon, Panes, Settings, Onboarding, hộp thoại Export/Get Data/Enter Data/File Options; tạo và lưu một `.pbix` ở chế độ Tiếng Việt và một bản ở chế độ English trên cùng thao tác, xác nhận `queryRef`, `nativeQueryRef`, M và metadata bên trong `.pbix` hoàn toàn đồng nhất.

**Kịch bản chấp nhận**:
1. **Cho** cài đặt ngôn ngữ là **Tiếng Việt** (mặc định khi khởi động lần đầu nếu chưa cấu hình), **thì** toàn bộ giao diện hiển thị tiếng Việt tự nhiên, nhất quán như các phase trước.
2. **Cho** người dùng chuyển ngôn ngữ sang **English** trong Cài đặt, **thì** Title bar, Ribbon, Rail, Status bar, Panes, Settings, Onboarding, các hộp thoại chính và nhãn phép gộp ngầm ("Tổng của X" → "Sum of X", "Trung bình của X" → "Average of X"…) đổi sang tiếng Anh (có thể áp ngay hoặc thông báo rõ nếu menu hệ thống macOS cần mở lại cửa sổ mới).
3. **Cho** cài đặt ngôn ngữ là **Theo hệ thống (System)**, **thì** dùng English khi ngôn ngữ ưu tiên của macOS là `en*`, còn lại dùng Tiếng Việt.
4. **Cho** cùng thao tác sửa/lưu `.pbix` ở hai ngôn ngữ, **thì** dữ liệu lưu trong tệp (PBIR, M, DAX, `metadata.sqlitedb`) không chứa chuỗi dịch UI sai lệch với Power BI Desktop.

---

### Câu chuyện 4 — Quick Look cho tệp `.pbix` trong Finder (Ưu tiên: P2)

Bạn chọn một tệp `.pbix` trong Finder và nhấn phím cách (**Space**) hoặc xem dạng biểu tượng/cột xem trước. Finder lập tức hiện ảnh thu nhỏ và bản xem trước của tệp `.pbix` (tên báo cáo, số trang, danh sách trang, số bảng/measure/quan hệ, sơ đồ bố cục trang đầu) mà không cần mở ứng dụng BI Pro.

**Vì sao P2**: Trải nghiệm native đặc trưng của macOS giúp phân biệt BI Pro với ứng dụng đa nền tảng; đọc trực tiếp bằng `PBIXKit` sẵn có.

**Kiểm độc lập**: Đóng gói `build/BI Pro.app` bằng `zsh scripts/build-app.sh`; chạy `qlmanage -p` và `qlmanage -t` trên `Nhom6_work.pbix` (PBIR), `w8.3.pbix` và một file định dạng cũ (`tuan6.2.pbix` / `Nhom2`), cùng một file `.pbix` hỏng → sinh ra bản xem trước và ảnh thu nhỏ hợp lệ dưới 1 giây, không sập tiến trình Quick Look.

**Kịch bản chấp nhận**:
1. **Cho** một tệp `.pbix` hợp lệ (PBIR hoặc Layout cũ), **khi** xem trước Quick Look (`qlmanage -p` hoặc nhấn Space trong Finder), **thì** hiện bản xem trước rõ ràng gồm: tên tệp, số trang và danh sách trang, thống kê mô hình (số bảng, cột, measure, quan hệ), sơ đồ thu nhỏ các khung visual của trang đầu (kèm tiêu đề visual nếu có), thích ứng Sáng/Tối.
2. **Cho** tệp `.pbix` trong Finder, **khi** hệ thống yêu cầu ảnh thu nhỏ (`qlmanage -t`), **thì** sinh ra ảnh thu nhỏ bố cục trang đầu rõ nét kèm nhãn `PBIX`.
3. **Cho** tệp `.pbix` lớn như `Nhom6_work.pbix` (~54 MB), **thì** bản xem trước và ảnh thu nhỏ dựng xong dưới **1 giây** (chỉ đọc phần báo cáo và metadata tóm tắt, không giải mã dữ liệu VertiPaq).
4. **Cho** tệp `.pbix` hỏng hoặc thiếu `DataModel`, **thì** hiển thị thông báo tóm tắt an toàn, không treo hay sập extension.

---

### Câu chuyện 5 — Trợ năng VoiceOver và điều hướng bàn phím (Ưu tiên: P2)

Người dùng bật VoiceOver trên macOS (hoặc điều hướng chủ yếu bằng bàn phím) mở một báo cáo trong BI Pro. Mọi nút chỉ có biểu tượng đều đọc rõ tên tiếng Việt/Anh, mọi vùng chính đều được nhóm hợp lý, từng visual trên canvas đọc được loại visual + tiêu đề + giá trị chính (với card/KPI hoặc tóm tắt số điểm/dòng dữ liệu), và các hành động quan trọng (đổi trang, lưu, xuất) phát thông báo VoiceOver.

**Vì sao P2**: Yêu cầu chất lượng v1.0 trong `BIPRO_BUILD_PLAN.md` và chuẩn ứng dụng native macOS.

**Kiểm độc lập**: Kiểm tra tự động bằng unit test cho bộ sinh nhãn/tóm tắt trợ năng (visual summary, field accessibility description, tree row traits) và kiểm tra thực tế bằng Accessibility Inspector / `AXUIElement` trên `build/BI Pro.app` mở `Nhom6_work.pbix`.

**Kịch bản chấp nhận**:
1. **Cho** toàn bộ nút biểu tượng ở Title bar, Ribbon, Rail, thanh Zoom, nút thu gọn/mở rộng Pane, **thì** mỗi nút đều có `accessibilityLabel` rõ ràng (không bị đọc là "button" trống) và trạng thái chọn/tắt chính xác.
2. **Cho** các visual đang hiển thị trên Report Canvas, **thì** mỗi visual có nhãn trợ năng gồm loại visual + tiêu đề (hoặc tên trường) và `accessibilityValue` tóm tắt nội dung (giá trị hiển thị với Card/KPI, số danh mục/chuỗi với biểu đồ, số hàng/cột với bảng/matrix, trạng thái chọn với slicer).
3. **Cho** Data pane, Filters pane, Bookmarks pane, Selection pane và thanh tab trang, **thì** cây dữ liệu đọc rõ loại đối tượng (bảng, cột, measure, phân cấp, trạng thái ẩn/hiện), tab trang đọc tên trang + trạng thái đang chọn.
4. **Cho** các sự kiện quan trọng (đổi trang, bật/tắt chế độ Sửa, lưu xong, xuất tệp xong), **thì** phát thông báo trợ năng qua `NSAccessibility.post(element:notification:.announcementRequested)`.

---

### Câu chuyện 6 — Biểu tượng ứng dụng, Hướng dẫn lần đầu và đóng gói v1.0 (Ưu tiên: P3)

Khi cài hoặc mở `build/BI Pro.app` lần đầu tiên, ứng dụng có biểu tượng native macOS sắc nét trên Dock/Finder (cả biểu tượng app lẫn biểu tượng file `.pbix`), hiện hộp thoại hướng dẫn lần đầu ngắn gọn giúp nắm ngay 3 điểm cốt lõi (mở/tạo `.pbix`, chuyển Xem/Sửa `⌘E` và 5 không gian làm việc, lưu an toàn & xuất), và mang số phiên bản **1.0.0**.

**Vì sao P3**: Hoàn thiện nhận diện và ấn tượng đầu tiên của bản phát hành v1.0; không chặn các tính năng chức năng P1/P2.

**Kiểm độc lập**: Chạy `zsh scripts/build-app.sh`, kiểm tra `BI Pro.app/Contents/Resources/AppIcon.icns` tồn tại và hợp lệ (`iconutil` / `sips`), `Info.plist` có `CFBundleShortVersionString = 1.0.0` và `CFBundleIconFile = AppIcon`; mở app với `UserDefaults` sạch để thấy Onboarding hiện đúng 1 lần, bấm Xong/Bỏ qua thì lần mở sau không hiện lại, bấm "Xem lại hướng dẫn" trong Settings thì mở lại được.

**Kịch bản chấp nhận**:
1. **Cho** `build/BI Pro.app` được đóng gói bằng `zsh scripts/build-app.sh`, **thì** có `AppIcon.icns` đủ kích cỡ (16×16 đến 1024×1024) theo phong cách squircle macOS Sequoia (màu chủ đạo `#0A84FF` / `#5E5CE6`), `CFBundleIconFile` khai báo đúng, `CFBundleShortVersionString` là `1.0.0`.
2. **Cho** người dùng khởi động BI Pro lần đầu (`bipro.onboarding.seen == false`), **thì** hiện hộp hướng dẫn 3 bước ngắn gọn (có thể chuyển bước, bấm "Bỏ qua" hoặc "Bắt đầu"), hỗ trợ cả Sáng/Tối và Việt/Anh.
3. **Cho** người dùng đã đóng hướng dẫn lần đầu, **khi** mở lại ứng dụng, **thì** hướng dẫn không tự bật lại; nhưng có thể mở lại bất kỳ lúc nào qua **Cài đặt ▸ Xem lại hướng dẫn** hoặc menu **Trợ giúp**.

---

### Trường hợp biên

- **Xuất PDF/PNG trên trang có visual đang tải dữ liệu**: hệ thống chờ các truy vấn visual của trang hoàn tất (có giới hạn thời gian và thanh tiến trình/nút huỷ) trước khi kết xuất, tránh xuất trang trống hay ô mờ đang nạp.
- **Xuất PDF báo cáo chỉ có 1 trang hoặc có trang ẩn**: trang ẩn bị bỏ qua khi chọn "Tất cả trang hiển thị"; nếu người dùng đang đứng trên một trang ẩn và chọn "Trang hiện tại" thì vẫn xuất được trang đó.
- **Xuất CSV trên visual có ký tự đặc biệt**: chuỗi chứa dấu phẩy `,`, dấu ngoặc kép `"`, xuống dòng `\n`, tiếng Việt có dấu được bọc ngoặc kép và nhân đôi `""` đúng RFC 4180, kèm UTF-8 BOM.
- **Xuất CSV trên matrix có hàng/cột nhiều cấp hoặc giá trị BLANK**: giá trị rỗng xuất ô trống `""` (không xuất chữ "nil"), giữ đúng thứ tự hàng đang mở.
- **Dark Mode với các màu chữ/nền tuỳ chỉnh của visual trong file `.pbix`**: màu chữ, màu chuỗi, màu nền thẻ do file `.pbix` quy định luôn được tôn trọng trên Report Canvas (vì Report Canvas giữ bề mặt sáng theo tài liệu); chỉ các thành phần chrome/inspector/editor đổi theo Dark Mode.
- **Quick Look khi không có chứng chỉ Developer ID (ký ad-hoc trên macOS 15)**: nếu hệ thống macOS 15 không tự kích hoạt extension ký ad-hoc trong Finder mà chỉ chạy được qua `qlmanage`, phải ghi rõ điều kiện ký/cài đặt trong tài liệu và `plan.md` sau khi spike kiểm chứng ở Đợt 0.
- **Đổi ngôn ngữ khi đang có hộp thoại mở hoặc có thay đổi chưa lưu**: đổi ngôn ngữ KHÔNG làm mất dữ liệu hay trạng thái chỉnh sửa đang có trong phiên.

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

**Xuất báo cáo & dữ liệu (Câu chuyện 1)**
- **FR-001**: Hệ thống PHẢI kích hoạt menu **Xuất** trên Title bar và menu **Tệp ▸ Xuất** với 3 lệnh: **Xuất PDF…**, **Xuất ảnh PNG của trang…**, **Xuất dữ liệu visual ra CSV…**.
- **FR-002**: **Xuất PDF…** PHẢI cho chọn phạm vi ("Tất cả trang hiển thị" hoặc "Trang hiện tại"), chờ dữ liệu các visual nạp xong trước khi vẽ, kết xuất mỗi trang đúng tỉ lệ `page.width × page.height`, bỏ khung chọn/tay nắm Sửa và visual đang bị ẩn.
- **FR-003**: **Xuất ảnh PNG của trang…** PHẢI xuất trang hiện tại ra PNG ở tỉ lệ chọn được (1× hoặc 2×, mặc định 2×), đúng kích thước pixel, bỏ khung chọn/tay nắm Sửa và visual đang bị ẩn.
- **FR-004**: **Xuất dữ liệu visual ra CSV…** PHẢI xuất dữ liệu tóm tắt đang hiển thị của visual đang chọn (phản ánh bộ lọc, slicer, lọc chéo và cấp drill hiện hành) theo chuẩn RFC 4180, UTF-8 có BOM; vô hiệu hoá kèm lý do khi chưa chọn visual hoặc visual không có dữ liệu.
- **FR-005**: Mọi thao tác xuất PHẢI hiện trạng thái tiến trình (với PDF nhiều trang) và báo lỗi rõ ràng khi không ghi được tệp, không làm mất dữ liệu đang mở.

**Dark Mode & Cài đặt (Câu chuyện 2)**
- **FR-010**: Hệ thống PHẢI cung cấp cửa sổ **Cài đặt** mở từ nút bánh răng ở Rail trái và lệnh `BI Pro ▸ Cài đặt…` (`⌘,`), lưu tuỳ chọn bền vững qua `UserDefaults`.
- **FR-011**: Cửa sổ Cài đặt PHẢI gồm: chế độ giao diện (Theo hệ thống / Sáng / Tối), ngôn ngữ (Theo hệ thống / Tiếng Việt / English), bám lưới mặc định (bật/tắt, cỡ lưới 8/16 px), driver ODBC SQLite mặc định (đồng bộ `UserDefaults["bipro.sqlite.odbcDriver"]`), thông tin thư mục sao lưu kèm nút "Mở trong Finder", và nút "Xem lại hướng dẫn".
- **FR-012**: `DS.Palette` PHẢI sử dụng màu động thích ứng Sáng/Tối theo chuẩn macOS 15; mọi vỏ cửa sổ, pane, sheet, workspace Table/Model/DAX/TMDL và thành phần AppKit liên quan PHẢI bỏ ép `.light`/`.aqua` để thích ứng chế độ giao diện đã chọn.
- **FR-013**: Report Canvas PHẢI giữ nguyên nền sáng/màu nền tài liệu của file `.pbix` ở cả chế độ Sáng và Tối để màu sắc biểu đồ và dữ liệu không bị sai lệch.

**Song ngữ Việt/Anh (Câu chuyện 3)**
- **FR-020**: Hệ thống PHẢI hỗ trợ chuyển đổi giao diện giữa **Tiếng Việt** (mặc định) và **English** (cùng chế độ Theo hệ thống) cho toàn bộ khung giao diện chính (Title bar, Ribbon, Rail, Status bar, Panes, Settings, Onboarding, hộp thoại Get Data/Navigator/Enter Data/File Options/Query Editor chính, nhãn phép gộp ngầm).
- **FR-021**: Việc đổi ngôn ngữ giao diện KHÔNG ĐƯỢC thay đổi bất kỳ chuỗi kỹ thuật nào ghi vào tệp `.pbix` (PBIR `queryRef`/`nativeQueryRef`, truy vấn M, công thức DAX, siêu dữ liệu SQLite) và KHÔNG ĐƯỢC làm mất thay đổi chưa lưu của tài liệu đang mở.

**Quick Look `.pbix` (Câu chuyện 4)**
- **FR-030**: Gói ứng dụng `BI Pro.app` PHẢI tích hợp Quick Look preview và thumbnail (sử dụng API hệ thống Apple `QuickLookUI` / `QuickLookThumbnailing`, không thêm thư viện ngoài) cho UTType `com.microsoft.powerbi.pbix`.
- **FR-031**: Quick Look Preview PHẢI hiển thị tóm tắt báo cáo và mô hình (tên tệp, số trang & tên các trang, số bảng/cột/measure/quan hệ, sơ đồ khung visual trang đầu) thích ứng Sáng/Tối; Thumbnail PHẢI hiển thị ảnh thu nhỏ sơ đồ trang đầu kèm nhãn `PBIX`.
- **FR-032**: Bộ đọc Quick Look PHẢI chỉ đọc phần báo cáo và metadata (không nạp/giải mã cột dữ liệu VertiPaq) và xử lý an toàn mọi file hỏng mà không sập.

**VoiceOver & Trợ năng (Câu chuyện 5)**
- **FR-040**: Mọi điều khiển chỉ có biểu tượng (Rail, Ribbon, Title bar, Zoom, nút thu gọn Pane, thanh công cụ kết quả) PHẢI có nhãn trợ năng (`accessibilityLabel`) theo đúng ngôn ngữ đang chọn.
- **FR-041**: Mỗi visual trên Report Canvas PHẢI có nhãn trợ năng (loại + tiêu đề) và giá trị tóm tắt dữ liệu (`accessibilityValue`); cây dữ liệu (Data/Selection/Bookmarks/Filters) PHẢI đọc rõ loại nút và trạng thái ẩn/chọn.
- **FR-042**: Hệ thống PHẢI phát thông báo VoiceOver (`announcementRequested`) khi đổi trang báo cáo, bật/tắt chế độ Sửa, lưu tài liệu xong, hoặc xuất PDF/PNG/CSV thành công.

**App Icon, Onboarding & Đóng gói v1.0 (Câu chuyện 6)**
- **FR-050**: `scripts/build-app.sh` PHẢI sinh và đóng gói `AppIcon.icns` (đủ kích cỡ 16×16 đến 1024×1024, tạo bằng mã/công cụ native macOS, không tải từ mạng), khai báo `CFBundleIconFile` và nâng `CFBundleShortVersionString` lên `1.0.0`.
- **FR-051**: Ứng dụng PHẢI hiển thị hộp thoại Hướng dẫn lần đầu (3 bước ngắn gọn, có nút Bỏ qua/Bắt đầu) ở lần mở đầu tiên, ghi nhớ trạng thái đã xem ở `UserDefaults`, và cho phép mở lại từ Settings hoặc menu Trợ giúp.

### Thực thể chính

- **AppPreferences**: tập tuỳ chọn toàn cục của ứng dụng lưu trong `UserDefaults` (`appearance`: system/light/dark, `language`: system/vi/en, `snapToGrid`, `gridSize`, `onboardingSeen`, `sqliteOdbcDriver`).
- **ReportExporter**: bộ kết xuất báo cáo (PDF nhiều trang, PNG 1×/2×) và trích xuất dữ liệu visual ra CSV (RFC 4180 + UTF-8 BOM) dùng lại `ReportPageView` (không khung Sửa) và `DataView` đã nạp.
- **L10n (Localization catalog)**: từ điển chuỗi song ngữ `vi` / `en` gắn với `AppPreferences.language`, dùng được cả trong SwiftUI lẫn logic thuần để kiểm thử tự động.
- **PBIXQuickLookSummary**: cấu trúc tóm tắt đọc nhanh từ `.pbix` (chỉ đọc ZIP `Report/` + `metadata.sqlitedb`, không giải mã VertiPaq) phục vụ cả Preview, Thumbnail và unit test.
- **VisualAccessibilitySummary**: hàm thuần sinh nhãn và tóm tắt dữ liệu VoiceOver từ `ReportVisual` + `VisualDataView` (test được không cần chạy VoiceOver thật).

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001 (Export)**: Xuất PDF toàn bộ trang hiển thị của `Nhom6_work.pbix` ra tệp PDF hợp lệ đủ số trang không ẩn; xuất PNG 2× trang D1 đúng kích thước pixel và mở kiểm bằng mắt rõ nét; xuất CSV từ ít nhất 3 loại visual khác nhau (Card, Biểu đồ cột/combo, Matrix) khớp **100%** từng ô với kết quả DAX của visual đó và mở đọc đúng tiếng Việt UTF-8 BOM.
- **SC-002 (Dark Mode & Settings)**: Chụp ảnh cửa sổ ứng dụng ở cả hai chế độ Sáng và Tối trên cả 5 workspace + Query Editor + Settings vào `docs/phase-g-evidence/`, không còn nền trắng chói hay chữ chìm mất tương phản; Report Canvas giữ đúng nền tài liệu `.pbix`; mọi tuỳ chọn Settings giữ nguyên sau khi khởi động lại.
- **SC-003 (Song ngữ)**: Chuyển đổi Tiếng Việt ↔ English áp dụng cho 100% nhãn UI đã đăng ký trong bộ kiểm tra tự động (không thiếu khoá dịch giữa `vi` và `en`); lưu cùng thao tác ở hai ngôn ngữ cho kết quả cấu trúc `.pbix` giống hệt nhau.
- **SC-004 (Quick Look)**: `PBIXQuickLookSummary` đọc `Nhom6_work.pbix` dưới **1 giây** (đo bản release); `qlmanage -t` và `qlmanage -p` chạy thành công trên `Nhom6_work.pbix` và file định dạng cũ (không sập trên file hỏng).
- **SC-005 (VoiceOver)**: Bộ test tự động kiểm tra `VisualAccessibilitySummary` và nhãn trợ năng qua 100%; kiểm tra trên `build/BI Pro.app` thấy mọi nút Rail, Title bar, Zoom và visual trên trang D1 đều có nhãn trợ năng khác rỗng.
- **SC-006 (Đóng gói v1.0 & Hồi quy)**: `zsh scripts/build-app.sh` tạo `build/BI Pro.app` phiên bản `1.0.0` có `AppIcon.icns` hợp lệ; `swift build`, toàn bộ `swift test` (≥ 2 387 test + test mới của Phase G) và bộ golden nặng (`Nhom6|ORA|VIS`) qua **100%** không hồi quy.

## Giả định & Điểm cần làm rõ trước khi lập kế hoạch

Các giả định mặc định đang áp dụng trong bản nháp này (bạn có thể giữ hoặc đổi khi duyệt):
1. **Quick Look trên macOS 15 không dùng Xcode**: sẽ tự biên dịch và đóng gói `.appex` trong `scripts/build-app.sh` (ký ad-hoc `codesign -s -`), kiểm chứng bằng `qlmanage` ngay ở Đợt 0 của `plan.md`. Nếu macOS 15 hạn chế Finder nạp extension ký ad-hoc (khi chưa có Developer ID), sẽ ghi rõ hướng dẫn ký/test và vẫn đảm bảo lõi `PBIXQuickLookSummary` + `qlmanage` chạy chuẩn.
2. **Dark Mode trên Report Canvas**: giữ nguyên nền trang báo cáo của file `.pbix` (giống Power BI Desktop và Apple Pages/Keynote), chỉ chuyển tối khung ứng dụng, backdrop, pane, hộp thoại và 4 workspace dữ liệu/mã.
3. **Phạm vi song ngữ Việt/Anh**: dịch toàn bộ giao diện người dùng (Title bar, Ribbon, Rail, Status bar, Panes, Settings, Onboarding, các hộp thoại chính, nhãn phép gộp); các thông báo lỗi kỹ thuật tầng thấp trong `PBIXKit`/`DAXEngine`/`MEngine` giữ nguyên tiếng Việt hiện có để tránh làm vỡ hàng trăm test kiểm chuỗi lỗi.
4. **Hành vi VM**: Phase G chủ yếu là tính năng macOS native nên **không cần dùng VM Windows**, trừ trường hợp kiểm tra nhanh định dạng Export PDF/CSV của Power BI Desktop nếu thấy điểm mơ hồ.
