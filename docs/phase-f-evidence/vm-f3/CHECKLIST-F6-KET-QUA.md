# Kết quả gate F-Query (T066), 2026-11-16: ĐẠT 4/4 + phần (b)

Power BI Desktop 2.159 trong VM "Windows 11", Claude lái theo lời cho phép của người dùng (2026-11-16). Bốn file do `FGateTests.taoFileGateTruyVan` ghi, M trỏ tới `C:\Users\bacpew\f6\sales_2026.csv/.xlsx` (đã chép vào VM). Ảnh cắt (không lộ tài khoản): `f6-q1-pq-4-buoc.png`, `f6-q2-pq-6-buoc.png`, `f6-q3-pq-kept-first-rows1.png`.

| File | Kết quả | Quan sát |
|---|---|---|
| `q1-csv.pbix` | ĐẠT | Mở không báo lỗi; Table view `sales_2026` "(500 rows)", cột OrderID…Amount; Transform data: truy vấn `sales_2026` đúng 4 bước Source, Promoted Headers, Changed Type, Kept First Rows, công thức `Table.FirstN(#"Changed Type",500)`, xem trước 8 cột 500 dòng, "PREVIEW DOWNLOADED" (đọc được CSV ở đường dẫn trong M). Làm mới riêng bảng (chuột phải bảng → Refresh → Schema and data): vẫn 500 dòng. |
| `q2-excel.pbix` | ĐẠT | Mở được; bảng `Sales` "(50 rows)", sắp Qty giảm dần (19 rồi 18); truy vấn `Sales` có Source, Navigation, Promoted Headers, Changed Type, Sorted Rows, Kept First Rows (`Table.FirstN(#"Sorted Rows",50)`); xem trước tải được từ Excel. |
| `q3-thay.pbix` | ĐẠT | Mở được; `sales_2026` "(20 rows)", hàng 1 đến 20 khớp CSV; truy vấn có Source, Promoted Headers, Changed Type, Kept First Rows, **Kept First Rows1** = `Table.FirstN(#"Kept First Rows",20)`. |
| `q4-xoa.pbix` | ĐẠT | Mở được; không còn `sales_2026`; đủ 11 bảng Nhom6 (Dim_Account "4,501 rows" có dữ liệu). |

**(b) BI Pro mở file Desktop lưu:** trong `q1-csv.pbix` kéo cột `Price` lên (Desktop tự thêm bước `Reordered Columns`), Close, Apply changes, Refresh bảng, lưu, chép về thành `q1-desktop.pbix`. `FGateTests.moFileDoDesktopLuuLai` (heavy): BI Pro mở được, `sales_2026` 500 dòng, 12 bảng, truy vấn đủ 5 bước đúng tên (Source, Promoted Headers, Changed Type, Kept First Rows, Reordered Columns), `Table.FirstN(#"Changed Type",500)` giữ nguyên văn, bước cuối `Table.ReorderColumns(#"Kept First Rows",{"OrderID", "OrderDate", "Region", "Price", "CustomerID", "Product", "Qty", "Amount"})`. ĐẠT.

## Ghi nhận thêm (không phải lỗi của BI Pro)

- Truy vấn gốc của Nhom6 (Fact_Transaction…) báo `DataSource.NotFound ... C:\Users\LOQ\Documents\DWH_Nhom6\olap_data\...csv` khi mở Power Query Editor: nguồn của file gốc không có trong VM; bảng vẫn có dữ liệu đã nạp.
- Desktop: sau "Apply changes" trong Power Query, bảng được sửa về 0 dòng kèm dải "Some of the tables have incomplete or no data" cho tới khi Refresh bảng đó. Menu chuột phải bảng ở Data pane: Refresh ▸ Schema and data / Schema / Data. BI Pro không cần theo (không có hành vi Refresh), ghi cho T063 (ca nguồn di chuyển).
- Tên bước Desktop sinh khi thêm bước lặp: `Kept First Rows1`; kéo cột trong lưới sinh `Reordered Columns` (M `Table.ReorderColumns(prev,{tất cả cột theo thứ tự mới})`), chưa có trong `StepFactory`.
- Bấm vào cửa sổ Desktop: lần đầu thường chỉ lấy tiêu điểm; ảnh `shot.sh` → toạ độ `vm.sh`: x = (x_ảnh − 48) × 1,064, y = (y_ảnh − 33) × 1,064 (đúng như ghi chú cũ).

Dọn: thư mục `C:\Users\bacpew\f6` và các file trong VM đã xoá; Desktop đã đóng.
