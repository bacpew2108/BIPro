# Phase H — Đưa giao diện BI Pro về giống Power BI Desktop

Ngày quan sát: 2026-11-21 · Chuẩn so sánh: Power BI Desktop 2.159 (Windows 11 VM) · Trạng thái: **đã duyệt (Q1–Q6 theo khuyến nghị, 2026-11-21)**; spec Kit `specs/016-…` đang soạn; chưa sửa code.

Tài liệu này là cấp trên của `specs/016-…` (sẽ tạo bằng Spec Kit sau khi bạn duyệt). Nếu mâu thuẫn với `specs/`, sửa tài liệu này trước.

## 1. Mục tiêu và phạm vi

**Mục tiêu:** người đã quen Power BI Desktop mở BI Pro phải thấy bố cục, tên tab, nhóm nút, thứ tự nút, trạng thái bật/tắt và màu nhấn gần như y hệt, nhưng vẫn là app SwiftUI native macOS.

**Trọng tâm: thanh Ribbon** (mục 5.A, chi tiết nhất). Sau đó là khung cửa sổ, các pane, thanh trang/trạng thái, màn hình khởi động và File.

**Trong phạm vi:** bố cục, tên/thứ tự/nhóm nút, kiểu nút (lớn/nhỏ/có mũi tên ▾), màu, kích thước, trạng thái vô hiệu, tooltip, tab theo ngữ cảnh.

**Ngoài phạm vi (giữ nguyên):** engine DAX/M, ghi `.pbix`, định dạng tài liệu, song ngữ Việt/Anh, Dark Mode, VoiceOver. Nút của Power BI mà BI Pro chưa có tính năng thật (Copilot, Dataverse, OneLake, Power Apps, Power Automate, Publish, Share, Sensitivity, Q&A…) vẫn **hiện đúng vị trí** nhưng ở trạng thái vô hiệu kèm tooltip lý do, theo quy ước `RibbonButton.disabledReason` hiện có.

## 2. Nguồn quan sát (VM-UI)

- Ảnh khởi động và báo cáo trống do bạn gửi (hai ảnh đầu cuộc hội thoại, Desktop 2.159).
- Phiên VM 2026-11-21: mở `Nhom6_d15.pbix` (4 trang, 11 bảng, 168 measure), bấm chuột Mac thật vào cửa sổ Parallels, chụp bằng `prlctl capture`. Công cụ: `build/vm-tools/ui.sh` (chụp, tự chụp lại khi khung dở dang, **che email tài khoản** ở thanh tiêu đề) và `build/vm-tools/vc.sh` (bấm theo toạ độ ảnh).
- Ảnh bằng chứng: `docs/phase-ui-evidence/vm-ui/` (`rb_*-2x.png` là ảnh ribbon độ phân giải cao; `o_*`, `v_*`, `r_*`, `p_*`, `f_*`, `t_*` là toàn màn hình). Ảnh BI Pro hiện tại: `docs/phase-ui-evidence/bipro-truoc/b_home.png`.
- Không giải mã/đảo ngược mã nguồn Power BI; chỉ quan sát giao diện (đúng quyết định "REA quan sát hành vi, không decompile").

**Đã quan sát bổ sung (VM-UI2, cùng ngày):** menu thả xuống New page, Buttons, Shapes, Page view, Refresh, Themes; hộp Get Data, hộp Options, pane Performance analyzer (mục 3.10). **Vẫn chưa quan sát (`[CHƯA QUAN SÁT]`, làm theo suy luận hợp lý và ghi lại khi có dịp):** menu Recent sources/Transform data/More visuals/Sensitivity/Optimization presets/Language/Linguistic schema/Groups/Align/Group, hộp Customize theme, hover/pressed chi tiết, ribbon khi thu gọn, Mobile layout.

## 3. Quan sát Power BI Desktop

Số đo lấy từ ảnh VM 1867×1017 pt logic (ảnh 1600 px nhân 1,167). Màu đo bằng lấy mẫu điểm ảnh nên lệch ±2 mã hex.

### 3.1 Khung cửa sổ (Report view)

Từ trên xuống: **thanh tiêu đề** (cao ≈ 35) → **hàng tab ribbon** (≈ 32) → **panel ribbon** trắng bo góc (cao ≈ 98, kể cả nhãn nhóm) → vùng làm việc → **thanh trang** (≈ 35) → **thanh trạng thái** (≈ 23).

Từ trái sang trong vùng làm việc: **rail điều hướng** (rộng ≈ 42, nền sát chrome, 5 biểu tượng) → canvas → dải **Filters** thu gọn dọc (≈ 31) → pane **Visualizations** (≈ 181) → pane **Data** (≈ 179).

| Thành phần | Quan sát |
|---|---|
| Nền chrome (tiêu đề, tab, rail, pane Data, thanh trạng thái) | `#F5F5F5` |
| Panel ribbon | `#FFFFFF`, nổi trên chrome, bo góc ≈ 6, bóng rất nhẹ |
| Nền canvas quanh trang | `#E6E6E6` (xám trung tính, **không** phải trắng) |
| Màu nhấn | xanh lục teal: vạch chọn rail `#006F5A`, nút Share `#238370` (≈ `#117865`), tab ngữ cảnh chữ xanh lục, nút `+` thêm trang nền xanh lục, công tắc "On" xanh lục |
| Chữ | Segoe UI ≈ 12–13 pt; nhãn nút ribbon ≈ 11; nhãn nhóm ≈ 10, xám, **không viết hoa** |
| Phân cách | đường 1 px `#DBDBDB` giữa các pane; giữa các nhóm ribbon là vạch dọc mảnh |

### 3.2 Thanh tiêu đề

Trái → phải: biểu tượng **Lưu** (đĩa) · **Hoàn tác** · **Làm lại** · `tên-file • Last saved: Today at 6:40 PM ▾` (menu thả xuống) · **ô Search** ở giữa (rộng ≈ 340, bo tròn) · biểu tượng **cài đặt** (bánh răng) · **chuyển sáng/tối** (mặt trời ▾) · tài khoản · **nút Share** xanh lục (chỉ bật khi có file) · điều khiển cửa sổ.

