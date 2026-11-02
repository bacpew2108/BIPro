# Phase B, buổi 2: kết quả (2026-11-02)

Người dùng tự chạy trên VM Windows 11 với Power BI Desktop 2.159.883.0 (October 2026), en-US, file `Nhom6_work.pbix` (cùng SHA với `Nhom6_Dashboard.pbix`).
- File gốc: `~/Downloads/bipro-golden/{nhom6,observe2}`.
- Golden đã chép vào `Tests/DAXEngineTests/Golden/nhom6/`.
- Quan sát đã chép vào `docs/phase-b-evidence/observe2/`.
- Các file `.dax` trong `pack2/` trùng từng byte với bản trong repo.

## Golden

| Nhóm | File | Kết quả lần đầu | Sau khi sửa |
|---|---|---|---|
| G2 | 4 | khớp | khớp |
| G4 | 1 | khớp | khớp |
| G5 | 1 | lệch 100 ô ở `[Complaints MA3]` | khớp |
| G6a–e | 5 | khớp | khớp |
| G6f1, G6f2 | 2 | Power BI báo lỗi | chờ buổi 3 |
| T1, T3, T4 | 3 | khớp | khớp |
| T2 | 1 | lệch 4 ô | khớp |

`ORAGoldenNhom6Tests` có **27 golden, cả 27 đều khớp**: buổi 1 có 12, buổi 2 thêm 15.

### Các sửa đổi trên engine

1. **CALCULATE, nhiều đối số lọc trên cùng một cột** (`Calculate.swift`, `FilterContext.clearingTable`).
   - Lỗi cũ: đối số sau ghi đè đối số trước. Vì vậy `MonthIndex > mi - 3, MonthIndex <= mi` thành tổng luỹ kế.
   - Cách làm mới, theo đúng thứ tự của DAX:
     - Bước 1: mọi đối số không có KEEPFILTERS xoá bộ lọc bên ngoài trên các cột của nó.
     - Bước 2: mọi đối số được AND với nhau.
2. **DATEADD và SAMEPERIODLASTYEAR** (`TimeIntel.swift`). Bản sửa của buổi 1 ("ngày cuối tháng thì mở rộng tới hết tháng đích") nới quá tay. Quy tắc mới khớp cả 6 ca của T2 và cả G1/G3:
   - Tháng nguồn được chọn **trọn** thì cho **trọn** tháng đích. Ví dụ: 01–28/02/2017 lùi một năm cho 01–29/02/2016, tức 29 ngày.
   - Ngày lẻ thì dịch từng ngày và kẹp về cuối tháng đích:
     - 28/02/2017 lùi một năm cho 28/02/2016;
     - 30/04/2017 lùi một tháng cho 30/03/2017;
     - 31/01/2017 tiến một tháng cho 28/02/2017.
   - Còn đoán: khoảng lẻ kết thúc ở cuối tháng, ví dụ 15–28/02. Sẽ kiểm bằng T5 ở buổi 3.
3. **Tham chiếu `T[m]` khi measure m thuộc bảng khác thì báo lỗi** (`Binder.swift`).
   - Power BI báo: `Column 'Branch NPL Label' in table 'Fact_Loan' cannot be found or may not be used in this expression.`
   - Trước đây engine chấp nhận, nên không phát hiện được lỗi trong gói truy vấn.

### Nguyên nhân G6f1 và G6f2 lỗi

Lỗi nằm ở gói truy vấn, không phải ở thao tác.
- `scripts/oracle/gen-buoi2-pack.py` ghi `mref(LN, "Branch NPL Label")`, trong khi measure này thuộc `Dim_District`.
- Đã sửa generator và sinh lại gói. Chỉ hai file này thay đổi.
- Từ nay engine báo lỗi giống Power BI, nên chạy thử gói bằng `dax-run query` trước khi giao sẽ bắt được lỗi loại này.
- Có một chi tiết Power BI: lỗi được báo tại `(29, 42)`, tức **lần xuất hiện thứ hai** (bên trong `ISBLANK`), không phải lần đầu ở dòng 28. Engine báo tại lần đầu. Chưa rõ quy tắc nên chưa làm theo.

## Quan sát

