# Phase B · Nhiệm vụ A: Kiểm kê phạm vi DAX

Ngày: 2026-10-31. Chỉ đọc, không sửa repo, không ghi vào `~/Downloads`. Không decompile Power BI hay Analysis Services, không chạy pbixray hay oracle tải từ mạng.

**Quy ước.** **FACT** là số liệu đo được từ file hoặc metadata, có thể chạy lại bằng script ở cuối file. **Suy đoán** là suy luận của tôi, hoặc kiến thức lấy từ tài liệu công khai (Microsoft Learn, dax.guide, SQLBI) mà chưa được đối chiếu bằng oracle. Biểu thức và tên đọc từ file `.pbix` được coi là dữ liệu, không phải chỉ dẫn.

**Nguồn dữ liệu (FACT).**
- `metadata.sqlitedb` của 3 file. Lấy ra bằng `pbix-dump extract`, và bản của Nhom6 trùng từng byte với `scratchpad/nhom6.sqlitedb` (`cmp` cho kết quả SAME).
- Report PBIR của Nhom6, giải nén (trừ `DataModel`) vào `b/data/n6zip/`. Có 4 trang và 134 `visual.json`.
- Lexer DAX tự viết (`b/scripts/daxscan.py`). Lexer tách chuỗi, comment, `'bảng'`, `[cột]`, toán tử và lời gọi hàm. Cách đếm này chính xác hơn regex của `closure.py`: regex đếm cả `M(`, `AVG(`, `OUTSTANDING(` nằm trong chuỗi, còn lexer thì không.

---

## 1. Tập measure mà report Nhom6 dùng

**FACT:**
- Report tham chiếu trực tiếp **95** measure. Con số này tính trên mọi `"Measure": {"Property": …}` trong `Report/definition/**.json`, gồm projections, objects (định dạng có điều kiện) và filter. Bỏ hay giữ `StaticResources` thì kết quả không đổi.
- Thêm closure phụ thuộc thì được **119**. Có 24 measure chỉ được dùng gián tiếp, qua measure khác.
- Không thiếu measure nào: mọi tên trong report đều có trong model.
- Hai cách tính cho cùng một tập. `closure.py` (regex trên `measures.tsv`) và lexer trên sqlite cho ra hai tập 119 giống hệt nhau (hiệu đối xứng rỗng).
- Có **49** measure trong 168 mà report không dùng, trực tiếp hay gián tiếp.
- Nơi dùng 95 measure trực tiếp: 67 measure nằm trong field well. **28** measure chỉ xuất hiện trong `objects`, tức là định dạng có điều kiện (màu chữ, màu nền, icon). Cả 28 đều trả về chuỗi màu hoặc data URI SVG, ví dụ `… Δ Color`, `NPL Color`, `Pareto Color`, `Peak Hour Top10 Icon`.
- Trong 119 có 50 measure trả về chuỗi (Color/Label/Text/Title/Icon). 55 measure có format string tĩnh. 14 measure có **dynamic format string**, đều dạng `IF(ABS(SELECTEDMEASURE()) < 0.05, "0.0%", "0%")`.

**95 measure dùng trực tiếp:**
`% Trans Amount`, `Active_Monthly_Payment`, `Active_Monthly_Payment Δ Color`, `Active_Monthly_Payment Δ Label`, `Avg Trans Value`, `Avg Trans Value Δ Color`, `Avg Trans Value Δ Label`, `Avg_Account_Balance`, `Avg_Account_Balance Δ Color`, `Avg_Account_Balance Δ Label`, `Avg_Days_To_Company`, `Avg_Days_To_Company Δ Color`, `Avg_Days_To_Company Δ Label`, `Bad Debt Loans`, `Bad_Debt_Principal`, `Bad_Debt_Principal Δ Color`, `Bad_Debt_Principal Δ Label`, `Bad_Debt_Ratio_Count`, `Bad_Debt_Ratio_Count Δ Color`, `Bad_Debt_Ratio_Count Δ Label`, `Bad_Debt_Ratio_Value`, `Bad_Debt_Ratio_Value Δ Color`, `Bad_Debt_Ratio_Value Δ Label`, `Branch Loan Amount`, `Branch Loan Count`, `Branch NPL Color`, `Branch NPL Label`, `Branch Outstanding`, `Branch Subtitle`, `Branch Title`, `Channel Share %`, `Complaints`, `Complaints MA3`, `Complaints per 1000 Clients`, `Complaints Δ Color`, `Complaints Δ Label`, `D4 Active Accounts`, `D4 Avg_Days_To_Company`, `D4 Complaints`, `D4 Dispute_Rate`, `D4 Overdraft Rate`, `D4 SLA_Timely_Rate`, `D4 Timely Color`, `D4 Trans Amount`, `D4 Trans Count`, `Dispute_Rate`, `Dispute_Rate Δ Color`, `Dispute_Rate Δ Label`, `Loan Amount`, `Loan Amount Δ Color`, `Loan Amount Δ Label`, `Loan Count`, `Loan Count Δ Color`, `Loan Count Δ Label`, `NPL Color`, `NPL Count Text Color`, `NPL Group Color`, `Neg Balance Trans`, `Neg Trans Alert Color`, `Net_Cashflow`, `Net_Cashflow Δ Color`, `Net_Cashflow Δ Label`, `Overdraft Rate`, `Pareto 80% Line`, `Pareto Color`, `Pareto Cum %`, `Peak Hour Font Color`, `Peak Hour Top10 Icon`, `Relief Rate`, `Relief Rate Δ Color`, `Relief Rate Δ Label`, `Response Share in Channel %`, `SLA_Timely_Rate`, `SLA_Timely_Rate Δ Color`, `SLA_Timely_Rate Δ Label`, `Sanction Count`, `Sanction Interest`, `Timely Color`, `Top Branches Text`, `Total_Clients`, `Total_Clients Sub Color`, `Total_Clients Sub Label`, `Total_Credit_Inflow`, `Total_Credit_Inflow Δ Color`, `Total_Credit_Inflow Δ Label`, `Total_Debit_Outflow`, `Total_Debit_Outflow Δ Color`, `Total_Debit_Outflow Δ Label`, `Trans Amount`, `Trans Count`, `Trans Count (k)`, `Trans Count Δ Color`, `Trans Count Δ Label`, `Trans per Client`, `Weighted Avg Term`

**24 measure chỉ là phụ thuộc** (có trong 119, không có trong 95):
`Active Accounts`, `Active_Monthly_Payment Δ`, `Avg Trans Value Δ`, `Avg_Account_Balance Δ`, `Avg_Days_To_Company Δ`, `Bad_Debt_Principal Δ`, `Bad_Debt_Ratio_Count Δ`, `Bad_Debt_Ratio_Value Δ`, `Complaints Δ`, `Dispute_Rate Δ`, `Loan Amount Δ`, `Loan Count Δ`, `Monthly Payment`, `NPL Avg (Selected)`, `Neg Trans PM`, `Net_Cashflow Δ`, `Outstanding (est.)`, `Overdraft Accounts`, `Relief Rate Δ`, `SLA Target`, `SLA_Timely_Rate Δ`, `Total_Credit_Inflow Δ`, `Total_Debit_Outflow Δ`, `Trans Count Δ`

**49 measure không dùng** (có trong 168, không có trong 119):
`% Trans Count`, `Accounts with Loan`, `Active Accounts Δ`, `Active Accounts Δ Color`, `Active Accounts Δ Label`, `Active Loans`, `Avg Balance After`, `Avg Complaints per Month`, `Avg Loan Amount`, `Branch Loan Rank`, `Card Accounts`, `Card Penetration %`, `Cards Issued`, `Closing_Balance`, `Complaints YoY %`, `Complaints YoY Color`, `Complaints YoY Label`, `Complaints_Sent`, `Dispute Color`, `Disputed Complaints`, `Loan Penetration %`, `Loan YoY %`, `Loan YoY Color`, `Loan YoY Label`, `NPL Count Color`, `Overdraft Rate Δ`, `Overdraft Rate Δ Color`, `Overdraft Rate Δ Label`, `Peak Hour Color`, `Settled Loans`, `Settled Rate`, `Settled Rate Δ`, `Settled Rate Δ Color`, `Settled Rate Δ Label`, `State Rank by Loan Amount`, `Title Loan Page`, `Total Accounts`, `Trans Amount MA3`, `Trans Amount MoM %`, `Trans Amount PM`, `Trans Amount YTD`, `Trans Amount Δ`, `Trans Amount Δ Color`, `Trans Amount Δ Label`, `Trans Heat Color`, `Trans YoY %`, `Trans YoY Color`, `Trans YoY Label`, `Within 3 Days %`

**Hai họ measure chiếm phần lớn (FACT, đếm theo tên và biểu thức):**
- **Họ Δ (so với cùng kỳ năm trước):** gồm 17 `X Δ`, 17 `X Δ Label` và 17 `X Δ Color`, tổng **51/119 (43%)**. Cả 17 `X Δ` dùng chung một khuôn: `endKey = MAX(Fact[date_key])`, rồi `endDt = DATE(INT(k/10000), MOD(INT(k/100),100), MOD(k,100))`. Kế tiếp `curDates = FILTER(VALUES(Dim_Date[full_date]), …)`. Cuối cùng là `CALCULATE([M], curDates, REMOVEFILTERS(Dim_Date))` và `CALCULATE([M], SAMEPERIODLASTYEAR(curDates), REMOVEFILTERS(Dim_Date))`. Khuôn này chạy đúng thì 51 measure gần như đúng theo.
- **Họ D4 (trang drill-through chi nhánh):** 8 measure `D4 …`, dạng `SWITCH(TRUE(), ISFILTERED(col), CALCULATE([M], TREATAS(SUMMARIZE(…) | VALUES(…), …)), …, [M])`. Họ này nối Dim_District/Dim_Account với Dim_Account/Dim_Client, là các cặp bảng **không có quan hệ** với nhau.

