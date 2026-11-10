# Kế hoạch triển khai: D2, sửa trường của visual bằng Build pane và lưu `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng) | **Ngày**: 2026-11-10 | **Spec**: [spec.md](spec.md)

**Đầu vào**: `specs/003-d2-build-pane-field-well/spec.md`

## Tóm tắt

Cho người dùng thêm, bỏ, đổi thứ tự, chuyển ô, đổi tên hiển thị (và, khi đã có quan sát, đổi phép gộp) cho trường của một visual đã có, bằng Build pane; visual vẽ lại ngay; hoàn tác chung với D1; lưu T1 mở được trong Power BI Desktop. Chi tiết quyết định ở [research.md](research.md).

Hướng chọn:

1. **Dùng lại bộ máy sửa của D1.** `LayoutEditor` đã giữ bản sao sửa được của từng trang (`PageEdit`), hoàn tác theo ảnh chụp, `isDirty`, và `makeChanges` ghép byte. D2 thêm vào `PageEdit` một bảng `queries` (mã visual → cấu hình trường đã sửa). Một thả trường là một lần `commit` nên một bước hoàn tác, chung ngăn xếp với kéo/đổi cỡ.
2. **Một đường duy nhất cho vẽ lại và lưu.** Hàm `PBIRQueryPatch.apply(...)` nhận `visual.json` gốc cùng cấu hình trường mới, trả `visual.json` mới bằng ghép byte (phần tử `projections` không đổi được chép nguyên byte; phần tử mới do hàm sinh theo mẫu Desktop). Editor phân tích lại byte đó để có `ReportVisual.raw` và `fields` mới, nên cái được vẽ chính là cái sẽ lưu, và bộ đọc truy vấn Phase C (`VisualQuerySpecReader`) dùng nguyên không đổi.
3. **Chỉ làm điều đã quan sát; phần chưa quan sát thì chặn, không đoán.** Cho thêm trường vào một ô chỉ khi tổ hợp (loại visual, ô, loại trường) có trong bảng đã quan sát trong Nhom6 hoặc đã được VM-D2 xác nhận. Bỏ một trường còn được nhắc ở sắp xếp, bộ lọc cấp visual hoặc định dạng thì chặn và báo rõ cho tới khi VM-D2 cho biết Desktop xử lý ra sao. Phép gộp chỉ làm sau VM-D2 (Nhom6 không có mẫu).
4. **Kéo thả từ pane Dữ liệu** bằng `onDrag` / `onDrop` với `NSItemProvider` của SwiftUI/AppKit (đã thử ở T001: `draggable`/`Transferable` không chạy, xem research R9), có bước thử nhanh (T001) như D1 để chắc nó chạy được trong `DocumentGroup(viewing:)`; không chạy được thì giữ menu "Thêm trường" và báo bạn. Ô tick của pane Dữ liệu (hiện chỉ hiển thị trường đang dùng) thành đường thêm/bỏ nhanh vào ô mặc định.
5. **Vẽ lại đúng một visual.** `LiveVisualView` chỉ nạp lại khi bộ lọc đổi; thêm cấu hình trường của visual vào khoá nạp để sửa trường thì đúng visual đó nạp lại, các visual khác không.

**Bảo đảm nguyên vẹn**: `visual.json` không sửa trường giữ nguyên từng byte; phần của `visual.json` ngoài `queryState` giữ nguyên; không đụng `DataModel`; golden Phase B/C giữ nguyên; lưu theo đúng đường kiểm ba lớp của D1.

## Bối cảnh kỹ thuật

**Ngôn ngữ/Phiên bản**: Swift 6 (SwiftPM). Module `PBIXKit` (đọc/ghi `.pbix`, ghép byte), `BIPro` (giao diện, editor)

**Phụ thuộc chính**: không thêm (Hiến pháp III). SwiftUI (`onDrag`, `onDrop`), AppKit (`NSItemProvider`), Foundation

**Lưu trữ**: tệp `.pbix` (ZIP/OPC, định dạng PBIR); đường lưu, sao lưu, `SecurityBindings` như D1