### 3.3 Rail điều hướng

Năm biểu tượng, cách nhau ≈ 40: **Report**, **Table view**, **Model view**, **DAX query view**, **TMDL View**. Mục đang chọn có vạch dọc xanh lục sát mép trái và nền nhạt; rê chuột hiện tooltip hình bong bóng bên phải ("Table view", "Model view"…). Báo cáo trống (ảnh bạn gửi) vẫn hiện đủ 5 biểu tượng. **Không có** nút cài đặt ở rail, **không** có nhãn chữ dưới biểu tượng.

### 3.4 Hàng tab ribbon

Chữ thường, không nền: `File`, rồi các tab. Tab đang chọn: chữ đậm và gạch chân dày ≈ 2 màu xanh lục. **Tab ngữ cảnh** (xuất hiện khi có lựa chọn) chữ xanh lục, **không** có vạch phân cách và nằm ngay sau tab cuối. Nút **Share** xanh lục neo mép phải hàng tab. Mũi tên `^` ở góc dưới phải panel để thu gọn ribbon.

**Tab theo từng view:**

| View | Tab thường | Tab ngữ cảnh |
|---|---|---|
| Report | File · Home · Insert · Modeling · **Design** · View · **Optimize** · Help | **Format** và **Data / Drill** khi chọn visual |
| Table view | File · Home · Help | **Table tools**, **Column tools** (luôn hiện khi có bảng; chọn cột thì Column tools nổi bật) |
| Model view | File · Home · Help | — |
| DAX query view | File · Home · Help | — |
| TMDL view | File · Home · Help | — |

Quy ước nút: **L** = nút lớn (biểu tượng ≈ 32 + nhãn 1–2 dòng bên dưới), **S** = nút nhỏ (biểu tượng ≈ 16 + nhãn bên phải, xếp dọc 3 hàng), **▾** = có menu thả xuống (mũi tên nhỏ ngay sau nhãn, xuống dòng nếu nhãn dài), **(tắt)** = vô hiệu khi chưa có dữ liệu/lựa chọn, chữ và biểu tượng xám nhạt.

### 3.5 Ribbon — Report view

**Home** — ảnh `rb_home-2x.png`

| Nhóm | Nút (theo thứ tự trái → phải) |
|---|---|
| Clipboard | Paste (L, tắt khi clipboard rỗng) · cột S: Cut · Copy · Format painter |
| Data | Get data ▾ (L) · Excel workbook (L) · OneLake catalog ▾ (L) · SQL Server (L) · Enter data (L) · Dataverse (L) · Recent sources ▾ (L) |
| Queries | Transform data ▾ (L) · Refresh (L, có ▾ nằm dưới nhãn) |
| Insert | New visual (L) · Text box (L) · More visuals ▾ (L) |
| Calculations | New visual calculation ▾ (L, tắt khi không chọn visual) · New measure (L) · Quick measure (L) |
| Sensitivity | Sensitivity ▾ (L, tắt) |
| Share | Publish (L) |
| Copilot | Prep data for AI (L) · Copilot (L, biểu tượng nhiều màu) |

Khi báo cáo trống (ảnh bạn gửi): chỉ Get data, Excel workbook, OneLake catalog, SQL Server, Enter data, Dataverse, Recent sources, Transform data, New visual, Text box, More visuals và Copilot bật; phần còn lại (Cut, Copy, Format painter, Refresh, New visual calculation, New measure, Quick measure, Sensitivity, Publish, Prep data for AI) tắt.

**Insert** — `rb_insert-2x.png`

| Nhóm | Nút |
|---|---|
| Pages | New page ▾ (L) |
| Visuals | New visual (L) · More visuals ▾ (L) |
| AI visuals | Key influencers (L) · Decomposition tree (L) · Narrative (L) |
| Power Platform | Paginated report (L) · Power Apps (L) · Power Automate (L) |
| Elements | Text box (L) · Buttons ▾ (L) · Shapes ▾ (L) · Image (L) |
| Sparklines | Add a sparkline (L, tắt) |

**Modeling** — `rb_modeling-2x.png`

| Nhóm | Nút |
|---|---|
| Relationships | Manage relationships (L) |
| Calculations | New visual calculation ▾ (tắt) · New measure · Quick measure · New column · New table (đều L) |
| Calendars | Mark as date table (L) |
| Page refresh | Change detection (L, tắt) |
| Parameters | New parameter ▾ (L) |
| Security | Manage roles (L) · View as (L) |
| Q&A | Q&A setup (L) · Language ▾ (L) · Linguistic schema ▾ (L) |

**Design** — `rb_design-2x.png`

| Nhóm | Nút |
|---|---|
| Themes | Thư viện 6 ô mẫu theme (≈ 56×44, ô đang dùng có viền) kèm mũi tên mở rộng · Theme gallery (L) · cột S: Customize theme (có chấm xanh lục) · Download theme · Import theme |
| Customize page | Page size ▾ (L) · Page background (L) · Wallpaper (L) |
| Help | How to create a theme (L) |

**View** — `rb_view-2x.png`

| Nhóm | Nút |
|---|---|
| Scale to fit | Page view ▾ (L) |
| Mobile | Mobile layout (L) |
| Page options | 3 hộp kiểm xếp dọc: Gridlines · Snap to grid · Lock objects |
| Show panes | Filters (L, **dạng bật/tắt**, nền xám khi đang hiện) · Bookmarks · Selection · Performance analyzer · Sync slicers (đều L) |

Pane **Data** và **Visualizations** không có nút ở tab View; đóng/mở bằng mũi tên « » ở tiêu đề pane.

**Optimize** — `rb_optimize-2x.png`

| Nhóm | Nút |
|---|---|
| Queries | Pause visuals (L) · Refresh visuals (L) |
| Report | Optimization presets ▾ (L) |
| Review | Performance analyzer (L) |
| Apply | Apply all slicers button (L) |

**Help** — `rb_help-2x.png`

