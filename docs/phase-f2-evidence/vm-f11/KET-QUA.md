# Gate VM-F11 (T037): kết quả

Buổi 2026-11-18 tối, Power BI Desktop 2.159 trên VM Windows 11 (Claude lái VM, người dùng cho phép). Thư mục thử trong VM: `C:\Users\bacpew\f11g`.

## Kết luận

**Đạt.** Desktop mở cả hai file BI Pro không lỗi. Số liệu, phân cấp ngày và quan hệ khớp Desktop.

Có hai điểm `[SUY ĐOÁN]` sai, đã sửa trong cùng buổi:

1. **Khoá lưu tuỳ chọn Autodetect** (`FileSettings`). Khoá đúng là `ReportSettings.IsRelationshipAutodetectionEnabled`, không phải `QueriesSettings.RunBackgroundAnalysis`.
2. **Luật tự phát hiện quan hệ** (`RelationshipDetector`). Cột số thực vẫn được làm khoá, không bị bỏ.

## 1. `bipro-f11.pbix` (T036)

- Mở không lỗi. Biểu đồ "Sum of Amount by Year" có hai cột 2025 và 2026 (`d1`).
- Data pane: `Sales[OrderDate]` và `Sales[OrderTime]` có biểu tượng lịch. Mở `OrderDate` ra thấy "Date Hierarchy" với Year, Quarter, Month, Day (`d2`).
- **Số theo năm** (DAX query view, `d3`), tính theo `'Sales'[OrderDate].[Year]` và đối chiếu `SUMX(FILTER(ALL(Sales), YEAR(OrderDate) = y), Amount)`:

  | Năm | Tổng | Đối chiếu | Số dòng |
  |---|---|---|---|
  | 2025 | 93 742,69 | 93 742,69 | 266 |
  | 2026 | 92 988,54 | 92 988,54 | 234 |

- **Số theo Năm × Quý:** `SUMMARIZECOLUMNS('Sales'[OrderDate].[Year], [Quarter], …)` trong Desktop và truy vấn tương đương bằng engine BI Pro (`dax-run`, qua `LocalDateTable_…`) cho cùng 8 ô. Ví dụ 2025 Qtr 1 là 26 071,26 (68 dòng), 2026 Qtr 4 là 18 316,47 (50 dòng).
- **Quan hệ** (`INFO.VIEW.RELATIONSHIPS()`, `d4`): ba quan hệ `AutoDetected_…` trùng `f11-desktop.pbix`:
  - `Sales[CustomerID]` → `Customers[CustomerID]`, hoạt động;
  - `Sales[Region]` → `Table (2)[Region]`, hoạt động;
  - `Customers[Region]` → `Table (2)[Region]`, không hoạt động.

  Cả ba nhiều–một, một chiều.
- **Refresh bảng Enter Data:** dữ liệu `Table` và `Table (2)` trước Refresh trùng BI Pro. Chuột phải `Table` ▸ Refresh ▸ Schema and data ra lại đúng 5 dòng.
  - Sau Refresh, tên cột `Tên` thành `\uFEFFTên` (UNICODE 65279), nên DAX gọi `'Table'[Tên]` báo lỗi (`d5`).
  - Nguyên nhân là M của `Table`, chép nguyên văn từ file Desktop buổi VM-F11, có `#"\uFEFFTên"`. Ký tự này sinh ra khi dán qua clipboard trong VM (QUAN-SAT mục a).
  - Lần nạp đầu Desktop bỏ U+FEFF, còn Refresh thì giữ. File Desktop tự làm có cùng M và cùng tên cột, nên sẽ bị y như vậy. Đây không phải lỗi của BI Pro.
- **Thêm visual theo Quý trong Desktop** (`d6`): tích cấp Quarter của Date Hierarchy rồi tích `Amount`, ra biểu đồ Qtr 1–4.

## 2. `w83_f2.pbix` (T066)

- Mở không lỗi. Bảng `Dự án` có mặt, `Sự kiện` đã xoá. Trang báo cáo vẽ đủ (`d8`).
- **Khoảng năm của phân cấp ngày:**

  | Cột | Năm nhỏ nhất | Năm lớn nhất |
  |---|---|---|
  | `Thông tin nhân viên[Ngày sinh]` (đã dời 10 năm) | 1996 | 2009 |
  | `Dự án[Ngày bắt đầu]` | 2030 | 2031 |

  Năm nhỏ nhất và lớn nhất của các giá trị `.[Year]` trùng `YEAR(MIN/MAX(cột))`.
