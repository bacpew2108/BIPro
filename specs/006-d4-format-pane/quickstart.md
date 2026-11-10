# Quickstart kiểm D4

Điều kiện: `swift build` qua; bản sao `Nhom6_work.pbix` trên Desktop (không sửa gốc ở `~/Downloads`).

## 1. Test tự động

```bash
swift test --filter "PBIRFormatPatchTests|FormatCatalogTests|FormatValueTests|FormatEditingTests|FormatUndoTests|FormatSavingTests"
swift test                      # toàn bộ (baseline 1116 qua)
BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel \
  --filter "Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D5Nhom6|D4Nhom6|EditNhom6|BatchedSerial"   # baseline 88 qua
```

`D4Nhom6Tests` dựng `build/d-out/D4/Nhom6_d4.pbix` (card đổi cỡ chữ, slicer tắt header, combo đổi legend/nhãn/tiêu đề/nền, matrix đổi cỡ chữ, một visual mới bật tiêu đề) cùng `CHECKLIST.md`.

## 2. Trong app (chế độ Sửa ⌘E)

1. Chọn card ở trang D3, tab Định dạng: đổi cỡ chữ "Giá trị", tắt "Nhãn danh mục": canvas đổi ngay.
2. Chọn biểu đồ cột/đường: bật Nhãn dữ liệu; đổi vị trí legend; bật tiêu đề trục: ô điều khiển có ghi chú "BI Pro chưa vẽ" ở thuộc tính chưa vẽ.
3. Chọn bất kỳ visual: phạm vi Chung, đổi chữ tiêu đề, màu nền (hex), viền bo góc: canvas đổi.
4. ⌘Z từng bước, ⇧⌘Z; "Đặt lại" thẻ Nhãn dữ liệu: thẻ về mặc định.
5. ⌘S; mở lại bằng BI Pro; đúng định dạng. Chế độ Xem: các ô mờ kèm lý do.

## 3. Trong Power BI Desktop (VM, Claude khi được phép)

Mở `Nhom6_d4.pbix` theo `CHECKLIST.md`: không báo lỗi; định dạng của các visual đã sửa hiện như BI Pro; bấm Format pane của Desktop thấy đúng giá trị. Ghi kết quả vào `docs/phase-d-evidence/vm-d4/CHECKLIST-KET-QUA.md`.