| Nhóm | Nút |
|---|---|
| Info | About (L, biểu tượng ⓘ xanh) |
| Help | Guided learning · Training videos · Documentation · Support |
| Community | Power BI blog · Community · Power BI for developers · Submit an idea · External tools |
| Resources | Examples ▾ · Consulting services |

**Format** (chọn visual) — `rb_vformat-2x.png`

| Nhóm | Nút |
|---|---|
| Interactions | Edit interactions (L) · nhãn "Apply drill down filters to" + ô thả xuống `Entire page` (tắt) |
| Arrange | Bring forward ▾ · Send backward ▾ · Selection · Align ▾ · Group ▾ (tắt khi chọn 1 visual) |

**Data / Drill** (chọn visual) — `rb_vdata-2x.png`

| Nhóm | Nút |
|---|---|
| Show | Visual table (L) · Data point table (L, tắt) |
| Interactions | "Apply drill down filters to" + ô `Entire page` |
| Drill actions | cột S 2×2: Switch to next level · Expand next level · Drill up · Drill down (đều tắt nếu visual không có phân cấp) · Drill through (L) |
| Data groups | Groups ▾ (L, tắt) |
| AI | Find anomalies (L, tắt) |

### 3.6 Ribbon — Table / Model / DAX / TMDL

**Table view — Home** (`rb_tv_home-2x.png`): Clipboard (Paste, Cut, Copy) · Data (như Home Report) · Queries · **Relationships** (Manage relationships) · Calculations (New measure, Quick measure, New column, New table) · Security (Manage roles, View as) · Sensitivity · Share (Publish). Không có Insert/Copilot.

**Table tools** (`rb_tv_table-2x.png`): Structure (ô `Name` + danh sách thả xuống tên bảng) · Relationships · Calculations (New measure, Quick measure, New column, New table) · Calendars (Mark as date table).

**Column tools** (`rb_tv_column-2x.png`, toàn màn hình `t_colsel.png`): Structure (`Name`, `Data type` là hai ô thả xuống) · Formatting (`Format` ▾, hàng `$ ▾ % , .00` và ô `Auto`) · Properties (`Summarization` ▾, `Data category` ▾) · Sort (Sort by column ▾) · Groups (Data groups ▾) · Relationships · Calculations (New column).

**Model view — Home**: Clipboard · Data · Queries · Relationships (Manage relationships) · Calculations (New measure, New column, New table, **Calculation group**) · **Parameters** (New parameter ▾) · Security · **Q&A** (Q&A setup, Language ▾, Linguistic schema ▾) · Sensitivity · Share. Không có Quick measure.

**DAX query view — Home** (`v_dax_1.png`): Clipboard (Paste, Cut, Copy) · **Editing**: Format · Comment · Uncomment · Find · Replace · Command palette · Copilot.

**TMDL view — Home** (`v_tmdl_2.png`): Clipboard · **Editing**: Format · Find · Replace · Command palette.

Cả hai view mã đều **không** còn nút Run/Apply trên ribbon; chúng nằm ngay phía trên trình soạn thảo (mục 3.8).

### 3.7 Các pane và thanh dưới (Report view)

- **Filters:** mặc định thu gọn thành dải dọc ≈ 31: mũi tên «, biểu tượng phễu, chữ "Filters" xoay dọc.
- **Visualizations:** tiêu đề + `»`. Dòng nhãn nhỏ "Build visual". Hàng 3 biểu tượng tab (Build visual / Format visual / Analytics; tab đang chọn có mũi tên chỉ lên và nền trắng). Lưới 6 cột biểu tượng visual (≈ 24 px, cách ≈ 24), nhiều hàng, hàng cuối là `…` rồi hàng visual tuỳ chỉnh. Dưới là các **well** có tiêu đề (Values / X-axis / Column y-axis… ) mỗi well là một hộp viền nét đứt "Add data fields here"; ô đã có trường là ô xám nhạt có `▾` và `×`. Cuối pane: **Drill through** — công tắc *Cross-report* (Off) và *Keep all filters* (On, xanh lục), hộp "Add drill-through fields here". Khi chọn visual, tab Format (`p_format.png`): hộp Search, hai tab nhỏ **Visual / General**, danh sách thẻ gập: Style presets, X-axis, Y-axis, Secondary y-axis, Legend (công tắc On), Small multiples, Gridlines, Zoom slider (Off), Columns, Lines, Shade area (Off), Markers, Data labels (Off), Series labels (Off)… mỗi thẻ có `›` bên trái.
- **Data:** tiêu đề + `»`, ô Search có biểu tượng kính lúp, cây bảng (biểu tượng bảng, `›` mở rộng; cột/measure có biểu tượng loại; cột ẩn có mắt gạch; thư mục hiển thị; ô tích xanh lục bên trái khi trường đang dùng trong visual đã chọn). Ở Model/DAX/TMDL view có thêm hai tab **Tables / Model**; tab Model là cây "Semantic model" (Calculation groups, Cultures, Expressions, Functions, Measures, Perspectives, Relationships, Roles, Tables, kèm số lượng).
- **Thanh trang** (`o_now.png`): biểu tượng **Desktop/Phone layout** ở trái → mũi tên ◂ ▸ → các **tab trang** (chữ thường, tab chọn nền trắng + gạch xanh lục ở dưới, trang ẩn có biểu tượng mắt gạch) → nút **`+`** vuông xanh lục. Ở Model view tab là "All tables" và `+`; ở DAX là "Query 1" và `+`; ở TMDL là "Script 1" và `+`.
- **Thanh trạng thái:** trái "Page 3 of 4" (Table view: "Table: Dim_Account (4,501 rows) Column: account_id (4,501 distinct values)"); phải: `−` thanh trượt `+` `69%` và biểu tượng *fit page*. Model view có thêm nút đặt lại.

### 3.8 Hành vi view đặc thù