---

## 2. Tần suất hàm, toán tử, từ khoá

**FACT.**
- Số hàm khác nhau: tập 95 dùng **41**, tập 119 dùng **43**, tập 168 dùng **46**.
- Ba hàm chỉ có trong 168: `ALL` (`State Rank by Loan Amount`), `RANKX` (`State Rank…`, `Branch Loan Rank`) và `USERELATIONSHIP` (`Complaints_Sent`). Không measure nào trong 3 measure này nằm trong 119.
- Ngoài measure, Nhom6 còn có:
  - cột tính toán: thêm `HOUR`, `DAY`;
  - dynamic format string: thêm `SELECTEDMEASURE`;
  - RLS: không thêm hàm nào.
  
  Cộng lại, toàn bộ DAX trong Nhom6 dùng **49 hàm**.

"Lần dùng" đếm số lần gọi hàm. "Số measure" đếm số measure có dùng hàm đó ít nhất một lần.

| Nhóm | Hàm | Lần dùng (119) | Số measure (119) | Số measure (95 trực tiếp) | Lần dùng (168) | Số measure (168) |
|---|---|---:|---:|---:|---:|---:|
| Tổng hợp | `MAX` | 39 | 38 | 19 | 53 | 50 |
| Tổng hợp | `SUM` | 6 | 6 | 5 | 6 | 6 |
| Tổng hợp | `COUNTROWS` | 2 | 2 | 2 | 4 | 4 |
| Tổng hợp | `DISTINCTCOUNT` | 3 | 3 | 1 | 4 | 4 |
| Tổng hợp | `AVERAGE` | 1 | 1 | 1 | 2 | 2 |
| Iterator | `SUMX` | 4 | 3 | 2 | 5 | 4 |
| Iterator | `AVERAGEX` | 1 | 1 | 1 | 3 | 3 |
| Iterator | `RANKX` | 0 | 0 | 0 | 2 | 2 |
| Iterator | `MINX` | 1 | 1 | 1 | 1 | 1 |
| Iterator | `MAXX` | 1 | 1 | 1 | 1 | 1 |
| Iterator | `CONCATENATEX` | 1 | 1 | 1 | 1 | 1 |
| Iterator | `PERCENTILEX.INC` | 1 | 1 | 1 | 1 | 1 |
| Filter / ngữ cảnh | `CALCULATE` | 83 | 47 | 27 | 113 | 68 |
| Filter / ngữ cảnh | `REMOVEFILTERS` | 40 | 21 | 3 | 60 | 32 |
| Filter / ngữ cảnh | `FILTER` | 22 | 22 | 4 | 29 | 29 |
| Filter / ngữ cảnh | `KEEPFILTERS` | 16 | 14 | 13 | 21 | 19 |
| Filter / ngữ cảnh | `ALLSELECTED` | 9 | 7 | 6 | 15 | 11 |
| Filter / ngữ cảnh | `TREATAS` | 24 | 8 | 8 | 24 | 8 |
| Filter / ngữ cảnh | `CALCULATETABLE` | 1 | 1 | 1 | 2 | 2 |
| Filter / ngữ cảnh | `ALL` | 0 | 0 | 0 | 1 | 1 |
| Filter / ngữ cảnh | `USERELATIONSHIP` | 0 | 0 | 0 | 1 | 1 |
| Thông tin | `ISBLANK` | 98 | 67 | 50 | 135 | 95 |
| Thông tin | `ISFILTERED` | 34 | 10 | 10 | 34 | 10 |
| Thông tin | `HASONEVALUE` | 2 | 2 | 1 | 7 | 7 |
| Thông tin | `SELECTEDVALUE` | 7 | 3 | 3 | 10 | 6 |
| Time intelligence | `SAMEPERIODLASTYEAR` | 17 | 17 | 0 | 21 | 21 |
| Logic | `IF` | 142 | 69 | 51 | 188 | 96 |
| Logic | `SWITCH` | 32 | 29 | 29 | 40 | 37 |
| Logic | `TRUE` | 32 | 29 | 29 | 40 | 37 |
| Logic | `COALESCE` | 3 | 3 | 3 | 3 | 3 |
| Toán | `DIVIDE` | 30 | 30 | 19 | 43 | 43 |
| Toán | `INT` | 68 | 34 | 17 | 84 | 42 |
| Toán | `MOD` | 68 | 34 | 17 | 84 | 42 |
| Toán | `ABS` | 29 | 18 | 17 | 35 | 22 |
| Chuỗi | `FORMAT` | 21 | 20 | 20 | 30 | 28 |
| Ngày giờ | `DATE` | 52 | 35 | 17 | 64 | 43 |
| Ngày giờ | `YEAR` | 34 | 34 | 17 | 42 | 42 |
| Ngày giờ | `MONTH` | 34 | 17 | 17 | 42 | 21 |
| Ngày giờ | `DATEDIFF` | 1 | 1 | 0 | 1 | 1 |
| Bảng | `VALUES` | 31 | 27 | 10 | 38 | 34 |
| Bảng | `SUMMARIZE` | 12 | 8 | 8 | 12 | 8 |
| Bảng | `CROSSJOIN` | 2 | 2 | 2 | 3 | 3 |
| Bảng | `ADDCOLUMNS` | 1 | 1 | 1 | 1 | 1 |
| Bảng | `TOPN` | 1 | 1 | 1 | 1 | 1 |
| Quan hệ | `RELATED` | 4 | 2 | 1 | 4 | 2 |
| Khác | `BLANK` | 30 | 30 | 24 | 40 | 40 |

**Toán tử và từ khoá (FACT).** Cột `=` gồm cả dấu gán trong `VAR x = …`. Trong 119 có 223 lần `VAR`, nên dấu `=` dùng để so sánh chỉ khoảng 30 lần. Cột `&` là nối chuỗi. `NOT` luôn ở dạng toán tử (`NOT ISBLANK(x)`), không có chỗ nào gọi `NOT(…)`. `IN { … }` dùng cùng table constructor `{}` (3 measure).

| Toán tử / từ khoá | Lần dùng (119) | Số measure (119) | Lần dùng (168) | Số measure (168) |
|---|---:|---:|---:|---:|
| `=` | 253 | 78 | 340 | 110 |
| `VAR` | 223 | 69 | 294 | 98 |
| `RETURN` | 71 | 69 | 101 | 98 |
| `-` | 42 | 41 | 60 | 56 |
| `>` | 37 | 37 | 53 | 51 |
| `/` | 69 | 35 | 85 | 43 |
| `NOT (toán tử)` | 26 | 24 | 37 | 34 |
| `<` | 57 | 29 | 68 | 34 |
| `\|\|` | 28 | 26 | 34 | 32 |
| `>=` | 20 | 20 | 32 | 29 |
| `&` | 155 | 21 | 198 | 29 |
| `<=` | 19 | 19 | 26 | 26 |
| `&&` | 19 | 19 | 24 | 24 |
| `*` | 8 | 8 | 15 | 12 |
| `+` | 3 | 3 | 4 | 4 |
| `tham số enum DESC` | 2 | 1 | 4 | 3 |
| `<>` | 1 | 1 | 3 | 3 |
| `{}` | 3 | 3 | 3 | 3 |
| `IN` | 3 | 3 | 3 | 3 |
| `tham số enum DENSE` | 0 | 0 | 2 | 2 |
| `tham số enum MONTH` | 1 | 1 | 1 | 1 |

Những đặc điểm cú pháp khác cần hỗ trợ (FACT):
- `VAR` lồng trong đối số của iterator, ví dụ `SUMX(t, VAR a = … RETURN …)` trong `Outstanding (est.)` và `Avg_Account_Balance`.
- Biến kiểu bảng dùng làm filter của CALCULATE (`curDates`), và làm đối số của `SAMEPERIODLASTYEAR`.
- Cột mở rộng `[@c]`, sinh từ `ADDCOLUMNS(…, "@c", …)` (`Pareto Cum %`).
- Measure tham chiếu không kèm tên bảng, ví dụ `[Trans Count]`.
- Tham số enum: `DESC`, `DENSE` (chỉ ở `RANKX`, ngoài 119) và `MONTH` (`DATEDIFF`).
- Literal `1e6`.
- `MAX(0, x)` hai đối số dạng vô hướng, tồn tại song song với `MAX(cột)`.
- Chuỗi Unicode (tiếng Việt, ký tự ▲▼●Δ) và chuỗi chứa data URI SVG.

---

## 3. Phân tầng độ khó của 119 measure

