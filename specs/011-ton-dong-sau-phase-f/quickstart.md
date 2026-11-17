# Kiểm chạy: Tồn đọng sau Phase F

Tiền đề: `swift build`; mẫu do Claude sinh ở `build/f2-out/` (Đợt 0); Nhom6 bản sao trong `build/f2-out/`; `w8.3.pbix` chỉ đọc; máy chủ `bipro-pg` chạy (US6, `BIPRO_PG=…`). Claude lái VM bằng `build/vm-tools/`.

1. **US1 gộp ngầm**: `swift test --filter "ImplicitAggregation|WellRules|DAXQueryBuilder"`. App: Mới → Get Data `sales_2026.xlsx` → card kéo `Amount` hiện "Tổng của Amount" → đổi Trung bình → ⌘S. Gate: Desktop mở, card cùng số, Performance Analyzer cùng văn bản (`vm-f10/KET-QUA.md`).
2. **US2 tài liệu mới**: khung trống hiện màn thêm dữ liệu; Dán dữ liệu vào bảng trống 3×5 → Tải; nạp `Sales` + `Customers` → quan hệ `AutoDetected_…`; biểu đồ theo Năm của `OrderDate`. `swift test --filter "AutoDateTime|RelationshipDetector|EnterData|F2"`. Gate: Desktop mở không lỗi, Refresh bảng Enter Data, cấu trúc như file Desktop tự làm (`vm-f11/KET-QUA.md`).
3. **US3 hàm văn bản**: `swift test --filter TextFunction` khớp `vm-f12/golden.tsv` 100%.
4. **US4**: bản sao Nhom6 sửa `Dim_District[branch_label]`; tài liệu thử sửa/xoá cột khoá quan hệ và cột sắp xếp; `BIPRO_HEAVY=1 … --filter F2Calc`. Gate Desktop (`vm-f13/KET-QUA.md`).
5. **US5**: `BIPRO_HEAVY=1 swift test -c release … --filter F2Large`: 10 triệu dòng lưu < 2 phút, < 4 GB; cỡ tệp ≤ 125% Desktop. Gate Desktop (`vm-f14/KET-QUA.md`).
6. **US6**: `swift test --filter "Postgres|Parquet|SQLite"`; app Get Data từng nguồn; gate Desktop Refresh (`vm-f15/KET-QUA.md`).
7. **Toàn bộ**: `swift test`; `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|Batched|F6|T116|F2"` (30 DAX, 72 truy vấn visual không đổi); `zsh scripts/build-app.sh` và bấm thử app.