- **Báo cáo trống** (ảnh bạn gửi): giữa canvas tiêu đề "Add data to your report" cỡ ≈ 26 và dòng phụ "Once loaded, your data will appear in the **Data** pane." (chữ Data đậm); 4 thẻ rộng ≈ 252, mỗi thẻ gồm nửa trên màu nhạt (xanh lục nhạt cho Excel, xanh dương nhạt cho SQL, vàng nhạt cho dán, xám cho mẫu) và nhãn đậm bên dưới; liên kết xanh lục "Get data from another source →". (`AddDataPanel` hiện đã gần khớp.)
- **Model view:** thẻ bảng trắng viền xám, tiêu đề đậm có biểu tượng + `…`, danh sách trường cuộn được, mũi tên `^` thu gọn ở đáy thẻ; đường quan hệ nét liền, đầu có nhãn `1` / `*` và tam giác chiều lọc; pane **Properties** (phần "Cards") nằm giữa canvas và pane Data.
- **DAX query view:** dải thông báo "DAX queries will be saved to your model…" có `×`; hàng nút **Run** (xanh lục, có biểu tượng ▷) và **Update model with changes (0)** (tắt); trình soạn có số dòng, bản đồ thu nhỏ (minimap) bên phải; vùng **Results** có tiêu đề và hình minh hoạ trống "Your query results will show up here"; ở dưới là tab truy vấn.
- **TMDL view:** hai nút **Apply**, **Preview** (tắt) trên đầu; lần đầu mở có hộp thoại giới thiệu "Edit your model with TMDL"; vùng dưới có tab **Problems (0)** / **Output**.
- **Table view:** thanh công thức (✕ ✓ + ô nhập) phía trên lưới; lưới có hàng tiêu đề kèm mũi tên lọc `▾`.

### 3.9 File (backstage) và màn hình khởi động

- **Khởi động** (`ảnh 1 của bạn`): rail trái hai mục **Home**, **Open** + hai mục đáy "Sign out", "Options and settings", "About". Giữa: "Select a data source or start with a blank report" cùng 6 thẻ vuông ≈ 210×210 (Blank report, OneLake catalog, Excel workbook, SQL Server, Learn with sample data, Get data from other sources); mục "Recommended" với thẻ *Getting started*; hai nút tròn **Recent / Shared with me**; ô "Filter by keyword" + nút Filter ▾; bảng **Name / Location / Opened**.
- **File menu khi đã mở file** (`f_file.png`): mũi tên quay lại ở góc trên trái; danh sách: **Home · Open** — **Save · Save as · Share · Get data · Import · Export · Publish** — **Sign out · Options and settings · About**. Trang Home có mục **New** (thẻ "Blank report"), **Recommended**, **Recent**. Trang Save as: "Save a copy" với Recent / OneDrive / SharePoint / Browse this device.

### 3.10 Menu thả xuống và hộp thoại (VM-UI2)

Ảnh: `dd_*.png`, `pn_perfanalyzer.png` trong `docs/phase-ui-evidence/vm-ui/`. Menu bật khi bấm **phần mũi tên/nhãn dưới cùng** của nút; bấm phần biểu tượng của nút có ▾ thường chạy hành động chính (Get data bấm biểu tượng mở hộp **Get Data**). Rê chuột chờ ≈ 0,5 s hiện tooltip hình chữ nhật trắng, bo góc, có dòng mô tả ("Add a page to your report.", "Assess your report's performance and identify areas for improvement.").

| Nút | Nội dung |
|---|---|
| **New page ▾** | Hai mục: New page (biểu tượng trang +), **Duplicate page**. |
| **Buttons ▾** | Right arrow · Reset · Back · Information · Help · Bookmark · Blank · Apply all slicers · Clear all slicers · **Navigator ›** (có menu con, nội dung `[CHƯA QUAN SÁT]`). Mỗi mục có biểu tượng bên trái. |
| **Shapes ▾** | Thư viện lưới biểu tượng (4 cột) theo nhóm: nhóm đầu không có tiêu đề (hình chữ nhật các kiểu góc), **Basic Shapes** (oval, bo tròn, tam giác, tam giác vuông, bình hành, hình thang, ngũ giác, lục giác, bát giác, trái tim, bóng thoại, đường chéo), **Block Arrows** (mũi tên phải/trái/lên/xuống, ngũ giác mũi tên, chevron…); có thể còn nhóm khác phía dưới `[CHƯA QUAN SÁT]`. |
| **Page view ▾** (View) | **Fit to page** · **Fit to width** · **Actual size**; có tooltip "Choose a page view. We'll save this setting with your report." |
| **Refresh ▾** (Home) | **Schema and data** · **Schema** · **Data**. |
| **Themes ▾** (Design) | Banner thông tin "Previous color-only themes are now color palettes. Open theme format pane."; mục **This report** (theme đang dùng, 1 ô); mục **Power BI** (9 ô mẫu xếp lưới 4 cột: ô đầu là ô trống gạch chéo = mặc định, các ô còn lại là theme có nền màu khác nhau; tên từng theme `[CHƯA QUAN SÁT]`); cuối là **Theme gallery**. Ô mẫu ≈ 72×44 (chữ "Aa" + 4 cột màu). |
| **Get data** (bấm biểu tượng) | Hộp thoại **Get Data**: tiêu đề nhóm **All** rồi danh sách nguồn có biểu tượng, mục đầu đang chọn (nền xám): Excel Workbook · Text/CSV · XML · JSON · Folder · PDF · Parquet · SharePoint folder · SQL Server database · Access database · SQL Server Analysis Services database · Oracle database · IBM Db2 database…; nút đóng `×` góc trên phải (cột danh mục bên trái và các nút đáy hộp `[CHƯA QUAN SÁT]`). (BI Pro đã có `GetDataDialog`, chỉ cần so lại cho khớp tiêu đề và thứ tự.) |
| **File ▸ Options and settings** | Trang có hai mục: **Options** và **Data source settings**. |
| **Hộp Options** | Hộp trắng ≈ 770×600, tiêu đề "Options". Cột trái **GLOBAL**: Data Load · Power Query Editor · DirectQuery · R scripting · Python scripting · Security · Privacy · Regional Settings · Updates · Usage Data · Diagnostics · Preview features · Save and Recover · Report settings · Copilot (preview); **CURRENT FILE**: Data Load · Regional Settings · Privacy · Auto recovery · Published semantic model settings · Query reduction · Report settings. Bên phải là nội dung mục (ví dụ Data Load: Type Detection, Background Data, Parallel loading of tables, Time intelligence "Auto date/time for new files", DAX Behavior, Data Cache Management Options + nút Clear Cache). Nút **OK** (xanh lục) và **Cancel** ở đáy phải. |
| **Performance analyzer** (View/Optimize) | Pane bên phải canvas (≈ 420 pt rộng): tiêu đề + `»`; nút **Start recording** (xanh lục, có biểu tượng ●), **Refresh visuals**, **Stop** (tắt); đoạn mô tả "Start monitoring your report to get details about the time taken by each visual to query for its data and render the result."; chân pane có đoạn liên kết "support site", "AppSource". Khi mở, canvas thu hẹp và Visualizations/Data pane giữ nguyên. |