**Luật xếp tầng** (tôi viết thành code trong `report.py`, xếp vào tầng cao nhất mà measure khớp):
- **T0:** tổng hợp, hằng số, số học, DIVIDE/COALESCE, tham chiếu measure.
- **T1:** CALCULATE với predicate đơn giản hoặc REMOVEFILTERS.
- **T2:** iterator không có context transition, VAR, IF/SWITCH, FORMAT, ISFILTERED/HASONEVALUE/SELECTEDVALUE, RELATED, FILTER/VALUES/SUMMARIZE, hàm ngày.
- **T3:** ALLSELECTED, KEEPFILTERS, TREATAS, USERELATIONSHIP, CALCULATETABLE, hoặc **context transition trong iterator**. Context transition được nhận ra khi thân của một iterator hay FILTER có tham chiếu measure hoặc CALCULATE.
- **T4:** SAMEPERIODLASTYEAR/DATEADD, hoặc "time intelligence thủ công", tức `REMOVEFILTERS(Dim_Date)` đi kèm lọc cột Dim_Date theo biến (MA3, PM).
- **T5:** hàm hiếm, gồm PERCENTILEX.INC, CONCATENATEX, RANKX, TOPN, CROSSJOIN, ADDCOLUMNS.

"Tầng hiệu dụng" là tầng cao nhất trong closure phụ thuộc của measure: measure chỉ khớp oracle khi mọi phụ thuộc đã khớp. `T3*` là T3 chỉ vì `KEEPFILTERS` bọc một predicate trên một cột, ví dụ `KEEPFILTERS(Dim_Trans_Type[trans_type] = "Credit")`. Thực chất loại này dễ, nên làm cùng T1.

**Phân bố (FACT, theo luật trên):**

| Tầng | Riêng (119) | Hiệu dụng (119) | Riêng (168) |
|---|---:|---:|---:|
| T0 | 19 | 15 | 25 |
| T1 | 1 | 1 | 3 |
| T2 | 49 | 5 | 67 |
| T3 | 27 | 39 | 37 |
| T4 | 19 | 54 | 29 |
| T5 | 4 | 5 | 7 |
| **Tổng** | 119 | 119 | 168 |

Trong 27 measure T3 riêng có **14** measure là `T3*`. Nếu tính chúng là T1 thì T1 có 15 measure và T3 thật chỉ còn 13.

**Suy đoán:** Thứ tự mở khoá hợp lý là T0 → T1/T3* → T2 → T3 → T4 → T5. Theo tầng hiệu dụng, sau T3 sẽ khớp khoảng 60/119 measure. Họ Δ (T4) mở khoá thêm 54 measure.

