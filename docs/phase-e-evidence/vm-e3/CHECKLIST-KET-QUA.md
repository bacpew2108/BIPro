# Gate Desktop, Câu chuyện 2 (quan hệ): kết quả (2026-11-14)

Claude tự bấm chuột thật lên cửa sổ Parallels (`vm.sh`, cliclick) trên hai file BI Pro vừa ghi (bản sao Nhom6 đã xoá khỏi VM và Mac).

| File | Việc BI Pro đã làm | Kết quả trong Power BI Desktop |
|---|---|---|
| `build/e-out/E2/Nhom6_e2.pbix` | kéo `Dim_Client[client_key]` thả lên `Fact_Loan[loan_count]`, xác nhận; lưu T2 (dòng `Relationship`, `RelationshipStorage`, `RelationshipIndexStorage`, bảng hệ thống `R$` và hai tệp chỉ mục ABF) | Mở được, không báo lỗi; **Manage relationships** thấy `Fact_Loan (loan_count)` → `Dim_Client (client_key)`, **Inactive** (đúng như Desktop tự tạo ở VM-E3) |
| `build/e-out/E2/Nhom6_e2_xoa.pbix` | xoá quan hệ `Fact_Loan[loan_profile_key]` → `Dim_Loan_Profile` (gỡ bảng `R$` và hai tệp ABF) | Mở được, không báo lỗi; quan hệ đó không còn trong Manage relationships |

Chưa kiểm trên Desktop: quan hệ **hoạt động** do BI Pro tạo (mô hình Nhom6 nối kín nên mọi quan hệ mới giữa hai bảng đã nối đều không hoạt động), đổi hướng lọc/hoạt động qua bảng thuộc tính (chỉ đổi một dòng, đã kiểm ở test và ở QUAN-SAT VM-E1), số liệu visual dùng quan hệ mới.
