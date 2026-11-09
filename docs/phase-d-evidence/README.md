# Phase D: bằng chứng và quan sát

## Lát D1 (sửa bố cục canvas, lưu T1): `specs/002-d1-canvas-luu-t1/`

### Đã quan sát trong file thật (Nhom6, PBIR)
- Vị trí visual: `position` = `{x, y, z, height, width, tabOrder}`, số nguyên; `z == tabOrder`, bước 1000.
- Mã visual: 20 ký tự hex thường, trùng `name`.
- Thư mục visual chỉ có `visual.json`; Nhom6 không có nhóm visual.
- Bookmark nhắc visual ở `options.targetVisualNames` và `explorationState.sections.<trang>.visualContainers`.

### Còn [SUY ĐOÁN] (chờ buổi VM-D1, `build/d-out/D1/VM-D1-QUAN-SAT.md`)
- Lưới bám 8 px; cỡ tối thiểu 16; phím mũi tên 1 px (Shift 8 px).
- Bản nhân bản: lệch +16, +16; `z = tabOrder = max z + 1000`.
- Bookmark/`visualInteractions` khi xoá visual: BI Pro dọn tham chiếu; chưa biết Power BI Desktop làm gì.
- Marquee chọn theo "giao" khung (không phải "chứa hẳn").

### Ảnh chụp cửa sổ app
- `01-view-mode.png`: chế độ Xem (D3), có nút Xem / Sửa.
- `02-edit-select.png`: chế độ Sửa, một card được chọn, 8 tay nắm.
- `03-edit-moved.png`, `04-edit-heavy.png`, `05-edit-resized.png`: kéo card, kéo biểu đồ nặng, đổi cỡ.
- `06-close-prompt.png`: hỏi lưu khi đóng/thoát.
- `07-downloads-readonly.png`: lưu từ file trong Downloads.
- `08-duplicated.png`: ⌘D nhân bản card.

### Số đo
`specs/002-d1-canvas-luu-t1/measurements.md`.

### Bài học kỹ thuật
`specs/002-d1-canvas-luu-t1/research.md` mục R2 (bổ sung): chạm `NSDocumentController.shared` trong lệnh menu làm app sập khi khởi động; `URL.resourceValues` nhớ giá trị cũ.
