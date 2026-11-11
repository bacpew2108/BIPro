# Số đo D6

## Mốc trước khi sửa (2026-11-11, commit `98198d7`)

- `swift test`: 1200 qua.
- Golden nặng (`Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D4Nhom6|D5Nhom6|EditNhom6|BatchedSerial`): 89 qua.
- Lưu Nhom6 (D4/D5): 0,18 đến 0,27 s.

## Sau khi làm xong (2026-11-11)

- `swift test`: 1284 qua (mốc 1200; thêm 84 test D6).
- Golden nặng (`Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D4Nhom6|D5Nhom6|D6Nhom6|EditNhom6|BatchedSerial`): 91 qua (mốc 89; thêm `D6Nhom6` và một test).
- `D6Nhom6`: ba thao tác bookmark (thêm, đổi tên, xoá) 0,1 ms (SC-004: dưới 100 ms); lưu Nhom6 0,24 s (SC-003: dưới 1 s).
- SC-001: `Nhom6_d6.pbix` mở được trong Power BI Desktop, bookmark và bộ lọc áp đúng (`docs/phase-d-evidence/vm-d6/CHECKLIST-KET-QUA.md`).
- SC-005: dạng chưa quan sát bị từ chối kèm lý do (`FilterExportTests`, `BookmarkExportTests`).
