# Gate F-Query (T066): Desktop mở file BI Pro có truy vấn M; BI Pro mở file Desktop

Bốn file do `Tests/BIProTests/Model/FGateTests.taoFileGateTruyVan` ghi ra `build/f-out/f6/` (bản sao Nhom6 54 MB, ngoài git). Nguồn M trong file trỏ tới `C:\Users\bacpew\f6\sales_2026.csv` và `C:\Users\bacpew\f6\sales_2026.xlsx`, nên chép cả hai file mẫu (`build/f-out/samples/sales_2026.csv`, `sales_2026.xlsx`) vào thư mục đó trước khi mở. Chưa chạy trên Desktop (2026-11-16).

| File | Nội dung | Kiểm trong Desktop |
|---|---|---|
| `q1-csv.pbix` | bảng `sales_2026` từ CSV, bước thêm "Kept First Rows" (`Table.FirstN(#"Changed Type",500)`) | mở không báo lỗi; Data view `sales_2026` 500 dòng, Sum `Qty` = 5 063, Sum `Amount` ≈ 182 260,61; Transform data: truy vấn `sales_2026` có 4 bước đúng thứ tự Source, Promoted Headers, Changed Type, Kept First Rows, không lỗi; Refresh (CSV có ở đường dẫn trên): vẫn 500 dòng |
| `q2-excel.pbix` | bảng `Sales` từ Excel, bước "Sorted Rows" (Qty giảm dần) rồi "Kept First Rows" 50 | mở được; 50 dòng, Sum `Qty` = 924 (Max 19, Min 18); truy vấn có Source, Navigation, Promoted Headers, Changed Type, Sorted Rows, Kept First Rows; Refresh được |
| `q3-thay.pbix` | như q1 nhưng mở lại trong BI Pro, giữ 20 dòng đầu, lưu (thay dữ liệu bảng đã có trong file) | mở được; `sales_2026` 20 dòng, Sum `Qty` = 261, Sum `Amount` ≈ 10 137,98; truy vấn có bước "Kept First Rows" với 20 |
| `q4-xoa.pbix` | như q1 nhưng tắt Enable load rồi lưu (xoá bảng) | mở được; không còn bảng `sales_2026`; bảng cũ của Nhom6 còn đủ (11 bảng) |

(b) BI Pro mở file do Desktop tạo: trong Desktop mở `q1-csv.pbix`, thêm một bước (ví dụ Remove Columns `Price`), Close & Apply, lưu thành `q1-desktop.pbix`; chép về Mac, mở trong BI Pro: Ribbon "Biến đổi dữ liệu" liệt kê truy vấn `sales_2026` với bước mới đúng tên và M; bảng còn 500 dòng.

Ghi kết quả vào `CHECKLIST-F6-KET-QUA.md` cùng thư mục (đạt/trượt từng file, thông báo lỗi nguyên văn nếu trượt; ảnh cắt không lộ tài khoản). Sau buổi: xoá file thử trong VM, thư mục `C:\Users\bacpew\f6`, và `build/f-out/f6`.
