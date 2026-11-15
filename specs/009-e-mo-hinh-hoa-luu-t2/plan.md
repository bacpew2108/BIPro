# Kế hoạch triển khai Phase E: mô hình hoá và lưu tầng T2

**Đặc tả**: [spec.md](spec.md) · **Quan sát**: `docs/phase-e-evidence/vm-e1/QUAN-SAT.md` · **Quyết định**: [research.md](research.md) R1–R12 · **Dữ liệu**: [data-model.md](data-model.md) · **Hợp đồng**: [contracts/](contracts/) · **Chạy thử**: [quickstart.md](quickstart.md)

## Bối cảnh kỹ thuật

- Swift/SwiftUI, các module: `PBIXKit` (đọc, ghi metadata và ABF), `ColumnStore` (cột đã giải mã, lược đồ, quan hệ), `DAXEngine` (parse, bind, chạy), `BIPro` (giao diện, `LayoutEditor`, `DocumentSaver`, Table/Model/TMDL View). SQLite của hệ điều hành (đã dùng ở `MetadataWriter`). Không thêm thư viện ngoài.
- Hiện trạng đọc: `Workspace` bất biến (`metadata`, `abf`, engine tạo lười từ `Catalog(metadata:)`). `ModelMetadata` chỉ đọc. Ghi: `PBIXChanges.measures` → `PBIXWriter.rebuiltDataModel` → `MetadataWriter.addMeasure` → `ABFWriter.rebuild` → `DataModelStream.compress`. Hoàn tác: `LayoutEditor` giữ `undoStack` các `LayoutSnapshot`.
- Ràng buộc: chỉ ghi phần đã quan sát (R3 đến R8); mô hình mở trong Desktop không được báo hỏng; golden Phase B/C và test D1 đến D7 vẫn qua; lưu T2 trên Nhom6 dưới 3 giây (SC-004), vẽ lại visual sau khi đổi mô hình dưới 1 giây.

## Kiểm tra theo hiến pháp

- **Quan sát trước, không dịch ngược**: VM-E1 xong (tạo/sửa measure, hướng lọc quan hệ, cấu trúc lưu trữ quan hệ). Phần còn [SUY ĐOÁN] được chia thành các buổi VM-E2 đến VM-E4 đặt ngay trước từng câu chuyện (tasks sẽ ghi); câu chuyện chưa quan sát thì hiện "(chưa kiểm)" chỉ đọc (FR-019).
- **VM**: hiến pháp "agent không điều khiển VM" giữ; VM-E1 chạy theo lời cho phép của bạn ("Ok, có thể dùng VM", 2026-11-14), mỗi buổi sau xin lại hoặc bạn làm tay.
- **Golden**: không đổi engine tính toán; thêm test golden cho measure mới (số khớp DAX viết tay) và cho quan hệ tạo lại (số trở về như trước). Chạy golden nặng ở cuối mỗi câu chuyện đụng engine.
- **Thư viện ngoài**: không. **Dữ liệu**: file gốc `~/Downloads` chỉ đọc, thử trên bản sao ở `build/e-out/`; `SecurityBindings` chỉ chép byte (R9).

## Thiết kế

