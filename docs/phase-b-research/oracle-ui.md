# Nhiệm vụ C: Chiến lược oracle/kiểm thử + đặc tả DAX Query View (Phase B)

Ngày 2026-10-31. Chỉ đọc repo. Mọi số liệu dưới đây lấy từ file của người dùng, đọc bằng `pbix-dump` và sqlite3 trên bản dữ liệu đã giải mã (nằm trong scratchpad), hoặc từ tài liệu công khai của Microsoft Learn. Không decompile, không chạy pbixray.

Quy ước nhãn:
- **FACT**: đã đo hoặc đọc trực tiếp, có nguồn.
- **SUY ĐOÁN**: suy luận hoặc đề xuất, cần Power BI xác nhận.

Sản phẩm phụ (nằm trong scratchpad, không thuộc repo):
- `b/sql/*.tsv` chứa 11 bảng Nhom6 đã giải mã. `b/sql/nhom6data.db` là bản sqlite của 11 bảng đó.
- `b/sql/closure_tiers.tsv`: 119 measure kèm tầng phân loại.
- `b/sql/oracle_ft.tsv`, `b/sql/oracle_crm_loan.tsv`: kết quả của oracle sqlite.
- `b/oracle/queries/*.dax`: bản nháp 16 truy vấn golden (G0–G3).
- `b/scripts/{load.py, classify.py, gen_oracle.py, oracle_t0.sql, oracle_crm_loan.sql}`.

---

## 0. Số liệu nền (FACT)

| Mục | Giá trị | Nguồn |
|---|---|---|
| Nhom6 | PBIR 1.32; 11 bảng; 168 measure; 14 quan hệ, tất cả single direction, 1 inactive (`Fact_CRM_Complaint[sent_date_key]`); 7 cột tính toán | `pbix-dump info/relationships` |
| Phân bố measure theo bảng | Fact_Transaction 59, Fact_Loan 48, Fact_CRM_Complaint 37, Dim_District 15, Dim_Account 6, Dim_Client 3 | `measures.tsv` |
| Closure của report | 95 measure dùng trực tiếp, 119 khi tính cả phụ thuộc, không thiếu measure nào | `closure.py` chạy trên `Report/` đã giải nén |
| Tầng của 119 measure (cách phân loại của mình, xem §2.4) | **T0 12 · T1 23 · T2 61 · TXT 23** | `classify.py` → `closure_tiers.tsv` |
| Hàm dùng trong closure, đếm theo số lần xuất hiện | IF 142, ISBLANK 98, CALCULATE 83, INT 68, MOD 68, DATE 52, REMOVEFILTERS 40, MAX 39, YEAR/MONTH/ISFILTERED 34, SWITCH 32, VALUES 31, DIVIDE 30, BLANK 30, ABS 29, TREATAS 24, FILTER 22, FORMAT 21, SAMEPERIODLASTYEAR 17, KEEPFILTERS 16, SUMMARIZE 12, ALLSELECTED 9… | `closure.py` |
| `USERELATIONSHIP` | Chỉ có trong 1 measure, `Complaints_Sent`. Measure này **không** nằm trong closure của report | grep `measures.tsv` |
| Filter cấp report | `Dim_Date[year]` Not In {9999L}; `Dim_Client[client_region]` Not In {'Unknown'} | `report.json` filterConfig |
| Filter cấp trang | Chỉ D4 có 4 filter drillthrough (`Dim_Account[branch_city/branch_state_name]`, `Dim_District[city/state_name]`) | `page.json` |
| Filter cấp visual | 1/134 visual (`Fact_Transaction[trans_hour]` Not In {17}, ở heatmap D1) | `visual.json` |
| Dim_Date | 2.922 dòng, 2011-01-01 → 2018-12-31, **không có dòng year = 9999**; `DataCategory = Time` (đánh dấu là bảng ngày), khoá `full_date` | sqlite + `metadata.sqlitedb` |
| Dim_Client | 5.370 dòng; đúng 1 dòng `client_key = -1`, region 'Unknown' | sqlite |
| Toàn vẹn tham chiếu | **0 dòng fact mồ côi** ở mọi khoá ngày, client, account. Client −1 không có dòng fact nào | sqlite |
| ⇒ Filter cấp report **không loại dòng fact nào** | Mọi measure cộng dồn cho cùng giá trị dù có hay không có filter report | suy ra từ hai dòng trên |
| Văn hoá model | `Model.Culture = en-US` | `metadata.sqlitedb` |
| FormatString của measure | 88 rỗng, `#,0` 24, `$#,0` 21, `+0.0%;-0.0%;0.0%` 17, `0.0%` 7… DataType: 2 (chuỗi) 69, 6 (int) 24, 8 (double) 75 | `metadata.sqlitedb` |
| Cột tính toán được **lưu sẵn giá trị** trong VertiPaq | 7 cột Nhom6 giải mã ra có giá trị. Đã đối chiếu bằng SQL: `MonthIndex`, `month_start`, `trans_hour`, `branch_label`, `age_at_loan` khớp **0 sai lệch** trên toàn bộ dòng | sqlite |
| Nhóm 2 | `info` báo 48 cột tính toán, nhưng bảng người dùng chỉ có **6** (DimClient 1, FactTransaction 5). Phần còn lại nhiều khả năng thuộc bảng ngày tự động (SUY ĐOÁN) | `pbix-dump columns` |
| Xuất dữ liệu bằng `pbix-dump rows` | Fact_Transaction 1.056.320 dòng mất **155,9 s**; các bảng nhỏ khoảng 0,7–1,5 s. Giải nén ABF chỉ 0,73 s | đo `time` |
| Bẫy kiểu dữ liệu khi nạp CSV | Đoán kiểu theo text làm 737.192/1.056.320 giá trị `amount` (double) thành integer. Hệ quả: `Weighted Avg Term` bị chia nguyên ra **44** thay vì **44,311067** | sqlite `typeof` |

---

# PHẦN 1: ORACLE VÀ KIỂM THỬ

## 1.1 Năm loại oracle, xếp theo chi phí

| Mã | Oracle | Ai chạy | Phủ được gì | Chi phí |
|---|---|---|---|---|
| **O-PBI** | Golden từ DAX Query View của Power BI Desktop (VM) | **người dùng** | Mọi measure, mọi ngữ cảnh. Đây là chuẩn cuối cùng | Khoảng 1,5 giờ thao tác tay, chia 2 buổi |
| **O-SQL** | Tính lại bằng sqlite từ dữ liệu đã giải mã (differential) | agent, tự động | T0 + T1 (35/119) và khoảng 10 measure T2 viết SQL tay | Thấp |
| **O-CC** | Cột tính toán: so engine với giá trị Power BI đã lưu trong VertiPaq | agent, tự động | Ngữ cảnh dòng: `RELATED`, `IF`, `SWITCH`, `HOUR`, `DATE`, `YEAR`/`MONTH`/`DAY`, `&`, `VAR`, `BLANK` (7 cột Nhom6 + 6 cột Nhóm 2) | Rất thấp. **Đây là golden thật của Power BI, có sẵn miễn phí** |
| **O-PROP** | Test thuộc tính và metamorphic | agent | Bất biến ngữ nghĩa (§1.6) | Thấp |
| **O-TINY** | Bộ ngữ nghĩa bảng tí hon, kết quả kỳ vọng lấy từ tài liệu công khai | agent viết; người dùng xác nhận một lần trong VM | Từng hàm khó, các ca biên (BLANK, blank row, ties, cuối tháng) | Trung bình |

Định nghĩa "Xong" của Phase B (đề xuất làm rõ "119 measure khớp oracle"): mỗi measure trong closure phải khớp O-PBI ở **mọi** nhóm-theo golden có chứa nó (G0–G3, cộng G5/G6/PA nếu liên quan), theo quy tắc so khớp §1.7. O-SQL, O-CC, O-PROP, O-TINY chạy trong `swift test` (CI cục bộ) để bắt lỗi trước khi phải nhờ người dùng.

## 1.2 Giới hạn thực tế của DAX Query View (FACT, Microsoft Learn "DAX query view", cập nhật 2026-10-22)