Quan sát này chốt thêm: **UI-A6** (Buttons/Shapes dùng đúng danh sách trên), **UI-A9** (Page view có 3 mục), **UI-A5** (Refresh ▾ có 3 mục: nếu BI Pro chưa tách schema/dữ liệu thì mục thừa vô hiệu), **UI-A8** (Themes ▾ có banner + This report + Power BI + Theme gallery), và thêm **UI-E4**: hộp **Options** nhóm GLOBAL/CURRENT FILE (dùng lại `FileOptionsView`/Settings hiện có, các mục chưa có tính năng hiển thị vô hiệu).

## 4. Hiện trạng BI Pro và khoảng cách

Ảnh `bipro-truoc/b_home.png`. Mã nguồn chính: `Shell/Ribbon.swift` (892 dòng), `Shell/ShellView.swift`, `DesignSystem/{Tokens,Components}.swift`, `DocumentState.swift` (`RibbonTab`, `tabs`).

| Hạng mục | Power BI Desktop | BI Pro hiện tại | Mức |
|---|---|---|---|
| Khung | Tiêu đề Windows (Save/Undo/Redo/Search/Share) | Thanh tiêu đề macOS: tên file + "View only", ô tìm ⌘K, nút Export | Lớn |
| Tab Report | File Home Insert Modeling **Design** View **Optimize** Help | Home Insert Modeling View Help (thiếu File, Design, Optimize) | Lớn |
| Tab Table/Model/DAX/TMDL | File Home Help (+ Table/Column tools) | Có thêm tab Modeling/View ở nhiều view | Vừa |
| Kiểu tab | Chữ thường, gạch chân xanh lục | Viên thuốc nền trắng bo góc, xanh dương | Vừa |
| Panel ribbon | Nền trắng bo góc nổi trên chrome | Dải trắng phẳng, hairline trên/dưới | Vừa |
| Nhãn nhóm | Chữ thường xám, dưới nhóm | CHỮ HOA, tracking 0,4 | Vừa |
| Nút ribbon | Biểu tượng Fluent nhiều màu ≈ 32, nhãn dưới | SF Symbols đơn sắc ≈ 17, tint tự chọn | Lớn |
| Home | 8 nhóm (xem 3.5) | Clipboard, Data, Queries, Insert, **Arrange**, Calculations; thiếu OneLake, Dataverse, Recent sources, More visuals, New visual calculation, Sensitivity, Publish, Copilot; Arrange thuộc Format ở Desktop | Lớn |
| Insert | 6 nhóm | 3 nhóm (Pages, Visuals, Elements); thiếu AI visuals, Power Platform, Sparklines, More visuals | Lớn |
| Modeling | 7 nhóm | 3 nhóm; thiếu Calendars (Mark as date table đang ở Table tools), Page refresh, Parameters, Q&A, Quick measure/New visual calculation | Lớn |
| View | Page view, Mobile, Page options, Show panes | Themes, Show panes (kèm Data/Visualizations), Zoom | Lớn |
| Design / Optimize | Có | Không có (Themes nằm ở View) | Lớn |
| Format / Data-Drill | Xem 3.5 | Có nhưng nhóm khác (Arrange nằm Home) | Vừa |
| Table/Column tools | Xem 3.6 | Gần khớp nhóm nhưng ô Name/Data type/Format là TextField/menu riêng | Nhỏ |
| Rail | 5 biểu tượng 42 pt, tooltip, vạch xanh lục, không bánh răng | 5 biểu tượng 56 pt trong nút vuông xanh dương + bánh răng đáy | Vừa |
| Filters pane | Dải dọc thu gọn mặc định | Pane rộng 260, mở sẵn kèm tiêu đề "Filters on this page / all pages" | Vừa |
| Visualizations | Tab Build/Format/Analytics bằng biểu tượng, lưới 6 cột biểu tượng màu | Phân đoạn "Build | Format", biểu tượng SF đơn sắc | Vừa |
| Data pane | Tên + `»`, kính lúp, cây | Gần khớp; thêm chân trang "11 tables · 168 measures" | Nhỏ |
| Trang | Tab chữ thường, nút `+` vuông xanh lục, biểu tượng Desktop/Phone | Chữ + `+` biểu tượng, không có Phone layout | Vừa |
| Trạng thái | "Page 3 of 4" + zoom thanh trượt + fit | Có "Trang 3 / 4", zoom `− 41% +`; chân từng pane cũng có thanh trạng thái riêng | Vừa |
| Màu nhấn | Xanh lục teal | Xanh dương hệ thống `#0A84FF` | Lớn |
| Canvas | Nền xám `#E6E6E6` | Nền chrome sáng (`#F5F5F7`) | Nhỏ |
| View/Edit | Không có (luôn sửa được) | Công tắc "View | Edit" trên canvas, mặc định chỉ xem | Cần quyết định |

## 5. Yêu cầu sửa

Mỗi yêu cầu có mã `UI-…`; tiêu chí nghiệm thu ở mục 7.

### A. Ribbon (ưu tiên cao nhất)

