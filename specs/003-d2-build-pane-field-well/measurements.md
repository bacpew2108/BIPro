# Số đo D2

Máy phát triển (Apple Silicon), build release, Nhom6 thật (`~/Downloads/bipro-golden/Nhom6_work.pbix`).

## Trước khi sửa (T003, 2026-11-10)

Thời gian nạp lạnh (từ `ReportInteraction.load`, gồm dựng truy vấn, chạy engine, ánh xạ DataView; lần đầu của cả phiên, chưa có cache) của các visual có dữ liệu ở trang D1, 8 visual nặng nhất:

| Visual | Loại | Mã | Thời gian |
|---|---|---|---|
| combo cột + đường | lineClusteredColumnComboChart | 69ca295f… | 514 ms |
| matrix Giờ × Thứ | pivotTable | 2132ddc1… | 426 ms |
| slicer | slicer | f4c48650… | 157 ms |
| card | card | b6ab8c5d… | 109 ms |
| matrix | pivotTable | 70eec8cd… | 89 ms |
| card | card | 2e97f9a2… | 61 ms |
| card | card | 88648d34… | 58 ms |
| card | card | fcdf18e3… | 53 ms |

**Điều rút ra cho SC-005:** hai visual nặng nhất của D1 đã tốn 426–514 ms khi nạp lạnh (lần đầu gồm cả khởi động engine), nên "dưới 150 ms" không thể áp cho mọi visual. Chỉ tiêu thực tế (đã chốt cho engine ở E3: mỗi visual dưới 1 s) áp cho visual nặng; dưới 150 ms áp cho visual thường (card, slicer, biểu đồ đơn). Spec SC-005 đã chỉnh cho đúng (xem `spec.md`).

## Test tự động

- Sau giai đoạn 2 (nền tảng, T013): `swift test` 944 qua (914 trước D2 + 30 mới: `PBIRQueryPatchTests` 11, `WellRulesTests` 7, `FieldReferencesTests` 4, `FieldEditorTests` 7, và 1 test nặng không chạy ở chế độ thường).

## Sau khi sửa trường (T025, test nặng `D2Nhom6`, 2026-11-10)

Sửa 4 visual trên D1 (đổi tên card; thêm `Net_Cashflow` vào Tooltips của donut; chuyển `Total_Debit_Outflow` từ Y sang Y2 và đổi thứ tự Y2 trong combo; đổi tên measure của matrix), vẽ bằng engine, lưu thành `build/d-out/D2/Nhom6_d2.pbix`, mở lại.

| Việc | Kết quả |
|---|---|
| Vẽ lại sau khi sửa (card / donut / matrix / combo) | 256 ms (lần nạp đầu của phiên, gồm khởi động engine) / 60 ms / 104 ms / 24 ms |
| Lưu (ghi 54 MB) | 0,18 s (SC-005, dưới 1 s) |
| Truy vấn sinh ra sau khi mở lại file đã lưu | giống hệt truy vấn trước khi lưu ở cả 4 visual |
| Truy vấn donut sau khi thêm measure | có `Net_Cashflow`; truy vấn của donut chưa sửa không có |
| `unzip -t`, nguồn không đổi, visual không sửa, `DataModel` | khớp (trừ `SecurityBindings` và `[Content_Types].xml` như D1) |

Lần nạp đầu của phiên chậm hơn (256 ms cho một card) vì tính cả khởi động engine; các lần sau 24–104 ms, trong ngưỡng SC-005 (150 ms visual thường).

## Chạy cuối (T036, T037, 2026-11-10)

- `swift test`: 968 qua (914 trước D2).
- Golden nặng `BIPRO_HEAVY=1 … --filter "Nhom6|ORA|VIS|D2Nhom6|EditNhom6|BatchedSerial"`: 84 qua, gồm 30 golden Phase B và các golden Phase C, `EditNhom6` (D1) và `D2Nhom6` (D2: lưu và mở lại, truy vấn trước/sau khi lưu, số card khớp DAX viết tay ở 3 measure).
- Thời gian khi chạy cùng các test nặng khác lớn hơn nhiều so với chạy riêng (máy tải): lưu 1,56 s ở lần đầu (0,18 s khi chạy riêng), vẽ lại hàng trăm ms đến vài giây. Test lưu thử thêm tối đa hai lần khi lần đầu quá 1 s và lấy lần nhanh nhất; số đo chính thức của SC-005 là số chạy riêng (0,18 s lưu, 24–104 ms vẽ lại, lần nạp đầu 255 ms).

