# Đặc tả tính năng: Đợt 4 (v1.2) — Mở khoá toàn bộ Ribbon, RLS, Mark as Date Table, Quick Measures & Công cụ DAX/TMDL

**Thư mục spec:** `specs/015-v12-hoan-thien-chuyen-nghiep/`
**Ngày lập:** 2026-11-21
**Trạng thái:** Chờ duyệt (Cổng duyệt 1/3 — `spec.md`)
**Bằng chứng nền:** [QUAN-SAT.md](file:///Users/macprom114/Desktop/PowerBINative/docs/phase-v12-evidence/vm-v12/QUAN-SAT.md) (Power BI Desktop 2.159.1231.0)

---

## 1. Mục tiêu

Xử lý dứt điểm **toàn bộ 18 nút/mục còn mờ trên giao diện BI Pro** (Report Ribbon, Data/Drill Ribbon, Modeling Ribbon, Table Tools Ribbon, DAX Query Ribbon, TMDL Ribbon và menu chuột phải `DataPane`), đưa trải nghiệm tác giả báo cáo & mô hình hoá tiệm cận trọn vẹn Power BI Desktop trên macOS 15 Sequoia (Apple Silicon, không thư viện ngoài, không gọi mạng).

---

## 2. Phạm vi tính năng (3 nhánh 4A · 4B · 4C)

### Nhánh 4A — Bảng nhớ tạm, Sao định dạng & Tab Dữ liệu / Truy sâu (Report Canvas)
- **US1 — Cut / Copy / Paste visual (kể cả sang trang khác):**
  - Mở khoá 3 nút *Cắt / Sao chép / Dán* trên Ribbon Home (kèm phím tắt `⌘X`, `⌘C`, `⌘V`).
  - Sao chép hoặc cắt 1 hay nhiều visual (nguyên JSON PBIR: loại, kích thước, trường, định dạng, đối tượng `objects`/`visualContainerObjects`) vào clipboard nội bộ của phiên; dán vào cùng trang (lệch `+16, +16`) hoặc **sang trang khác** với mã định danh mới duy nhất, hỗ trợ Undo/Redo nguyên khối.
- **US2 — Format Painter (Sao định dạng):**
  - Bấm *Sao định dạng* khi đang chọn 1 visual nguồn → bật chế độ chờ chọn đích (hiện dải gợi ý trên canvas, `Esc` để huỷ) → bấm visual đích để chép toàn bộ `visualContainerObjects` (tiêu đề, viền, nền, đổ bóng, khoảng đệm) và các nhóm `objects` tương thích (`dataPoint`, `labels`, `legend`, `categoryAxis`, `valueAxis`), hỗ trợ Undo 1 bước `⌘Z`.
- **US3 — Tab Dữ liệu / Truy sâu (`Data / Drill`) & Xem dưới dạng bảng (`Show as a table`):**
  - Mở khoá 3 nút *Lên một cấp (Drill up)*, *Xuống một cấp (Drill down)*, *Mở rộng cấp (Expand next level)* nối trực tiếp với trạng thái drill của `ReportInteraction` cho visual đang chọn.
  - Mở khoá nút **Xem dữ liệu (Show as a table)**: mở bảng dữ liệu chia đôi phía dưới (hoặc sheet tập trung) hiển thị chính xác bảng số liệu sau khi chạy DAX của visual đang chọn (đủ tiêu đề cột, số đã định dạng, nút **Xuất CSV** nhanh).

### Nhánh 4B — Mô hình hoá chuyên sâu, Bảo mật RLS & Menu DataPane
- **US4 — Quick Measures (Measure nhanh):**
  - Mở khoá nút **Measure nhanh** trên Ribbon Home/Modeling → mở hộp thoại `QuickMeasureSheet` gồm **8 phép tính chuẩn Power BI**:
    1. Tổng luỹ kế năm (*Year-to-date total* — `TOTALYTD`)
    2. Tổng luỹ kế (*Running total*)
    3. Trung bình trượt (*Rolling average* N kỳ)
    4. Tỷ trọng % tổng (*% of grand total* — `DIVIDE` + `ALLSELECTED`)
    5. Giá trị đã lọc (*Filtered value* — `CALCULATE`)
    6. Trung bình có trọng số (*Weighted average* — `SUMX` / `SUM`)
    7. Tăng trưởng YoY % (*Year-over-year % change* — `SAMEPERIODLASTYEAR`)
    8. Phép chia an toàn (*Division* — `DIVIDE`)
  - Chọn trường từ dropdown mô hình → xem trước công thức DAX sinh ra → bấm Tạo sẽ kiểm bằng `DAXEngine`, thêm vào mô hình qua `ModelEditor` (hoàn tác `⌘Z` được) và lưu T2.
- **US5 — Mark as Date Table (Đánh dấu bảng ngày):**
  - Mở khoá nút **Đánh dấu bảng ngày** trên tab *Công cụ bảng* → mở `MarkAsDateTableSheet` cho bảng đang chọn.
  - Chỉ cho phép chọn cột kiểu `.dateTime`; tự động kiểm tra tính hợp lệ (không có ô trống, các giá trị ngày duy nhất trên toàn bảng) qua `ColumnStore` trước khi xác nhận.
  - Khi bật/tắt: ghi `Table.DataCategory = "Time"` (hoặc xoá về `nil`) và đặt `Column.IsKey = true` cho cột ngày đã chọn (`false` cho các cột còn lại trong bảng), đồng bộ `ModelMetadata` + `MetadataWriter` (SQLite) + hoàn tác `⌘Z` + lưu T2 chuẩn Power BI Desktop 2.159.
- **US6 — Row-Level Security (Manage Roles & View As):**
  - Đọc đầy đủ `[Role]` và `[TablePermission]` trong `ModelMetadata` (tên vai trò, mô tả, `ModelPermission`, danh sách cặp `(tableName, filterExpression)`).
  - Bổ sung `ModelEdit` cho vai trò RLS (`.upsertRole`, `.deleteRole`) và ghi SQLite trong `MetadataWriter` theo đúng hằng số Desktop 2.159 (`ModelPermission = 2`, `State = 1`, `MetadataPermission = 0`).
  - Mở khoá **Quản lý vai trò (Manage roles)** (`ManageRolesSheet`): tạo/đổi tên/xoá vai trò, nhập biểu thức lọc DAX cho từng bảng, kiểm cú pháp/ngữ nghĩa bằng `DAXEngine` trên bảng đích trước khi lưu, hỗ trợ hoàn tác `⌘Z` và lưu T2.
  - Mở khoá **Xem dưới vai trò (View as)** (`ViewAsRoleSheet`): chọn 1 hoặc nhiều vai trò RLS để mô phỏng trên phiên hiện tại → hiển thị **dải vàng cảnh báo trên đầu Report Canvas** (*"Đang xem dưới vai trò: … [Dừng xem]"*) và tự động gắn điều kiện lọc RLS (hợp OR giữa nhiều vai trò đang chọn, AND giữa các bảng trong một vai trò) vào toàn bộ truy vấn DAX của visual trong `ReportInteraction` & `DAXQueryBuilder`!
- **US7 — Mở khoá menu ẩn/hiện ở `DataPane`:**
  - Bật **Ẩn/Hiện trong chế độ báo cáo** trong menu chuột phải cho Bảng và Cột, và bật **Hiện tất cả (Unhide all)** cho bảng/mô hình (hoàn tác `⌘Z` được).

### Nhánh 4C — Hoàn thiện DAX Query View, TMDL View, SQL Quick Connect & Phiên bản 1.2.0
- **US8 — DAX Formatter (`Định dạng` trên DAX Ribbon):**
  - Bộ định dạng DAX thuần Swift dựa trên `DAXLexer.tokenize` (giữ nguyên 100% chuỗi `"..."`, tên bảng `'...'`, cột `[...]`, chú thích `--`/`//`/`/* */`): chuẩn hoá xuống dòng & thụt lề 4 khoảng trắng cho `DEFINE`, `MEASURE`, `VAR`, `RETURN`, `EVALUATE`, `ORDER BY`, hàm lồng sâu (`CALCULATE`, `SUMMARIZECOLUMNS`, `FILTER`, `IF`, `SWITCH`), hỗ trợ hoàn tác trên editor.
- **US9 — DAX Query View → `Cập nhật mô hình` (Update model):**
  - Mở khoá nút **Cập nhật mô hình** trên DAX Ribbon: quét các định nghĩa `DEFINE MEASURE Table[Name] = <expr>` trong tab truy vấn đang mở → phân loại measure **mới** vs measure **sửa công thức** → mở sheet xem trước diff & xác nhận → kiểm bằng `DAXEngine` và ghi toàn bộ vào mô hình qua `ModelEditor` trong 1 bước `⌘Z`.
- **US10 — TMDL View → `Áp dụng thay đổi` & Ribbon `SQL` Quick Connect & Phiên bản 1.2.0:**
  - Nối nút **Áp dụng thay đổi** trên TMDL Ribbon trực tiếp vào bản nháp TMDL đang sửa của `TMDLWorkspace` (hiển thị trạng thái sáng/mờ thật khi có thay đổi chưa áp dụng).
  - Mở khoá nút **SQL** trên Ribbon Home: mở trực tiếp Get Data đã chọn sẵn nhóm Cơ sở dữ liệu (PostgreSQL / SQLite).
  - Nâng chuỗi phiên bản hiển thị trong *Giới thiệu (About)* và `scripts/build-app.sh` lên **1.2.0** (`Info.plist` `CFBundleShortVersionString = 1.2.0`).

---

## 3. Tiêu chí nghiệm thu (`SC-001` – `SC-004`)

- **SC-001 (Cổng Power BI Desktop 2.159 VM Gate):** Tệp `build/v12-out/bipro-v12-gate.pbix` tạo từ `Nhom6` có đủ: visual đã Paste sang trang mới & Format Painter, 1 Quick Measure mới, 1 bảng đánh dấu `Mark as Date Table`, và 1 vai trò RLS `[Role]` + `[TablePermission]` hợp lệ → mở trên **Power BI Desktop 2.159 (VM Windows 11)** với **0 hộp thoại lỗi/hỏng/thiếu trường**, chụp ảnh cắt sạch vùng canvas (0 email) lưu `docs/phase-v12-evidence/vm-v12/gate-desktop.png`, đóng Desktop & dọn sạch VM.
- **SC-002 (RLS View As chính xác tuyệt đối):** Kích hoạt *View as* cho một vai trò có biểu thức `Dim_District[region] = "Midwest"` → mọi KPI/biểu đồ trên trang lọc đúng theo `Midwest` khớp giá trị DAX khi lọc tay; bấm *Dừng xem* khôi phục nguyên số liệu toàn mô hình.
- **SC-003 (Không còn nút Ribbon nào gắn `phase:` mờ vô tác dụng):** Ngoại trừ các mục thực sự cần trạng thái ngữ cảnh (chưa có mô hình / chưa chọn visual), toàn bộ 18 nút/mục mục tiêu ở 4A–4C hoạt động thật, song ngữ Việt/Anh (`bi(_:_:)`/`L10n`) và hỗ trợ Dark Mode (`DS.Palette`).
- **SC-004 (Hồi quy & Đóng gói Release 1.2.0):** `swift test --no-parallel` 100% xanh, `BIPRO_HEAVY=1` release golden 100% xanh, `zsh scripts/build-app.sh release` + `codesign --verify --deep --strict "build/BI Pro.app"` đạt với phiên bản `1.2.0`.
