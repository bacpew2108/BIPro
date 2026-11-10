# Kế hoạch triển khai: D1, sửa bố cục trang trên canvas và lưu `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng) | **Ngày**: 2026-11-09 | **Spec**: [spec.md](spec.md)

**Đầu vào**: `specs/002-d1-canvas-luu-t1/spec.md`

## Tóm tắt

Cho người dùng chọn, di chuyển, đổi cỡ, xoá, nhân bản visual trên canvas, hoàn tác/làm lại, rồi lưu `.pbix` sao cho Power BI Desktop vẫn mở được. Chi tiết quyết định ở [research.md](research.md).

Hướng chọn:

1. **Mô hình sửa nằm ngoài `Workspace`.** `Workspace` giữ nguyên bất biến (bản gốc khi mở). Một đối tượng mới `LayoutEditor` giữ bản sao có thể sửa của bố cục từng trang (chỉ trang đã sửa), vùng chọn và hai ngăn xếp hoàn tác dạng ảnh chụp cả trang. `DocumentState.page` trả về trang đã áp phần sửa, nên mọi view đang nhận `ReportPage` theo giá trị tự thấy bố cục mới.
2. **Ghi bằng cách ghép byte.** Đổi vị trí visual chỉ thay các số trong `position` của `visual.json` (như `PBIRPatch` đã làm với tiêu đề), nên mọi byte khác giữ nguyên. Nhân bản là chép `visual.json` rồi đổi `name` và `position`. Xoá là bỏ phần khỏi ZIP, kèm dọn tham chiếu trong bookmark. `PBIXChanges` mở rộng thêm `addedParts` và `removedParts` (hợp đồng Phase W, lead sửa).
3. **Đường lưu có kiểm tra ba lớp**: dựng trong bộ nhớ và đọc lại so với `LayoutEditor`; ghi file tạm cùng thư mục rồi mở lại; thay file bằng `replaceItemAt`. Bản sao lưu nằm ở thư mục hỗ trợ của app. Mọi file dưới `~/Downloads` chỉ được "Lưu thành".
4. **Chế độ Xem / Sửa**: mặc định Xem (giữ nguyên lọc chéo, drill như hiện nay); Sửa (⌘E) tắt tương tác bên trong visual để kéo thả được.
5. **Lưu/hoàn tác/đóng cửa sổ tự quản** trên `DocumentGroup(viewing:)` (không dùng `FileDocument` ghi, vì SwiftUI tự lưu nền vào chỗ cũ, trái Hiến pháp IV). Có bước thử nhanh (T001) để chắc cách gắn dấu "chưa lưu" và hỏi khi đóng chạy được; không chạy được thì dừng và báo bạn.

**Bảo đảm nguyên vẹn**: phần không sửa giữ nguyên từng byte (kiểm bằng test so từng thành viên ZIP); không đụng `DataModel`; chế độ Xem không đổi hành vi; golden Phase B/C giữ nguyên.

## Bối cảnh kỹ thuật

**Ngôn ngữ/Phiên bản**: Swift 6 (SwiftPM). Module `PBIXKit` (ghi), `BIPro` (giao diện)

**Phụ thuộc chính**: không thêm (Hiến pháp III). SwiftUI, AppKit (`NSSavePanel`, `NSWindow`), Foundation

**Lưu trữ**: tệp `.pbix` (ZIP/OPC, định dạng PBIR). Bản sao lưu ở `~/Library/Application Support/BI Pro/Backups/`

**Kiểm thử**: `swift test` (819 test); thêm test `PBIXKitTests` (ghép byte, thêm/bớt phần, round-trip), `BIProTests/Edit/` (logic sửa, hoàn tác, lưu); golden nặng `BIPRO_HEAVY=1 … --filter "Nhom6|ORA|VIS"`; chụp ảnh cửa sổ app; gói test tay `build/d-out/D1/`

**Nền tảng**: macOS 15+ Apple Silicon

**Loại dự án**: ứng dụng desktop (SwiftUI) cộng thư viện `PBIXKit`

**Mục tiêu hiệu năng**: lưu một thay đổi bố cục trên Nhom6 (90 MB) dưới 1 s (SC-004); kéo/đổi cỡ phản hồi dưới 150 ms mỗi khung hình (SC-005)

**Ràng buộc**: không ghi `~/Downloads`; file đích còn nguyên nếu ghi lỗi; phần không sửa khớp byte; chế độ Xem không đổi

**Quy mô**: Nhom6 có 4 trang, 134 phần `visual.json`, trang nặng nhất D1 có 37 visual

## Kiểm tra theo Hiến pháp

*Cổng: phải qua trước Phase 0, kiểm lại sau Phase 1.*