| # | Measure | Bảng | Trực tiếp? | Tầng riêng | Tầng hiệu dụng | Lý do / tính năng | Hàm | Phụ thuộc measure | Dùng ở |
|---:|---|---|:-:|:-:|:-:|---|---|---|---|
| 1 | Total_Clients Sub Color | Dim_Client | x | T0 | T0 | tổng hợp/hằng/số học | — | — | card.objects |
| 2 | Branch Loan Amount | Dim_District | x | T0 | T0 | tổng hợp/hằng/số học | COALESCE | Loan Amount | card.Values |
| 3 | Branch Loan Count | Dim_District | x | T0 | T0 | tổng hợp/hằng/số học | COALESCE | Loan Count | card.Values |
| 4 | Branch Outstanding | Dim_District | x | T0 | T2 | tổng hợp/hằng/số học | COALESCE | Outstanding (est.) | card.Values |
| 5 | Complaints | Fact_CRM_Complaint | x | T0 | T0 | tổng hợp/hằng/số học | SUM | — | card.Values, clusteredBarChart.Tooltips, lineClusteredColumnComboChart.Y, lineStackedColumnComboChart.Tooltips, lineStackedColumnComboChart.Y, treemap.Values |
| 6 | Complaints per 1000 Clients | Fact_CRM_Complaint | x | T0 | T3 | tổng hợp/hằng/số học | DIVIDE | Complaints, Total_Clients | clusteredBarChart.Y |
| 7 | Pareto 80% Line | Fact_CRM_Complaint | x | T0 | T0 | tổng hợp/hằng/số học | — | — | lineClusteredColumnComboChart.Y2 |
| 8 | SLA Target | Fact_CRM_Complaint |  | T0 | T0 | tổng hợp/hằng/số học | — | — | (phụ thuộc) |
| 9 | Loan Amount | Fact_Loan | x | T0 | T0 | tổng hợp/hằng/số học | SUM | — | card.Values, donutChart.Y, lineStackedColumnComboChart.Y, shapeMap.Tooltips |
| 10 | Loan Count | Fact_Loan | x | T0 | T0 | tổng hợp/hằng/số học | SUM | — | card.Values, clusteredBarChart.Tooltips, donutChart.Tooltips, donutChart.Y, hundredPercentStackedColumnChart.Y, lineClusteredColumnComboChart.Y, lineStackedColumnComboChart.Y2 |
| 11 | Monthly Payment | Fact_Loan |  | T0 | T0 | tổng hợp/hằng/số học | SUM | — | (phụ thuộc) |
| 12 | Active Accounts | Fact_Transaction |  | T0 | T0 | tổng hợp/hằng/số học | DISTINCTCOUNT | — | (phụ thuộc) |
| 13 | Avg Trans Value | Fact_Transaction | x | T0 | T0 | tổng hợp/hằng/số học | DIVIDE | Trans Amount, Trans Count | card.Values |
| 14 | Net_Cashflow | Fact_Transaction | x | T0 | T3 | tổng hợp/hằng/số học | — | Total_Credit_Inflow, Total_Debit_Outflow | card.Values, lineClusteredColumnComboChart.Y2 |
| 15 | Overdraft Rate | Fact_Transaction | x | T0 | T3 | tổng hợp/hằng/số học | DIVIDE | Active Accounts, Overdraft Accounts | lineClusteredColumnComboChart.Tooltips |
| 16 | Trans Amount | Fact_Transaction | x | T0 | T0 | tổng hợp/hằng/số học | SUM | — | donutChart.Y, lineChart.Y |
| 17 | Trans Count | Fact_Transaction | x | T0 | T0 | tổng hợp/hằng/số học | SUM | — | card.Values, donutChart.Tooltips, lineChart.Tooltips |
| 18 | Trans Count (k) | Fact_Transaction | x | T0 | T0 | tổng hợp/hằng/số học | DIVIDE | Trans Count | pivotTable.Values |
| 19 | Trans per Client | Fact_Transaction | x | T0 | T0 | tổng hợp/hằng/số học | DISTINCTCOUNT, DIVIDE | Trans Count | pivotTable.Values |
| 20 | Response Share in Channel % | Fact_CRM_Complaint | x | T1 | T1 | CALCULATE | CALCULATE, DIVIDE, REMOVEFILTERS | Complaints | lineStackedColumnComboChart.Y |
| 21 | Total_Clients Sub Label | Dim_Client | x | T2 | T3 | T2:FORMAT,IF,VAR | DIVIDE, FORMAT, IF, ISBLANK | Complaints, Total_Clients | card.Values |
| 22 | Branch NPL Label | Dim_District | x | T2 | T3 | T2:FORMAT,IF,VAR | FORMAT, IF, ISBLANK | Bad_Debt_Ratio_Count | card.Values |
| 23 | Branch Subtitle | Dim_District | x | T2 | T2 | T2:IF,ISFILTERED,SELECTEDVALUE,SWITCH,VAR | IF, ISBLANK, ISFILTERED, SELECTEDVALUE, SWITCH, TRUE | — | card.Values |
| 24 | Branch Title | Dim_District | x | T2 | T2 | T2:IF,ISFILTERED,SELECTEDVALUE,SWITCH,VAR | IF, ISBLANK, ISFILTERED, SELECTEDVALUE, SWITCH, TRUE | — | card.Values |
| 25 | D4 Timely Color | Dim_District | x | T2 | T3 | T2:IF,VAR | BLANK, IF, ISBLANK | D4 SLA_Timely_Rate, SLA Target | card.objects |
| 26 | Avg_Days_To_Company Δ Color | Fact_CRM_Complaint | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Avg_Days_To_Company Δ | card.objects |
| 27 | Avg_Days_To_Company Δ Label | Fact_CRM_Complaint | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Avg_Days_To_Company Δ | card.Values |
| 28 | Complaints Δ Color | Fact_CRM_Complaint | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Complaints Δ | card.objects |
| 29 | Complaints Δ Label | Fact_CRM_Complaint | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Complaints Δ | card.Values |
| 30 | Dispute_Rate Δ Color | Fact_CRM_Complaint | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Dispute_Rate Δ | card.objects |
| 31 | Dispute_Rate Δ Label | Fact_CRM_Complaint | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Dispute_Rate Δ | card.Values |
| 32 | Relief Rate Δ Color | Fact_CRM_Complaint | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Relief Rate Δ | card.objects |
| 33 | Relief Rate Δ Label | Fact_CRM_Complaint | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Relief Rate Δ | card.Values |
| 34 | SLA_Timely_Rate Δ Color | Fact_CRM_Complaint | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | SLA_Timely_Rate Δ | card.objects |
| 35 | SLA_Timely_Rate Δ Label | Fact_CRM_Complaint | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | SLA_Timely_Rate Δ | card.Values |
| 36 | Timely Color | Fact_CRM_Complaint | x | T2 | T3 | T2:IF | IF | SLA Target, SLA_Timely_Rate | card.objects |
| 37 | Active_Monthly_Payment Δ Color | Fact_Loan | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Active_Monthly_Payment Δ | card.objects |
| 38 | Active_Monthly_Payment Δ Label | Fact_Loan | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Active_Monthly_Payment Δ | card.Values |
| 39 | Bad_Debt_Principal Δ Color | Fact_Loan | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Bad_Debt_Principal Δ | card.objects |
| 40 | Bad_Debt_Principal Δ Label | Fact_Loan | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Bad_Debt_Principal Δ | card.Values |
| 41 | Bad_Debt_Ratio_Count | Fact_Loan | x | T2 | T3 | T2:IF | DIVIDE, IF, ISBLANK | Bad Debt Loans, Loan Count | card.Values, clusteredBarChart.Y, lineClusteredColumnComboChart.Y2, shapeMap.Tooltips |
| 42 | Bad_Debt_Ratio_Count Δ Color | Fact_Loan | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Bad_Debt_Ratio_Count Δ | card.objects |
| 43 | Bad_Debt_Ratio_Count Δ Label | Fact_Loan | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Bad_Debt_Ratio_Count Δ | card.Values |
| 44 | Bad_Debt_Ratio_Value | Fact_Loan | x | T2 | T3 | T2:IF | DIVIDE, IF, ISBLANK | Bad_Debt_Principal, Loan Amount | card.Values, clusteredBarChart.Tooltips |
| 45 | Bad_Debt_Ratio_Value Δ Color | Fact_Loan | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Bad_Debt_Ratio_Value Δ | card.objects |
| 46 | Bad_Debt_Ratio_Value Δ Label | Fact_Loan | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Bad_Debt_Ratio_Value Δ | card.Values |
| 47 | Branch NPL Color | Fact_Loan | x | T2 | T3 | T2:IF,VAR | BLANK, IF, ISBLANK | Bad_Debt_Ratio_Count, NPL Avg (Selected) | shapeMap.objects |
| 48 | Loan Amount Δ Color | Fact_Loan | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Loan Amount Δ | card.objects |
| 49 | Loan Amount Δ Label | Fact_Loan | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Loan Amount Δ | card.Values |
| 50 | Loan Count Δ Color | Fact_Loan | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Loan Count Δ | card.objects |
| 51 | Loan Count Δ Label | Fact_Loan | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Loan Count Δ | card.Values |
| 52 | NPL Color | Fact_Loan | x | T2 | T3 | T2:SWITCH,VAR | BLANK, ISBLANK, SWITCH, TRUE | Bad_Debt_Ratio_Value | card.objects |
| 53 | NPL Count Text Color | Fact_Loan | x | T2 | T3 | T2:SWITCH,VAR | BLANK, ISBLANK, SWITCH, TRUE | Bad_Debt_Ratio_Count | card.objects |
| 54 | NPL Group Color | Fact_Loan | x | T2 | T3 | T2:IF,VAR | BLANK, IF, ISBLANK | Bad_Debt_Ratio_Count | clusteredBarChart.objects, lineClusteredColumnComboChart.objects |
| 55 | Outstanding (est.) | Fact_Loan |  | T2 | T2 | T2:DATE,DATEDIFF,FILTER,RELATED,SUMX,VAR | DATE, DATEDIFF, FILTER, MAX, RELATED, SUMX | — | (phụ thuộc) |
| 56 | Weighted Avg Term | Fact_Loan | x | T2 | T2 | T2:RELATED,SUMX | DIVIDE, RELATED, SUMX | Loan Amount | donutChart.Tooltips |
| 57 | Avg Trans Value Δ Color | Fact_Transaction | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Avg Trans Value Δ | card.objects |
| 58 | Avg Trans Value Δ Label | Fact_Transaction | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Avg Trans Value Δ | card.Values |
| 59 | Avg_Account_Balance Δ Color | Fact_Transaction | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Avg_Account_Balance Δ | card.objects |
| 60 | Avg_Account_Balance Δ Label | Fact_Transaction | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Avg_Account_Balance Δ | card.Values |
| 61 | Neg Trans Alert Color | Fact_Transaction | x | T2 | T4 | T2:IF,VAR | BLANK, IF, ISBLANK | Neg Balance Trans, Neg Trans PM | lineClusteredColumnComboChart.objects |
| 62 | Net_Cashflow Δ Color | Fact_Transaction | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Net_Cashflow Δ | card.objects |
| 63 | Net_Cashflow Δ Label | Fact_Transaction | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Net_Cashflow Δ | card.Values |
| 64 | Total_Credit_Inflow Δ Color | Fact_Transaction | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Total_Credit_Inflow Δ | card.objects |
| 65 | Total_Credit_Inflow Δ Label | Fact_Transaction | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Total_Credit_Inflow Δ | card.Values |
| 66 | Total_Debit_Outflow Δ Color | Fact_Transaction | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Total_Debit_Outflow Δ | card.objects |
| 67 | Total_Debit_Outflow Δ Label | Fact_Transaction | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Total_Debit_Outflow Δ | card.Values |
| 68 | Trans Count Δ Color | Fact_Transaction | x | T2 | T4 | T2:IF,VAR | IF, ISBLANK | Trans Count Δ | card.objects |
| 69 | Trans Count Δ Label | Fact_Transaction | x | T2 | T4 | T2:DATE,FORMAT,IF,INT,MOD,MONTH,SWITCH,YEAR,VAR | ABS, BLANK, DATE, FORMAT, IF, INT, ISBLANK, MAX, MOD, MONTH, SWITCH, TRUE, YEAR | Trans Count Δ | card.Values |
| 70 | Total_Clients | Dim_Client | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, COUNTROWS, KEEPFILTERS | — | card.Values |
| 71 | D4 Active Accounts | Dim_District | x | T3 | T3 | CALCULATE; T2:ISFILTERED,SUMMARIZE,SWITCH,VALUES; T3:TREATAS | CALCULATE, ISFILTERED, SUMMARIZE, SWITCH, TREATAS, TRUE, VALUES | Active Accounts | card.Values |
| 72 | D4 Avg_Days_To_Company | Dim_District | x | T3 | T3 | CALCULATE; T2:ISFILTERED,SUMMARIZE,SWITCH,VALUES; T3:TREATAS | CALCULATE, ISFILTERED, SUMMARIZE, SWITCH, TREATAS, TRUE, VALUES | Avg_Days_To_Company | card.Values |
| 73 | D4 Complaints | Dim_District | x | T3 | T3 | CALCULATE; T2:ISFILTERED,SUMMARIZE,SWITCH,VALUES; T3:TREATAS | CALCULATE, ISFILTERED, SUMMARIZE, SWITCH, TREATAS, TRUE, VALUES | Complaints | card.Values, clusteredBarChart.Y |
| 74 | D4 Dispute_Rate | Dim_District | x | T3 | T3 | CALCULATE; T2:ISFILTERED,SUMMARIZE,SWITCH,VALUES; T3:TREATAS | CALCULATE, ISFILTERED, SUMMARIZE, SWITCH, TREATAS, TRUE, VALUES | Dispute_Rate | card.Values, clusteredBarChart.Tooltips |
| 75 | D4 Overdraft Rate | Dim_District | x | T3 | T3 | CALCULATE; T2:ISFILTERED,SUMMARIZE,SWITCH,VALUES; T3:TREATAS | CALCULATE, ISFILTERED, SUMMARIZE, SWITCH, TREATAS, TRUE, VALUES | Overdraft Rate | card.Values |
| 76 | D4 SLA_Timely_Rate | Dim_District | x | T3 | T3 | CALCULATE; T2:ISFILTERED,SUMMARIZE,SWITCH,VALUES; T3:TREATAS | CALCULATE, ISFILTERED, SUMMARIZE, SWITCH, TREATAS, TRUE, VALUES | SLA_Timely_Rate | card.Values, clusteredBarChart.Tooltips |
| 77 | D4 Trans Amount | Dim_District | x | T3 | T3 | CALCULATE; T2:ISFILTERED,SUMMARIZE,SWITCH,VALUES; T3:TREATAS | CALCULATE, ISFILTERED, SUMMARIZE, SWITCH, TREATAS, TRUE, VALUES | Trans Amount | card.Values, lineChart.Y |
| 78 | D4 Trans Count | Dim_District | x | T3 | T3 | CALCULATE; T2:ISFILTERED,SUMMARIZE,SWITCH,VALUES; T3:TREATAS | CALCULATE, ISFILTERED, SUMMARIZE, SWITCH, TREATAS, TRUE, VALUES | Trans Count | card.Values, lineChart.Tooltips |
| 79 | Avg_Days_To_Company | Fact_CRM_Complaint | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | AVERAGE, CALCULATE, KEEPFILTERS | — | card.Values, clusteredBarChart.Tooltips |
| 80 | Channel Share % | Fact_CRM_Complaint | x | T3 | T3 | CALCULATE; T3:ALLSELECTED | ALLSELECTED, CALCULATE, DIVIDE | Complaints | lineStackedColumnComboChart.Tooltips |
| 81 | Dispute_Rate | Fact_CRM_Complaint | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, DIVIDE, KEEPFILTERS | Complaints | card.Values, clusteredBarChart.Y, lineStackedColumnComboChart.Y2, treemap.Tooltips |
| 82 | Pareto Color | Fact_CRM_Complaint | x | T3 | T5 | CALCULATE; T2:IF; T3:ALLSELECTED | ALLSELECTED, CALCULATE, DIVIDE, IF | Complaints, Pareto Cum % | lineClusteredColumnComboChart.objects |
| 83 | Relief Rate | Fact_CRM_Complaint | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, DIVIDE, KEEPFILTERS | Complaints | card.Values, clusteredBarChart.Y |
| 84 | SLA_Timely_Rate | Fact_CRM_Complaint | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, DIVIDE, KEEPFILTERS | Complaints | card.Values, clusteredBarChart.Y, treemap.Tooltips |
| 85 | Active_Monthly_Payment | Fact_Loan | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, KEEPFILTERS | Monthly Payment | card.Values |
| 86 | Bad Debt Loans | Fact_Loan | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, KEEPFILTERS | Loan Count | clusteredBarChart.Tooltips |
| 87 | Bad_Debt_Principal | Fact_Loan | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, KEEPFILTERS | Loan Amount | card.Values |
| 88 | NPL Avg (Selected) | Fact_Loan |  | T3 | T3 | CALCULATE; T3:ALLSELECTED | ALLSELECTED, CALCULATE | Bad_Debt_Ratio_Count | (phụ thuộc) |
| 89 | % Trans Amount | Fact_Transaction | x | T3 | T3 | CALCULATE; T3:ALLSELECTED | ALLSELECTED, CALCULATE, DIVIDE | Trans Amount | donutChart.Tooltips |
| 90 | Avg_Account_Balance | Fact_Transaction | x | T3 | T3 | CALCULATE; T2:AVERAGEX,VALUES,VAR; T3:CALCULATETABLE,CT(AVERAGEX) | AVERAGEX, CALCULATE, CALCULATETABLE, MAX, REMOVEFILTERS, VALUES | — | card.Values, lineClusteredColumnComboChart.Y2 |
| 91 | Neg Balance Trans | Fact_Transaction | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, KEEPFILTERS | Trans Count | lineClusteredColumnComboChart.Y |
| 92 | Overdraft Accounts | Fact_Transaction |  | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, DISTINCTCOUNT, KEEPFILTERS | — | (phụ thuộc) |
| 93 | Sanction Count | Fact_Transaction | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, KEEPFILTERS | Trans Count | lineClusteredColumnComboChart.Tooltips |
| 94 | Sanction Interest | Fact_Transaction | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, KEEPFILTERS | Trans Amount | lineClusteredColumnComboChart.Tooltips |
| 95 | Total_Credit_Inflow | Fact_Transaction | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, KEEPFILTERS | Trans Amount | card.Values, lineClusteredColumnComboChart.Y |
| 96 | Total_Debit_Outflow | Fact_Transaction | x | T3* | T3 | CALCULATE; T3:KEEPFILTERS | CALCULATE, KEEPFILTERS | Trans Amount | card.Values, lineClusteredColumnComboChart.Y |
| 97 | Avg_Days_To_Company Δ | Fact_CRM_Complaint |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | BLANK, CALCULATE, DATE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Avg_Days_To_Company | (phụ thuộc) |
| 98 | Complaints MA3 | Fact_CRM_Complaint | x | T4 | T4 | CALCULATE; T2:HASONEVALUE,IF,VAR; T4:REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, DIVIDE, HASONEVALUE, IF, MAX, REMOVEFILTERS | Complaints | lineStackedColumnComboChart.Y2 |
| 99 | Complaints Δ | Fact_CRM_Complaint |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, DATE, DIVIDE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Complaints | (phụ thuộc) |
| 100 | Dispute_Rate Δ | Fact_CRM_Complaint |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | BLANK, CALCULATE, DATE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Dispute_Rate | (phụ thuộc) |
| 101 | Relief Rate Δ | Fact_CRM_Complaint |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | BLANK, CALCULATE, DATE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Relief Rate | (phụ thuộc) |
| 102 | SLA_Timely_Rate Δ | Fact_CRM_Complaint |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | BLANK, CALCULATE, DATE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | SLA_Timely_Rate | (phụ thuộc) |
| 103 | Active_Monthly_Payment Δ | Fact_Loan |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, DATE, DIVIDE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Active_Monthly_Payment | (phụ thuộc) |
| 104 | Bad_Debt_Principal Δ | Fact_Loan |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, DATE, DIVIDE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Bad_Debt_Principal | (phụ thuộc) |
| 105 | Bad_Debt_Ratio_Count Δ | Fact_Loan |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | BLANK, CALCULATE, DATE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Bad_Debt_Ratio_Count | (phụ thuộc) |
| 106 | Bad_Debt_Ratio_Value Δ | Fact_Loan |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | BLANK, CALCULATE, DATE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Bad_Debt_Ratio_Value | (phụ thuộc) |
| 107 | Loan Amount Δ | Fact_Loan |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, DATE, DIVIDE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Loan Amount | (phụ thuộc) |
| 108 | Loan Count Δ | Fact_Loan |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, DATE, DIVIDE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Loan Count | (phụ thuộc) |
| 109 | Avg Trans Value Δ | Fact_Transaction |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, DATE, DIVIDE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Avg Trans Value | (phụ thuộc) |
| 110 | Avg_Account_Balance Δ | Fact_Transaction |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, DATE, DIVIDE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Avg_Account_Balance | (phụ thuộc) |
| 111 | Neg Trans PM | Fact_Transaction |  | T4 | T4 | CALCULATE; T2:HASONEVALUE,IF,VAR; T4:REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, HASONEVALUE, IF, MAX, REMOVEFILTERS | Neg Balance Trans | (phụ thuộc) |
| 112 | Net_Cashflow Δ | Fact_Transaction |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | ABS, CALCULATE, DATE, DIVIDE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Net_Cashflow | (phụ thuộc) |
| 113 | Total_Credit_Inflow Δ | Fact_Transaction |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, DATE, DIVIDE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Total_Credit_Inflow | (phụ thuộc) |
| 114 | Total_Debit_Outflow Δ | Fact_Transaction |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, DATE, DIVIDE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Total_Debit_Outflow | (phụ thuộc) |
| 115 | Trans Count Δ | Fact_Transaction |  | T4 | T4 | CALCULATE; T2:DATE,FILTER,IF,INT,MOD,VALUES,YEAR,VAR; T4:SAMEPERIODLASTYEAR,REMOVEFILTERS(Dim_Date)+lọc ngày | CALCULATE, DATE, DIVIDE, FILTER, IF, INT, ISBLANK, MAX, MOD, REMOVEFILTERS, SAMEPERIODLASTYEAR, VALUES, YEAR | Trans Count | (phụ thuộc) |
| 116 | Pareto Cum % | Fact_CRM_Complaint | x | T5 | T5 | T2:FILTER,IF,SELECTEDVALUE,SUMX,VAR; T3:ALLSELECTED,CT(ADDCOLUMNS); T5:ADDCOLUMNS | ADDCOLUMNS, ALLSELECTED, DIVIDE, FILTER, IF, ISBLANK, SELECTEDVALUE, SUMX | Complaints | lineClusteredColumnComboChart.Y2 |
| 117 | Top Branches Text | Fact_Loan | x | T5 | T5 | T2:FILTER,FORMAT,IF,VALUES,VAR; T3:CT(CONCATENATEX),CT(FILTER),CT(TOPN); T5:CONCATENATEX,TOPN | CONCATENATEX, COUNTROWS, FILTER, FORMAT, IF, ISBLANK, TOPN, VALUES | Bad_Debt_Ratio_Count, Loan Amount | shapeMap.Tooltips |
| 118 | Peak Hour Font Color | Fact_Transaction | x | T5 | T5 | T2:FILTER,IF,MAXX,MINX,VAR; T3:ALLSELECTED,CT(FILTER),CT(MAXX),CT(MINX); T5:CROSSJOIN | ALLSELECTED, BLANK, CROSSJOIN, DIVIDE, FILTER, IF, ISBLANK, MAXX, MINX | Trans Count (k) | pivotTable.objects |
| 119 | Peak Hour Top10 Icon | Fact_Transaction | x | T5 | T5 | T2:FILTER,IF,VAR; T3:ALLSELECTED,CT(FILTER),CT(PERCENTILEX.INC); T5:CROSSJOIN,PERCENTILEX.INC | ALLSELECTED, CROSSJOIN, FILTER, IF, ISBLANK, PERCENTILEX.INC | Trans Count (k) | pivotTable.objects |