- **Measure khớp engine BI Pro:**
  - `[Tỷ lệ nam/nữ]` = 1,1667;
  - `[Chi phí đào tạo nhân viên]` = 46 400 000;
  - số người sinh từ năm 2000 = 46.
- `[Mức lương trung bình < 35 tuổi]`: Desktop ra 7 539 772,73. Engine BI Pro chưa có hàm `TODAY` nên chưa tính được (tồn đọng mới, ngoài T037).

## 3. Các điểm `[SUY ĐOÁN]`

### Cờ `active` khi thả phân cấp ngày: đúng

- Tích cả `OrderDate` (Year, Quarter, Month, Day): chỉ cấp Year có `active: true`, ba cấp còn lại `false`. Xem `desk-a.pbix`, ngoài git.
- Visual chỉ có cấp Quarter: cấp đó `active: true`.

### Khoá tuỳ chọn Autodetect: sai, đã sửa

Options ▸ Current File ▸ Data Load ▸ bỏ tích "Autodetect new relationships after data is loaded" (`d7`) ▸ lưu thì `Settings` thành:

```
{"Version":4,"ReportSettings":{"IsRelationshipAutodetectionEnabled":false},"QueriesSettings":{…}}
```

- **Tích lại rồi lưu:** khoá bị xoá, `ReportSettings` trở về `{}`.
- **`RunBackgroundAnalysis`:** là ô "Allow data previews to download in the background". File BI Pro không có khoá này nên Desktop hiện ô đó bỏ tích. Tích ô đó rồi lưu thì Desktop cũng không ghi khoá, nên chưa rõ khi nào Desktop ghi nó.
- **Đã sửa `FileSettings`** cho đúng quan sát. Test `FileSettingsTests` dùng đúng chuỗi Desktop lưu ở `desk-a` và `desk-b`.
- **Kiểm lại trên Desktop:** `bipro-noauto.pbix` (do `FileOptionsTests` sinh) mở ra thấy ô Autodetect bỏ tích (`d10`).

### Luật tự phát hiện quan hệ

Thí nghiệm trong một tài liệu trống: nạp lần lượt sáu bảng bằng Enter Data, mỗi lần một bảng (`d9`).

| Bảng | Cột (kiểu Desktop nhận) | Giá trị |
|---|---|---|
| `Table` | `k` (Integer), `d` (Number) | k 1, 2, 3; d 1,5, 2,5, 3,5 |
| `Table (2)` | `K` (Integer) | 1, 1, 2 |
| `Table (3)` | `d` (Number) | 1,5, 1,5, 2,5 |
| `Table (4)` | `flag` (True/False) | TRUE, FALSE |
| `Table (5)` | `flag` (True/False) | TRUE, TRUE, FALSE |
| `Table (6)` | `k`, `d` | k 1, 1, 2; d 1,5, 1,5, 2,5 |

Desktop tạo đúng ba quan hệ, đều hoạt động, nhiều–một:
- `Table (2)[K]` → `Table[k]`;
- `Table (3)[d]` → `Table[d]`;
- `Table (6)[k]` → `Table[k]`.

Kết luận từng luật:
- **So tên không phân biệt hoa thường:** đúng (`K` nối với `k`).
- **Bỏ cột số thực:** sai. Desktop có tạo quan hệ trên cột Number. Đã sửa `RelationshipDetector` để chỉ còn bỏ cột logic và cột chưa rõ kiểu.
- **Bỏ cột logic:** đúng. `Table (4)` và `Table (5)` không được nối.
- **Mỗi cặp bảng một quan hệ, lấy cột đầu tiên:** đúng. `Table (6)` khớp cả `k` và `d` nhưng chỉ có quan hệ theo `k`.
- Test `RelationshipDetectorFlowTests.gateF11HoaThuongSoThucLogicMoiCapMot` lặp lại đúng thí nghiệm này.
- **Còn `[SUY ĐOÁN]`:**
  - hai phía cùng duy nhất thì bỏ;
  - chỉ xét cặp có bảng mới nạp;
  - thứ tự xét các cặp bảng.

### Chưa kiểm ở buổi này

- Cột ngày toàn BLANK ra năm 3799.
- Mẫu ngày `FORMAT` en-US của bảng ngày cục bộ: Desktop dùng dữ liệu đã lưu, không tính lại.

## File

- **Ngoài git:** `build/f2-out/f11/desk-a.pbix` (Autodetect tắt, có hai visual mới) và `desk-b.pbix` (bật lại). Cả hai do Desktop lưu.
- **Ảnh** `d1`–`d10` trong thư mục này. Mọi ảnh đã cắt bỏ thanh tiêu đề.