1. **Mô hình sửa được** (`PBIXKit/Writing/ModelEdit.swift`, mới): `ModelEdit` là enum thao tác (thêm, sửa, xoá measure; sửa thuộc tính quan hệ; sửa thuộc tính cột; ghi `DiagramLayout`), `ModelEdits` là danh sách có thứ tự gộp được. `ModelMetadata.applying(_ edits:)` trả `ModelMetadata` mới (đọc "mô hình hiệu lực"), không đụng ABF. Một nguồn sự thật cho cả giao diện, engine và lưu (R1).
2. **Ghi T2** (`MetadataWriter`): thêm `updateMeasure`, `deleteMeasure`, `updateRelationship`, `updateColumn`; mọi thao tác đặt `ModifiedTime`, `DBPROPERTIES` như Desktop (QUAN-SAT mục 1 đến 3), dùng chung bộ đếm `MAXID`. `PBIXChanges` thay `measures: [NewMeasure]` bằng `modelEdits: ModelEdits` (giữ `measures` như tiện ích cũ) và thêm `diagramLayout: Data?`; `tier` = `.metadata` khi có `modelEdits` (R2).
3. **Suy kiểu và định dạng measure** (`MeasureTyping`, BIPro): chạy biểu thức qua engine (`EVALUATE ROW`) để lấy kiểu kết quả → `DataType` và `FormatString` mặc định như Desktop (mục R3); lỗi cú pháp/bind thì chặn.
4. **Engine nạp lại** (`ModelRuntime`, BIPro): giữ `ColumnStore` đã giải mã của `Workspace`; khi mô hình hiệu lực đổi tạo `DAXEngine` mới với `Catalog(metadata: hiệu lực)` (đổi measure: rẻ, dùng chung store). Đổi quan hệ: dùng `RelationshipOverride` (đổi hoạt động, hướng lọc) nếu đủ, không thì dựng `ColumnStore` mới với `ModelSchema` mới dùng lại cột đã giải mã (R4). `MeasureCache` của engine mới rỗng. Visual vẽ lại qua `layoutRevision` hiện có.
5. **Hoàn tác chung** (`LayoutEditor`): `LayoutSnapshot` thêm `model: ModelEdits`; mọi lệnh sửa mô hình đi qua `ModelEditor` (BIPro/Model/Edit) gọi `pushUndo`. `isDirty` gồm cả mô hình (R5).
6. **Chặn tham chiếu** (`ModelReferences`): tra ai dùng một measure/cột/bảng: visual (`FieldReferences` hiện có, mở rộng cho cả measure), DAX của measure khác (quét bằng `Lexer`/`Binder`, không dùng regex), quan hệ, cột sắp xếp, bookmark/bộ lọc. Dùng cho xoá (FR-004) và đổi tên (FR-020) (R6).
7. **Table View** (`Table/`): thanh công thức thật (nhập, kiểm lỗi ngay bằng `DAXEngine.validate` + chạy thử, áp dụng/huỷ), "Measure mới", bảng Column metadata sửa được, sắp xếp/lọc lưới (đã có `GridFilter`) chỉ trong phiên.
8. **Model View** (`Model/`): kéo thẻ (ghi `DiagramLayout` bằng `DiagramLayoutPatch`, giữ nguyên các khoá không biết), tab bố cục, bảng Relationship properties sửa được, tạo quan hệ bằng kéo cột (giai đoạn 2b), ẩn bảng/cột.
9. **TMDL View** (`Query/`, `PBIXKit/TMDLParser.swift`): bộ phân tích tập con (contracts/tmdl-subset.md), so với `TMDLWriter.documents` hiện tại, sinh `ModelEdits`, áp nguyên khối (R9).
10. **Lưu và kiểm** (`DocumentSaver`): rẽ nhánh `modelEdits` → `PBIXWriter.build` (T2) → `verifyModel` (mô hình đọc lại khớp mô hình hiệu lực: đếm bảng, cột, measure, quan hệ, từng dòng đã sửa; VertiPaq nguyên vẹn bằng `pbix-dump verify`; `integrity_check`; `MAXID`) → ghi tạm, sao lưu, thay (R10).
11. **Bằng chứng**: `docs/phase-e-evidence/vm-e*/`, Desktop mở file BI Pro lưu ở mỗi câu chuyện (`CHECKLIST-KET-QUA.md`).

## Thứ tự và phụ thuộc

