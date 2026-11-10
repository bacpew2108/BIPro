# Kế hoạch triển khai: D4, Format pane sửa được và lưu `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng) | **Ngày**: 2026-11-10 | **Spec**: [spec.md](spec.md)

**Đầu vào**: `specs/006-d4-format-pane/spec.md`; quan sát VM-D4 ở `docs/phase-d-evidence/vm-d4/QUAN-SAT.md`

## Tóm tắt

Format pane hiện chỉ liệt kê các khoá đã có trong `visual.json` và không sửa được. D4 làm nó sửa được cho cả hai phạm vi (Visual = `objects`, Chung = `visualContainerObjects`), ghi `.pbix` T1 và mở lại được ở Power BI Desktop. Quyết định chi tiết ở [research.md](research.md).

Hướng chọn:

1. **Danh mục thuộc tính dựng từ quan sát, là dữ liệu chứ không phải suy đoán.** `FormatCatalog` (BIPro) là bảng tĩnh: theo phạm vi và nhóm loại visual, mỗi thẻ có tên khoá trong file, tên hiển thị tiếng Việt, và danh sách thuộc tính (tên khoá, kiểu điều khiển, giá trị cho phép, nguồn quan sát, đường vẽ đã đọc hay chưa). Chỉ có thuộc tính đã thấy ở Nhom6 hoặc VM-D4 (SC-005). Tên thẻ trong giao diện không trùng tên khoá (R3), nên bảng này là phần quan trọng nhất.
2. **Một cách ghi duy nhất, ghép byte.** `PBIRFormatPatch` (PBIXKit) nhận danh sách `FormatEdit` (đặt thuộc tính, bỏ thuộc tính, bỏ cả khoá) và ghép vào `visual.json` bằng `JSONCursor` như `PBIRQueryPatch` (D2): thay đúng đoạn byte của giá trị, thêm thuộc tính mới ở cuối `properties`, thêm khoá mới ở cuối `objects`/`visualContainerObjects`, tạo khoá phạm vi mới ở đúng chỗ (R2). Phần không đụng giữ từng byte; kết quả được đọc lại và so với cấu trúc mong đợi.
3. **Trạng thái sửa theo mẫu D2/D3.** `PageEdit` thêm `formats` (mã visual → danh sách `FormatEdit` đã gộp, giá trị cuối thắng). `LayoutEditor.setFormat/resetFormat` cập nhật `raw`, `objects`, `containerObjects` của `ReportVisual` trong bộ nhớ nên đường vẽ vẽ lại ngay; mỗi lần sửa là một bước hoàn tác chung ngăn xếp, gộp theo khoá khi sửa liên tiếp cùng một thuộc tính (cơ chế `lastCoalesce` của D1). `makeChanges` thêm một bước patch trước bước `patch` cuối; `DocumentSaver.verifyLayout` so định dạng đọc lại với trạng thái đang sửa.
4. **Chỉ sửa mục chung.** Mục có `selector` kiểu `metadata`/`data`/`id` khác `default` hiện chỉ-đọc và giữ nguyên byte (FR-007). Mục mới của `cardVisual` ghi `selector:{id:default}` sau `properties` như Desktop (R6).
5. **Giao diện.** `FormatPane` (file mới, thay `FormatCard` chỉ-đọc) vẽ thẻ theo danh mục: công tắc, ô số, danh sách, bảng màu (lưới theme + ô hex + "Reset to default"), ô chữ; nút "Đặt lại" theo thẻ. Thuộc tính ngoài danh mục (khoá lạ có sẵn trong file) hiện chỉ-đọc ở một mục "Khác (chỉ đọc)". Mờ kèm lý do ở chế độ Xem, báo cáo định dạng cũ, nhiều visual được chọn.

**Bảo đảm nguyên vẹn**: part không sửa khớp byte; `DataModel` không đụng; golden Phase B/C và test D1 đến D5 giữ nguyên số; visual không sửa vẽ cùng số; file gốc `~/Downloads` chỉ đọc; không bịa khoá.