- **UI-A1 Bộ tab.** Đổi `RibbonTab`/`state.tabs` theo bảng 3.4: thêm `file`, `design`, `optimize`; Table/Model/DAX/TMDL chỉ còn File · Home · Help (+ Table tools, Column tools ở Table view). Tab `File` mở backstage (UI-E2) thay vì hiện ribbon.
- **UI-A2 Kiểu hàng tab.** Chữ thường 13 pt, tab chọn chữ đậm + gạch chân 2 pt màu nhấn; tab ngữ cảnh chữ màu nhấn, **bỏ vạch phân cách**; nút **Share** neo phải (vô hiệu, tooltip "BI Pro chưa hỗ trợ chia sẻ").
- **UI-A3 Panel ribbon.** Nền trắng (`canvas`), nổi trên chrome, bo góc 6, cao 98 (hiện 88), nhãn nhóm chữ thường xám 10 pt, vạch dọc mảnh giữa nhóm; nút `^` thu gọn ở góc dưới phải (lưu trạng thái thu gọn).
- **UI-A4 Kiểu nút.** Chuẩn hoá `RibbonButton`: *L* biểu tượng 28–32, nhãn tối đa 2 dòng căn giữa; *S* xếp dọc tối đa 3 hàng; thêm tham số `hasMenu` vẽ ▾ sau nhãn. Biểu tượng chuyển sang bộ **nhiều màu tự vẽ** (Canvas/SwiftUI shapes) ở dạng gần giống Fluent: khuyến nghị dùng SF Symbols *hierarchical* hai màu cho phiên bản đầu, rồi thay dần; không thêm thư viện ngoài. Vô hiệu = mờ 45%, không đổi tint.
- **UI-A5 Home (Report).** Dựng đúng 8 nhóm và thứ tự của 3.5. Nút chưa có tính năng thật (OneLake catalog, Dataverse, Sensitivity, Publish, Prep data for AI, Copilot, New visual calculation, Recent sources nếu chưa làm) hiện **vô hiệu có tooltip**. Chuyển nhóm **Arrange** sang tab Format (UI-A10). Giữ hành vi các nút đã chạy được (Get data, Excel, SQL → "SQL Server", Enter data, Transform data, Refresh, New visual, Text box, New measure, Quick measure, Cut/Copy/Paste/Format painter).
- **UI-A6 Insert.** Dựng 6 nhóm (Pages, Visuals, AI visuals, Power Platform, Elements, Sparklines). Key influencers / Decomposition tree / Narrative / Paginated report / Power Apps / Power Automate / Add a sparkline: vô hiệu có tooltip. More visuals ▾ mở popover `VisualCatalog` hiện có.
- **UI-A7 Modeling.** Dựng 7 nhóm 3.5: chuyển *Mark as date table* sang nhóm Calendars; thêm Page refresh (vô hiệu), Parameters (vô hiệu), Q&A (vô hiệu); thêm Quick measure & New visual calculation (vô hiệu).
- **UI-A8 Design (mới).** Nhóm Themes (dùng lại `ThemePickerPopover`, hiển thị 6 ô mẫu ngay trên ribbon + nút Theme gallery, Customize theme, Download/Import theme), Customize page (Page size, Page background, Wallpaper: vô hiệu nếu chưa làm), Help. Bỏ Themes khỏi tab View.
- **UI-A9 View + Optimize.** View: Scale to fit (Page view ▾: Fit to page / Fit to width / Actual size → dùng `state.zoom`), Mobile layout (vô hiệu), Page options (3 hộp kiểm Gridlines / Snap to grid / Lock objects — nối vào canvas nếu đã có, nếu chưa thì hộp kiểm vô hiệu), Show panes (Filters bật/tắt, Bookmarks, Selection, Performance analyzer, Sync slicers — các nút chưa có vô hiệu). **Bỏ** nút Data/Visualizations khỏi View (mở bằng `»`). Optimize: Pause visuals, Refresh visuals, Optimization presets ▾, Performance analyzer, Apply all slicers button (vô hiệu cho phần chưa có).
- **UI-A10 Format & Data/Drill.** Format = Interactions (Edit interactions + "Apply drill down filters to" ▾) + Arrange (Bring forward ▾, Send backward ▾, Selection, Align ▾, Group ▾; Ungroup/Merge dời vào menu Group ▾). Data/Drill = Show (Visual table, Data point table) · Interactions · Drill actions (Switch to next level, Expand next level, Drill up, Drill down, Drill through) · Data groups · AI.
- **UI-A11 Table view.** Home theo 3.6; Table tools = Structure(Name ▾) · Relationships · Calculations · Calendars; Column tools = Structure (Name, Data type) · Formatting · Properties · Sort · Groups · Relationships · Calculations; giữ hành vi đã có (`ColumnToolsCommands`, `TableToolsCommands`), chỉ sắp lại nhóm/bố cục.
- **UI-A12 Model / DAX / TMDL.** Model Home có thêm Calculation group, Parameters, Q&A (vô hiệu nếu chưa làm); DAX Home = Clipboard · Editing (Format, Comment, Uncomment, Find, Replace, Command palette) · Copilot (vô hiệu); TMDL Home = Clipboard · Editing (Format, Find, Replace, Command palette). Chuyển **Run** / **Update model with changes (n)** (DAX) và **Apply** / **Preview** (TMDL) xuống thanh nút phía trên trình soạn (UI-G).
- **UI-A13 Tooltip & bàn phím.** Mọi nút vô hiệu có `.help` nêu lý do (đã có cơ chế); giữ phím tắt macOS hiện có (`⌘Z`, `⇧⌘R`…), không dùng phím gợi ý Alt của Windows.

### B. Khung cửa sổ

- **UI-B1 Thanh tiêu đề.** Giữ traffic lights của macOS (không vẽ nút Windows). Trái: Lưu · Hoàn tác · Làm lại · `tên • Last saved: …` (nút Menu ▾) ; giữa: ô Search; phải: bánh răng (mở Settings `⌘,`), chuyển sáng/tối, tài khoản (ẩn), nút **Share**. Bỏ nút "Export" riêng: chuyển vào File ▸ Export. Cao thanh tiêu đề 52 → 36.
- **UI-B2 Rail.** Rộng 42, biểu tượng 22, vạch chọn dọc 3 pt màu nhấn sát mép trái + nền nhạt, bỏ khối nền xanh vuông; bỏ nhãn; tooltip bong bóng "Report view / Table view / Model view / DAX query view / TMDL View"; bỏ bánh răng đáy (dời lên thanh tiêu đề). Luôn hiện đủ 5 biểu tượng (khớp Desktop, kể cả báo cáo trống).
- **UI-B3 Màu và bề mặt.** Chrome `#F5F5F5` (sáng) / giữ bộ màu tối hiện có; canvas quanh trang `#E6E6E6` (sáng) với trang giữ nền giấy tài liệu; màu nhấn mới (UI-F1).

