# Gate Desktop T116 (FR-060): sửa và xoá cột, bảng tính toán

Ngày 2026-11-17, Power BI Desktop 2.159 trong VM, Claude lái VM (người dùng cho phép trong Phase F). File sinh bằng
`T116Nhom6Tests.suaXoaCotVaBangTinhToanLuuHaiLanKhopTungDong` (`build/f-out/f9/Nhom6_t116.pbix`, ngoài git), chép sang VM (đã dọn sau buổi).

Nội dung file: bản sao Nhom6, lưu T3 hai lần.
- Lần 1 thêm cột tính toán `Fact_Loan[Nhãn tuổi]`, `Fact_Loan[Nhãn dài] = Fact_Loan[Nhãn tuổi] & "!"`, `Fact_Loan[Bỏ]`, bảng tính toán `Nhóm tuổi = DISTINCT(Fact_Loan[age_group_at_loan])`, `Tạm = DISTINCT(Dim_Date[year])`.
- Lần 2 (mở lại, mọi mục đã nằm trong file):
  - sửa công thức hai cột gốc của Desktop: `Dim_Date[MonthIndex]` (thành `year * 100 + month_num`) và `Fact_Transaction[trans_hour]` (1 056 320 dòng, thành `MOD(HOUR(...) + 7, 24)`);
  - sửa `Nhãn tuổi` (thành `"Tuổi " & age_group_at_loan`), nên cột phụ thuộc `Nhãn dài` được tính lại và ghi lại;
  - xoá cột `Bỏ`, sửa công thức bảng `Nhóm tuổi` (lọc bỏ "Unknown"), xoá bảng `Tạm`.

| Kiểm | BI Pro | Desktop | Kết quả |
|---|---|---|---|
| Mở file | | không lỗi, báo cáo đủ số, có `Nhóm tuổi`, không còn `Tạm` (`g1-mo-file.png`) | **ĐẠT** |
| `MonthIndex` lệch so với biểu thức mới (Desktop tự tính trong truy vấn) | 0 | 0 | **ĐẠT** |
| Σ `MonthIndex` | 588 655 860 | 588 655 860 | **ĐẠT** |
| `trans_hour` lệch so với biểu thức mới | 0 | 0 | **ĐẠT** |
| Σ `trans_hour` | 20 042 573 | 20 042 573 (`g2-dax-cot-goc.png`) | **ĐẠT** |
| `Nhãn dài` lệch so với `"Tuổi " & age_group_at_loan & "!"` | 0 | 0 | **ĐẠT** |
| Số dòng `Nhóm tuổi` | 4 | 4 | **ĐẠT** |
| `MIN(Nhãn tuổi)` | Tuổi <25 | Tuổi <25 (`g3-dax-cot-bang-bi-pro.png`) | **ĐẠT** |

Lần gate đầu trượt ("Unable to execute DAX … TMProcessPartitionJob::CreateReaderFromExpression"). Nguyên do nằm ở đường thêm bảng
tính toán có từ T082–T085: cột kết quả lấy từ cột mô hình phải có `SourceColumn = Bảng[Cột]` và `ColumnOriginID`. Đã quan sát và sửa
(VM-F9b, `vm-f6/QUAN-SAT.md` mục 6). Golden Desktop `obs-desktop.pbix` ở thư mục này, ngoài git.

Bấm thử app (T099 kiểu): chọn `trans_hour` ở pane Dữ liệu thì thanh công thức sửa được; sửa rồi ⌘↩ thì lưới hiện giá trị mới. Trước đó
lưới giữ dữ liệu cũ khi tên cột không đổi; đã sửa (`TableWorkspace`, dựng lại lưới mỗi lần nạp). Chuột phải ▸ "Xoá khỏi mô hình" hỏi
"Bạn có chắc muốn xoá …?" (Huỷ/Có); cột còn được dùng thì báo "Không xoá được" kèm nơi dùng.
