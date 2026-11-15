# VM-E6: gate Desktop cho tab bố cục, quan hệ hoạt động, tổng hợp và sắp xếp cột (2026-11-14)

File `Nhom6_f2.pbix` do BI Pro lưu (`FGateTests.taoFileGateDesktop`) từ bản sao Nhom6, mở trong Power BI Desktop trên VM (Claude bấm chuột thật qua `vm.sh`). Desktop mở được, không báo hỏng.

| # | Kiểm | Kết quả |
|---|---|---|
| A | Tab bố cục "Vay von" (BI Pro thêm, đổi tên, đặt `Fact_Loan` và `Dim_Client` vào) | Đạt: Model view có tab "All tables" và "Vay von", tab "Vay von" đang chọn, hiện hai bảng và đường quan hệ giữa chúng (`g2-tab-vay-von.png`) |
| B | Quan hệ `Fact_Loan[loan_profile_key]` → `Dim_Loan_Profile` do BI Pro tạo ở dạng **hoạt động** (xoá quan hệ cũ rồi kéo cột tạo lại; không bị buộc không hoạt động vì không còn đường khác) | Đạt: Manage relationships ghi **Active**, Many to one, Cross-filter Single (`g3-quan-he-hoat-dong.png`) |
| C1 | `Fact_Loan[loan_amount]` tổng hợp mặc định Trung bình | Đạt: Column tools hiện Summarization = **Average** (`g7-loan-amount-average.png`) |
| C2 | `Fact_Loan[loan_count]` tổng hợp mặc định Lớn nhất | Đạt: Summarization = **Maximum** |
| C3 | `Dim_Client[age_group_current]` sắp xếp theo `age_group_order` | Đạt: danh sách "Sort by column" của cột này tô sáng `age_group_order`; cột `client_city` (không sắp xếp theo cột khác) tô sáng chính nó (`g10-sort-by-age-group.png`) |

Ảnh đã cắt bỏ phần có tài khoản đăng nhập. VM: thư mục tạm đã xoá; file Mac tạm đã xoá.
