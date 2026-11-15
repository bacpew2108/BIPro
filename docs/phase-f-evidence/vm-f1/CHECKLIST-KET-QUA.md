# Kết quả gate F-T3 đầy đủ (T026), 2026-11-15

Người làm: Claude lái Power BI Desktop 2.159.1231 trong VM (bạn cho phép trong phiên này), bằng `vm.sh`/`openv3.sh`. File chép vào VM, mở, không bấm Refresh, không lưu lại. Ảnh cắt chỉ giữ lưới dữ liệu hoặc hộp thoại.

```
Kết quả: ĐẠT 5/5 (file e đạt sau một vòng sửa, xem dưới)
```

| File | Kết quả trong Desktop | Ảnh |
|---|---|---|
| `Nhom6_f1_a_mot_bang_csv` | mở được, báo cáo D3 vẽ bình thường; Data pane có `sales_2026`; Table view "sales_2026 (10,000 rows)", `OrderDate` kiểu ngày ("Monday, March 2, 2026"), dòng 1 khớp CSV; bảng cũ `Dim_Account` "4,501 rows" | `f1-a-sales-2026-10000-dong.png` |
| `Nhom6_f1_b_ba_bang` | `Customers` "50 rows" (Khách 1…, Wholesale/Online/Retail), `Sales` "500 rows", `sales_2026` có mặt | `f1-b-ba-bang-sales-500-dong.png` |
| `Nhom6_f1_c_quan_he_measure` | Manage relationships có `sales_2026 (CustomerID)` → `Customers (CustomerID)`, nhiều-một, Active (chỉ mục quan hệ BI Pro ghi được Desktop chấp nhận) | `f1-c-quan-he-sales-customers.png` |
| `Nhom6_f1_d_100000_dong` | "Table: Lon (100,000 rows)"; ô trống đúng chỗ (dòng 0: `Tien`, `Ngay`, `GhiChu` trống), tiếng Việt đúng | `f1-d-lon-100000-dong.png` |
| `Nhom6_f1_e_null_moi_kieu` | "Table: Null (5 rows)": `So` 1, trống, 3, trống, 5; `Thuc` 1,5; 2,25; trống; trống; 0; `Ngay` ngày/trống đúng; `Chu` "Đà Nẵng", trống (NULL), "Huế", trống (chuỗi rỗng), "Đà Nẵng" | `f1-e-null-moi-kieu.png` |

Chưa xem trong Desktop: giá trị measure `Tong Amount` của file c (Desktop không tính lại khi mở; BI Pro mở lại đọc ra 3 654 202,84).

## Lỗi tìm được và đã sửa trong buổi này

File e lần đầu báo "Database consistency checks (DBCC) failed while checking the string store". Nguyên nhân: từ điển chuỗi có mục rỗng cần cờ "có chuỗi rỗng" trong tiêu đề trang (1 byte). Tôi nạp thêm `probe2.csv` (tiếng Việt + ô rỗng) vào Desktop, so `.dictionary` byte với bộ ghi, thấy lệch đúng một byte, sửa `VertiPaqWriter.stringDictionary` và thêm test vàng `HierarchyEncodingTests.tuDienChuoiCoMucRongKhopDesktop` (byte của Desktop). Bốn file kia không có chuỗi rỗng nên không bị.

Quan sát: Desktop đọc ô trống trong cột chuỗi của CSV là chuỗi rỗng (không phải NULL).

## Bổ sung: logic và cột ít giá trị (file e làm lại)

Bảng `Null` của file e thêm cột logic (`Dung` có ô trống, `Luon` hằng true), chuỗi hằng (`Hang`), chuỗi hai giá trị (`Hai`), ngày hằng (`NgayHang`). Lần đầu Desktop báo "DBCC failed while checking the 'H$Null…$Luon' table… segment map" (cột một giá trị cần cắt `H$` thành 4 đoạn). Sau khi sửa bộ ghi theo byte của Desktop, mở được: "Table: Null (5 rows)", `Dung` True/trống/False/True/True, `Luon` True cả năm dòng, `Hang` a, `Hai` x/y/x/y/x, `NgayHang` Thursday, January 1, 2026 (ảnh `f1-f-logic-hang-so-hai-gia-tri.png`).
