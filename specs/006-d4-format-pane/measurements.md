# Số đo D4

## Mốc trước khi sửa (2026-11-10, T001)

- `swift test`: 1116 test qua.
- Golden nặng (`Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D5Nhom6|EditNhom6|BatchedSerial`): 88 test qua.
- Lưu Nhom6 sau sửa (D5Nhom6): 0,19 đến 0,27 s khi máy rảnh.
- Đường vẽ đang đọc khoảng 70 cặp (khoá, thuộc tính) (T002, `research.md` R9).

## Sau khi làm (2026-11-10, T023, T025)

- `swift test`: 1198 qua (mốc 1116). Thêm: `PBIRFormatPatchTests` 23, `FormatValueTests` 8, `FormatCatalogTests` 12, `FormatEditingTests` 23, `FormatSavingTests` 8, `FormatUndoTests` 6, cộng test hoàn tác thông báo (1) của D5.
- Golden nặng (`Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D5Nhom6|D4Nhom6|EditNhom6|BatchedSerial`): 89 qua (mốc 88; `huyTruyVanNangDungNhanh` chập chờn khi máy tải, đã biết).
- `D4Nhom6` trên Nhom6, máy rảnh: card (2 sửa) 2,9 ms; slicer (2) 2,7 ms; biểu đồ (9 sửa gồm tiêu đề, nền, viền) 19,3 ms; matrix 3,1 ms; visual mới 0,8 ms (SC-001: dưới 0,5 s); lưu 0,18 s (SC-003).
- Truy vấn của card, biểu đồ và matrix không đổi sau khi sửa định dạng; mọi part khác khớp byte (trừ `SecurityBindings`, `[Content_Types].xml` và các `visual.json` đã sửa); mọi visual không sửa giữ nguyên `objects` và `visualContainerObjects`.
- Danh mục chưa phủ 33 cặp (loại, phạm vi, khoá, thuộc tính) trên Nhom6: nút (`actionButton` căn lề, lề, `icon`, `visualLink`), `dataPoint` các biểu đồ, `donutChart.value`, `image`, `forecast`/`trend`, `valueAxis.sec*`, `pivotTable.columnWidth`, `shapeMap`, `slicer.data`/`general`, `textbox.general`, `treemap`. Đều chỉ-đọc, giữ nguyên byte khi lưu.
- Desktop mở `Nhom6_d4.pbix` không lỗi và vẽ đúng định dạng (`docs/phase-d-evidence/vm-d4/CHECKLIST-KET-QUA.md`).
