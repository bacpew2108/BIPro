# Kế hoạch triển khai: D3, thêm visual mới và đổi loại visual, lưu `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng) | **Ngày**: 2026-11-10 | **Spec**: [spec.md](spec.md)

**Đầu vào**: `specs/004-d3-them-visual-doi-loai/spec.md`

## Tóm tắt

Cho người dùng thêm visual mới (từ thư viện của Build pane hoặc nút ribbon), đổi loại visual đã chọn (giữ trường), sửa nội dung hộp văn bản, hoàn tác chung với D1 và D2, rồi lưu T1 mở được trong Power BI Desktop. Chi tiết quyết định ở [research.md](research.md).

Hướng chọn:

1. **Dùng lại bộ máy D1 + D2.** Visual mới đi vào `PageEdit.visuals` và `PageEdit.added` y như bản sao ở D1 (nên lưu bằng `addedParts`, xoá, nhân bản, hoàn tác đã có). Đổi loại và sửa văn bản thêm hai bảng nhỏ vào `PageEdit` (`retyped`, `texts`) bên cạnh `queries` của D2; mỗi thao tác là một `commit`, một bước hoàn tác.
2. **Công thức ghi xác định, áp lại lên byte trên đĩa lúc lưu.** Với visual đã có trong file, `makeChanges` áp theo thứ tự: đổi `visualType` và tỉa `objects` → sửa văn bản → ghi `queryState` (D2) → ghép vị trí (D1). Với visual mới, cùng chuỗi áp lên `visual.json` mẫu đã sinh. Cái vẽ trong app là cái phân tích lại từ chính byte đó (như D2), nên vẽ và lưu không thể lệch.
3. **Mẫu `visual.json` mới sinh trong `PBIXKit`** (`PBIRNewVisual`), khoá theo đúng thứ tự và tập khoá quan sát trong Nhom6 cho từng loại; `$schema` lấy từ một visual có sẵn của chính báo cáo. `PBIRQueryPatch` biết tạo `visual.query.queryState` khi visual chưa có.
4. **Chỉ làm điều đã quan sát; phần chưa quan sát thì chặn, không đoán** (bài học D1 và D2). Loại thêm được ở bản đầu = loại có ô ở mức `observed` trong `WellRules` (11 loại + hộp văn bản); các biến thể cột/thanh/vùng khác (cột nhóm, xếp chồng…) mở sau buổi VM-D3. Đổi loại bị chặn khi làm mất trường còn dùng ở sắp xếp/bộ lọc/định dạng (quy tắc D2). Định dạng `objects` khi đổi loại chỉ giữ khoá thấy trên visual cùng loại đích trong chính báo cáo.
5. **Giao diện**: thư viện biểu tượng thành bấm được (không chọn visual: thêm; chọn một visual: đổi loại; loại chưa hỗ trợ: mờ kèm lý do); nút ribbon "Visual mới" và "Hộp văn bản" nối vào cùng hàm; hộp văn bản có ô nội dung ở Build pane; vùng nhìn thấy của canvas báo về `DocumentState` để đặt visual mới ở giữa.

**Bảo đảm nguyên vẹn**: visual không đụng tới giữ nguyên từng byte; phần mới và phần đổi loại chỉ chạm các khoá đã nêu; không đụng `DataModel`; golden Phase B/C giữ nguyên; đường lưu ba lớp của D1 giữ nguyên và `verifyLayout` kiểm thêm loại, văn bản.

## Bối cảnh kỹ thuật

**Ngôn ngữ/Phiên bản**: Swift 6 (SwiftPM). Module `PBIXKit` (mẫu và ghép byte), `BIPro` (editor, giao diện)

**Phụ thuộc chính**: không thêm (Hiến pháp III). SwiftUI (`onScrollGeometryChange` của macOS 15), Foundation

**Lưu trữ**: tệp `.pbix` (ZIP/OPC, PBIR); đường lưu, sao lưu, `SecurityBindings` như D1

