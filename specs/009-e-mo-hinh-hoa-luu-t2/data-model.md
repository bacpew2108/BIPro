# Mô hình dữ liệu Phase E

Kiểu mới nằm trong `PBIXKit` (`Writing/ModelEdit.swift`) trừ khi ghi khác. Mọi giá trị là `Sendable`, bất biến, so sánh được.

## ModelEdit (một thao tác)

| Trường hợp | Tham số | Ghi vào `metadata.sqlitedb` |
|---|---|---|
| `addMeasure(NewMeasure)` | bảng, tên, biểu thức, định dạng, thư mục, mô tả, ẩn, kiểu | `INSERT Measure` (đã có) |
| `updateMeasure(table, name, MeasurePatch)` | `MeasurePatch`: `name?`, `expression?`, `formatString??`, `displayFolder??`, `description??`, `isHidden?`, `dataType?` | `UPDATE Measure … WHERE ID` |
| `deleteMeasure(table, name)` | | `DELETE Measure` (+ `Annotation`/`ExtendedProperty` của nó) |
| `updateRelationship(name, RelationshipPatch)` | `isActive?`, `crossFiltering?` (đơn/hai chiều), `cardinality?` (nếu quan sát cho phép), `relyOnReferentialIntegrity?` | `UPDATE Relationship` |
| `addRelationship(RelationshipDraft)` / `deleteRelationship(name)` | từ/đến (bảng, cột), cardinality, hướng lọc, hoạt động | Giai đoạn 2b, theo spike S1 (R7) |
| `updateColumn(table, name, ColumnPatch)` | `name?`, `isHidden?`, `formatString??`, `summarizeBy?`, `dataCategory??`, `sortBy??`, `displayFolder??`, `description??` | `UPDATE Column` (+ `Annotation` nếu quan sát) |
| `setDiagramLayout(DiagramLayoutPatch)` | tab, nút (bảng, `x, y, w, h`), thu phóng | thay phần `DiagramLayout` (không đụng ABF) |

`??` là "đặt hoặc xoá" (`Optional<Optional<…>>`). `name?` ở cột/measure chỉ dùng khi `ModelReferences` không thấy nơi dùng (FR-020).

## ModelEdits

- Danh sách `[ModelEdit]` theo thứ tự thực hiện, kèm `static func merging` để gộp liên tiếp cùng đối tượng (hai lần sửa biểu thức = một).
- `ModelMetadata.applying(_ edits: ModelEdits) throws -> ModelMetadata`: kiểm tính hợp lệ (đối tượng tồn tại, tên không trùng, cột sắp xếp cùng bảng) và trả mô hình hiệu lực; ném `ModelEditError` có lý do.
- `isEmpty`, `touchesData` (`true` nếu có thao tác ghi ABF), `tier` (`.metadata` nếu có thao tác metadata, ngược lại `.report`).

## Quan hệ giữa các kiểu

- `PBIXChanges.modelEdits: ModelEdits` → `PBIXWriter.rebuiltDataModel` mở `MetadataWriter(sqlite:)`, gọi từng `apply(_:)`, `serialize()`, `ABFWriter.rebuild(replacing:)`.
- `LayoutSnapshot.model: ModelEdits` (BIPro) → hoàn tác.
- `ModelRuntime(workspace:edits:)` (BIPro) → `metadata` hiệu lực, `engine`, `version` (tăng khi đổi) → khoá nạp lại của `LiveVisual`.

## Trạng thái giao diện

- `MeasureDraft` (BIPro): bảng, tên, văn bản biểu thức, kết quả kiểm gần nhất (`ok(Value, DataType)`/`error(DAXError)`), đang ở chế độ `new` hay `edit(table,name)`.
- `ColumnSelection`/`RelationshipSelection` (có sẵn ở `DocumentState.table/column/relationship`).
- `RelationshipDraft`: hai đầu, cardinality và hướng lọc đã dò, cảnh báo, trạng thái hộp thoại xác nhận.
- `DiagramState`: tab đang xem, thu phóng, nút được kéo (đã có phần đọc ở `ModelWorkspace`).

## Quy tắc kiểm hợp lệ

- Tên measure: không rỗng, không NUL, không trùng measure hoặc cột cùng bảng (không phân biệt hoa thường), không trùng tên bảng.
- Biểu thức: parse và bind qua `DAXEngine.validate` không lỗi; chạy thử `ROW` không ném lỗi cứng.
- Xoá/đổi tên measure, cột, bảng: `ModelReferences.usages(of:)` rỗng.
- Quan hệ: hai cột cùng `DataType`; không tạo vòng hoạt động; không trùng cặp bảng hoạt động (mới thành không hoạt động).
- Cột sắp xếp theo: cùng bảng, không là chính nó.
