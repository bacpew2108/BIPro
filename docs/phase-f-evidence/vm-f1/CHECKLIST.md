# Gate F-T3 đầy đủ (T025, T026): file BI Pro lưu bảng nạp từ Get Data, mở trong Desktop

Các file do `Tests/BIProTests/Model/F3Nhom6Tests.swift` ghi ra `build/e-out/F3/` (bản sao Nhom6, ngoài git). Mỗi file đã được BI Pro mở lại và đối chiếu từng ô, tổng, số dòng với dữ liệu nguồn. Đây là bước kiểm trên Desktop (chép file vào VM, mở, không bấm Refresh).

| File | Nội dung | Kiểm trong Desktop |
|---|---|---|
| `Nhom6_f1_a_mot_bang_csv.pbix` | bảng `sales_2026` từ CSV, 10 000 dòng (số nguyên, thập phân, ngày, chuỗi) | mở không báo lỗi; Data view `sales_2026` ghi "10,000 rows"; cột `OrderDate` kiểu ngày; Sum `Qty` = 99 742; Sum `Amount` ≈ 3 654 202,84; bảng cũ của Nhom6 còn |
| `Nhom6_f1_b_ba_bang.pbix` | `sales_2026` (CSV) + `Sales` (500) + `Customers` (50) cùng lúc | ba bảng, số dòng 10 000, 500, 50 |
| `Nhom6_f1_c_quan_he_measure.pbix` | `sales_2026` + `Customers`, quan hệ `sales_2026[CustomerID]` → `Customers[CustomerID]`, measure `Tong Amount` | Model view có quan hệ; measure `Tong Amount` ≈ 3 654 202,84; chọn một khách thì tổng bảng bán thu hẹp |
| `Nhom6_f1_d_100000_dong.pbix` | bảng `Lon` 100 000 dòng, 5 cột, có ô trống | "100,000 rows"; `ThanhPho` 7 giá trị; `GhiChu` có 20 000 ô trống |
| `Nhom6_f1_e_null_moi_kieu.pbix` | bảng `Null` 5 dòng, ô trống ở mọi kiểu, "Đà Nẵng", "Huế", chuỗi rỗng | Sum `So` = 9; Sum `Thuc` = 3,75; một ô `Chu` trống, một ô `Chu` rỗng |

Ghi kết quả vào `CHECKLIST-KET-QUA.md` cùng thư mục (đạt/trượt từng file, thông báo lỗi nguyên văn nếu trượt; ảnh cắt không lộ tài khoản). Sau buổi: xoá file thử trong VM và `build/e-out/F3`.
