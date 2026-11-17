# VM-F2 (T032): Get Data CSV và Excel trên Desktop: chỉ mục quan sát

Buổi VM-F2 làm chung với VM-F1 (2026-11-15, Desktop 2.159, Claude lái VM); ghi chép đầy đủ ở `../vm-f1/QUAN-SAT.md`:

- Mục 2 (hộp thoại nạp): Text/CSV mở hộp xem trước với File Origin (65001 cho tệp có chữ Việt, 1252 cho tệp ASCII), Delimiter Comma,
  Data Type Detection "Based on first 200 rows"; Excel: Navigator liệt kê bảng đặt tên trước, rồi trang tính theo thứ tự chữ cái.
- Mục 3 (M sinh ra): CSV `Csv.Document(File.Contents(…),[Delimiter=",", Columns=8, Encoding=65001, QuoteStyle=QuoteStyle.None])` →
  `Promoted Headers` → `Changed Type`; Excel `Excel.Workbook(…, null, true)` → `Sales_Sheet` → `Promoted Headers` → `Changed Type`.
- Mục 4–5, 7: hàng `Column`, cách lưu VertiPaq, logic, chuỗi rỗng.

Bổ sung từ buổi khác:

- Tên trùng: Desktop thêm hậu tố ` (2)`, ` (3)`… (`Query1 (2)`, `sales_2026 (2)`, `sales_2026 (3)`: `../vm-f8/QUAN-SAT.md`). BI Pro
  `TableNaming.uniqueName` làm đúng như vậy; so tên không phân biệt hoa thường vẫn là [SUY ĐOÁN].
- Ô trống trong cột chuỗi của CSV là chuỗi rỗng, không phải null (`../vm-f1/CHECKLIST-KET-QUA.md`).
- Gate CSV/Excel (T046): `Nhom6_f1_a_mot_bang_csv` (`../vm-f1/CHECKLIST-KET-QUA.md`), `q1-csv.pbix`, `q2-excel.pbix` (`../vm-f3/CHECKLIST-F6-KET-QUA.md`): ĐẠT.