- Tối đa **15 MB dữ liệu mỗi truy vấn**. Vượt ngưỡng thì dòng hiện tại được ghi nốt, các dòng sau bị bỏ.
- Tối đa **1.000.000 giá trị mỗi truy vấn**. Ví dụ của tài liệu: 20 cột thì tối đa 50.000 dòng.
- **Không thấy tài liệu nêu giới hạn số cột**. Ràng buộc thực tế là 1.000.000 giá trị và 15 MB.
- Editor có độ trễ rõ khi gõ ở **trên 500 dòng**. Vì vậy mỗi file golden nên dưới khoảng 100 dòng. Bản nháp hiện tại dài 28–67 dòng.
- Nút **Copy** chép **toàn bộ lưới thành bảng phân tách bằng tab, có tiêu đề**.
- Nhiều `EVALUATE` trong một tab cho ra nhiều kết quả, chuyển qua lại bằng dropdown **Result**. Mỗi kết quả phải Copy riêng.
- **Lưới kết quả không áp định dạng** (Currency, số nguyên có phân cách hàng nghìn…). Giá trị ở dạng thô, rất có lợi cho oracle.
- Lỗi hiện trong lưới, có nút copy, và mở đầu bằng vị trí: `Query (4, 23) The value for 'Sales 2' can't be determined…` nghĩa là dòng 4, ký tự 23.
- Các tab truy vấn được **lưu trong file `.pbix`** khi Save.
- "Define all measures" không dùng được khi model có hơn 500 measure (Nhom6 có 168, không ảnh hưởng).
- `SUMMARIZECOLUMNS` **bỏ nhóm khi mọi biểu thức tổng hợp đều BLANK**. `TOPN` có thể trả về nhiều hơn N dòng khi giá trị biên trùng nhau, và không bảo đảm thứ tự.

Áp vào Nhom6 (FACT, tính toán): ROW với 59 measure cho 59 giá trị. Theo năm, 59 × 8 dòng khoảng 470 giá trị. Theo tháng, 96 dòng × khoảng 10 measure khoảng 1.000 giá trị. Tất cả nằm rất xa giới hạn 1.000.000.

## 1.3 Gói oracle cho người dùng (O-PBI)

### Thiết kế truy vấn
- **Dạng rộng** (mỗi measure một cột), tách theo **bảng chủ** của measure thành 4 phần: `FT` 59, `LN` 48, `CR` 37, `DIM` 24 (gồm Account 6, Client 3, District 15). Lấy cả **168 measure**, không chỉ 119, vì thêm vào gần như không tốn gì.
- Lý do chia 4 phần (SUY ĐOÁN): nếu một measure lỗi thì cả EVALUATE hỏng, nên chia nhỏ để khoanh vùng. Trong khi đó 4 file vẫn ít thao tác.
- Không chọn dạng dài (`UNION` các dòng tên–giá trị): cột giá trị phải trộn số với chuỗi, bị ép về text và có nguy cơ mất độ chính xác. Dạng dài cũng làm truy vấn dài hơn nhiều, gặp ngưỡng trễ 500 dòng.
- Tên cột kết quả trùng tên measure (alias = tên measure), để bộ so khớp map 1-1.
- Measure được tham chiếu kèm tên bảng (`'Fact_Loan'[Loan Amount]`). Cách này hợp lệ trong DAX và tránh trùng tên.

Mẫu (đã sinh, xem `b/oracle/queries/G3-rf-year__DIM.dax`):
```dax
// BI Pro oracle G3-rf-year__DIM: 24 measure. Chạy → Copy → dán vào G3-rf-year__DIM.tsv
EVALUATE
SUMMARIZECOLUMNS (
	'Dim_Date'[year],
	KEEPFILTERS ( FILTER ( ALL ( 'Dim_Date'[year] ), NOT 'Dim_Date'[year] IN { 9999 } ) ),
	KEEPFILTERS ( FILTER ( ALL ( 'Dim_Client'[client_region] ), NOT 'Dim_Client'[client_region] IN { "Unknown" } ) ),
	"Total Accounts", 'Dim_Account'[Total Accounts],
	...
)
ORDER BY 'Dim_Date'[year]
```

### Danh sách truy vấn

| Nhóm | Nội dung | Số file | Kiểm tra cái gì |
|---|---|---|---|
| **G0-total** | `ROW(...)`, không filter | 4 | Ngữ cảnh rỗng, nhánh `ISFILTERED = FALSE`, các Δ ở năm cuối |
| **G1-year** | `SUMMARIZECOLUMNS('Dim_Date'[year], …)` | 4 | Lọc qua quan hệ Date → 3 fact; measure Dim không bị Date lọc (hằng theo năm); Δ YoY; `Complaints_Sent` theo năm gửi (quan hệ inactive) |
| **G2-region** | `SUMMARIZECOLUMNS('Dim_Client'[client_region], …)` | 4 | Lọc qua Dim_Client → 3 fact; nhóm 'Unknown' không có fact |
| **G3-rf-year** | Như G1, cộng 2 filter cấp report ở dạng `KEEPFILTERS(FILTER(ALL(..)))` | 4 | Cơ chế filter report. Kỳ vọng FACT-derived: **mọi measure cộng dồn bằng G1** vì filter không loại dòng fact nào |
| **G4-inactive** | `DEFINE MEASURE` các biến thể `USERELATIONSHIP(sent_date_key)` của Complaints, Avg_Days, Dispute_Rate, SLA_Timely_Rate, nhóm theo `Dim_Date[year]` | 1 | Quan hệ inactive. Giá trị SQL kỳ vọng đã có (§1.5) |
| **G5-month** | `SUMMARIZECOLUMNS('Dim_Date'[MonthIndex], 'Dim_Date'[year_month], …)` với Complaints, Complaints MA3, Trans Count, Neg Balance Trans, Neg Trans PM, Loan Amount | 1 | `HASONEVALUE`, `REMOVEFILTERS(Dim_Date)` + filter cửa sổ MonthIndex |
| **G6-visual** | 6 truy vấn theo ngữ cảnh visual: (a) `Dim_CRM_Issue[issue]` cho Complaints, Pareto Cum %, Pareto Color; (b) `submitted_via` cho Channel Share %; (c) `submitted_via × company_response` cho Response Share in Channel %; (d) `trans_type × operation` cho % Trans Amount; (e) `trans_hour × day_name` cho Trans Count (k), Peak Hour Font Color, Peak Hour Top10 Icon; (f) `Dim_District[city], [state_name]` và `Dim_Account[branch_city]` cho các measure D4 *, NPL Avg (Selected), Branch NPL Color, Branch Title/Subtitle, Top Branches Text | 6 | `ALLSELECTED`, `SELECTEDVALUE`, `ISFILTERED` theo từng nhánh, `TREATAS(SUMMARIZE())`, `TOPN` + `CONCATENATEX` |
| **PA** | Performance Analyzer: Start recording → Refresh visuals → **Copy query** của khoảng 8 visual (2 visual/trang: card KPI có Δ, matrix/heatmap, Pareto, bảng D4) rồi Run trong DAX Query View → Copy kết quả | 8 cặp (query + kết quả) | **Truy vấn đúng như visual gửi đi**, kể cả cách Power BI mã hoá filter report/trang/visual. Phase C dùng lại làm đặc tả |
| **N2** (tuỳ chọn) | G0 + G1 cho 23 measure của Nhóm 2 | 2 | Kiểm tra engine trên model thứ hai |

Tổng cộng: **24 file lõi** (G0–G6) + 8 cặp PA (+2 nếu làm N2).
- **Gói tối thiểu** nếu người dùng ít thời gian: G0 + G1 + G3 = 12 file.

### Quy ước tên file golden
- Thư mục người dùng ghi vào, qua thư mục chia sẻ Parallels như Phase W: `~/Downloads/bipro-golden/nhom6/`. Lead chép vào repo `Tests/Golden/nhom6/`. Agent không ghi vào `~/Downloads`.
- Mỗi truy vấn có cặp file cùng tên gốc: `<nhóm>__<phần>.dax` (đầu vào, do mình sinh) và `<nhóm>__<phần>.tsv` (Copy → dán vào Notepad → Save As, UTF-8). Ví dụ: `G1-year__FT.dax`, `G1-year__FT.tsv`, `G6-visual__e-heatmap.tsv`, `PA__d1-card-tienvao.dax`, `PA__d1-card-tienvao.tsv`.
- File `manifest.tsv`, mỗi file một dòng: `file`, `sha1_dax`, `ngày`, `phiên bản Power BI (Help → About)`, `Windows regional format`, `số dòng`, `ghi chú lỗi`. Lỗi thì dán thông báo lỗi vào `<tên>.error.txt` thay cho `.tsv`.
- **SUY ĐOÁN, cần quan sát O2**: nếu Windows đặt locale vi-VN thì Copy có thể ra dấu phẩy thập phân. Bộ đọc golden phải ghi nhận locale theo manifest.