**Kiểm thử**: `swift test` (914 test hiện có); thêm `PBIXKitTests/PBIRQueryPatchTests` (ghép byte `queryState`), `BIProTests/Edit/` (`FieldEditorTests`, `WellRulesTests`, hoàn tác đan xen D1), test nặng `D2Nhom6` (sửa trường, lưu, mở lại, so số liệu với truy vấn DAX); golden `BIPRO_HEAVY=1 … --filter "Nhom6|ORA|VIS"`; chụp ảnh cửa sổ app; gói test tay `build/d-out/D2/`

**Nền tảng**: macOS 15+ Apple Silicon

**Loại dự án**: ứng dụng desktop (SwiftUI) cộng thư viện `PBIXKit`

**Mục tiêu hiệu năng**: thả trường rồi visual vẽ lại xong dưới 150 ms với visual thường và dưới 1 s với visual nặng nhất của Nhom6 (SC-005; mốc trước khi sửa ở `measurements.md`); lưu sau khi sửa trường dưới 1 s (đã đạt 0,22–0,52 s ở D1)

**Ràng buộc**: như D1 (không ghi `~/Downloads`, file đích còn nguyên nếu ghi lỗi, phần không sửa khớp byte); không để tham chiếu treo tới trường đã bỏ trong file lưu ra

**Quy mô**: Nhom6 có 134 `visual.json`, trong đó 89 có `queryState` (171 trường: 106 measure, 47 cột, 18 cấp hierarchy, 0 phép gộp); 4 visual có `sortDefinition`, 1 có `filterConfig`, 14 chỗ định dạng tham chiếu trường qua `metadata`

## Kiểm tra theo Hiến pháp

*Cổng: phải qua trước Phase 0, kiểm lại sau Phase 1.*

| Nguyên tắc | Kết quả | Ghi chú |
|---|---|---|
| I. Quan sát Power BI trước | Qua, kèm điều kiện | Cấu trúc `queryState`, `projections`, `queryRef`, `nativeQueryRef`, `displayName` đã quan sát trong 171 trường thật (research R1). Phần chưa quan sát: ghi phép gộp, quy tắc mỗi ô nhận loại trường nào ngoài tổ hợp có trong Nhom6, Desktop xử lý sắp xếp/bộ lọc/định dạng khi bỏ trường, ô trở nên trống. Đánh dấu [SUY ĐOÁN], chặn trong mã (R5, R7), buổi VM-D2 của bạn kiểm. Không dịch ngược |
| II. Power BI là chuẩn | Qua | Số liệu vẫn do engine DAX và bộ sinh truy vấn trùng văn bản Performance Analyzer; không có đường tính thứ hai (FR-008). Golden Phase B/C chạy lại (SC-006). Tiêu chuẩn cuối là Power BI Desktop mở được và vẽ cùng số (bạn kiểm tay) |
| III. Native, không thư viện ngoài | Qua | Chỉ SwiftUI/Foundation |
| IV. Ranh giới dữ liệu | Qua | Không ghi `~/Downloads`; test ghi vào `build/d-out/`. `SecurityBindings` bị bỏ khi sửa phần báo cáo (D1, R13); không đọc nội dung nó |
| V. Hợp đồng trước, mỗi file một chủ | Qua | Hợp đồng ở `contracts/`; `PBIXKit` (`PBIRQueryPatch`) và `BIPro` (editor, pane) tách bạch; lát này lead tự làm (các file chung `LayoutEditor`, `ReportPanes`, `LiveVisual` giao nhau, không tách worker được). Bảng quyền ở `docs/phase-d-ownership.tsv` ghi chủ từng file mới |

Sau thiết kế (Phase 1), kiểm lại: không phát sinh vi phạm. Hai điểm theo dõi: bước thử kéo thả (T001) và việc VM-D2 có xác nhận được các điều đang [SUY ĐOÁN] hay không; chưa xác nhận thì phần đó giữ ở trạng thái chặn.

## Cấu trúc dự án

### Tài liệu (tính năng này)

