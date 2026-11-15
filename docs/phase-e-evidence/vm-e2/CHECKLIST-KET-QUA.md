# Gate Desktop, Câu chuyện 1 (measure): kết quả (2026-11-14)

File: `build/e-out/E1/Nhom6_e1.pbix` do BI Pro lưu (T2) từ bản sao Nhom6: thêm `E_Loan Amount = SUM(Fact_Loan[loan_amount])` và `E_Copy` (biểu thức chép từ `Net_Cashflow`, thư mục hiển thị `Thu muc E`, mô tả `mo ta E`), qua thanh công thức ở Table view. Bạn cho dùng VM; Claude điều khiển Desktop trên bản sao (đã xoá).

| Mục | Kết quả |
|---|---|
| Desktop mở file, không báo "file is corrupted" | Đạt (trang D3 hiện đủ dữ liệu) |
| `SecurityBindings` giữ nguyên, không cần bỏ | Đạt |
| `E_Loan Amount` có trong bảng `Fact_Loan` (ngăn Data) | Đạt |
| Thư mục hiển thị `Thu muc E` của `E_Copy` hiện ở `Fact_Transaction` | Đạt |
| Số liệu card dùng measure mới | Chưa kiểm trên Desktop; số trong BI Pro khớp DAX viết tay ở test `E1Nhom6Tests` (mở lại file đã lưu: `E_Loan Amount` = `SUM(...)`, `E_Copy` = `Net_Cashflow`) |

Ảnh chụp toàn cửa sổ có địa chỉ tài khoản nên không đưa vào git.
