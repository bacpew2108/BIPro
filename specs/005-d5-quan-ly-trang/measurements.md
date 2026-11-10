# Số đo D5

## Mốc trước khi sửa (2026-11-10, T003)

- `swift test`: 1042 test qua.
- Golden nặng (`Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|EditNhom6|BatchedSerial`): 85 test qua.
- Lưu Nhom6 sau sửa (D2Nhom6/D3Nhom6): 0,17 đến 0,20 s khi máy rảnh.
- Nhân bản visual (D1): dưới 30 ms cho một visual (không có mốc cho 36 visual; đo ở T030).

## Sau khi làm (2026-11-10, T036)

- `swift test`: 1115 test qua (mốc trước: 1042).
- Golden nặng (`Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D5Nhom6|EditNhom6|BatchedSerial`): 87 test qua (mốc: 85).
- `D5Nhom6` trên Nhom6 (36 visual ở D1), máy rảnh: thêm trang 0,3 ms; đổi tên 0,2 ms; kéo 0,0 ms; nhân bản D1 90 đến 113 ms; xoá D1 (gỡ 2 bookmark) 150 đến 175 ms; lưu 0,19 đến 0,27 s (SC-001, SC-003: dưới 1 s).
- Trang nhân bản vẽ cùng truy vấn với trang gốc cho 20+ visual có dữ liệu (SC-004 phần vẽ).
- File lưu mở được trong Power BI Desktop (`docs/phase-d-evidence/vm-d5/CHECKLIST-KET-QUA.md`).
- Chưa tự bấm thử trong app: Nhân bản và Xoá ở menu tab (đã bấm thử Thêm, Đổi tên, kéo, ⌘Z, ⌘S); logic hai thao tác có test (`PageDuplicateTests`, `PageRemoveTests`, `PageSavingTests`).

