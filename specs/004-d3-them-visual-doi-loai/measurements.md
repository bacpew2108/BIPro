# Số đo D3

Máy phát triển (Apple Silicon), Nhom6 thật (`~/Downloads/bipro-golden/Nhom6_work.pbix`). Mốc trước khi sửa (vẽ lại 24–104 ms, lần nạp đầu của phiên 255 ms, lưu 0,18 s) lấy từ `specs/003-d2-build-pane-field-well/measurements.md`.

## Test tự động

- Sau giai đoạn 2 (nền tảng, T013): `swift test` 1002 qua (968 trước D3 + 34 mới: `PBIRNewVisualTests` 6, `PBIRVisualPatchTests` 10, thêm 4 ca vào `PBIRQueryPatchTests`, `VisualTypesTests` 4, `TypeChangeTests` 10).

## Sau khi thêm và đổi loại (T019, T026, T037, T038, 2026-11-10)

Test nặng `D3Nhom6` trên Nhom6 thật: thêm một card và một biểu đồ thanh nhóm, thả trường, đổi loại ba cặp (đường → thanh nhóm, combo → đường, donut → treemap), sửa chữ hộp văn bản tiêu đề, vẽ bằng engine, lưu thành `build/d-out/D3/Nhom6_d3.pbix`, mở lại.

| Việc | Kết quả |
|---|---|
| Vẽ lại sau khi thêm hoặc đổi loại (chạy riêng): card mới / thanh mới / đường → thanh / donut → treemap / combo → đường (nặng nhất) | 19 và 188 ms (hai visual mới; có một lần nạp lạnh) / 23 ms / 34 ms / 441 ms (mốc trước khi sửa của chính combo này: 492 ms) |
| Lưu (ghi 54 MB) | 0,17 đến 0,20 s (SC-005, dưới 1 s); khi chạy cùng các test nặng khác có lần 1,8 s trên máy tải (test `EditNhom6` của D1), nên mọi test lưu nặng thử lại tối đa hai lần |
| Số card mới (Net_Cashflow) | khớp truy vấn DAX viết tay cùng hai bộ lọc cấp report |
| Truy vấn sinh ra sau khi mở lại file đã lưu | giống hệt truy vấn trước khi lưu ở cả 5 visual |
| `unzip -t`, nguồn không đổi, visual không sửa, `DataModel` | khớp (trừ `SecurityBindings` và `[Content_Types].xml` như D1) |

- `swift test`: 1034 qua (968 trước D3).
- Golden nặng `BIPRO_HEAVY=1 … --filter "Nhom6|ORA|VIS|D3Nhom6|D2Nhom6|EditNhom6|BatchedSerial"`: 85 qua, gồm 30 golden Phase B, các golden Phase C, `EditNhom6`, `D2Nhom6`, `D3Nhom6`.