### C. Pane

- **UI-C1 Filters thu gọn mặc định.** Dải dọc rộng 31 với «, biểu tượng phễu, chữ "Filters" xoay 90°; mở rộng khi chọn visual hoặc bấm.
- **UI-C2 Visualizations.** Tiêu đề + `»`; nhãn "Build visual"; hàng 3 biểu tượng (Build visual, Format visual, Analytics) thay phân đoạn "Build | Format" (Analytics = `AnalyticsPane` hiện có); lưới 6 cột; thứ tự biểu tượng theo Desktop (xem `p_format.png`/`o_now.png`: bar/column ×6, line/area ×6, …); phần Drill through cuối pane (Cross-report, Keep all filters) đưa lên tab Build.
- **UI-C3 Wells.** Hộp viền nét đứt, nhãn "Add data fields here", ô trường có `▾` `×`; tiêu đề well theo loại visual (đã có trong `WellRules`).
- **UI-C4 Format pane.** Hộp Search; tab **Visual / General**; thẻ gập có `›`; công tắc On/Off bên phải tiêu đề thẻ khi áp dụng.
- **UI-C5 Data pane.** Bỏ chân trang đếm bảng/measure (dời vào thanh trạng thái chung); ô tích xanh lục nhấn khi trường đang dùng; hai tab **Tables / Model** ở Model/DAX/TMDL view với cây "Semantic model" (Calculation groups, Cultures, Expressions, Functions, Measures, Perspectives, Relationships, Roles, Tables và số lượng — dùng dữ liệu `ModelTree` hiện có).
- **UI-C6 Bỏ thanh trạng thái riêng của từng pane** ("2 active filters", "No visual selected"…), thay bằng một thanh trạng thái toàn cửa sổ (UI-D2).

### D. Thanh trang và trạng thái

- **UI-D1 Thanh trang.** Biểu tượng Desktop/Phone (Phone vô hiệu) · mũi tên ◂ ▸ · tab trang chữ thường (tab chọn nền trắng + gạch xanh lục) · nút `+` vuông xanh lục.
- **UI-D2 Thanh trạng thái.** Cao 23: trái "Page n of m" (hoặc thông tin bảng/cột ở Table view, "Query n of m" ở DAX, "Script…" ở TMDL); phải zoom `− ─── + n%` và nút *fit page*. Giữ dải chấm trạng thái ghi tệp nếu cần, đặt cạnh nhãn trái.

### E. File, khởi động, báo cáo trống

- **UI-E1 Màn hình khởi động** khi chưa có tài liệu: rail Home/Open + Sign out/Options/About (hai mục sau mở Settings/About); khối "Select a data source or start with a blank report" gồm 6 thẻ (Blank report, OneLake catalog [vô hiệu], Excel workbook, SQL Server, Learn with sample data [vô hiệu], Get data from other sources); mục Recommended có thể bỏ; danh sách **Recent** (Name / Location / Opened) dùng lịch sử tài liệu gần đây của macOS.
- **UI-E2 File backstage** khi mở tab File: mũi tên quay lại; Home · Open — Save · Save as · Share(vô hiệu) · Get data · Import(vô hiệu) · Export · Publish(vô hiệu) — Sign out(ẩn) · Options and settings · About. Home hiển thị New ▸ Blank report và Recent. Mọi mục nối vào hành động đã có (`DocumentActions`, `FileOptionsView`, Export PDF/PNG/CSV).
- **UI-E4 Hộp Options.** Cột trái GLOBAL / CURRENT FILE theo 3.10, nội dung phải của Data Load (Type Detection, Time intelligence, DAX Behavior…) nối vào `FileOptionsView`; OK xanh lục, Cancel.
- **UI-E3 Báo cáo trống.** Đã gần khớp; chỉnh lại cỡ chữ tiêu đề 26, dòng phụ có chữ "Data" đậm, thẻ rộng ≈ 252 với nửa trên tô màu nhạt đúng thứ tự (xanh lục nhạt, xanh dương nhạt, vàng nhạt, xám), liên kết xanh lục.

### F. Bảng màu và số đo

- **UI-F1 Màu nhấn.** Đổi `DS.Palette.accent` từ xanh dương `#0A84FF` sang teal `#117865` (nhấn chạm `#0E6655`, dark mode `#3FB59B`). **Ghi đè quyết định cũ "system-blue palette"** (xem mục 6, câu hỏi Q1). Màu chủ đề biểu đồ `DS.Palette.series` giữ nguyên.
- **UI-F2 Token mới.** `DS.Metrics`: `titleBar 36`, `tabRow 32`, `ribbon 98`, `rail 42`, `pageTabs 35`, `statusBar 23`, `pane 181`, `collapsedPane 31`; `DS.Palette.canvasWell #E6E6E6` (sáng) / `#1C1C1E` (tối).
- **UI-F3 Chữ.** Giữ SF Pro (không nhúng Segoe UI); cỡ theo 3.1: tab 13, nhãn nút 11, nhãn nhóm 10, nội dung pane 12.

### G. Các view mã/mô hình

- **UI-G1 DAX query view.** Dải thông báo "DAX queries will be saved to your model" (đóng được); hàng nút **Run** (nền nhấn) + **Update model with changes (n)**; vùng soạn có minimap (tuỳ chọn); khu **Results** có trạng thái trống minh hoạ; tab truy vấn "Query 1 +".
- **UI-G2 TMDL view.** Hàng **Apply / Preview** trên đầu; khu dưới **Problems (n) / Output**; tab "Script 1 +"; hộp thoại giới thiệu lần đầu (có thể dùng `OnboardingView`, đóng được, nhớ trong `AppPreferences`).
- **UI-G3 Model view.** Thêm pane **Properties** giữa canvas và pane Data (nhóm "Cards" với 3 công tắc như 3.8); tab dưới "All tables +".
- **UI-G4 Table view.** Giữ thanh công thức; chân trạng thái "Table: … (n rows) Column: … (n distinct values)".