## Bối cảnh kỹ thuật

**Ngôn ngữ/Phiên bản**: Swift 6 (SwiftPM). Module `PBIXKit` (đọc/ghi `.pbix`, ghép byte), `BIPro` (giao diện, editor)

**Phụ thuộc chính**: không thêm (Hiến pháp III). SwiftUI (`Picker`, `Slider`/`TextField`, `popover`), Foundation

**Lưu trữ**: tệp `.pbix` (ZIP/OPC, PBIR); đường lưu, sao lưu, `SecurityBindings` như D1

**Kiểm thử**: `swift test` (1116 test hiện có); thêm `PBIXKitTests/PBIRFormatPatchTests`, `BIProTests/Edit/{FormatCatalogTests, FormatValueTests, FormatEditingTests, FormatUndoTests, FormatSavingTests, D4Nhom6Tests}`; golden `BIPRO_HEAVY=1 … --filter "Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D5Nhom6|D4Nhom6|EditNhom6|BatchedSerial"` (88 hiện có); chụp ảnh cửa sổ app; gói thử tay `build/d-out/D4/` và kiểm ở Desktop (VM-D4 vòng 2 khi có quyền)

**Nền tảng**: macOS 15+ Apple Silicon

**Loại dự án**: ứng dụng desktop (SwiftUI) cộng thư viện `PBIXKit`

**Mục tiêu hiệu năng**: mỗi lần sửa định dạng thấy trên canvas dưới 0,5 s (SC-001); lưu sau chuỗi sửa dưới 1 s (SC-003, đã đạt 0,17 đến 0,27 s ở D1 đến D5)

**Ràng buộc**: như D1 (không ghi `~/Downloads`, file đích còn nguyên nếu ghi lỗi, phần không sửa khớp byte); không bịa khoá; mục có selector chỉ-đọc

**Quy mô**: Nhom6 có 134 visual, 25 khoá `objects` (72 tên thuộc tính), 7 khoá `visualContainerObjects`; danh mục bản đầu phủ khoảng 11 khoá `objects` và 8 khoá `visualContainerObjects` (R4)

## Kiểm tra theo Hiến pháp

*Cổng: phải qua trước Phase 0, kiểm lại sau Phase 1.*

| Nguyên tắc | Kết quả | Ghi chú |
|---|---|---|
| I. Quan sát Power BI trước | Qua, kèm điều kiện | Cấu trúc `objects`, kiểu giá trị đọc từ Nhom6; cách Desktop ghi từng thao tác quan sát ở VM-D4 (R1 đến R7). Chưa quan sát: matrix, `dataPoint`, màu viền/nền/bóng, phông, khoảng số (R4 liệt kê); những chỗ đó chỉ-đọc hoặc không có trong danh mục. Không dịch ngược; không tải schema thuộc tính (schema `visualContainer` công khai chỉ mô tả khung) |
| II. Power BI là chuẩn | Qua | Không đổi đường tính hay đường vẽ; thuộc tính chưa vẽ được đánh dấu, ghi vẫn đúng cấu trúc Desktop. Tiêu chuẩn cuối là Desktop mở được và vẽ cùng (kiểm tay hoặc Claude khi được phép) |
| III. Native, không thư viện ngoài | Qua | Chỉ SwiftUI/Foundation |
| IV. Ranh giới dữ liệu | Qua | Không ghi `~/Downloads`; test ghi vào `build/d-out/`. `SecurityBindings` bỏ như D1. Hiến pháp: agent không điều khiển VM; VM-D4 làm theo lời cho phép của người dùng cho lần này |
| V. Hợp đồng trước, mỗi file một chủ | Qua | Hợp đồng ở `contracts/`; `PBIXKit` (`PBIRFormatPatch`) và `BIPro` (danh mục, editor, pane) tách bạch; lát này lead tự làm (`LayoutEditor`, `DocumentState`, `ReportPanes` giao nhau). Bảng quyền ở `docs/phase-d-ownership.tsv` ghi chủ từng file mới |