| Nguyên tắc | Kết quả | Ghi chú |
|---|---|---|
| I. Quan sát Power BI trước | Qua, kèm điều kiện | Cấu trúc `position`, `z`, `tabOrder`, id 20 hex đã quan sát trong file thật (research R1). Hành vi kéo/nhân bản/xoá của Power BI Desktop và xử lý bookmark treo chưa quan sát: đánh dấu [SUY ĐOÁN], buổi VM-D1 của bạn kiểm (quickstart §4). Không dịch ngược |
| II. Power BI là chuẩn | Qua | Chỉ đổi toạ độ, không đổi số liệu. Golden Phase B/C chạy lại (SC-006). Tiêu chuẩn cuối là Power BI Desktop mở được file (bạn kiểm tay) |
| III. Native, không thư viện ngoài | Qua | Chỉ SwiftUI/AppKit/Foundation |
| IV. Ranh giới dữ liệu | Qua | Không ghi `~/Downloads` (chặn trong mã, FR-014, test). Test ghi vào `build/d-out/`. `SecurityBindings` bị bỏ khi sửa phần báo cáo (research R13; bản đầu chép nguyên và Power BI Desktop từ chối file) |
| V. Hợp đồng trước, mỗi file một chủ | Qua | Hợp đồng ghi ở `contracts/`; sửa `Contracts.swift` có chủ là lead. Lát này lead tự làm, không giao agy: các file chung (`DocumentState`, `ReportCanvas`, `PBIXWriter`) giao nhau, không tách được. Bảng quyền ở `docs/phase-d-ownership.tsv` ghi chủ từng file mới |

Sau thiết kế (Phase 1), kiểm lại: không phát sinh vi phạm. Một điểm theo dõi: bước thử T001 có thể cho thấy `DocumentGroup(viewing:)` không đủ; khi đó dừng và hỏi bạn (không tự đổi sang `FileDocument` vì phạm IV).

## Cấu trúc dự án

### Tài liệu (tính năng này)

```text
specs/002-d1-canvas-luu-t1/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── layout-editing.md     # hành vi sửa bố cục (lưới, kẹp, chọn, hoàn tác)
│   └── save-pipeline.md      # hợp đồng ghi: thay đổi, thứ tự kiểm tra, lỗi
├── checklists/requirements.md
└── tasks.md                  # do /speckit-tasks tạo
```

### Mã nguồn

```text
Sources/PBIXKit/Writing/
├── Contracts.swift           # SỬA: PBIXChanges thêm addedParts, removedParts
├── PBIXWriter.swift          # SỬA: xử lý thêm/bớt phần, kiểm tra, chính sách sao lưu
├── PBIRLayoutPatch.swift     # MỚI: ghép byte position, đổi name, dọn tham chiếu visual
└── ZipWriter.swift           # giữ nguyên (đã có .bytes và .rawCopy)

Sources/BIPro/Report/Edit/
├── LayoutEditor.swift        # MỚI: bố cục sửa được, vùng chọn, hoàn tác, dirty
├── LayoutGeometry.swift      # MỚI: lưới 8 px, kẹp trang, cỡ tối thiểu, tay nắm (hàm thuần)
├── EditCanvasOverlay.swift   # MỚI: kéo, đổi cỡ, khung chọn, phím
├── DocumentSaver.swift       # MỚI: Save, Save As, sao lưu, kiểm tra file đổi, quy tắc ~/Downloads
└── SpikeDocumentWindow.swift # TẠM (T001), xoá ở T040

Sources/BIPro/
├── DocumentState.swift       # SỬA: giữ LayoutEditor, fileURL, chế độ Xem/Sửa; page trả về trang đã sửa
├── App.swift                 # SỬA: lệnh menu Lưu/Lưu thành/Hoàn tác/Làm lại, giữ DocumentGroup(viewing:)
└── Report/
    ├── ReportCanvas.swift    # SỬA: dùng overlay khi ở chế độ Sửa, tắt hit-test bên trong
    ├── ReportWorkspace.swift # SỬA: nút Xem/Sửa
    └── (Panes/ReportPanes.swift)  # SỬA: Selection pane theo vùng chọn nhiều

Sources/pbix-dump/main.swift  # SỬA: lệnh phụ move-visual, dup-visual, remove-visual (kiểm tay, gói VM sớm)
scripts/build-app.sh          # SỬA: CFBundleTypeRole Viewer → Editor

Tests/PBIXKitTests/           # MỚI: PBIRLayoutPatchTests, PBIXWriterEditTests, EditRoundTripTests (nặng)
Tests/BIProTests/Edit/        # MỚI: LayoutGeometryTests, LayoutEditorTests, DocumentSaverTests, Nhom6 nặng
docs/phase-d-ownership.tsv    # MỚI
docs/phase-d-evidence/        # MỚI: quan sát VM-D1, ảnh chụp
build/d-out/D1/               # MỚI: file test tay + CHECKLIST.md
```

**Quyết định cấu trúc**: tách logic thuần (hình học, hoàn tác, ghép byte) khỏi giao diện để test không cần cửa sổ. Phần ghi nằm hết trong `PBIXKit` để dùng lại cho CLI `pbix-dump` và cho các lát sau (T2/T3).

## Theo dõi độ phức tạp

Không có vi phạm Hiến pháp cần biện minh. Hai điểm ghi nhận:

| Điểm | Vì sao cần | Cách đơn giản hơn bị loại vì |
|---|---|---|
| Sửa `Contracts.swift` (hợp đồng Phase W) | Xoá/nhân bản cần thêm/bớt phần ZIP, hợp đồng cũ chỉ thay phần có sẵn | Ghi đè nguyên `Report/` bằng tay ngoài `PBIXWriter` sẽ bỏ qua bước kiểm tra chung |
| Hoàn tác bằng ảnh chụp cả trang | Đơn giản, đúng ngay với mọi loại thao tác (di chuyển nhiều visual, xoá, nhân bản) | Lệnh đảo ngược từng loại dễ sai khi hoàn tác chồng nhau; trang tối đa vài chục visual nên ảnh chụp rẻ (JSON dùng chung bộ nhớ) |