```text
specs/003-d2-build-pane-field-well/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── field-editing.md       # hành vi sửa trường: ô, quy tắc nhận, thao tác, hoàn tác, chặn
│   └── query-state-patch.md   # hợp đồng ghi: cấu trúc queryState, phần tử mẫu, kiểm tra
├── checklists/requirements.md
└── tasks.md                   # do /speckit-tasks tạo
```

### Mã nguồn

```text
Sources/PBIXKit/Writing/
├── PBIRQueryPatch.swift       # MỚI: ghép byte queryState (giữ nguyên phần tử cũ, sinh phần tử mới, đổi displayName)
└── (JSONCursor trong PBIRPatch.swift dùng lại)

Sources/PBIXKit/
└── ReportDefinition.swift     # SỬA nhỏ: ReportField có nativeQueryRef và active (đọc được, dùng khi ghi)

Sources/BIPro/Report/Edit/
├── FieldEditor.swift          # MỚI: thao tác thêm/bỏ/đổi thứ tự/chuyển ô/đổi tên trên cấu hình trường (hàm thuần)
├── WellRules.swift            # MỚI: bảng ô theo loại visual, loại trường nhận, số lượng tối đa (đã quan sát / chưa)
├── FieldReferences.swift      # MỚI: tìm nơi khác trong visual.json nhắc tới một trường (sort, filter, metadata)
├── LayoutEditor.swift         # SỬA: PageEdit.queries, thao tác sửa trường qua commit, makeChanges gọi PBIRQueryPatch
└── DocumentSaver.swift        # SỬA: verifyLayout kiểm cả trường

Sources/BIPro/Panes/
├── ReportPanes.swift          # SỬA: Build pane sửa được (ô nhận thả, menu thêm, bỏ, kéo đổi thứ tự, đổi tên)
├── DataPane.swift             # SỬA: trường kéo được; ô tick thêm/bỏ vào ô mặc định
└── VisualCatalog.swift        # SỬA: nhãn ô lấy từ WellRules

Sources/BIPro/Report/
└── LiveVisual.swift           # SỬA: LoadKey thêm cấu hình trường của visual

Sources/pbix-dump/main.swift   # SỬA: lệnh phụ add-field, remove-field, move-field (gói VM sớm)

Tests/PBIXKitTests/PBIRQueryPatchTests.swift
Tests/BIProTests/Edit/{FieldEditorTests, WellRulesTests, FieldReferencesTests, FieldEditingUndoTests, D2Nhom6Tests}.swift
docs/phase-d-ownership.tsv     # SỬA: thêm các file D2
docs/phase-d-evidence/vm-d2/   # MỚI: quan sát VM-D2, ảnh chụp
build/d-out/D2/                # MỚI: file test tay + CHECKLIST.md + VM-D2-QUAN-SAT.md
```

**Quyết định cấu trúc**: phần ghi (`PBIRQueryPatch`) nằm trong `PBIXKit` để dùng lại cho CLI và các lát sau (tạo visual mới ở lát tiếp theo cũng sinh `queryState`); phần luật và thao tác (`FieldEditor`, `WellRules`) là hàm thuần để test không cần cửa sổ.

## Theo dõi độ phức tạp

Không có vi phạm Hiến pháp cần biện minh. Hai điểm ghi nhận:

| Điểm | Vì sao cần | Cách đơn giản hơn bị loại vì |
|---|---|---|
| Sinh `visual.json` mới bằng ghép byte rồi phân tích lại để vẽ | Một nguồn sự thật cho vẽ và lưu; bộ đọc truy vấn không phải đổi | Sửa mô hình bộ nhớ riêng rồi sinh JSON lúc lưu: hai đường có thể lệch, và lỗi chỉ lộ ở Power BI Desktop |
| Chặn thay vì đoán ở các điểm chưa quan sát (ô nhận gì, tham chiếu tới trường đã bỏ, phép gộp) | Bài học D1: ghi sai (giữ `SecurityBindings`) làm Power BI Desktop từ chối cả file | Cho thêm tự do rồi sửa sau: file hỏng nằm trên đĩa người dùng |