### Các bước cho người dùng (mỗi file)
1. Mở `.dax` trên Mac (thư mục chia sẻ) → Ctrl+A, Ctrl+C.
2. Power BI → DAX Query View → tab mới (+) → dán → Run.
3. Copy (trên lưới) → Notepad → dán → Save As `<tên>.tsv` (UTF-8).

Ước tính khoảng 1,5–2 phút/file (SUY ĐOÁN; Fact_Transaction 1 triệu dòng, các truy vấn theo năm có thể chạy vài giây).
- **Buổi 1 (golden):** 24 file khoảng 40–50 phút. Gói tối thiểu 12 file khoảng 20–25 phút.
- **Buổi 2 (quan sát O1–O18 + PA 8 visual + bộ tí hon):** khoảng 45–60 phút.

### Cách giảm thao tác (đề xuất)
1. **Một tab, nhiều EVALUATE**: gộp 4 phần của cùng nhóm vào một file → chỉ dán và Run một lần, rồi chuyển dropdown Result 1..4 và Copy từng kết quả. Cần quan sát O5 trước: một EVALUATE lỗi thì các EVALUATE còn lại có vẫn chạy không.
2. **Nhúng sẵn tab truy vấn vào `.pbix`**: tab được lưu trong file (FACT), nên nếu biết nơi lưu thì BI Pro (writer Phase W) có thể ghi sẵn 24 tab vào một bản sao Nhom6. Người dùng chỉ việc mở, Run và Copy. Hiện **chưa biết nơi lưu**: Nhom6 không có part ZIP nào, cũng không có annotation nào tên giống DAX query (FACT). Cần quan sát O7.
3. DAX Studio (xuất CSV hàng loạt) chỉ dùng **nếu người dùng tự quyết định cài** trong VM. Mặc định không dùng.

## 1.4 Chọn nhóm-theo cho golden (lý do)

- **Tổng (G0)**: ngữ cảnh rỗng là ca cơ sở.
  - Measure kiểu `D4 *` rơi vào nhánh mặc định `[Trans Count]`.
  - `Δ` lấy `endKey = MAX(date_key)` = 20181231 (FT) nên so 2018 với 2017.
- **Năm (G1)**: Dim_Date lọc cả 3 fact qua 3 quan hệ active. `Total_Clients` và các measure Dim_Account **không đổi theo năm**, vì không có đường lọc từ Date sang Dim (single direction). Đây là ca dễ sai nếu engine lan filter sai chiều.
- **Quan hệ inactive (G1 qua `Complaints_Sent`, G4)**: FACT có **12.819/23.419** khiếu nại có `sent_date_key ≠ received_date_key`, nên khác biệt đủ lớn để thấy (ví dụ năm 2011: 164 theo ngày nhận, 157 theo ngày gửi).
- **Filter cấp report (G3)**: visual trong report luôn chịu filter này. Kỳ vọng số học trùng G1 (FACT-derived, §0), nhưng test được 2 điều:
  - (a) cú pháp và cơ chế filter;
  - (b) `ISFILTERED(Dim_Client[client_region])` = TRUE. Hiện không measure nào trong closure hỏi cột này (FACT, grep), nên không làm đổi số.
- **Vùng (G2)**: chiều thứ hai đi qua Dim_Client, có thành viên 'Unknown' không có fact. Kiểm tra `SUMMARIZECOLUMNS` bỏ nhóm toàn BLANK; nhóm Unknown có thể bị bỏ hoặc còn lại nếu có measure hằng (TXT màu). Đây là ca tốt để kiểm tra.
- **Tháng (G5)** và **visual (G6/PA)**: các measure T2 chỉ có nghĩa khi một cột cụ thể đang được nhóm theo (`HASONEVALUE`, `SELECTEDVALUE`, `ALLSELECTED`).

## 1.5 Oracle tự động bằng sqlite (O-SQL)

### Cách làm (đề xuất)
- Không xuất CSV qua `pbix-dump rows`: chậm (155,9 s cho FT) và mất kiểu.
- Viết test Swift dùng **SQLite3 C API**. PBIXKit đã dùng sẵn qua `sqlite3_deserialize`, nên không cần python trong test.
- Các bước: nạp `DecodedColumn` vào bảng in-memory **theo `dataType` trong metadata** (int64 → INTEGER, double → REAL, dateTime → TEXT ISO, string → TEXT, blank → NULL), chạy SQL, rồi so với kết quả DAX engine.
- Có thể thêm lệnh CLI `pbix-dump export-sqlite <file> <out.db>` để debug tay.
- Bản thử bằng python stdlib (scratchpad) nạp 11 bảng mất 5,1 s. Bộ truy vấn FT theo 3 nhóm chạy 4,7 s.

### Tầng (định nghĩa của mình; cần thống nhất với tầng T0/T1 của các agent khác nếu khác)
- **T0**: một phép tổng hợp (`SUM`/`COUNTROWS`/`DISTINCTCOUNT`/`AVERAGE`), có thể bọc `CALCULATE(…, KEEPFILTERS(cột op hằng))`, hoặc là hằng số. Có **12** measure: Total_Clients, Avg_Days_To_Company, Complaints, Pareto 80% Line, SLA Target, Loan Amount, Loan Count, Monthly Payment, Active Accounts, Overdraft Accounts, Trans Amount, Trans Count.
- **T1**: kết hợp T0 bằng `DIVIDE`/số học/`IF`/`COALESCE`/`KEEPFILTERS` trên cột dim. Có **23** measure, gồm: Net_Cashflow, Total_Credit_Inflow/Debit_Outflow, Avg Trans Value, Overdraft Rate, Neg Balance Trans, Sanction Count/Interest, Trans Count (k), Trans per Client, Dispute_Rate, SLA_Timely_Rate, Relief Rate, Complaints per 1000 Clients, Bad Debt Loans, Bad_Debt_Principal, Bad_Debt_Ratio_Count/Value, Active_Monthly_Payment, Branch Loan Amount/Count, Timely Color, NPL Group Color.
- ⇒ **35/119 (29%) đối chiếu SQL trực tiếp.**
- **T2 viết được SQL tay** (khoảng 10): Weighted Avg Term, Outstanding (est.) và Branch Outstanding (`DATEDIFF MONTH` = số ranh giới tháng), % Trans Amount, Channel Share %, Response Share in Channel % (khi không có filter ngoài), Complaints MA3, Neg Trans PM (cửa sổ MonthIndex), NPL Avg (Selected), các measure D4 * ở ngữ cảnh không filter. Tổng là khoảng **45/119 (38%)**.
- **Chỉ có O-PBI mới kiểm được**: 13 measure Δ (SAMEPERIODLASTYEAR có ngữ nghĩa "mở rộng cuối tháng", §1.8), 13 Δ Color, 13 Δ Label (`FORMAT`, chuỗi), Pareto, Peak Hour, Top Branches Text, Branch Title, Avg_Account_Balance (`AVERAGEX` + `MAX` theo timestamp).

### Kết quả O-SQL đã tính (FACT trên dữ liệu đã giải mã; chưa đối chiếu với Power BI)

| Nhóm | Trans Amount | Trans Count | Active Accounts | Overdraft Rate | Credit_Inflow | Debit_Outflow | Net_Cashflow | Trans per Client |
|---|---|---|---|---|---|---|---|---|
| TOTAL | 6257793560.3 | 1056320 | 4500 | 0.064 | 3227472424.5 | 3030321135.8 | 197151288.7 | 234.7378 |
| 2013 | 204308528.7 | 28205 | 1139 | 0.005268 | 120442237.4 | 83866291.3 | 36575946.1 | 24.7629 |
| 2018 | 1894783357.3 | 322277 | 4492 | 0.036064 | 960964282.2 | 933819075.1 | 27145207.1 | 71.7447 |
| Northeast | 3333676560.2 | 554718 | 2342 | 0.067464 | 1718730244.5 | 1614946315.7 | 103783928.8 | 236.8565 |

| Nhóm | Complaints | Avg_Days_To_Company | Dispute_Rate | SLA_Timely_Rate | Relief Rate |
|---|---|---|---|---|---|
| TOTAL | 23419 | 2.624704 | 0.198688 | 0.984158 | 0.339895 |
| năm nhận 2011 | 164 | 8.975309 | 0.228188 | 0.835366 | 0.469512 |
| **năm gửi 2011** (USERELATIONSHIP) | **157** | 1.703226 | 0.232394 | 0.834395 | 0.477707 |
| năm nhận 2017 / năm gửi 2017 | 1377 / 1387 | 1.312999 / 1.553713 | | | |