---

## 4. Cột tính toán, bảng tính toán, calculation group (Nhom6)

**FACT:** có 7 cột tính toán (`Column.Type=2`). Giá trị của cả 7 cột **đã lưu sẵn trong VertiPaq**. `pbix-dump rows Fact_Loan` in được `age_at_loan` và `age_group_at_loan`, còn `pbix-dump verify` báo 110 cột, 0 lệch. Vì vậy viewer và mốc oracle **không cần tự tính** cột tính toán. Engine chỉ cần tính chúng khi người dùng tạo hoặc sửa cột (Phase E).

| Bảng | Cột | Kiểu (DataType) | Hàm | Row context / RELATED | Biểu thức |
|---|---|---|---|---|---|
| Dim_Date | MonthIndex | Int64 | BLANK, IF | row context | `IF ( Dim_Date[date_key] = -1, BLANK (), Dim_Date[year] * 12 + Dim_Date[month_num] )` |
| Fact_Transaction | trans_hour | Int64 | HOUR | row context | `HOUR ( Fact_Transaction[trans_timestamp] )` |
| Dim_District | branch_label | String | — (chỉ `&`) | row context | `Dim_District[city] & ", " & Dim_District[state_abbrev]` |
| Dim_Date | month_start | DateTime | BLANK, DATE, IF | row context | `IF ( Dim_Date[date_key] = -1, BLANK (), DATE ( Dim_Date[year], Dim_Date[month_num], 1 ) )` |
| Fact_Loan | age_at_loan | Int64 | BLANK, DAY, IF, ISBLANK, MONTH, RELATED, YEAR | row context + RELATED | `VAR b = RELATED ( Dim_Client[birth_date] ) VAR d = RELATED ( Dim_Date[full_date] ) RETURN IF ( ISBLANK ( b ) \|\| ISBLANK ( d ), BLANK (), YEAR ( d ) - YEAR ( b ) - IF ( MONTH ( d ) * 100 + DAY ( d ) < MONTH ( b ) * 100 + DAY ( b ), 1, 0 ) )` |
| Fact_Loan | age_group_at_loan_order | Int64 | ISBLANK, SWITCH, TRUE | row context; phụ thuộc cột tính toán age_at_loan | `VAR a = Fact_Loan[age_at_loan] RETURN SWITCH ( TRUE (), ISBLANK ( a ), 9, a < 25, 1, a < 35, 2, a < 50, 3, a < 65, 4, 5 )` |
| Fact_Loan | age_group_at_loan | String | ISBLANK, SWITCH, TRUE | row context; phụ thuộc cột tính toán age_at_loan | `VAR a = Fact_Loan[age_at_loan] RETURN SWITCH ( TRUE (), ISBLANK ( a ), "Unknown", a < 25, "<25", a < 35, "25-34", a < 50, "35-49", a < 65, "50-64", "65+" )` |