Sau thiết kế (Phase 1), kiểm lại: không phát sinh vi phạm. Điểm theo dõi: danh mục quá hẹp so với kỳ vọng người dùng (R4, R12), và ô kiểu số/danh sách chưa có khoảng quan sát.

## Cấu trúc dự án

### Tài liệu (tính năng này)

```text
specs/006-d4-format-pane/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── format-editing.md   # hành vi: điều khiển, từ chối, gộp bước, đặt lại, thông báo
│   └── format-save.md      # ghi gì cho từng thao tác, thứ tự khoá, kiểm lúc lưu
├── checklists/requirements.md
└── tasks.md                # do /speckit-tasks tạo
```

### Mã nguồn

```text
Sources/PBIXKit/Writing/
└── PBIRFormatPatch.swift      # MỚI: FormatEdit; apply (ghép byte objects/visualContainerObjects); read; kiểm cấu trúc

Sources/BIPro/Report/Edit/
├── FormatCatalog.swift        # MỚI: bảng thẻ/thuộc tính theo phạm vi và nhóm loại (dữ liệu quan sát)
├── FormatValue.swift          # MỚI: FormatValue (đọc từ JSON), chuẩn hoá và kiểm giá trị, dựng JSON giá trị (D/L, nháy đơn, màu)
├── LayoutEditor+Format.swift  # MỚI: setFormat, resetFormat, gộp bước, cập nhật raw/objects/containerObjects
├── LayoutEditor.swift         # SỬA nhỏ: PageEdit.formats; makeChanges thêm bước patch; commit nhận khoá gộp
└── DocumentSaver.swift        # SỬA nhỏ: verifyLayout so định dạng

Sources/BIPro/Panes/
├── FormatPane.swift           # MỚI: giao diện Format pane (thay FormatCard chỉ-đọc trong ReportPanes)
└── ReportPanes.swift          # SỬA: gọi FormatPane; bỏ FormatCard

Sources/BIPro/DocumentState.swift  # SỬA nhỏ: bọc setFormat/resetFormat, trạng thái chọn thẻ mở

Tests/PBIXKitTests/PBIRFormatPatchTests.swift
Tests/BIProTests/Edit/{FormatCatalogTests, FormatValueTests, FormatEditingTests, FormatUndoTests, FormatSavingTests, D4Nhom6Tests}.swift
docs/phase-d-ownership.tsv     # SỬA: thêm các file D4
docs/phase-d-evidence/vm-d4/   # quan sát VM-D4 (đã có), ảnh app, kết quả kiểm Desktop
build/d-out/D4/                # gói thử tay + CHECKLIST.md
```

**Quyết định cấu trúc**: phần ghi (`PBIRFormatPatch`) nằm trong `PBIXKit` để CLI và các lát sau (D6, định dạng trang) dùng lại; danh mục và kiểm giá trị là giá trị thuần (`FormatCatalog`, `FormatValue`) để test không cần cửa sổ.

## Theo dõi độ phức tạp

Không có vi phạm Hiến pháp cần biện minh. Hai điểm ghi nhận:

| Điểm | Vì sao cần | Cách đơn giản hơn bị loại vì |
|---|---|---|
| Danh mục viết tay thay vì sinh từ schema | Schema công khai không liệt kê thuộc tính; tên thẻ giao diện ≠ tên khoá (R3) | Sinh tự động từ `visual.json` hiện có: không biết thuộc tính còn thêm được, không có tên Việt, không biết kiểu điều khiển |
| Ghép byte thay vì dựng lại `objects` | Giữ từng byte phần không sửa (D1 đến D5) và thứ tự khoá | Ghi lại cả `visual.json` bằng serializer: đổi thứ tự khoá, khác mọi lát trước; Desktop tự chuẩn hoá khi lưu nhưng ta không cần bắt chước |