| Nhóm | Loan Amount | Loan Count | Bad_Debt_Ratio_Count | Bad_Debt_Ratio_Value | Weighted Avg Term |
|---|---|---|---|---|---|
| TOTAL | 103261740 | 682 | 0.111437 | 0.15088 | **44.311067** (bản nạp sai kiểu cho ra 44) |
| 2013 | 2619276 | 20 | 0.2 | 0.309736 | |
| 2013 Active_Monthly_Payment | **BLANK** (không có khoản vay active) | | | | |

Khác: Total_Clients = 5369; Total Accounts = 4500; Card Accounts = 892; Cards Issued = 892; Accounts with Loan = 682.

Bảng đầy đủ nằm ở `b/sql/oracle_ft.tsv` và `b/sql/oracle_crm_loan.tsv`.

### Bẫy khi dịch DAX sang SQL (FACT theo tài liệu; một phần đã gặp thật)
1. **Kiểu dữ liệu** phải lấy từ metadata. Nếu không, chia nguyên trong sqlite làm sai (đã gặp, xem bảng trên).
2. `DISTINCTCOUNT` **đếm cả BLANK**, còn `COUNT(DISTINCT)` của SQL bỏ NULL. Cần cộng thêm `MAX(x IS NULL)`. Nguồn: MS Learn DISTINCTCOUNT.
3. `SUM`/`COUNTROWS`/`DISTINCTCOUNT` trên tập rỗng trả **BLANK**, không phải 0. Nguồn: MS Learn DISTINCTCOUNT, COUNTROWS trong cheat sheet. Phía SQL phải giữ NULL, không `COALESCE`.
4. `DIVIDE(x, 0)` → BLANK. `DIVIDE(5,0,1)` → 1. Toán tử `/`: `5/BLANK` = Infinity, `0/BLANK` = NaN, `BLANK/BLANK` = BLANK. Nguồn: MS Learn DIVIDE và Data types.
5. So sánh: `BLANK = 0` là TRUE, `==` thì không. `[days_to_company] >= 0` sẽ giữ cả blank. Với Nhom6 thì FACT: `days_to_company` không có null, có 192 giá trị âm bị loại.
6. `KEEPFILTERS(cột op hằng)` tương đương `AND` với filter ngoài. Không có KEEPFILTERS thì filter CALCULATE **ghi đè** filter ngoài trên cùng cột. Nguồn: MS Learn KEEPFILTERS. Trong SQL, KEEPFILTERS = `CASE WHEN` cộng `WHERE` ngoài.
7. Measure của Dim **không bị fact lọc ngược** (single direction). SQL không được join Dim_Client vào fact khi tính `Total_Clients` theo năm.
8. Blank row khi vi phạm toàn vẹn tham chiếu (MS Learn VALUES). Nhom6 có 0 dòng mồ côi nên **không kiểm được ở đây**, phải dùng O-TINY.
9. `is_disputed` có giá trị −1 (1.002 dòng, "Chưa rõ"), không phải NULL. Biểu thức `IN {0,1}` loại các dòng này. FACT, sqlite.
10. Tổng double phụ thuộc thứ tự cộng (MS Learn Data types: "sum … can return unexpected results"). Không so khớp tuyệt đối, xem §1.7.

## 1.6 Test thuộc tính và metamorphic (O-PROP)

Mỗi thuộc tính chạy trên Nhom6 thật và trên dữ liệu ngẫu nhiên nhỏ (có seed cố định).

1. **Tổng = ALL**: `CALCULATE([m], ALL(Dim_Date))` ở mọi dòng của nhóm theo năm bằng `[m]` ở G0, áp cho mọi measure không dùng `ALLSELECTED`/`ISFILTERED`.
2. **Cộng được**: với T0 dạng SUM/COUNT (Trans Amount, Trans Count, Complaints, Loan Amount/Count, Monthly Payment), tổng các nhóm năm (và vùng) bằng tổng chung.
   - Ví dụ FACT: tổng 6 năm của Trans Count = 28205+91628+133022+196779+284409+322277 = 1.056.320.
3. **Không cộng được**: tổng các nhóm của DISTINCTCOUNT **lớn hơn hoặc bằng** tổng chung (Active Accounts: 1139+…+4492 ≥ 4500), và tỷ lệ không cộng được.
4. **Filter report trung lập** (riêng Nhom6): G3 = G1 với mọi measure trong closure (§1.4).
5. **KEEPFILTERS so với ghi đè**: nhóm theo `Dim_Trans_Type[trans_type]`. Với KEEPFILTERS thì `Total_Credit_Inflow` ở dòng Debit là **BLANK**. Thay bằng `CALCULATE(…, Dim_Trans_Type[trans_type]="Credit")` thì mọi dòng có cùng giá trị 3227472424.5.
6. **DIVIDE**: `DIVIDE(x,0)` = BLANK; `DIVIDE(BLANK,y)` = BLANK; `DIVIDE(x,0,1)` = 1. Cột tỷ lệ không bao giờ là ±Inf hay NaN.
7. **BLANK lan truyền**: `[Bad Debt Loans] + 0` ra 0 chứ không BLANK (Bad_Debt_Ratio_Count dùng mẹo này). `IF(NOT ISBLANK([Loan Count]), …)` = BLANK khi không có khoản vay.
8. **SUMMARIZECOLUMNS bỏ nhóm toàn BLANK**: số dòng kết quả bằng số nhóm có ít nhất một measure khác BLANK.
9. **Đổi tên/thứ tự cột group-by** (metamorphic) không đổi giá trị. Thêm `ORDER BY` không đổi tập dòng.
10. **DEFINE MEASURE ghi đè**: định nghĩa lại `[Trans Amount]` = `SUM(amount)*2` thì Net_Cashflow nhân đôi. Kiểm tra measure phụ thuộc dùng định nghĩa trong query (MS Learn DAX queries: "Measure definitions for a query override model measures").
11. **USERELATIONSHIP**: nhóm theo năm, tổng `Complaints_Sent` qua các năm = 23.419 = tổng `Complaints`.
12. **Cột tính toán (O-CC)**: engine tính lại 13 cột, phải khớp từng dòng với giá trị lưu sẵn.

## 1.7 Quy tắc so khớp (đề xuất; một số chỗ chờ O1/O2)

| Kiểu | Quy tắc |
|---|---|
| Số nguyên (int64, đếm) | Khớp tuyệt đối |
| Số thực | `abs(a−b) ≤ 1e-9 · max(1, abs(a), abs(b))`. Nếu O2 cho thấy Copy làm tròn (ví dụ 15 chữ số có nghĩa) thì nới theo số chữ số thực tế. Không so tuyệt đối vì tổng double phụ thuộc thứ tự cộng (MS Learn Data types) |
| Currency (Fixed decimal) | 4 chữ số thập phân, khớp tuyệt đối sau khi làm tròn 4 chữ số |
| BLANK | Ô rỗng trong TSV. **BLANK ≠ 0**. Ô rỗng không phân biệt được BLANK với chuỗi `""`; khi cần, thêm cột thăm dò `ISBLANK([m])` vào truy vấn |
| Infinity / NaN | Theo cách Power BI hiển thị (O1). Engine phải tạo được hai giá trị này từ toán tử `/` |
| Chuỗi | Khớp tuyệt đối, phân biệt hoa thường ở đầu ra (engine Power BI so sánh không phân biệt hoa thường, nhưng giữ cách viết lần đầu gặp; MS Learn Data types). Chuẩn hoá xuống dòng `\r\n` thành `\n` |
| Chuỗi từ `FORMAT` (23 measure TXT) | Khớp tuyệt đối theo văn hoá model `en-US`. Cần O15 xác nhận FORMAT dùng culture nào |
| Ngày/giờ | Chuẩn hoá về ISO-8601. Thời gian có độ phân giải 1/300 s (MS Learn), nên cho sai lệch tối đa 3,34 ms |
| Boolean | `True`/`False` (O1) |
| Thứ tự dòng | Không có `ORDER BY`: so như multiset, khoá là các cột group-by. Có `ORDER BY`: so theo trình tự, còn các dòng trùng khoá sắp xếp thì so như multiset |
| Thứ tự cột | So theo tên cột. Thiếu hoặc thừa cột tính là lỗi |
| Định dạng hiển thị | Bỏ qua, vì lưới Power BI không áp FormatString (FACT) |
| Lỗi | Golden `.error.txt` khớp khi engine cũng báo lỗi cùng **loại** và cùng **vị trí (dòng, cột)**. Không yêu cầu khớp văn bản |