Kiểu dữ liệu: 2 là String, 6 là Int64, 9 là DateTime. Ghi chú về các cột:
- Cả 7 cột đều chạy trong row context.
- Chỉ `age_at_loan` cần `RELATED`, đi qua hai quan hệ M:1: Fact_Loan → Dim_Client và Fact_Loan → Dim_Date.
- `age_group_at_loan*` phụ thuộc vào một cột tính toán khác (`age_at_loan`), nên khi tính lại phải theo thứ tự phụ thuộc.
- Không cột nào dùng CALCULATE, nên không có context transition trong cột tính toán.

**FACT về các đối tượng khác:**
- Calculated table: 0. Mọi partition đều có `Type=4` (M/Power Query, `Csv.Document`).
- Calculation group: 0 (`CalculationGroup` và `CalculationItem` đều rỗng).
- `Calendar`: 0. `Function` (UDF DAX): 0.
- RLS: có 4 role (`Vung Northeast/Midwest/South/West`), mỗi role dùng filter `Dim_Account[branch_region] = "<vùng>"`.
- `FormatStringDefinition`: có 19 bản ghi, 14 trong số đó thuộc tập 119.

---

## 5. Mô hình Nhom6

**Quan hệ (FACT,** từ `pbix-dump relationships` và bảng `Relationship`). Cả 14 quan hệ đều là **M:1**, `CrossFilteringBehavior=1` (lọc một chiều), `SecurityFilteringBehavior=1`, `JoinOnDateBehavior=1`, `RelyOnReferentialIntegrity=0`.

| # | Từ (nhiều) | Tới (một) | Active |
|---:|---|---|:-:|
| 1 | Fact_Loan[loan_date_key] | Dim_Date[date_key] | x |
| 2 | Fact_Loan[account_key] | Dim_Account[account_key] | x |
| 3 | Fact_Loan[client_key] | Dim_Client[client_key] | x |
| 4 | Fact_Loan[disbursed_district_key] | Dim_District[district_key] | x |
| 5 | Fact_Loan[loan_profile_key] | Dim_Loan_Profile[loan_profile_key] | x |
| 6 | Fact_CRM_Complaint[received_date_key] | Dim_Date[date_key] | x |
| 7 | Fact_CRM_Complaint[sent_date_key] | Dim_Date[date_key] | **inactive** |
| 8 | Fact_CRM_Complaint[client_key] | Dim_Client[client_key] | x |
| 9 | Fact_CRM_Complaint[issue_key] | Dim_CRM_Issue[issue_key] | x |
| 10 | Fact_CRM_Complaint[channel_response_key] | Dim_CRM_Channel_Response[channel_response_key] | x |
| 11 | Fact_Transaction[date_key] | Dim_Date[date_key] | x |
| 12 | Fact_Transaction[account_key] | Dim_Account[account_key] | x |
| 13 | Fact_Transaction[client_key] | Dim_Client[client_key] | x |
| 14 | Fact_Transaction[trans_type_key] | Dim_Trans_Type[trans_type_key] | x |

Hình dạng mô hình (FACT):
- Đây là star schema với 3 bảng fact.
- Mọi quan hệ tới Dim_Date đi qua `date_key`, là số nguyên dạng yyyymmdd, không phải cột ngày.
- **Không có quan hệ** giữa Dim_Account và Dim_District, Dim_Account và Dim_Client, Dim_District và Dim_Client. Muốn lọc chéo giữa các cặp này thì chỉ có thể dùng TREATAS (họ D4) hoặc đi qua một bảng fact.
- Quan hệ inactive duy nhất chỉ được `Complaints_Sent` dùng, mà measure này nằm ngoài 119. Report vì thế không kích hoạt USERELATIONSHIP.

**Bảng ngày (FACT):**
- `Dim_Date` có `Table.DataCategory = 'Time'`, `full_date` (DateTime) có `IsKey=1`. Nghĩa là bảng **đã Mark as date table, theo cột `full_date`**.
- Auto date/time bị tắt (`__PBI_TimeIntelligenceEnabled=0`), không có LocalDateTable.
- Bảng có 2.922 dòng, đủ mọi ngày từ 2011-01-01 tới 2018-12-31. Không có dòng `date_key=-1` hay năm 9999, nên nhánh `IF(date_key = -1, BLANK(), …)` của `MonthIndex` và `month_start` không bao giờ chạy.
- `MonthIndex = year*12 + month`, ví dụ 2011-07 cho ra 24139.

**Suy đoán (theo tài liệu công khai về "Mark as date table"):** khi CALCULATE lọc trên cột ngày của một date table đã đánh dấu, engine tự thêm `REMOVEFILTERS` trên toàn bảng ngày. Measure của Nhom6 luôn tự ghi `REMOVEFILTERS(Dim_Date)` nên kết quả không phụ thuộc hành vi này, nhưng engine vẫn nên cài cho đúng.

**Hierarchy (FACT, 6 cái):**

| Bảng | Hierarchy | Các cấp (cột) |
|---|---|---|
| Dim_Date | Thời gian | Năm (year) › Quý (quarter_name) › Tháng (month_name) › Ngày (day_of_month) |
| Dim_Account | Chi nhánh | Vùng (branch_region) › Bang (branch_state_name) › Chi nhánh (branch_city) |
| Dim_Client | Địa lý KH | Vùng (client_region) › Bang (client_state_name) › Chi nhánh (client_city) |
| Dim_District | Địa lý | Vùng (region) › Bang (state_name) › Chi nhánh (branch_label, là cột tính toán) |
| Dim_CRM_Issue | Sản phẩm | Sản phẩm (product) › Sản phẩm con (sub_product) › Vấn đề (issue) |
| Dim_Trans_Type | Loại giao dịch | Chiều tiền (trans_type) › Nghiệp vụ (operation) › Mục đích (trans_purpose) |

**Sort by column (FACT, 6 cặp):** day_name→day_of_week, month_name→month_num, quarter_name→quarter_num, age_group_current→age_group_order, age_group_at_loan→age_group_at_loan_order, days_bucket→days_bucket_order.

**Các thuộc tính model khác (FACT):** `DiscourageImplicitMeasures=1`, nên report không có projection `Aggregation` nào (kiểm tra cho ra 0). Culture là `en-US`.

**Dung lượng (FACT):** Fact_Transaction 1.056.320 dòng, Fact_CRM_Complaint 23.419, Dim_Client 5.370, Dim_Account 4.501, Dim_Date 2.922, Fact_Loan 682, Dim_District 77, Dim_CRM_Issue 58, Dim_Loan_Profile 47, Dim_CRM_Channel_Response 42, Dim_Trans_Type 14.

---

## 6. Visual và hình dạng truy vấn cho Phase C

**FACT, theo loại visual (134 visual):**

| Loại | Số | Field well (projection) | Ghi chú |
|---|---:|---|---|
| card | 50 | 1 measure trong `Values` | 23 card có thêm 1 measure màu trong `objects` |
| image | 30 | không có | trang trí |
| slicer | 17 | `Values`: 15 projection cột, 9 projection cấp hierarchy | tất cả ở chế độ Dropdown; d1 có 5, d2 có 6, d3 có 6, d4 không có |
| textbox | 7 | không có | không có measure động |
| actionButton | 5 | không có | 2 cái ẩn |
| clusteredBarChart | 4 | Category, Series (1), Y, Tooltips | |
| lineClusteredColumnComboChart | 4 | Category (cột hoặc hierarchy), Y, Y2, Tooltips | 3 cái có màu theo measure |
| lineStackedColumnComboChart | 3 | Category, Series, Y, Y2, Tooltips | |
| donutChart | 3 | Category (cấp 1 active, các cấp sau để drill), Y, Tooltips | |
| lineChart | 3 | Category, Series, Y, Tooltips | 1 cái ẩn, dùng cho bookmark |
| pageNavigator | 3 | không có | |
| pivotTable | 2 | Rows, Columns (có hierarchy), Values | cả 2 có màu hoặc icon theo measure |
| shapeMap | 1 | Category = Dim_District[state_name], Tooltips | màu theo `Branch NPL Color` |
| hundredPercentStackedColumnChart | 1 | Category, Series, Y | |
| treemap | 1 | Group (2 cấp), Values, Tooltips | |

Số visual cần truy vấn dữ liệu: 50 card, 17 slicer, 22 biểu đồ hoặc bảng. Theo trang: d1 có 24, d2 có 24, d3 có 24, d4 có 17.