0. **Nền**: `ModelEdits`, `applying`, `MetadataWriter.update*/delete*`, `ModelRuntime`, snapshot hoàn tác, `verifyModel`, spike S0 (T2 trên Nhom6: thời gian lưu, Desktop mở, `SecurityBindings`).
1. **Câu chuyện 1 (measure, P1)**: dùng nền; VM-E2 (xoá measure, kiểu khác, lỗi cú pháp).
2. **Câu chuyện 2 (quan hệ, P1)**: 2a sửa thuộc tính (hoạt động, hướng lọc, cardinality nếu quan sát cho phép) là T2 thuần; **2b tạo và xoá quan hệ** cần chỉ mục `R$` (R7): spike S1, nếu thất bại thì 2b hiện "(chưa hỗ trợ)" và Phase E vẫn xong theo điều kiện "thêm measure và sửa quan hệ"; báo bạn trước khi bỏ.
3. **Câu chuyện 3 (cột, P2)** và **4 (bố cục Model View, P2)**: độc lập nhau, sau nền.
4. **Câu chuyện 5 (TMDL, P3)**: sau 1 đến 3 (áp dụng gộp các thao tác của chúng).
5. Tích hợp, `/speckit-converge`, `/code-review`, VM-E cuối (Desktop mở file lưu), cập nhật `STATE.md`.

## Tệp dự kiến

- Mới: `Sources/PBIXKit/Writing/ModelEdit.swift`, `DiagramLayoutPatch.swift`; `Sources/PBIXKit/TMDLParser.swift`; `Sources/BIPro/Model/Edit/ModelEditor.swift`, `ModelRuntime.swift`, `ModelReferences.swift`, `MeasureTyping.swift`, `RelationshipDraft.swift`; `Sources/BIPro/Table/MeasureEditorView.swift`, `ColumnMetadataEditor.swift`; test `Tests/PBIXKitTests/ModelEditTests.swift`, `MetadataWriterUpdateTests.swift`, `TMDLParserTests.swift`; `Tests/BIProTests/Model/*`; `Tests/BIProTests/Model/E1Nhom6Tests.swift` (golden nặng).
- Sửa: `MetadataWriter.swift`, `PBIXWriter.swift`, `Contracts.swift`, `ModelMetadata.swift`, `DiagramLayout.swift`, `TMDLWriter.swift`; `Workspace.swift`, `DocumentState.swift`, `DocumentSaver.swift`, `LayoutEditor.swift`, `TableWorkspace.swift`, `ModelWorkspace.swift`, `QueryWorkspaces.swift`, `Ribbon.swift`, `ReportPanes.swift` (ngăn Dữ liệu: measure mới, thư mục).

## Rủi ro

- **Tạo quan hệ cần chỉ mục `R$` (VertiPaq)**: có thể Desktop tự dựng lại khi mở (thử ở S1) hoặc ta phải viết chỉ mục bằng `VertiPaqWriter`; nếu cả hai thất bại, bỏ 2b có báo. Giảm nhẹ: 2a đủ cho "xong khi" cùng thêm measure; kiểm cardinality/duy nhất bằng engine trước khi cho tạo.
- **T2 trên file lớn (Nhom6 51 MB, ~1 triệu hàng)**: dựng lại ABF và nén XPress9 có thể chậm hơn 3 giây; W3 chỉ thử file nhỏ. S0 đo; nếu chậm, lưu chạy nền với thanh tiến trình.
- **`SecurityBindings`** có thể liên quan cả `DataModel`: S0 mở trong Desktop; nếu lỗi, bỏ như R13 của D1.
- **Suy kiểu measure** có thể lệch Desktop với kiểu hiếm (tiền tệ, ngày): chỉ ghi kiểu đã quan sát, kiểu khác để người dùng chọn định dạng; ghi `[SUY ĐOÁN]`.
- **Engine nạp lại** đổi quan hệ có thể đắt: R4 quyết định bằng số đo; tới lúc đó dùng `RelationshipOverride`.
- **Ngăn xếp hoàn tác** gộp mô hình và báo cáo: sửa mô hình xoá nhánh làm lại như hiện nay; test hoàn tác qua lại giữa visual và measure.
