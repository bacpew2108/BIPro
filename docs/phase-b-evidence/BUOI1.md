# Phase B, buổi 1: kết quả quan sát và golden (2026-11-01)

Người dùng chạy trong Power BI Desktop trên VM Windows 11. File gốc nằm ở `~/Downloads/bipro-golden/`; bản trong repo đã chuẩn hoá tên (`01`→`O1`, `04`→`O4`, `08`→`O8`, `010`→`O10`). Hai file `.pbix` (54 MB) không chép vào repo.

- Golden: `Tests/DAXEngineTests/Golden/nhom6/` (12 file G0, G1, G3 và `manifest.tsv`).
- Quan sát: `docs/phase-b-evidence/observe/`.
- Power BI Desktop 2.159.883.0 64-bit (October 2026); Windows regional format: United States (en-US). Đã ghi vào `manifest.tsv` trong repo. Định dạng Copy không phụ thuộc locale (O2).

## Quan sát

| Mã | Kết quả (FACT) | Dùng cho |
|---|---|---|
| O1 | Lưới **hiển thị** đã định dạng: `0.33`, `-0.000001` hiện `0`, currency `1.23`, ngày `12/31/2018 12:00:00 AM`, boolean `True`. Thanh trên lưới có "Result 1 of 1" và nút **Copy**. | UI1 (định dạng lưới) |
| O2 | **Copy** lấy giá trị đầy đủ, không phụ thuộc locale: có dòng tiêu đề (cột measure trong ngoặc vuông `[int]`, cột của bảng dạng `Dim_Date[year]`), xuống dòng CRLF, số thực đủ để đọc lại (`0.3333333333333333`), không phân nhóm, dấu thập phân `.`, currency 4 chữ số (`1.2346`), ngày `Mon, 31 Dec 2018 16:03:36`, boolean `true` (biểu thức) hoặc `True` (cột boolean trong quick query), `Infinity`, `NaN`. BLANK và chuỗi rỗng đều là ô rỗng. | Bộ đọc golden (`scripts/oracle/compare-golden.py`) |
| O3 | Lỗi có dạng `Query (dòng, cột) thông báo`, dòng và cột đếm từ 1, **tab tính 1 cột** (O3d: `(3, 17)`). Thiếu `)` ở cuối: `The end of the input was reached.` (không có vị trí). Lỗi lúc chạy (`CONVERT`): `Failed to move the data reader to the next row.` (không vị trí). O3e (hai lỗi): chỉ báo **một** lỗi, ở `(5, 7)`. Mọi thông báo có kèm `Correlation Id`. | LANG (`SourceRange`), UI1 |
| O4 | O4a (`GENERATESERIES(1, 1200000)`): **Out of memory** trên VM. O4b có ảnh. O4c không chạy. Giới hạn hiển thị dùng số của Microsoft Learn (1.000.000 giá trị hoặc 15 MB). | UI1 |
| O5 | Một tab có ba EVALUATE, cái thứ hai lỗi lúc chạy: **không có kết quả nào** ("Resolve the error to see results"), kể cả Result 1 và Result 3. | UI1, cách đóng gói golden (mỗi truy vấn một file) |
| O7 | Tab truy vấn được lưu trong `.pbix` thành phần ZIP riêng: `DAXQueries/<tên tab>.dax` (UTF-16LE) và `DAXQueries/.pbi/daxQueries.json` (UTF-16LE, `{"version":"1.0.0","tabOrder":[…],"defaultTab":"…"}`). Khi lưu, Power BI còn thêm `DiagramLayout` và đổi `[Content_Types].xml`, `DataModel`, `SecurityBindings`. | Phase D (giữ tab khi BI Pro lưu file) |
| O8 | Đã lưu **kết quả** của các quick query (`O8-*.dax` chứa dữ liệu, không phải văn bản truy vấn). Văn bản truy vấn nằm trong ảnh `O8-*.png`. Column statistics có các cột Count, Distinct Values, Null Count, Min, Max, Median, Mean, Standard Deviation, Zeros, Evens, Odds, P25, P75, Range in Days/Months/Years. | UI3 |
| O9 | Format query: mỗi đối số một dòng, thụt lề bằng tab, `ORDER BY` thụt một tab dưới `EVALUATE`. | UI4 (DAXFormatter) |
| O10 | Bốn ảnh IntelliSense (`O10-a..d.png`). | UI2 |
| O12 | Ảnh Cancel (`O12-cancel.png`). | UI1 |

## Golden G0, G1, G3: đối chiếu với engine

Lệnh:

```
dax-run query ~/Downloads/Nhom6_Dashboard.pbix <out-dir> docs/phase-b-oracle/queries/G{0-total,1-year,3-rf-year}__*.dax
python3 scripts/oracle/compare-golden.py Tests/DAXEngineTests/Golden/nhom6 <out-dir>
```

**Kết quả cuối: 12/12 file khớp, 0 ô lệch.** Cả 119 measure (và cột thăm dò ISBLANK) khớp Power BI ở G0, G1 và G3.

Lần so đầu có 21 measure lệch. Ba lỗi engine đã sửa nhờ golden:

1. **Đếm trên tập rỗng trả BLANK** (COUNTROWS, COUNT, DISTINCTCOUNT). Golden: `Active Accounts` là BLANK ở năm không có giao dịch; engine trả 0.
2. **Lan truyền bộ lọc theo dòng phải chính xác.** Bộ lọc trên cột dense (ngày) và `FILTER(T, …)` trước đây được chiếu thành tập mã từng cột trước khi lan truyền. Với khoảng ngày không trọn năm, phép chiếu rộng hơn đáp án (Loan Count Δ lọt thêm 3 khoản vay đầu tháng 12/2017). Nay `Propagation.visibleRows` nhận `TableFilter` (tập dòng) và lan truyền qua chỉ mục quan hệ theo từng dòng.
3. **DATEADD/SAMEPERIODLASTYEAR với ngày cuối tháng:** ngày cuối tháng nguồn cho ngày cùng số ở tháng đích cộng mọi ngày còn lại tới hết tháng. Trước đây 28/02/2017 chỉ dịch thành 29/02/2016 và mất 28/02/2016 (Complaints Δ lệch đúng 3 khiếu nại của ngày đó).

Thêm: `SUMMARIZECOLUMNS` nhận `KEEPFILTERS(bảng bộ lọc)` (dạng G3 dùng cho bộ lọc cấp report).

Ghi chú: G1 và G3 giống hệt từng byte. Điều này khớp dự đoán (hai bộ lọc cấp report không loại dòng fact nào), nhưng không phân biệt được với việc dán nhầm. Engine cũng cho G1 = G3.

## Còn lại cho buổi 2

G2 (theo vùng), G5 (theo tháng), G6 (ngữ cảnh visual), G4, PA và các quan sát O6, O11, O13–O18. Tiêu chí xong Phase B còn cần G2, G5, G6.