**Nhóm theo (group-by) của 22 biểu đồ và bảng (FACT):**
- Ở trạng thái ban đầu (chỉ tính projection active): 15 visual nhóm theo 1 cột, 7 visual nhóm theo 2 cột.
- Nếu tính cả các cấp drill: 9 visual có 1 cột, 8 có 2, 4 có 3, 1 có 4.
- 3 visual có drill hierarchy: Thời gian (Năm › Quý › Tháng) trên 2 combo, Chi nhánh (Vùng › Bang › Chi nhánh) trên 1 pivot.
- Mỗi visual cần 1 tới 6 measure, tính cả measure định dạng có điều kiện. Phổ biến nhất là 3 measure (9 visual).
- 7 biểu đồ hoặc bảng có measure định dạng có điều kiện. Measure này phải được tính theo **cùng** group-by của visual.

**Cột nhóm theo phổ biến (FACT, tính cả slicer và các cấp drill):**

| Cột | Số lần |
|---|---:|
| Dim_Client[age_group_current] | 6 |
| Dim_Date hierarchy Năm, Quý, Tháng | 4 mỗi cấp |
| Dim_CRM_Issue[product] | 4 |
| Dim_Date[year], Dim_Date[year_month], Dim_Loan_Profile[status_vn], Dim_CRM_Channel_Response[submitted_via] | 3 mỗi cột |

Ngoài ra có `Fact_Transaction[trans_hour]` × `Dim_Date[day_name]` (pivot heatmap 24×7) và `Fact_Loan[age_group_at_loan]`.

**Sắp xếp (FACT):**
- 18 visual dùng thứ tự mặc định.
- 2 visual sắp tăng theo cột: `month_name` và `age_group_at_loan`. Cả hai cột đều có sort-by-column, nên truy vấn phải mang theo cả cột dùng để sắp.
- 2 visual sắp **giảm theo measure**: Pareto sắp theo `[Complaints]`, D4 theo `[D4 Complaints]`.

**Filter (FACT):**
- Cấp report, 2 filter:
  - `Dim_Date[year] NOT IN {9999}`. Filter này không loại dòng nào vì không có năm 9999.
  - `Dim_Client[client_region] NOT IN {'Unknown'}`. Filter này **có tác dụng**: nó lọc mọi bảng fact nối với Dim_Client, nên mọi phép so với oracle phải áp dụng filter này.
- Cấp trang: chỉ trang d4. Trang này có `pageBinding` kiểu Drillthrough với 4 tham số: `Dim_Account[branch_city]`, `Dim_Account[branch_state_name]`, `Dim_District[city]`, `Dim_District[state_name]`. Trang ẩn ở chế độ xem (`HiddenInViewMode`).
- Cấp visual: chỉ 1 filter, trên pivot heatmap: `trans_hour NOT IN {17}`.
- Không có filter TopN, RelativeDate hay Advanced nào.
- Có 2 bookmark (`Q1.3 · Giờ × Thứ` và `Q1.3 · Tháng trong năm`). Chúng không mang measure, chỉ dùng để bật hoặc tắt visual.
- Không có `reportExtensions.json`, tức là không có measure cấp report.

**Hình dạng truy vấn Phase C cần có. Suy đoán**, dựa trên mô tả công khai về truy vấn Power BI sinh ra (DAX Studio, Performance Analyzer). Cần xác nhận bằng cách bắt truy vấn thật trong VM:
- **Card:** `SUMMARIZECOLUMNS(<bảng filter>, "v", [M])`, hoặc `ROW("v", CALCULATE([M], <filters>))`. Không có group-by.
- **Slicer:** lấy giá trị phân biệt của 1 cột, hoặc nhiều cấp hierarchy, có sắp xếp. Thường kèm `TOPN` để giới hạn dữ liệu.
- **Biểu đồ:** `SUMMARIZECOLUMNS(col1[, col2], <filters>, "m1", [M1], …)`, rồi `TOPN(<giới hạn>, …)` và `ORDER BY`. Khi cột có sort-by-column thì phải thêm cột đó vào group-by.
- **Pivot (2 cái):** cần tổng phụ, nên phải có `ROLLUPADDISSUBTOTAL` / `ISSUBTOTAL`, hoặc engine tự tính hàng tổng.
- **Filter từ slicer và report:** truyền vào dưới dạng bảng filter (`TREATAS({…}, col)` hoặc `FILTER(ALL(col), …)`), và dùng `KEEPFILTERS` cho filter cấp visual.
- **Shadow context cho ALLSELECTED:** cả 7 measure ALLSELECTED trong 119 cần biết "phần mà người dùng đã chọn". Vì vậy truy vấn phải tách được filter bên ngoài (slicer, report, trang) khỏi group-by của visual.
- **Cross-filter giữa các visual:** sinh thêm filter, cùng dạng với filter của slicer.

---

## 7. Phạm vi thứ cấp: Nhóm 3 và Nhóm 2

**FACT, Nhóm 3** (`dashboard_DW&BI_nhom_3_20252.pbix`, phiên bản 1.28, Layout cũ):
- 125 measure, **5 measure ở trạng thái lỗi** (`Measure.State=5`): `Cảnh báo CR`, `Year`, `Quarter`, `Trạng thái giao hàng`, `Nhóm thời gian giao hàng`. Ví dụ `Cảnh báo CR` tham chiếu `dim_date[Year]`, nhưng dim_date không có cột `Year`.
- `pbix-dump info` báo "52 calc columns". Thực tế chỉ **10 cột của người dùng**. 42 cột còn lại thuộc 6 `LocalDateTable_*` và 1 `DateTableTemplate_*`, do auto date/time sinh ra (`__PBI_TimeIntelligenceEnabled=1`).
- Có 7 calculated table, đều là bảng auto date: `Calendar(Date(Year(MIN(col)),1,1), Date(Year(MAX(col)),12,31))`.
- Có 14 quan hệ của người dùng, cộng 6 quan hệ tới LocalDateTable. Trong 14 quan hệ:
  - **2 quan hệ lọc hai chiều**: `fact_web_traffic[date]→dim_date` (M:1) và `fact_order_items[order_id]→fact_returns[order_id]` (**M:M**);
  - 1 quan hệ inactive: `fact_order_items[zip]→dim_geography`.
- Không bảng nào được Mark as date table.
- `DATEADD(dim_date[date_key], -1, MONTH)` được dùng trên `date_key` (DateTime) của một bảng ngày **chưa đánh dấu**.
- Cột tính toán `dim_customer[Customer Purchase Status]` dùng `CALCULATE(DISTINCTCOUNT(fact_order_items[order_id]))`. Đây là **context transition trong cột tính toán**.
- Có `SWITCH(<giá trị>, …)` dạng so khớp giá trị, không phải `SWITCH(TRUE(), …)`.
- Context transition trong iterator xuất hiện ở 11 measure, qua `FILTER` và `AVERAGEX(ALL(dim_date), [measure])`.

**FACT, Nhóm 2** (`Nhóm 2 - Financial Service .pbix`, phiên bản 1.28, Layout cũ):
- 23 measure, không measure nào lỗi.
- `pbix-dump info` báo "48 calc columns". Thực tế chỉ **6 cột của người dùng**, 42 cột còn lại là auto date (6 LocalDateTable và 1 template).
- Có 7 calculated table auto date.
- Có 10 quan hệ của người dùng, cộng 6 quan hệ auto date. Trong 10 quan hệ:
  - **2 quan hệ 1:1 lọc hai chiều**: DimCard↔DimDisposition và DimClient↔DimDisposition;
  - 1 quan hệ inactive: `FactReview[Client_id]→DimClient`.
- Không bảng nào được Mark as date table.
- Tên cột không phân biệt hoa thường. `DATEADD(DimDate[date], -1, YEAR)` chạy được dù cột tên là `Date`.
- `DIVIDE` dùng 3 đối số (có giá trị thay thế).
- Cột tính toán `FactTransaction[Account Segment]` dùng `CALCULATE(SUM(…), ALLEXCEPT(FactTransaction, FactTransaction[account_id]))`, tức context transition cộng với ALLEXCEPT.
- Cột tính toán `account_id (groups)` do tính năng Groups sinh ra, viết `SWITCH(TRUE, …)` với `TRUE` **không có ngoặc**, cùng `IN {"A5285"}`.
- Có tên cột chứa dấu chấm, ví dụ `[cplt_crm_review.stars]`.

**Hàm bổ sung, không có ở đâu trong Nhom6 (FACT):**

| Hàm | File | Nơi dùng (ví dụ) |
|---|---|---|
| `DATEADD` | Nhóm 3 (10 measure), Nhóm 2 (2 measure) | `Doanh Thu Kỳ Trước`, `Total Loan Amount Prev` |
| `QUARTER` | Nhóm 3 (1 measure, 3 cột tính toán) | `fact_inventory[Quarter]` |
| `COUNT` | Nhóm 2 (5 measure) | `Transaction Count` |
| `MIN` | Nhóm 2 (1 measure), và trong calculated table auto date của cả hai file | `Active Days` |
| `FLOOR` | Nhóm 2 (1 cột tính toán) | `FactTransaction[Amount Bin]` |
| `ALLEXCEPT` | Nhóm 2 (1 cột tính toán) | `FactTransaction[Account Segment]` |
| `CALENDAR` | cả hai file, chỉ trong calculated table auto date | `LocalDateTable_*` |

`ALL` có trong Nhóm 3 (3 measure) và có trong tập 168 của Nhom6, nhưng không có trong tập 119.

