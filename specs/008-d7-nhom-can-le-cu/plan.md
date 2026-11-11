# Kế hoạch triển khai D7: căn lề và phân bố, dán giữa trang, nhóm visual, sửa báo cáo định dạng cũ

**Đặc tả**: [spec.md](spec.md) · **Quan sát**: `docs/phase-d-evidence/vm-d7/QUAN-SAT.md` · **Quyết định**: [research.md](research.md) R1–R7

## Bối cảnh kỹ thuật

- Swift/SwiftUI, hai module: `PBIXKit` (đọc, ghi, ghép byte) và `BIPro` (giao diện, `LayoutEditor`, `DocumentSaver`). Không thêm thư viện ngoài.
- Lưu T1 đi qua `LayoutEditor.makeChanges` → `PBIXChanges` → `PBIXWriter.build` (dựng và kiểm trong bộ nhớ, ghi tạm, mở lại, thay). Hoàn tác theo ảnh chụp trạng thái (`LayoutSnapshot`). Khung hình học nguyên (`Frame`, `LayoutGeometry`).
- Ràng buộc: PBIR chỉ ghép byte phần đổi; định dạng cũ cũng ghép byte; không ghi cấu trúc chưa quan sát; không ghi dưới `~/Downloads`; golden Phase B/C và test D1 đến D6 vẫn qua; chuẩn mực tốc độ: mỗi lệnh dưới 150 ms trên trang 36 visual.

## Kiểm tra theo hiến pháp

- Quan sát Power BI trước khi code: VM-D7 xong (nhóm, căn, phân bố, dán). Phần chưa quan sát nằm ở R7, mỗi mục có cách xử lý thận trọng (từ chối hoặc phương án an toàn hoàn tác được).
- Hiến pháp "agent không điều khiển VM": VM-D7 và VM vòng 2 chạy theo lời cho phép của người dùng ("Ok, có thể điều khiển VM", 2026-11-11), ngoại lệ ghi vào QUAN-SAT.
- Tệp gốc trong `~/Downloads` chỉ đọc: test dùng bản sao ở `build/`; file Nhóm 2 và Nhóm 3 chỉ được copy ra `build/` rồi mở.
- Không dịch ngược; chỉ đọc file Desktop ghi.

## Thiết kế

1. **PBIXKit đọc** (`ReportDefinition`): `ReportVisual.parentGroup`; bộ đọc PBIR cộng `x,y` nhóm vào con; container nhóm vào danh sách visual của trang với `type "visualGroup"`. Bộ đọc định dạng cũ: giữ nguyên, thêm `container index` để ghép byte (R5).
2. **PBIXKit ghi**:
   - `PBIRGroupPatch` (mới): `groupJSON(...)`, `settingParent(json, group, relX, relY)`, `clearingParent(json, absX, absY)`; số thập phân được (mở rộng `PBIRLayoutPatch.setPosition` nhận `Double`, giữ kiểm "không âm", kẹp, ghi số nguyên khi giá trị nguyên).
   - `LegacyLayoutPatch` (mới): theo `contracts/legacy-layout.md`.
   - `PBIXWriter.insertionIndex`: thứ tự chèn part nhóm như visual (cùng thư mục `visuals/`).
3. **BIPro hình học**: `LayoutGeometry.align(_:frames:page:)`, `distribute(_:frames:page:)` (thuần, theo R1); `GroupGeometry.frame(of:)`, `scale(children:from:to:)`.
4. **BIPro editor** (`LayoutEditor+Align.swift`, `LayoutEditor+Group.swift` mới): `align`, `distribute`, `group(ids:)`, `ungroup(id:)`, di chuyển/đổi cỡ nhóm (mở rộng `move`/`resize`/`apply(frames:)`), xoá/nhân bản/chép nhóm; bỏ `isLockedByGroup` cho con (chỉ còn khoá nhóm lồng); `paste` dùng +10 và `z`+1 (R2). Chế độ định dạng cũ: `LayoutEditor` biết `isLegacy`; `makeChanges` rẽ nhánh sang `makeLegacyChanges` (R5).
5. **BIPro giao diện**: menu Định dạng (Căn lề, Phân bố, Nhóm, Bỏ nhóm), phím ⌘G/⇧⌘G, menu chuột phải; mờ kèm lý do; Selection pane có cây nhóm; canvas chọn nhóm trước rồi con (R4); khung chọn nhóm. `canEditLayout` tách thành `canEditCanvas` (PBIR và định dạng cũ) và `canEditStructure` (chỉ PBIR) cho các chỗ hiện có.
6. **Lưu và kiểm** (`DocumentSaver`): `verifyGroups` và `verifyLegacyLayout` (R6).
7. **Bằng chứng**: VM vòng 2 mở `Nhom6_d7.pbix`, `Nhom2_d7.pbix` (Desktop); ghi vào `docs/phase-d-evidence/vm-d7/CHECKLIST-KET-QUA.md`.

## Thứ tự và phụ thuộc

Nền (đọc nhóm, số thập phân) → Câu chuyện 1 (căn) và 2 (dán), độc lập nhau → Câu chuyện 3 (nhóm, dùng nền và căn lề trong nhóm) → Câu chuyện 4 (định dạng cũ, dùng lệnh căn, dán, xoá đã có) → tích hợp, VM vòng 2, review. Câu chuyện 4 không phụ thuộc nhóm.

## Tệp dự kiến

- Mới: `Sources/PBIXKit/Writing/PBIRGroupPatch.swift`, `LegacyLayoutPatch.swift`; `Sources/BIPro/Report/Edit/LayoutEditor+Align.swift`, `LayoutEditor+Group.swift`, `LayoutEditor+Legacy.swift`, `AlignCommand.swift`; test tương ứng; `Tests/BIProTests/Edit/D7Nhom6Tests.swift`.
- Sửa: `ReportDefinition.swift`, `PBIRLayoutPatch.swift`, `PBIXWriter.swift`, `LayoutGeometry.swift`, `LayoutEditor.swift`, `DocumentSaver.swift`, `DocumentState.swift`, `DocumentState+Report.swift`, `PageOperations.swift`, `EditCommands.swift`, `EditCanvasOverlay.swift`, `ReportCanvas.swift`, `ReportPanes.swift`, `ReportWorkspace.swift`.

## Rủi ro

- Desktop từ chối `Report/Layout` đã ghép byte hoặc nhóm do BI Pro viết → giữ chặn kèm lý do (không phát hành phần đó), ghi vào STATE.
- Số thập phân của Desktop và hình học nguyên của BI Pro → so sánh có dung sai, chỉ ghi phần đổi thật.
- `config` thoát ký tự không khớp chính xác → từ chối ở khâu kiểm, không ghi đoán.