## 6. Quyết định cần bạn chốt

| # | Câu hỏi | Khuyến nghị |
|---|---|---|
| Q1 | Quyết định cũ: bảng màu xanh dương hệ thống. Bạn muốn "giống" nên đổi màu nhấn sang teal của Power BI? | **Đổi** (UI-F1), vì màu nhấn xuất hiện ở tab, gạch chân, Share, `+`, công tắc — thiếu nó nhìn không giống |
| Q2 | Quyết định cũ "viewer-first": giữ công tắc View/Edit trên canvas hay bỏ như Desktop (luôn sửa được)? | **Giữ ở dạng ẩn:** mặc định mở ở chế độ Sửa như Desktop, vẫn có "Chế độ chỉ xem" trong menu View để bảo vệ tệp. Cần bạn xác nhận vì đảo mặc định |
| Q3 | Biểu tượng ribbon: SF Symbols hai màu (nhanh, lệch Fluent) hay tự vẽ bộ biểu tượng giống Fluent? | **SF Symbols hai màu** ở lần đầu; tự vẽ sau cho 15–20 nút nổi bật nhất (Get data, New visual, Paste…) |
| Q4 | Nút Windows-only/cloud (Copilot, Publish, Share, Dataverse, OneLake, Power Apps/Automate, Q&A, Sensitivity): hiện vô hiệu hay ẩn hẳn? | **Hiện vô hiệu có tooltip** để giữ đúng vị trí và số nút |
| Q5 | Thanh tiêu đề: giữ traffic lights macOS và dồn Save/Undo/Redo/Search/Share vào đó (khuyến nghị), hay vẽ nút điều khiển kiểu Windows? | Giữ traffic lights macOS |
| Q6 | Có thêm phiên VM bổ sung? | **Đã chốt: có** — VM-UI2 xong ngày 2026-11-21 (mục 3.10) |

## 7. Tiêu chí nghiệm thu

1. **So ảnh:** chụp BI Pro ở cùng kích thước 1600×1000 pt và Desktop ở 1867×1017 pt, đặt cạnh nhau cho từng tab (Home, Insert, Modeling, Design, View, Optimize, Help, Format, Data/Drill; Table/Column tools; Model/DAX/TMDL Home). Đạt khi: đúng **số tab**, đúng **thứ tự và tên nhóm**, đúng **thứ tự và tên nút**, đúng kiểu L/S/▾, đúng trạng thái bật/tắt theo ngữ cảnh (bảng 3.5, 3.6).
2. **Số đo:** các `DS.Metrics` trong UI-F2 lệch ≤ 2 pt so với 3.1; màu nhấn và chrome lệch ≤ 3% về độ sáng.
3. **Hành vi không lùi:** toàn bộ nút đang chạy được vẫn chạy (kể cả `ColumnToolsCommands`, `TableToolsCommands`, `AppLaunchPolicy`); đủ test hiện có (2 478 unit + 124 golden) vẫn qua, không đổi byte `.pbix`.
4. **Test mới (theo `/tdd`):** test mô hình dữ liệu của ribbon (danh sách tab/nhóm/nút theo từng `mode` × tab, kiểm thứ tự và trạng thái vô hiệu); test song ngữ (mọi nhãn mới có cả Việt/Anh, chế độ Anh dùng đúng chữ của Desktop như "Get data", "Quick measure"); test Dark Mode (không mất tương phản — dùng các token `paper*`/`chrome`).
5. **Cổng Desktop:** mở cùng một `.pbix` trong BI Pro và Power BI Desktop, đối chiếu ảnh ở từng bước 1; không đòi giống từng điểm ảnh, đòi giống bố cục và nhận diện thị giác.
6. **VoiceOver:** mọi nút mới có `accessibilityLabel`; tab ngữ cảnh có `isSelected`.

## 8. Kế hoạch triển khai (đề xuất)

Theo CLAUDE.md, dùng Spec Kit và dừng duyệt ở 3 cổng. Đề xuất một feature `specs/016-v13-giao-dien-powerbi/` chia pha để chạy từng đợt:

| Pha | Nội dung | Rủi ro |
|---|---|---|
| H1 | Nền: token (UI-F), `RibbonTab`, khung tab + panel ribbon + kiểu nút (UI-A1–A4), rail + thanh tiêu đề (UI-B) | Thấp, thay đổi thuần giao diện |
| H2 | Nội dung ribbon từng tab: Home, Insert, Modeling, Design, View, Optimize, Help (UI-A5–A9) | Trung bình: di chuyển nút giữa tab, phải giữ hành vi |
| H3 | Format/Data-Drill, Table view, Model/DAX/TMDL (UI-A10–A13, UI-G) | Trung bình |
| H4 | Pane, thanh trang, thanh trạng thái (UI-C, UI-D) | Trung bình: bỏ thanh trạng thái từng pane |
| H5 | Khởi động, File backstage, báo cáo trống (UI-E) | Thấp–trung bình |
| H6 | Cổng Desktop so ảnh, sửa lệch, dựng `.app` v1.3.0 | Thấp |

Bắt đầu từ H1+H2 vì Ribbon là trọng tâm bạn nêu; mỗi pha kết thúc bằng một lần chụp so sánh và cập nhật `docs/STATE.md`.

## 9. Việc kế tiếp

1. Bạn duyệt tài liệu này và trả lời Q1–Q6 (hoặc chấp nhận khuyến nghị).
2. Chạy Spec Kit: `/speckit-specify` → `/speckit-clarify` (dừng duyệt `spec.md`), rồi plan, tasks, analyze.
3. (Nếu Q6 = có) phiên VM bổ sung để chụp các menu thả xuống và hộp thoại còn thiếu.