**Các đặc điểm ngữ nghĩa bổ sung cho Nhóm 2/3**, đều là FACT về cấu trúc. Hành vi chi tiết vẫn là **suy đoán** cho tới khi có oracle:
- Lọc hai chiều.
- Quan hệ M:M và 1:1.
- Time intelligence trên bảng ngày chưa đánh dấu nhưng nối bằng cột DateTime.
- Context transition trong cột tính toán.
- Measure lỗi phải báo lỗi giống Power BI.
- Auto date/time: report có thể dùng biến thể `[col].[Date]` qua LocalDateTable. Measure không dùng cú pháp này (grep `].[` cho ra 0). Phần report Layout cũ của hai file chưa được quét.

**Lưu ý:** dữ liệu của cột tính toán và bảng auto date cũng đã lưu sẵn trong VertiPaq. Đây là **suy đoán**, theo cùng cơ chế với Nhom6, và chưa chạy `verify` trên hai file này. Nếu đúng thì `CALENDAR` cùng các hàm của cột tính toán chỉ cần ở Phase E.

---

## 8. Kết luận

### 8.1 Hàm bắt buộc cho mốc "119 measure Nhom6 khớp oracle" (FACT: 43 hàm)

| Nhóm | Hàm |
|---|---|
| Tổng hợp (5) | SUM, AVERAGE, COUNTROWS, DISTINCTCOUNT, MAX (cả dạng một cột và dạng hai đối số vô hướng) |
| Iterator (6) | SUMX, AVERAGEX, MINX, MAXX, CONCATENATEX, PERCENTILEX.INC |
| Filter và ngữ cảnh (7) | CALCULATE, CALCULATETABLE, FILTER, REMOVEFILTERS, KEEPFILTERS, ALLSELECTED, TREATAS |
| Thông tin (4) | ISBLANK, ISFILTERED, HASONEVALUE, SELECTEDVALUE |
| Time intelligence (1) | SAMEPERIODLASTYEAR (với đối số là bảng ngày một cột lấy từ biến) |
| Logic (4) | IF, SWITCH, TRUE, COALESCE |
| Toán (4) | DIVIDE (2 đối số), INT, MOD, ABS |
| Chuỗi (1) | FORMAT (các mẫu: `0.0%`, `0%`, `0.0`, `#,0.0`, `$#,0.0`) |
| Ngày giờ (4) | DATE, YEAR, MONTH, DATEDIFF (đơn vị MONTH) |
| Bảng (5) | VALUES, SUMMARIZE, ADDCOLUMNS, TOPN, CROSSJOIN |
| Quan hệ (1) | RELATED |
| Khác (1) | BLANK |

Toán tử cần có: `+ - * /`, `= <> < > <= >=`, `&& || NOT`, `&`, `IN {…}`. Ngoài ra cần `VAR`/`RETURN` (kể cả lồng nhau) và table constructor `{}`.

Ngữ nghĩa phải đúng. Đây là **suy đoán về mức rủi ro**, dựa trên tài liệu DAX công khai, và cần kiểm bằng oracle:
- **BLANK.** `BLANK = 0` cho TRUE. `ISBLANK(d) || d = 0`. `[x] + 0` biến BLANK thành 0. DIVIDE cho BLANK khi chia cho 0 hoặc cho BLANK. So sánh `<` và `>` với BLANK. `&` với BLANK cho chuỗi rỗng. Khi nối chuỗi với số, số tự đổi thành chuỗi (`" (T1–T" & MONTH(endDt)`).
- **Context transition** khi gọi measure trong iterator hoặc FILTER, và với `CALCULATE` lồng trong `AVERAGEX(accts, …)`.
- **ALLSELECTED** cần shadow filter context lấy từ truy vấn hoặc visual.
- **KEEPFILTERS** giao filter mới với filter đang có, thay vì ghi đè.
- **TREATAS** với bảng nhiều cột lấy từ SUMMARIZE.
- **Lineage** của biến bảng: `curDates` dùng làm filter, rồi qua `SAMEPERIODLASTYEAR`.
- **SAMEPERIODLASTYEAR**: cách lùi ngày cuối tháng và ngày 29/2.
- **ISFILTERED** với filter drill-through.
- **FORMAT** theo culture `en-US`.
- **PERCENTILEX.INC** dùng nội suy.
- **CONCATENATEX** có tham số sắp xếp.
- **TOPN** khi có giá trị bằng nhau.

### 8.2 Hàm nên có thêm

- **Đủ 168 measure Nhom6 (+3):** ALL, RANKX (`DESC`, `DENSE`), USERELATIONSHIP. Riêng USERELATIONSHIP cần quan hệ inactive.
- **Mức truy vấn và DAX Query View (+6, theo kế hoạch Phase B và §6):** `EVALUATE`, `DEFINE MEASURE/VAR`, `ORDER BY`, `SUMMARIZECOLUMNS`, `ROW`, `ROLLUPADDISSUBTOTAL`/`ISSUBTOTAL` cho pivot. `TOPN`, `TREATAS`, `KEEPFILTERS` đã có ở 8.1.
- **Hiển thị (Phase C):** `SELECTEDMEASURE`, cho 19 dynamic format string.
- **Nhóm 2/3 (+7):** DATEADD, QUARTER, COUNT, MIN, FLOOR, ALLEXCEPT, DIVIDE 3 đối số. Thêm `CALENDAR` nếu phải tự tính bảng auto date. Nhóm này còn cần thêm ngữ nghĩa: lọc hai chiều, quan hệ M:M và 1:1, TI trên bảng chưa đánh dấu, context transition trong cột tính toán, so khớp tên không phân biệt hoa thường, và báo lỗi measure.
- **Cột tính toán (Phase E):** HOUR, DAY (Nhom6), SWITCH dạng giá trị, `TRUE` không ngoặc.

### 8.3 Ước lượng số hàm

| Mốc | Số hàm | Ghi chú |
|---|---:|---|
| 95 measure trực tiếp | 41 | FACT |
| **119 measure (mốc Phase B)** | **43** | FACT. Kế hoạch tổng ghi "khoảng 40", nên con số này hơi cao hơn |
| 119 measure cộng lớp truy vấn | khoảng 49 | 43 cộng khoảng 6 cấu trúc truy vấn |
| 168 measure Nhom6 | 46 | FACT. Cộng thêm HOUR, DAY, SELECTEDMEASURE thì toàn bộ DAX của Nhom6 dùng 49 hàm |
| Nhom6 + Nhóm 2 + Nhóm 3 | khoảng 56 | 49 cộng DATEADD, QUARTER, COUNT, MIN, FLOOR, ALLEXCEPT, CALENDAR |

**Suy đoán về khối lượng:** số hàm không phải phần tốn công nhất. Khoảng 25 trong 43 hàm là hàm vô hướng hoặc tổng hợp đơn giản. Phần khó nằm ở khoảng 8 cơ chế: filter context cùng context transition, KEEPFILTERS, ALLSELECTED với shadow context, TREATAS và lineage, time intelligence trên biến bảng, quan hệ (lan truyền filter một chiều), ngữ nghĩa BLANK, và FORMAT.

**Đề xuất chia gói (suy đoán, để orchestrator cân nhắc):**
- Gói 1, nền tảng: lexer/parser, evaluator vô hướng, BLANK, FORMAT. Mở khoá T0 và một phần T2.
- Gói 2: filter context, CALCULATE, KEEPFILTERS, REMOVEFILTERS, lan truyền filter qua quan hệ. Mở khoá T1 và T3*.
- Gói 3: iterator và context transition, RELATED, VALUES/SUMMARIZE/FILTER.
- Gói 4: ALLSELECTED, TREATAS, kèm lớp truy vấn SUMMARIZECOLUMNS.
- Gói 5: SAMEPERIODLASTYEAR và họ Δ (51 measure).
- Gói 6: T5, gồm PERCENTILEX.INC, CONCATENATEX, TOPN, CROSSJOIN, ADDCOLUMNS.

Chọn **pilot** là họ Δ của một bảng fact cộng card tương ứng: nó đi qua gần như mọi gói, và chỉ cần 3 khuôn measure là phủ 51/119.

**Hiệu năng (suy đoán):** cần đo sớm. Fact_Transaction có 1.056.320 dòng. `Avg_Account_Balance` lặp qua khoảng 4.501 tài khoản, mỗi vòng có 2 CALCULATE. Heatmap 24×7 ô, mỗi ô lại chạy CROSSJOIN 168 ô cho `PERCENTILEX` và `MINX`/`MAXX`, tức khoảng 28 nghìn lần tính measure mỗi lần render.

---

## Phụ lục: cách chạy lại (chỉ đọc)

```
S=/private/tmp/claude-501/-Users-macprom114-Desktop-PowerBINative/39e5fdc8-d27c-46a2-b750-47ff2adaa733/scratchpad
pbix-dump extract <file.pbix> metadata.sqlitedb $S/b/data/meta/<x>.sqlitedb
python3 -I $S/b/scripts/daxscan.py $S/b/data/meta/n6.sqlitedb $S/b/data/n6.json $S/b/data/n6zip/Report
python3 -I $S/b/scripts/visscan.py $S/b/data/n6zip/Report/definition $S/b/data/n6vis.json
python3 -I $S/b/scripts/report.py $S/b/data/n6.json $S/b/data/n3.json $S/b/data/n2.json $S/b/data/n6where.json $S/b/data/out
```

Dữ liệu trung gian:
- `$S/b/data/n6.json`, `n3.json`, `n2.json`: kết quả quét từng measure.
- `$S/b/data/n6vis.json`: visual.
- `$S/b/data/out/summary.json`
- `$S/b/data/out/*.md`: các bảng.
