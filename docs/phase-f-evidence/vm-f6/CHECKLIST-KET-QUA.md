# Gate T085: cột và bảng tính toán do BI Pro ghi, mở trong Desktop 2.159 (2026-11-16)

Người dùng cho lái VM. File: `build/f-out/f6/Nhom6_f4.pbix` (ngoài git) do test `F6Nhom6CalcTests` sinh: bản sao Nhom6 thêm hai cột tính toán và một bảng tính toán bằng BI Pro, lưu kèm dữ liệu VertiPaq. Ảnh đã cắt bỏ thanh tiêu đề (tài khoản đăng nhập).

| Kiểm | Kết quả | Ảnh |
|---|---|---|
| Mở file | **ĐẠT.** Không lỗi, không cần Refresh; báo cáo Nhom6 (D3) vẽ đủ; Data pane có thêm `Lịch 2026` với biểu tượng bảng tính toán | `g1-mo-file.png` |
| Bảng `Lịch 2026 = CALENDAR(DATE(2026,1,1), DATE(2026,12,31))` | **ĐẠT.** Desktop nhận là bảng tính toán: thanh công thức hiện đúng biểu thức; `Lịch 2026 (365 rows)`, dòng đầu Thursday, January 1, 2026 | `g2-bang-lich-2026.png` |
| Cột `Dim_District[Nhãn đầy đủ] = city & " (" & state_abbrev & ")"` | **ĐẠT.** Công thức hiện đúng, kiểu Text, biểu tượng cột tính toán; 77 dòng, 77 giá trị phân biệt, ví dụ `New York City (NY)` | `g3-cot-nhan-day-du.png` |
| Cột `Fact_Loan[Tuổi năm sau] = IF(ISBLANK(age_at_loan), BLANK(), age_at_loan + 1)` | **ĐẠT.** Công thức hiện đúng, Whole number, Sum; 682 dòng, 49 giá trị phân biệt (bằng `age_at_loan`); mọi dòng nhìn thấy bằng `age_at_loan + 1` (37→38, 48→49…) | `g4-cot-tuoi-nam-sau.png` |

Xác nhận thêm cho QUAN-SAT mục 4: bảng tính toán BI Pro ghi với `SystemFlags = 2`, phân vùng `Type = 2`, cột `Type = 4` được Desktop 2.159 đọc như bảng tính toán của chính nó. VM đã dọn (Desktop tắt không lưu, thư mục thử đã xoá).