## 1.8 Bộ ngữ nghĩa tí hon (O-TINY)

**Fixture 1 (lấy nguyên từ MS Learn "DAX query view", mục SQL to DAX cheat sheet):** bảng `Sales` 12 dòng (SalesKey 1..12, ProductKey 101–104, Quantity, SalesAmount có một giá trị null ở SalesKey 6). Tài liệu cho sẵn script TMDL `createOrReplace`, kèm kết quả.

| # | Truy vấn | Kỳ vọng | Nguồn |
|---|---|---|---|
| S1 | `EVALUATE ROW("SalesRows", COALESCE(COUNTROWS('Sales'),0))` | 12 | MS Learn DAX query view ("row-count query returns 12") |
| S2 | `EVALUATE ROW("TotalSales", SUM('Sales'[SalesAmount]))` | 3650 | idem ("total-sales query returns 3,650") |
| S3 | `EVALUATE FILTER('Sales', ISBLANK('Sales'[SalesAmount]))` | 1 dòng, SalesKey 6 | idem |
| S4 | `SUMMARIZECOLUMNS('Sales'[ProductKey], "T", SUM(..))` | 101→1200, 102→1500, 103→800, 104→150 | tính tay từ dữ liệu của tài liệu |
| S5 | `TOPN(8, 'Sales', 'Sales'[SalesAmount], DESC)` | 11 dòng (giá trị biên 50 trùng ở 4 dòng) | MS Learn: "TOPN can return more than the requested number of rows when the boundary values tie" (số dòng là SUY ĐOÁN từ quy tắc) |
| S6 | `FILTER(SUMMARIZECOLUMNS(...), [TotalSales] > 1000)` | 102 (1500), 101 (1200) | cheat sheet, mẫu HAVING |
| S7 | `DISTINCTCOUNT('Sales'[SalesAmount])` và `DISTINCTCOUNTNOBLANK` | 9 và 8 (có BLANK) | MS Learn DISTINCTCOUNT: "counts the BLANK value" |

**Fixture 2: biểu thức thuần, không cần bảng** (`EVALUATE ROW(...)`):

| # | Biểu thức | Kỳ vọng | Nguồn |
|---|---|---|---|
| B1–B6 | `BLANK()+BLANK()`, `BLANK()+5`, `BLANK()*5`, `5/BLANK()`, `0/BLANK()`, `BLANK()/BLANK()` | BLANK, 5, BLANK, Infinity, NaN, BLANK | MS Learn "Data types", bảng Blanks |
| B7–B12 | `FALSE()\|\|BLANK()`, `FALSE()&&BLANK()`, `TRUE()\|\|BLANK()`, `TRUE()&&BLANK()`, `BLANK()\|\|BLANK()`, `BLANK()&&BLANK()` | FALSE, FALSE, TRUE, FALSE, BLANK, BLANK | idem |
| D1–D3 | `DIVIDE(5,2)`, `DIVIDE(5,0)`, `DIVIDE(5,0,1)` | 2.5, BLANK, 1 | MS Learn DIVIDE |
| C1–C2 | `BLANK() = 0`, `BLANK() == 0` | TRUE, FALSE | MS Learn DAX operators |
| C3 | `IF("12">12, 1, 0)` | **Tài liệu mâu thuẫn**: trang Data types nói trả "true"; trang DAX operators nói so sánh Text với Integer báo lỗi. Đưa vào quan sát O17 | hai trang MS Learn |
| C4 | `22 & ""` / `"22"+22` / `12 & 34` / `TRUE()+1` | "22" / 44 / "1234" / 2 | MS Learn Data types |
| P1–P2 | `-2^2`, `(-2)^2` | −4, 4 | MS Learn DAX operators |

**Fixture 3: Geo tí hon cho KEEPFILTERS** (dựng lại mẫu MS Learn KEEPFILTERS với số của mình). Bảng Geo(State: WA, OR, BC), Sales(State, Amt: 10, 20, 40).

| Biểu thức | Kỳ vọng |
|---|---|
| WA | 10 |
| WA+OR | 30 |
| WA+BC | 50 |
| `CALCULATE(CALCULATE(m, WA\|\|OR), WA\|\|BC)` | 30 (trong ghi đè ngoài) |
| `CALCULATE(CALCULATE(m, KEEPFILTERS(WA\|\|OR)), WA\|\|BC)` | 10 (giao) |

Cách suy ra kỳ vọng: áp đúng quy tắc của trang KEEPFILTERS. Trên AdventureWorks, tài liệu cho WA = 2.467.248,34 ở cả hai ca "WA" và "!!".

**Fixture 4: quan hệ, blank row, USERELATIONSHIP.** Bảng Date(2023-01-01..2024-12-31, đánh dấu bảng ngày), Orders(OrderDate active, ShipDate inactive, Amt), Customer(1, 2) và Orders có một CustKey = 9 không có trong Customer.

| Biểu thức | Kỳ vọng | Nguồn |
|---|---|---|
| `VALUES(Customer[CustKey])` khi không filter | {1, 2, BLANK} | MS Learn VALUES |
| `DISTINCT(Customer[CustKey])` | {1, 2} | idem |
| Nhóm theo `Customer[CustKey]` | Có dòng BLANK mang Amt của khách 9 | idem: "matched to this unknown member" |
| `COUNTROWS(Customer)` nhóm theo `Orders[Amt]` | Không bị lọc (single direction): luôn 2 | quy tắc lan filter, MS Learn cheat sheet "filters propagate through active relationships according to their configured filter direction" |
| `CALCULATE(SUM(Amt), USERELATIONSHIP(Orders[ShipDate], Date[Date]))` theo năm | Tổng theo năm giao hàng | MS Learn USERELATIONSHIP (SUY ĐOÁN về số cụ thể; tự tính từ dữ liệu fixture) |

**Fixture 5: SAMEPERIODLASTYEAR** (Date 2007–2009). Nguồn: MS Learn SAMEPERIODLASTYEAR.

| Chọn | Kỳ vọng |
|---|---|
| {2009-02-27, 2009-02-28} | {2008-02-27, 28, **29**}: ngữ nghĩa "mở rộng" vì chọn hai ngày cuối tháng |
| {2009-02-27} | {2008-02-27} |
| {2008-02-29} (classic) | {2007-02-28} |
| Bằng `DATEADD(dates,-1,YEAR)` | Tương đương |

Liên hệ Nhom6 (FACT): các measure Δ lấy `curDates` từ 01/01 đến `endDt` = ngày lớn nhất có fact. Nếu `endDt` rơi vào cuối tháng thì cú mở rộng này đổi giá trị năm trước.

**Fixture 6: ALLSELECTED, ISFILTERED, SELECTEDVALUE, HASONEVALUE trong SUMMARIZECOLUMNS.** Kỳ vọng lấy từ mô tả của SQLBI/dax.guide (đọc để hiểu). Đánh dấu SUY ĐOÁN và **bắt buộc người dùng xác nhận trong VM**.

**Xác nhận O-TINY trong Power BI (1 lần, khoảng 15 phút):** người dùng tạo file mới → TMDL view → dán `tiny-model.tmdl` (Sales của MS Learn cộng Geo, Date, Orders, Customer) → Apply → Refresh → DAX Query View → chạy `tiny-suite.dax` → Copy từng kết quả. Có thể dùng chung bộ fixture này cho test M/TMDL về sau.

---

# PHẦN 2: DAX QUERY VIEW (UI)

## 2.1 Hiện trạng code (FACT, đọc `QueryWorkspaces.swift` 150 dòng, `CodeEditor.swift` 163 dòng, `DataPane.swift`, `Ribbon.swift`, `DocumentState.swift`)

- **Tab**: thêm và đóng được. Chưa có biểu tượng trạng thái, chưa đổi tên được, chưa có dấu "đã sửa". Model là `DAXQueryTab { id, title, text }`.
- **Editor**: `NSTextView`, tô màu bằng regex (tô lại toàn văn bản mỗi lần gõ), có thước số dòng. Chưa hiện Ln/Col, chưa gạch chân lỗi, chưa tự hoàn thành, chưa Find.
- **Toolbar**: "Chạy" và "Định dạng" bị disable. "Chú thích //" dùng được, chuyển đổi trên **toàn văn bản** chứ không theo dòng đang chọn như Power BI.
- **"Định nghĩa và đánh giá"** (`DAXSnippets.defineAndEvaluate`):
  - Ghi đè tab **hiện tại** và sinh `EVALUATE { ref }`.
  - Power BI (FACT, MS Learn) tạo quick query trong **tab mới và tự chạy**. Quick query "Evaluate" dùng `SUMMARIZECOLUMNS`. "Define…" chèn mô tả `///`. Có thêm "Define with references and evaluate".