**Kiểm thử**: `swift test` (968 test hiện có); thêm `PBIXKitTests` (`PBIRNewVisualTests`, `PBIRVisualTypePatchTests`, `PBIRTextPatchTests`, thêm ca tạo `queryState` cho `PBIRQueryPatchTests`), `BIProTests/Edit/` (`InsertVisualTests`, `TypeChangeTests`, `TextboxEditingTests`, mở rộng `FieldEditingUndoTests` chuỗi ngẫu nhiên), test nặng `D3Nhom6` (thêm, đổi loại, thả trường, lưu, mở lại, so số với DAX viết tay); golden `BIPRO_HEAVY=1 … --filter "Nhom6|ORA|VIS"`; chụp ảnh cửa sổ app; gói test tay `build/d-out/D3/`

**Nền tảng**: macOS 15+ Apple Silicon

**Loại dự án**: ứng dụng desktop (SwiftUI) cộng thư viện `PBIXKit`

**Mục tiêu hiệu năng**: kết quả thêm hoặc đổi loại hiện ngay; vẽ lại dưới 150 ms với visual thường và dưới 1 s với visual nặng (SC-005, mốc `specs/003-d2-build-pane-field-well/measurements.md`); lưu dưới 1 s

**Ràng buộc**: như D1 và D2 (không ghi `~/Downloads`, file đích còn nguyên nếu ghi lỗi, phần không sửa khớp byte, không tham chiếu treo tới trường đã bỏ)

**Quy mô**: Nhom6 có 134 `visual.json` (card 50, image 30, slicer 17, textbox 7, 12 biểu đồ…); trang nặng nhất D1 có 37 visual

## Kiểm tra theo Hiến pháp

*Cổng: phải qua trước Phase 0, kiểm lại sau Phase 1.*

| Nguyên tắc | Kết quả | Ghi chú |
|---|---|---|
| I. Quan sát Power BI trước | Qua, kèm điều kiện | Tập khoá của `visual.json` theo loại (card, slicer, textbox, biểu đồ), cỡ thường gặp và `z` khi dán đã quan sát (research R1). Chưa quan sát: khoá bắt buộc của visual mới do Desktop ghi, cỡ mặc định, ánh xạ ô khi đổi loại, giữ hay bỏ `objects`, `queryState` rỗng. Đánh dấu [SUY ĐOÁN], chặn hoặc chọn phương án thận trọng trong mã (R2, R4, R7, R8), buổi VM-D3 của bạn kiểm. Không dịch ngược |
| II. Power BI là chuẩn | Qua | Số liệu vẫn do engine DAX và bộ sinh truy vấn trùng văn bản Performance Analyzer; không có đường tính thứ hai (FR-018). Golden Phase B/C chạy lại (SC-006). Tiêu chuẩn cuối là Power BI Desktop mở được và vẽ cùng số (bạn kiểm tay) |
| III. Native, không thư viện ngoài | Qua | Chỉ SwiftUI/Foundation |
| IV. Ranh giới dữ liệu | Qua | Không ghi `~/Downloads`; test ghi vào `build/d-out/`. `SecurityBindings` bị bỏ khi sửa phần báo cáo (D1, R13); không đọc nội dung nó |
| V. Hợp đồng trước, mỗi file một chủ | Qua | Hợp đồng ở `contracts/`; `PBIXKit` (mẫu, ghép byte) và `BIPro` (editor, pane) tách bạch; lát này lead tự làm (các file chung `LayoutEditor`, `ReportPanes`, `VisualCatalog`, `PBIRQueryPatch` giao nhau với D1 và D2, không tách worker được). Bảng quyền ở `docs/phase-d-ownership.tsv` ghi chủ từng file mới |

Sau thiết kế (Phase 1), kiểm lại: không phát sinh vi phạm. Hai điểm theo dõi: kết quả buổi VM-D3 có xác nhận được các điều đang [SUY ĐOÁN] hay không (chưa xác nhận thì phần đó giữ phương án thận trọng), và việc `onScrollGeometryChange` báo đúng vùng nhìn thấy khi thu phóng (nếu không thì đặt ở giữa trang).

## Cấu trúc dự án

### Tài liệu (tính năng này)

