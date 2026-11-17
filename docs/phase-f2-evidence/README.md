# Bằng chứng: tồn đọng sau Phase F (`specs/011-ton-dong-sau-phase-f/`)

Desktop 2.159 trong VM Windows 11; Claude lái VM (bạn cho phép 2026-11-17, hiến pháp 1.1.0).

| Buổi | Câu chuyện | Nội dung |
|---|---|---|
| `vm-f10/` | US1 | Gộp ngầm: phép gộp mặc định, menu, PBIR `Aggregation`, Performance Analyzer; gate |
| `vm-f11/` | US2 | Màn "Add data to your report", Enter Data, Auto date/time, tự phát hiện quan hệ; gate |
| `vm-f12/` | US3 | Hàm văn bản DAX: `golden.tsv` từ DAX query view; gate |
| `vm-f13/` | US4 | Sửa/xoá cột tính toán là khoá quan hệ, cấp phân cấp, cột sắp xếp; gate |
| `vm-f14/` | US5 | Chia đoạn dữ liệu, RLE, cỡ tệp Desktop; gate |
| `vm-f15/` | US6 | PostgreSQL kiểu mới, Parquet lồng, driver ODBC SQLite; gate |

Mỗi buổi: `QUAN-SAT.md` (viết trước khi code), `KET-QUA.md` (gate), ảnh đã cắt.

Quy tắc:
- Ảnh VM cắt bằng `sips -c 900 1500 --cropOffset 130 50` để che tên tài khoản; xoá ảnh gốc và `full.png`.
- Ảnh BI Pro: chỉ cửa sổ app.
- `.pbix` Desktop lưu (`f1x-desktop.pbix`…) để ngoài git; test đọc chúng thì bỏ qua khi thiếu.
- Không ghi mật khẩu PostgreSQL vào đây.
- Dọn thư mục VM (`C:\Users\bacpew\f1x\`) sau mỗi buổi.
