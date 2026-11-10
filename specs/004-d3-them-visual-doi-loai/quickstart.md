# Quickstart: kiểm D3 từ đầu đến cuối

Điều kiện: `Nhom6_work.pbix` ở `~/Downloads/bipro-golden/` hoặc biến `BIPRO_NHOM6=<đường dẫn>`.

## 1. Test tự động

```
swift build
swift test                                    # gồm PBIRNewVisualTests, PBIRVisualPatchTests, BIProTests/Edit (InsertVisual, TypeChange, Textbox, hoàn tác ngẫu nhiên)
BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS|D3Nhom6|D2Nhom6|EditNhom6"
```

Kỳ vọng: không test nào trượt thêm; golden 30/30; `D3Nhom6` (thêm, đổi loại, lưu vào `build/d-out/D3/`, mở lại, so số) qua; thời gian lưu in ra dưới 1 s.

## 2. Chạy thử trong app

```
zsh scripts/build-app.sh
open "build/BI Pro.app"      # rồi mở một bản sao Nhom6 ở Desktop (không phải trong Downloads)
```

1. ⌘E bật Sửa. Bấm vùng trống của trang để không chọn visual nào. Bấm biểu tượng card trong thư viện: một card trống xuất hiện ở giữa phần nhìn thấy, được chọn; ô "Field" của Build pane trống.
2. Kéo measure `Net_Cashflow` từ pane Dữ liệu vào ô Field: card hiện số. ⌘Z gỡ trường, ⌘Z gỡ card.
3. Bỏ chọn, bấm biểu tượng đường: biểu đồ trống; thả `year_month` vào Trục X và một measure vào Trục Y.
4. Chọn biểu đồ đó, bấm biểu tượng thanh nhóm: loại đổi, hai trường còn ở ô cũ. Bấm biểu tượng donut: thông báo trường bị bỏ (nếu có); ⌘Z trả lại.
5. Chọn một visual có sắp xếp theo trường trục X rồi đổi loại làm mất trường đó: bị chặn kèm lý do.
6. Bấm "Hộp văn bản" ở ribbon: hộp xuất hiện; sửa nội dung ở ô "Nội dung".
7. Ở chế độ Xem, các nút và biểu tượng mờ kèm lý do.
8. ⌘S trên bản sao ở Desktop; mở lại: giữ nguyên visual mới, loại, trường, văn bản.

## 3. Gói VM

`build/d-out/D3/`: `Nhom6_d3.pbix` (do test `D3Nhom6` sinh qua đúng đường lưu), `CHECKLIST.md`, `VM-D3-QUAN-SAT.md`. Mở `Nhom6_d3.pbix` trong Power BI Desktop, kiểm các visual mới và đổi loại vẽ đúng loại, đúng chỗ và cùng số với BI Pro.

## 4. Buổi quan sát VM-D3

Theo `research.md` R14; kết quả vào `docs/phase-d-evidence/vm-d3/`. Cần để chốt cấu trúc `visual.json` mới, cỡ mặc định, ánh xạ ô khi đổi loại, giữ hay bỏ định dạng, và mở thêm các loại cột/thanh/vùng.