```text
specs/004-d3-them-visual-doi-loai/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── insert-and-retype.md      # hành vi thêm, đổi loại, hộp văn bản: điều kiện, từ chối, hoàn tác
│   └── visual-json-patches.md    # hợp đồng ghi: mẫu visual mới, đổi visualType, tỉa objects, văn bản, tạo queryState
├── checklists/requirements.md
└── tasks.md                      # do /speckit-tasks tạo
```

### Mã nguồn

```text
Sources/PBIXKit/Writing/
├── PBIRNewVisual.swift         # MỚI: sinh visual.json của visual mới theo loại; cỡ mặc định theo loại
├── PBIRVisualPatch.swift       # MỚI: đổi visualType, tỉa khoá objects, sửa văn bản hộp văn bản (ghép byte)
└── PBIRQueryPatch.swift        # SỬA: tạo visual.query.queryState khi visual chưa có

Sources/BIPro/Report/Edit/
├── VisualTypes.swift           # MỚI: loại thêm được/đổi tới được, cỡ mặc định, họ loại (hàm thuần)
├── TypeChange.swift            # MỚI: ánh xạ ô khi đổi loại, danh sách trường bị bỏ, kiểm tham chiếu (hàm thuần)
├── LayoutEditor.swift          # SỬA: insertVisual, changeType, editText; PageEdit.retyped/texts; makeChanges áp công thức
├── DocumentSaver.swift         # SỬA: verifyLayout kiểm loại và văn bản
└── (FieldEditor.swift, WellRules.swift dùng lại)

Sources/BIPro/Panes/
├── ReportPanes.swift           # SỬA: thư viện biểu tượng bấm được
├── BuildWells.swift            # SỬA: ô nội dung của hộp văn bản, thông báo trường bị bỏ khi đổi loại
└── VisualCatalog.swift         # SỬA: cờ hỗ trợ theo VisualTypes

Sources/BIPro/
├── DocumentState.swift         # SỬA: vùng nhìn thấy của canvas, insertVisual/changeType tiện lợi
├── Report/ReportCanvas.swift   # SỬA: báo vùng nhìn thấy (onScrollGeometryChange)
└── Shell/Ribbon.swift          # SỬA: nối nút "Visual mới", "Hộp văn bản"

Sources/pbix-dump/main.swift    # SỬA: lệnh phụ add-visual, set-visual-type (gói VM sớm)

Tests/PBIXKitTests/{PBIRNewVisualTests, PBIRVisualPatchTests}.swift
Tests/BIProTests/Edit/{InsertVisualTests, TypeChangeTests, TextboxEditingTests, D3Nhom6Tests}.swift
docs/phase-d-ownership.tsv      # SỬA: thêm các file D3
docs/phase-d-evidence/vm-d3/    # MỚI: quan sát VM-D3, ảnh chụp
build/d-out/D3/                 # MỚI: file test tay + CHECKLIST.md + VM-D3-QUAN-SAT.md
```

**Quyết định cấu trúc**: phần sinh và ghép byte nằm trong `PBIXKit` để dùng lại cho CLI và các lát sau (tạo trang, Format pane sinh `objects`); phần luật (loại, ánh xạ ô) là hàm thuần để test không cần cửa sổ.

## Theo dõi độ phức tạp

Không có vi phạm Hiến pháp cần biện minh. Hai điểm ghi nhận:

| Điểm | Vì sao cần | Cách đơn giản hơn bị loại vì |
|---|---|---|
| Áp lại công thức (đổi loại → văn bản → trường → vị trí) lên byte trên đĩa lúc lưu, thay vì lưu byte cuối trong bộ nhớ | Lưu lần hai sau khi file đã đổi vẫn đúng và không ghi đè phần Desktop hay người dùng đổi ngoài; cùng mô hình với D1 và D2 | Giữ nguyên byte cuối của mọi visual đã sửa: lệch ngay khi file trên đĩa khác bản lúc mở |
| Giữ khoá `objects` theo bằng chứng của chính báo cáo (khoá thấy trên visual cùng loại đích) | Không có bảng "khoá hợp lệ theo loại" chính thức; ghi khoá sai có thể làm Desktop từ chối file | Giữ nguyên mọi `objects` (có thể không hợp lệ) hoặc bỏ hết (mất định dạng vô cớ) |