- **Kết quả**: chỉ có placeholder. **Status bar** ghi "Truy vấn i / n".
- **Lỗi nhỏ phát hiện được**: truy vấn mẫu `DAXQueryTab.starter` tham chiếu `[Transaction Count]`, **measure này không tồn tại trong Nhom6** (0 kết quả trong `measures.tsv`; tên đúng là `Trans Count`). Khi chạy được, truy vấn mẫu sẽ báo lỗi.
- Ribbon: "Chạy", "Định dạng" ghi `phase: "Phase B"`; "Cập nhật mô hình" ghi `phase: "Phase E"`.

## 2.2 Thiết kế `dax_query_view` (FACT, screen.png và code.html) so với Power BI (FACT, MS Learn)

| Thành phần | Thiết kế | Power BI | Đề xuất |
|---|---|---|---|
| Ô AI "Show sales…" + nút Generate | có | Copilot | **Bỏ** (quyết định của người dùng) |
| Run, Cancel | Run xanh, Cancel riêng | Run tự đổi thành Cancel khi đang chạy | Run ⌘↵, Cancel ⌘. |
| Format query | có | Shift+Alt+F: hàm viết HOA, thụt lề tab, thêm dòng | ⇧⌥F, theo spec O9 |
| Comment // | có | Ctrl+/ bật tắt **theo dòng chứa con trỏ hoặc vùng chọn** | ⌘/, sửa lại theo dòng |
| Update model | có | Nút "Update model with changes" + CodeLens | Disable, ghi Phase E |
| Dòng thông tin editor | `DAX • Tabular Model Script • UTF-8 · Ln 7, Col 25 · Spaces: 2 · ● Valid Syntax` | không mô tả | Ln/Col từ con trỏ; "Cú pháp hợp lệ" hoặc "n lỗi" lấy từ parser (chạy sau 300 ms ngừng gõ) |
| Tab | "Query 1 •" (chấm = chưa lưu), × | Đổi tên/xoá được; icon: không có / ✓ xanh / ✗ đỏ / ■ huỷ / đồng hồ đang chạy; chạy nền khi chuyển tab | Làm đủ |
| Kết quả | "RESULTS (1)", "Result 1 of 1", pill "Success · 12 rows · 0.24 s", Copy, Export CSV, ghim, cột #, sort ↓, dropdown lọc | Dropdown Result khi nhiều EVALUATE; Copy = TSV có tiêu đề; sort và lọc trên header (chỉ áp lên dữ liệu đã trả về, có thể đã bị cắt) | Làm đủ; thêm Export CSV |
| Định dạng số trong lưới | `$1,842,500.00`, `28.4%` | **Không áp định dạng** | Mặc định **thô** như Power BI (Copy và oracle khớp nhau); nút bật "Áp định dạng" là P2 |
| Lỗi | (không vẽ) | Hiện trong lưới: `Query (dòng, cột) thông điệp` + nút copy | Giữ tiền tố `Query (l, c)`; bấm vào thì nhảy tới vị trí; gạch chân đỏ trong editor |
| Data pane | Tìm kiếm ⌘F, bảng kèm số dòng (1.2M), folder `_Measures`, menu Quick queries ▸ (Evaluate / Define and evaluate / Define with references and evaluate), Rename F2, Hide, Delete | Quick queries cho bảng (Top 100 rows, Column statistics, Define all measures in this table), cột (Data preview, Column statistics), measure (3 mục), mục chung (Define all measures, Define new measure) | Phase B: các quick query đọc dữ liệu. Rename/Hide/Delete disable (Phase E) |
| Thẻ "DAX Quick Guide" | có | không | P2, nội dung tĩnh |
| Status bar | "VertiPaq Engine: Idle (1,248,390 rows loaded)" · "Direct execution" · zoom | Trạng thái truy vấn ở status bar | "Engine: Rảnh · 1.056.320 dòng FT…", thời gian, số dòng |
| Header model | "Model: Contoso Retail DW · 4.8 GB · DirectQuery / Import Hybrid" | — | Đã có "Mô hình: file · Import"; thêm kích thước |
| Hover measure | — | Hiện công thức, tên, mô tả | P1 |
| Light bulb Define / Define with references | — | Có (chỉ khi tab chưa có DEFINE) | P2 |
| IntelliSense | — | Gợi ý; Enter/Tab chấp nhận; Shift+Enter xuống dòng không chấp nhận; Esc đóng | P0 cho bảng/cột/measure/hàm/từ khoá |
| Find/Replace, Command palette | — | Ctrl+F / Ctrl+H / Ctrl+Alt+P | ⌘F / ⌥⌘F; bảng lệnh là P2 |
| Chạy phần đang chọn | — | Run chạy vùng chọn nếu có | P0 |
| Giới hạn | — | 1.000.000 giá trị, 15 MB, cắt và vẫn hiện | Áp cùng giới hạn mặc định + thông báo "Đã cắt ở N dòng" (chữ cụ thể theo O4) |
| Lưu tab vào file | — | Có | Phase B: giữ trong `DocumentState`; đọc tab đã lưu khi mở file (sau O7); ghi lại khi lưu thuộc Phase D |

## 2.3 Yêu cầu UI còn thiếu cho Phase B (ưu tiên)

**P0 (bắt buộc để Phase B xong):**
1. **Chạy truy vấn**: Run / ⌘↵ / chạy vùng chọn. Chạy async trên hàng đợi nền; **Cancel** được (token huỷ truyền vào evaluator). Mỗi tab giữ trạng thái `idle | running | ok | error | cancelled` kèm kết quả lần chạy gần nhất.
2. **Lưới kết quả** dùng `NSTableView` ảo hoá: cột `#`, header đúng tên cột của truy vấn, căn phải cho số, font mono (DESIGN.md `data-mono`), dòng cao 24 px (DESIGN.md), sort khi bấm header. Giá trị hiển thị **thô** theo đúng quy tắc của O1 (BLANK, số, ngày).
3. **Nhiều EVALUATE** → "Kết quả i / n" + dropdown.
4. **Copy** = TSV có tiêu đề, giống hệt định dạng Copy của Power BI (theo O2). **Export CSV**.
5. **Pill trạng thái**: "Thành công · N dòng · 0,24 s" hoặc "Lỗi". Status bar có thời gian chạy và số dòng.
6. **Lỗi có vị trí**: hiện trong vùng kết quả theo dạng `Query (dòng, cột) thông điệp`, nút copy; bấm vào thì đưa con trỏ tới vị trí; gạch chân trong editor. Lỗi phân tích cú pháp hiện ngay khi gõ (debounce). Cách đếm cột (tab tính 1 hay 4) theo O3.
7. **Tab**: biểu tượng trạng thái, đổi tên (nhấp đúp), dấu chưa lưu, chạy nền khi chuyển tab.
8. **Quick queries** từ Data pane: measure (Evaluate / Define and evaluate / Define with references and evaluate), bảng (Show top 100 rows), cột (Show data preview). Mở **tab mới và tự chạy**, sinh đúng văn bản như Power BI (O8). Sửa `DAXSnippets` cho đúng (đang dùng `{ }` và ghi đè tab hiện tại).
9. **Tự hoàn thành**: `'`/tên bảng → bảng; `Bảng[` → cột và measure của bảng; `[` → measure; tên hàm (khoảng 40 hàm engine hỗ trợ, đánh dấu hàm chưa hỗ trợ); từ khoá. Có tooltip chữ ký hàm.
10. Sửa truy vấn mẫu: `[Transaction Count]` → measure có thật (ví dụ `[Trans Count]`), hoặc sinh từ measure đầu tiên của model.
11. Bỏ hẳn phần AI/Copilot.

**P1:**
- **Format query** (⇧⌥F) theo spec O9, chạy trên token stream của lexer engine (không dùng regex).
- Hover measure hiện công thức.
- Comment theo dòng.
- Find/Replace.
- Chuyển tô màu sang token của lexer engine, chỉ tô vùng vừa sửa (tránh lag như Power BI ở hơn 500 dòng).
- Lọc trên header lưới.
- Ln/Col + "Cú pháp hợp lệ".
- Thông báo cắt kết quả.

