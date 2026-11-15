# Kiểm chạy Phase F

Tiền đề: `swift build`; file mẫu do Claude sinh vào `build/f-out/` (đợt 0); Nhom6 bản sao ở `build/f-out/Nhom6_f*.pbix` (không đụng file gốc `~/Downloads`). Test Desktop trên VM do bạn làm hoặc cho phép từng lần.

1. **Gate F-T3 (S0)**: mở `build/w-out/W4/tuan6.2_W4_table.pbix` trong Desktop theo `CHECKLIST.md`; ghi `docs/phase-f-evidence/vm-f0/`. Kỳ vọng: bảng 100 dòng, dữ liệu đúng.
2. **Lưu T3 lõi**: `swift test --filter "VertiPaqWriter|TableMetadata|T3"`; sau đó dựng `Nhom6_f1.pbix` có bảng mới (đủ kiểu, có null), Desktop mở: số dòng, tổng, quan hệ.
3. **Get Data**: mở app, "Get data" → CSV rồi `sales_2026.xlsx` → Navigator → Load; bảng có trong Table View; ⌘Z; ⌘S; mở lại trong BI Pro và Desktop.
4. **Query Editor**: `sales_2026.xlsx` → Transform → thăng tiêu đề, đổi kiểu, lọc, bỏ cột → Close & Apply; so với bản Desktop làm cùng bước (golden M).
5. **Biến đổi nâng cao**: Merge, Append, Group By, Custom Column, Advanced Editor, Query Dependencies; so golden.
6. **File mới**: "Mới" → Get data → báo cáo → lưu; Desktop mở.
7. **Cột/bảng tính toán**: thêm cột và bảng DAX, lưu, Desktop mở thấy cùng giá trị.
8. **Đợt 2 (P3)**: Parquet, JSON, SQLite, PostgreSQL theo `contracts/data-source.md`.
9. **Toàn bộ**: `swift test`; golden nặng `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|Batched"` (30 DAX, 72 truy vấn không đổi); `zsh scripts/build-app.sh`.
