# Quickstart: kiểm D2 từ đầu đến cuối

Điều kiện: `Nhom6_work.pbix` ở `~/Downloads/bipro-golden/` hoặc biến `BIPRO_NHOM6=<đường dẫn>`.

## 1. Test tự động

```
swift build
swift test                                    # gồm PBIRQueryPatchTests, BIProTests/Edit (FieldEditor, WellRules, hoàn tác đan xen)
BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS|D2Nhom6|EditNhom6"
```

Kỳ vọng: không test nào trượt thêm; golden 30/30; `D2Nhom6` (sửa trường, lưu vào `build/d-out/D2/`, mở lại, so với truy vấn DAX) qua; thời gian vẽ lại và lưu in ra dưới 150 ms và 1 s.

## 2. Chạy thử trong app

```
zsh scripts/build-app.sh
open "build/BI Pro.app"      # rồi mở một bản sao Nhom6 ở Desktop (không phải trong Downloads)
```

1. ⌘E bật Sửa. Chọn biểu đồ cột ở trang D1: Build pane hiện Trục X, Trục Y, Chú giải, Chú giải công cụ đúng loại.
2. Kéo một measure từ pane Dữ liệu vào Trục Y: biểu đồ vẽ lại; ⌘Z hoàn tác.
3. Kéo một measure vào ô Chú giải: bị từ chối, có lý do.
4. Bỏ một measure khỏi Trục Y: biểu đồ vẽ lại. Bỏ cột đang dùng sắp xếp: bị chặn kèm lý do.
5. Biểu đồ combo: chuyển một measure từ ô cột sang ô đường.
6. Đổi tên hiển thị của một trường; trả về tên gốc.
7. Dời một visual (D1), sửa trường, ⌘Z từng bước theo thứ tự ngược.
8. ⌘S trên bản sao ở Desktop; mở lại: giữ nguyên các thay đổi.

## 3. Gói VM

`build/d-out/D2/`: `Nhom6_d2.pbix` (do test `D2Nhom6` sinh qua đúng đường lưu), `CHECKLIST.md`, `VM-D2-QUAN-SAT.md`. Mở `Nhom6_d2.pbix` trong Power BI Desktop, kiểm các visual đã sửa vẽ đúng trường và cùng số với BI Pro.

## 4. Buổi quan sát VM-D2

Theo `research.md` R14; kết quả vào `docs/phase-d-evidence/vm-d2/`. Cần cho D2b (phép gộp) và để nâng các ô từ `unverified` lên `observed`.