**P2:** light bulb Define, command palette, thẻ Quick Guide, bật "Áp định dạng", ghim kết quả, Column statistics, Define all measures.

## 2.4 Danh sách quan sát cần người dùng làm trong Power BI Desktop (VM)

Mỗi mục ghi rõ thao tác và file bằng chứng. Ảnh chụp và file bỏ vào `~/Downloads/bipro-golden/observe/` (lead chép vào `docs/phase-b-evidence/`). Mình chuẩn bị sẵn file `observe.dax`.

| Mã | Quan sát | Thao tác | Bằng chứng |
|---|---|---|---|
| **O1** | **Định dạng kết quả trong lưới** | Chạy `EVALUATE ROW("int", 1, "dbl", 1/3, "big", 6257793560.3, "neg", -0.000001, "cur", CURRENCY(1.23456), "date", DATE(2018,12,31), "dt", NOW()*0+DATE(2018,12,31)+TIME(16,3,36), "bool", TRUE(), "blank", BLANK(), "empty", "", "vn", "Không có số liệu ▲", "inf", 5/BLANK(), "nan", 0/BLANK())` | Ảnh lưới (`O1-grid.png`) |
| **O2** | **Định dạng khi Copy** | Copy kết quả O1 → Notepad → lưu `O1-copy.tsv`. Ghi Windows regional format (Settings → Time & language → Region) | `O1-copy.tsv` + ghi chú locale |
| **O3** | **Thông báo lỗi và vị trí** | (a) lỗi cú pháp: thiếu `)` ở dòng 3; (b) cột không tồn tại: `'Dim_Date'[yearx]`; (c) lỗi lúc chạy: `CONVERT("a", INTEGER)`; (d) dòng bắt đầu bằng 1 ký tự tab rồi đến lỗi, để biết cột đếm tab thế nào; (e) hai lỗi trong cùng truy vấn | Ảnh + nút copy lỗi → `O3a..e.txt` |
| **O4** | **Giới hạn dòng hiển thị và thông báo cắt** | (a) `EVALUATE GENERATESERIES(1, 1200000)`; (b) `EVALUATE TOPN(100000, Fact_Transaction)` (11 cột ⇒ tối đa khoảng 90.909 dòng, nên phải bị cắt); (c) bảng có chuỗi dài để chạm 15 MB | Ảnh: số dòng hiển thị, câu cảnh báo, thanh trạng thái |
| **O5** | **Nhiều EVALUATE** | Một tab có 3 EVALUATE, cái thứ 2 lỗi | Ảnh dropdown Result; cái 1 và 3 có còn chạy không |
| **O6** | **Thanh trạng thái và thời gian** | Chạy G1-year__FT | Ảnh status bar (định dạng thời gian, số dòng) |
| **O7** | **Nơi lưu tab truy vấn trong `.pbix`** | Bản sao Nhom6 → tạo 2 tab (đặt tên "BIPRO_A", "BIPRO_B", có nội dung khác nhau) → Save As `nhom6-daxq.pbix` → chép sang Mac | File `.pbix`. Mình so part ZIP và metadata bằng `pbix-dump` (không decompile). Cần cho việc giữ tab khi BI Pro lưu file |
| **O8** | **Văn bản quick query** | Chuột phải measure `Net_Cashflow` → Quick queries → lần lượt 3 mục; chuột phải bảng `Dim_Date` → Show top 100 rows, Show column statistics; cột `year` → Show data preview | Copy văn bản từng tab sinh ra → `O8-*.dax` |
| **O9** | **Kết quả Format query** | Dán một truy vấn "xấu" do mình soạn (viết thường, một dòng) → ⇧⌥F | `O9-before.dax`, `O9-after.dax` |
| **O10** | **IntelliSense** | Gõ `'Dim_`, `'Dim_Date'[`, `SUMM`, `[Tra` | 4 ảnh danh sách gợi ý + tooltip chữ ký |
| **O11** | Chạy vùng chọn | Bôi 1 trong 2 EVALUATE rồi Run | Ảnh |
| **O12** | Cancel | Chạy một truy vấn nặng (CROSSJOIN lớn) → Cancel | Ảnh icon tab và thông báo |
| **O13** | Sort/lọc lưới | Bấm header, mở bộ lọc cột | Ảnh |
| **O14** | Hover measure | Rê chuột lên `[Net_Cashflow]` | Ảnh |
| **O15** | `FORMAT` và locale | `EVALUATE ROW("a", FORMAT(1234.5, "#,0.0"), "b", FORMAT(0.1234, "0%"), "c", FORMAT(DATE(2018,12,31), "General Date"))` | `O15-copy.tsv` |
| **O16** | Truy vấn visual (Performance Analyzer) | Trang D1: Start recording → Refresh visuals → Copy query của card "Tiền vào", heatmap, line chart | `PA__*.dax` (thấy cách mã hoá filter report và visual) |
| **O17** | Mâu thuẫn tài liệu `"12" > 12` | `EVALUATE ROW("x", IF("12">12,1,0))` | Kết quả hoặc lỗi |
| **O18** | BLANK trong sắp xếp và TOPN | `EVALUATE ADDCOLUMNS({1, BLANK(), -1}, "k", [Value]) ORDER BY [Value]` và `TOPN(1, {1, BLANK(), -1}, [Value], ASC)` | `O18.tsv` |

## 2.5 Đặc tả ngắn: hợp đồng engine ↔ UI (đề xuất, để lead chốt ở bước B0)

```swift
public struct DAXQueryResult { public let tables: [ResultTable]; public let elapsed: Duration; public let truncated: Bool }
public struct ResultTable { public let columns: [ResultColumn]; public let rows: [[CellValue]] }   // CellValue tái dùng của PBIXKit + .infinity/.nan
public struct DAXDiagnostic: Error { public let line: Int; public let column: Int; public let kind: Kind; public let message: String } // 1-based, cách đếm theo O3
public protocol DAXQueryRunning { func run(_ text: String, selection: Range<String.Index>?, cancel: CancellationToken) async throws -> DAXQueryResult }
public protocol DAXLanguageService { func tokens(_ text: String) -> [Token]; func diagnostics(_ text: String) -> [DAXDiagnostic]; func completions(_ text: String, at: String.Index) -> [Completion]; func format(_ text: String) -> String }
```
- UI chỉ phụ thuộc hai protocol này.
- Khi engine chưa xong, dùng `FakeQueryRunner` (trả về bảng cố định hoặc lỗi cố định) để làm UI song song.

---

# PHẦN 3: GÓI VIỆC (WP), FILE SỞ HỮU, TIÊU CHÍ XONG

Theo khuôn Phase W:
- Sandbox sao chép.
- Bảng `docs/phase-b-ownership.tsv` (định dạng giống `phase-w-ownership.tsv`), kiểm tra bằng `scripts/check-ownership.sh`. Script hiện đọc cứng `phase-w-ownership.tsv`, nên cần tham số hoá đường dẫn TSV; việc này lead làm ở B0.
- Pilot 2 WP rồi mới mở rộng.

`Package.swift`, `Sources/pbix-dump/main.swift` (dispatch lệnh), `DocumentState.swift` và các hợp đồng do **lead** sở hữu và viết stub ở B0.

