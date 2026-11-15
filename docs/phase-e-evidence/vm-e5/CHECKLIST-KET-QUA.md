# Gate Desktop, Câu chuyện 5 (TMDL View sửa được): kết quả (2026-11-14)

File `build/e-out/E5/Nhom6_e5.pbix` do BI Pro lưu (T2) sau khi sửa văn bản `tables/Dim_Account.tmdl` trong TMDL View rồi bấm Áp dụng: thêm `measure 'E_Tmdl Tong' = COUNTROWS(Dim_Account) + 1` (formatString 0, displayFolder "Thu muc TMDL", mô tả `///`) và thêm `isHidden` vào cột `branch_division`. Claude tự bấm chuột trên cửa sổ Parallels; bản sao đã xoá khỏi VM và Mac.

| Mục | Kết quả trong Power BI Desktop |
|---|---|
| Mở file | Đạt, không báo lỗi |
| Measure thêm bằng TMDL, thư mục "Thu muc TMDL" | Đạt: ngăn Data của `Dim_Account` có thư mục "Thu muc TMDL" |
| Cột `branch_division` ẩn | Đạt: ngăn Data và thẻ hiện biểu tượng ẩn |

Số liệu và mô tả của measure đã kiểm ở test `TMDLApplyTests` (mở lại file: biểu thức, thư mục, mô tả, định dạng đúng). Ảnh chụp toàn cửa sổ có địa chỉ tài khoản nên không đưa vào git.