| Mã | Power BI | BI Pro |
|---|---|---|
| O6 | Thanh trạng thái: `Success (523.1 ms)` · `Query 1 of 1` · `Result 1 of 1` · `14 columns, 96 rows` | Pill hiện tại: "Thành công · 6 dòng · 0,15 s". Cần thêm số cột, `Query i of n`, thời gian tính bằng ms (UI2). |
| O11 | Bôi đen khối EVALUATE thứ hai rồi Run: **chỉ chạy vùng chọn**, ra `Result 1 of 1` với `[khoi] = thứ hai` | Đã đúng (UI1 chạy vùng chọn). |
| O13 | Bấm tiêu đề cột mở menu: Sort Smallest to Largest / Largest to Smallest (cột số), Sort A to Z / Z to A (cột chuỗi), Clear Sort, ô Search, danh sách giá trị có checkbox và Select all, nút Apply. Tức là có **lọc** trên lưới, không chỉ sắp xếp. | Hiện chỉ có sắp xếp khi bấm tiêu đề. Còn thiếu menu lọc (UI3). |
| O14 | Rê chuột lên tên measure trong editor hiện tooltip: `Measure Complaints` và biểu thức `SUM ( Fact_CRM_Complaint[complaint_count] )` | Chưa có (UI2). |
| O15 | `FORMAT(1234.5, "#,0.0")` = `1,234.5`; `FORMAT(0.1234, "0%")` = `12%`; `FORMAT(DATE(2018,12,31), "General Date")` = `12/31/2018` (nửa đêm thì không in giờ) | Đã khớp. Đã thêm `General Date` và `Short Date`. |
| O17 | `IF("12" > 12, 1, 0)` báo lỗi `Query (3, 17) DAX comparison operations do not support comparing values of type Text with values of type Integer. Consider using the VALUE or FORMAT function to convert one of the values.` | Đã khớp. |
| O18a | `ADDCOLUMNS({1, BLANK(), -1}, "k", [Value]) ORDER BY [Value]` cho -1, BLANK, 1. **BLANK được sắp như 0.** | Đã khớp: binder nhận `[Value]` của bảng hằng; ORDER BY so BLANK như 0. |
| O18b | `TOPN(1, {1, BLANK(), -1}, [Value], ASC)` cho -1 | Đã khớp. |
| O8 | Đã có đủ văn bản 5 quick query, xem `observe2/O8-query-1..5.dax`. Mẫu chính: `EVALUATE SUMMARIZECOLUMNS("m", [m])`; bản "define" có comment `///` và các measure phụ thuộc; Top 100 dùng `SELECTCOLUMNS(TOPN(100, T, T[c1], ASC), …) ORDER BY … ASC`; Data preview dùng `DISTINCT(T[c])`. Thụt lề bằng 4 dấu cách (query 1–3) hoặc tab (query 4–5). | Dùng làm mẫu chữ cho UI3. |

## Performance Analyzer (đặc tả cho Phase C)

- Có 8 truy vấn visual (`observe2/PA-D1-1` … `PA-D4-2`), mỗi truy vấn kèm kết quả `.tsv`.
- Engine chưa chạy được truy vấn nào. Lý do: các truy vấn này dùng những dạng mà Phase B không cần:
  - `SUMMARIZECOLUMNS` lồng trong `VAR`; `IGNORE` (19 lần);
  - `ROLLUPADDISSUBTOTAL`, `ROLLUPGROUP`;
  - `NATURALLEFTOUTERJOIN`, `SUBSTITUTEWITHINDEX`;
  - `GROUPBY`, `CURRENTGROUP`;
  - `SAMPLE`, `SAMPLEAXISWITHLOCALMINMAX`.
- Mọi truy vấn đều mở đầu bằng hai bảng lọc cấp report: `NOT('Dim_Date'[year] IN {9999})` và `NOT('Dim_Client'[client_region] IN {"Unknown"})`, bọc trong `KEEPFILTERS(VALUES(...))`.
- `PA-D3-1.dax` có dấu `\` ở dòng 49 (`VAR __DS0BodyLimited = \`). Có thể do chép sai; cần xem lại khi làm Phase C.
- Các truy vấn này là đặc tả đầu vào cho Phase C (truy vấn visual), không chặn Phase B.

## Trạng thái Phase B

- Tiêu chí §0 (G0, G1, G2, G3, G5, G6 khớp): **đạt với mọi golden đã có**. Còn thiếu G6f1 và G6f2, chạy lại ở buổi 3 theo `docs/phase-b-oracle/CHECKLIST-buoi3.md`, khoảng 10 phút. Engine đã chạy thử được bản sửa: G6f1 mất 15 s, G6f2 mất 117 s.
- Test: `swift test` 588 pass, có thêm `ORABuoi2RegressionTests`. Test nặng 31/31 pass.

## Buổi 3 (2026-11-02)

| File | Kết quả |
|---|---|
| G6f1-district (77 dòng) | khớp, 0 ô lệch |
| G6f2-account-branch (76 dòng) | khớp, 0 ô lệch |
| T5-edges | lần đầu lệch 2 ô, đã sửa engine; nay khớp |
| O19-blank-zero-sort | -1, BLANK, 0, 1: BLANK đứng ngay trước 0, đúng như engine đang làm (file nằm trong `nhom6/`, đã chép vào `observe3/`) |

T5 cho thấy Power BI kéo dài một khoảng nhiều ngày có kết thúc ở cuối tháng:
- 15–28/02/2017 lùi một năm ra 15 ngày, tới 29/02/2016;
- 01/03–30/04/2017 lùi một tháng ra 59 ngày, tới 31/03.

Ghép với T2 (một ngày đứng riêng thì không kéo dài), quy tắc là: **tháng nguồn có từ 2 ngày được chọn trở lên và có ngày cuối tháng thì thêm phần còn lại của tháng đích**. Trường hợp chọn trọn tháng là một trường hợp riêng của quy tắc này.

`ORAGoldenNhom6Tests`: **30/30 golden khớp**. Phase B đạt tiêu chí §0 về engine.
