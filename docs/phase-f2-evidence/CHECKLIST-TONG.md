# Gate tổng: tồn đọng sau Phase F (specs/011), T063

Ngày 2026-11-19. Mỗi câu chuyện có buổi quan sát Desktop và gate Desktop (SC-009); chi tiết ở `KET-QUA.md` của từng thư mục.

| Câu chuyện | Quan sát | Gate | Kết quả |
|---|---|---|---|
| US1 phép gộp ngầm | `vm-f10/` | `vm-f10/KET-QUA.md` | ĐẠT |
| US2 tài liệu mới (Auto date/time, tự phát hiện quan hệ, Thêm dữ liệu, Enter Data) | `vm-f11/QUAN-SAT.md` | `vm-f11/KET-QUA.md` (T037) | ĐẠT |
| US3 hàm văn bản DAX | `vm-f12/QUAN-SAT.md` | `vm-f12/KET-QUA.md` (T023) | ĐẠT |
| US4 sửa/xoá cột tính toán còn được dùng | `vm-f13/QUAN-SAT.md` (TOM + UI T071) | `vm-f13/KET-QUA.md` (T052, T071) | ĐẠT |
| US5 dữ liệu lớn | `vm-f14/QUAN-SAT.md` (DMV + tệp thật Desktop) | `vm-f14/KET-QUA.md` (T059, T067, T068, T069) | ĐẠT (10 đoạn 10M dòng, cột tính toán trên bảng nhiều đoạn Desktop, SC-006 đạt 90,5 %) |
| US6 nguồn | `vm-f15/QUAN-SAT.md` | `vm-f15/KET-QUA.md` (T046, T072) | ĐẠT (PostgreSQL, Parquet lồng, SQLite Refresh driver Devart) |

## Luồng SC-002

Tài liệu mới → nạp hai bảng có khoá chung và cột ngày → biểu đồ theo Năm → lưu → Desktop mở.

- Gate VM-F11 (`bipro-f11.pbix`): Desktop mở không lỗi.
  - Ba quan hệ `AutoDetected_…` trùng tệp Desktop tự tạo cùng bước (`f11-desktop.pbix`).
  - Bảng ngày cục bộ và phân cấp Year/Quarter/Month/Day trùng; số theo năm khớp.
- Thao tác trong app (T038, bấm thử): Thêm dữ liệu → dán bảng → nạp → kéo trường ngày vào biểu đồ → lưu, làm được trong vài phút.
  - Không đo bằng đồng hồ ở buổi này (`[SUY ĐOÁN]` dưới 3 phút).

## Dọn VM

Đã xoá `C:\Users\bacpew\f12g`, `f13`, `f14`, `f15` và các tệp tạm ở `C:\Users\Public` sau buổi 2026-11-19.