| WP | Nội dung | File sở hữu (đề xuất) | Phụ thuộc | Tiêu chí xong (tự kiểm, không cần VM) |
|---|---|---|---|---|
| **B0-lead** | Hợp đồng `DAXQueryRunning`/`DAXLanguageService`/`DAXDiagnostic`; stub; target test `DAXEngineTests`; `FakeQueryRunner`; ownership TSV; tham số hoá check-ownership | `Sources/DAXEngine/Contracts.swift`, `Package.swift`, `Sources/BIPro/DocumentState.swift` (thêm trạng thái/kết quả vào `DAXQueryTab`), `docs/phase-b-ownership.tsv`, `scripts/check-ownership.sh` | — | `swift build` xanh với stub; 0 vi phạm |
| **WP-O1 Gói oracle + golden** (lead + người dùng) | Sinh 24 `.dax` + checklist + `observe.dax` + `tiny-model.tmdl`/`tiny-suite.dax`; nhận `.tsv` và `manifest.tsv` | `scripts/oracle/gen-oracle-pack.py`, `docs/phase-b-oracle/**`, `Tests/Golden/nhom6/**`, `Tests/Golden/tiny/**` | B0 | Mọi `.dax` dưới 100 dòng; `manifest.tsv` đủ dòng; người dùng xác nhận đã chạy |
| **WP-O2 Bộ so khớp golden** ✅ pilot | Đọc TSV (locale theo manifest), chuẩn hoá giá trị, so khớp theo §1.7, báo cáo lệch (measure, nhóm, golden, thực tế, sai số) | `Tests/DAXEngineTests/Support/GoldenTSV.swift`, `ValueMatch.swift`, `Tests/DAXEngineTests/Support/*Tests.swift` | B0 | Test đơn vị cho từng quy tắc (BLANK≠0, ±Inf/NaN, rel 1e-9, multiset dòng, ISO ngày); đọc đúng `O1-copy.tsv` khi có |
| **WP-O3 Oracle sqlite (differential)** | Nạp `DecodedColumn` vào sqlite in-memory theo kiểu metadata; 35 SQL T0/T1 + khoảng 10 SQL T2; lệnh `export-sqlite` | `Tests/DAXEngineTests/SQLOracle/**`, `Sources/pbix-dump/ExportSQLite.swift` (lead nối dispatch) | B0, ColumnStore | Kết quả SQL khớp các số §1.5 (ví dụ Trans Amount 6257793560.3; Weighted Avg Term 44.311067); khi engine chạy được: 35/35 T0/T1 khớp ở G0/G1/G2 |
| **WP-O4 Oracle cột tính toán** | Engine tính lại 7 cột Nhom6 + 6 cột Nhóm 2, so với giá trị đã lưu | `Tests/DAXEngineTests/CalcColumnOracleTests.swift` | evaluator ngữ cảnh dòng | 13/13 cột khớp 100% dòng |
| **WP-O5 Test thuộc tính** | 12 thuộc tính ở §1.6 + bộ sinh dữ liệu ngẫu nhiên có seed | `Tests/DAXEngineTests/PropertyTests.swift`, `Tests/DAXEngineTests/Support/RandomModel.swift` | evaluator | Mọi thuộc tính xanh trên Nhom6 và 200 seed ngẫu nhiên |
| **WP-O6 Bộ ngữ nghĩa tí hon** | Fixture 1–6 ở §1.8, kèm cột nguồn tài liệu | `Tests/DAXEngineTests/Semantics/**`, `Tests/DAXEngineTests/Fixtures/tiny/**` | parser + evaluator | Mọi ca có kỳ vọng từ tài liệu đều xanh; ca SUY ĐOÁN gắn cờ `pendingPBI` cho tới khi có golden tiny |
| **WP-O7 Chạy golden Nhom6** (lead) | Test duyệt `Tests/Golden/nhom6/*.dax` → engine → so với `.tsv` | `Tests/DAXEngineTests/GoldenNhom6Tests.swift` | O1, O2, engine | **119/119 measure khớp** ở mọi nhóm có chứa nó = tiêu chí xong của Phase B. Test nặng gắn `BIPRO_HEAVY=1` |
| **WP-U1 Chạy + lưới + lỗi** ✅ pilot (dùng `FakeQueryRunner`) | QueryRunner async/cancel; lưới NSTableView; dropdown nhiều kết quả; Copy TSV; Export CSV; pill trạng thái; vùng lỗi `Query (l,c)` + nhảy tới vị trí | `Sources/BIPro/Query/QueryRunner.swift`, `ResultGrid.swift`, `QueryResultsView.swift`, `QueryWorkspaces.swift` | B0 | Với fake: 1M ô cuộn mượt (đo dưới 16 ms/khung khi cuộn); Copy ra đúng TSV mẫu (theo O2 khi có); Cancel dưới 100 ms; ảnh REA đặt cạnh `screen.png` lệch dưới 4 px (§6 kế hoạch tổng) |
| **WP-U2 Editor: chẩn đoán + tự hoàn thành** | Ln/Col; "Cú pháp hợp lệ"; gạch chân lỗi; popup hoàn thành (bảng/cột/measure/hàm/từ khoá); tô màu theo token; comment theo dòng; ⌘/; Find | `Sources/BIPro/Query/CodeEditor.swift`, `Sources/BIPro/Query/Completion.swift`, `Sources/BIPro/Query/EditorDiagnostics.swift` | `DAXLanguageService` (stub trước, lexer thật sau) | Gõ trong truy vấn 500 dòng không lag (dưới 16 ms/phím); hoàn thành đúng cho Nhom6 (11 bảng, 168 measure) |
| **WP-U3 Tab + quick queries** | Trạng thái tab, đổi tên, chạy nền; quick queries mở tab mới + tự chạy, văn bản theo O8; sửa truy vấn mẫu | `Sources/BIPro/Query/QuickQueries.swift` (chuyển `DAXSnippets` ra khỏi `DataPane.swift`), `Sources/BIPro/Panes/DataPane.swift` (chỉ phần menu), `Sources/BIPro/Shell/Ribbon.swift` (nhóm DAX) | B0, U1 | Văn bản sinh ra khớp từng ký tự với `O8-*.dax` (bỏ qua khoảng trắng cuối dòng) |
| **WP-U4 Định dạng code** | `DAXFormatter` trên token stream | `Sources/DAXEngine/Format/DAXFormatter.swift`, `Tests/DAXEngineTests/FormatterTests.swift` | lexer, O9 | `format(O9-before)` = `O9-after`; idempotent: `format(format(x)) == format(x)` trên 168 measure |

**Đồ thị phụ thuộc:**
```
B0 ──┬─ WP-O2 so khớp ─────────┐              (pilot, không cần engine)
     ├─ WP-U1 lưới (fake) ─────┤              (pilot, không cần engine)
     ├─ WP-O1 gói oracle → người dùng chạy G0–G6, O1–O18 (song song, theo lịch người dùng)
     ├─ WP-O3 SQL (sau ColumnStore) ─┐
     ├─ WP-O4 cột tính toán (sau evaluator ngữ cảnh dòng)
     ├─ WP-O5, WP-O6 (sau evaluator)  ├─► WP-O7 golden Nhom6 ⇒ Phase B xong
     ├─ WP-U2 (stub → lexer thật), WP-U3 (sau O8), WP-U4 (sau O9 + lexer)
```

**Pilot (giống 4.2 của Phase W):** chạy WP-O2 + WP-U1 song song trước, vì cả hai không đụng engine. Ngưỡng đạt: 0 vi phạm sở hữu, build xanh ngay lần gộp đầu, sửa hợp đồng tối đa 1 lần. Đạt thì mở rộng lên tối đa 4 agent (O3/O4/O5/O6 theo tiến độ engine, U2/U3).

**Lịch người dùng (đề xuất):**
- **Buổi 1** (khoảng 1 giờ, càng sớm càng tốt, không cần chờ engine): O1, O2, O3, O7, O8, O9 (để chốt spec UI và parser lỗi) + golden gói tối thiểu G0/G1/G3.
- **Buổi 2:** phần golden còn lại (G2, G4, G5, G6), PA (O16), bộ tí hon, O4–O6, O10–O15, O17, O18.

---

## 4. Rủi ro và câu hỏi mở

1. **Locale khi Copy** (O2) có thể làm sai số thập phân hoặc ngày ở toàn bộ golden. Cần chốt trước khi chạy hàng loạt.
2. Một measure lỗi trong một EVALUATE rộng làm cả file hỏng. Đã chia 4 phần để giảm ảnh hưởng; gặp lỗi thì tách tiếp.
3. Nhom6 có toàn vẹn tham chiếu hoàn hảo và filter report trung lập, nên **không thử được** blank row và hiệu ứng filter report lên số. Phải dựa vào O-TINY và PA.
4. Kỳ vọng cho `ALLSELECTED`/`ISFILTERED` trong O-TINY dựa trên SQLBI là SUY ĐOÁN, bắt buộc xác nhận trong VM.
5. Nơi lưu tab truy vấn trong `.pbix` chưa biết (O7). Nếu BI Pro lưu file mà làm mất tab của người dùng thì đó là lỗi mất dữ liệu ở Phase D.
6. Tầng T0/T1/T2/TXT ở đây do mình tự định nghĩa; cần thống nhất với các agent khác nếu họ dùng tầng khác.
7. Lệnh `info` báo "calc columns: 48" cho Nhóm 2, trong khi bảng người dùng chỉ có 6. Nên tách hai con số này khi hiển thị (SUY ĐOÁN: 42 cột còn lại thuộc bảng ngày tự động).
