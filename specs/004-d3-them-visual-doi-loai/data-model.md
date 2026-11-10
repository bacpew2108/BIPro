# Mô hình dữ liệu: D3

Các kiểu mới hoặc mở rộng. Tên Swift là gợi ý; hợp đồng hành vi ở `contracts/`.

## `VisualTypeInfo` (BIPro, mới, `VisualTypes.swift`)

Thông tin một loại visual thêm được.

| Thuộc tính | Ý nghĩa |
|---|---|
| `type` | `visualType` của PBIR (`card`, `clusteredBarChart`…, `textbox`) |
| `defaultSize` | cỡ mặc định (rộng, cao) theo loại, R3 |
| `family` | họ loại (`xy`, `circular`, `matrix`, `value`, `slicer`, `text`, `map`, `treemap`) dùng cho thông báo và kiểm thử |
| `isSupported` | thêm được và đổi tới được ở lát này (R2) |

`VisualTypes.info(for:)`, `VisualTypes.supported`, `VisualTypes.refusal(for:)` (lý do tiếng Việt cho loại chưa hỗ trợ).

## `Retype` (BIPro, mới)

Công thức đổi loại của một visual đã có trong file: `type: String` (loại mới) và `dropObjectKeys: Set<String>` (khoá `visual.objects` cần bỏ, R8). Lưu trong `PageEdit.retyped[mãVisual]`.

## `TypeChangePlan` (BIPro, mới, `TypeChange.swift`)

Kết quả của `TypeChange.plan(visual:wells:to:objectKeysSeen:)`:

| Thuộc tính | Ý nghĩa |
|---|---|
| `wells` | cấu hình ô mới (`[PBIRQueryPatch.Well]`) sau ánh xạ (phần tử giữ byte) |
| `droppedFields` | trường bị bỏ vì không có ô nhận (R7) |
| `droppedObjectKeys` | khoá `objects` bị bỏ (R8) |
| `blocked` | lý do chặn (trường bị bỏ còn được nhắc ở sắp xếp, bộ lọc, định dạng) hoặc nil |

## `PageEdit` (mở rộng, D1 và D2)

Thêm `retyped: [String: Retype]` và `texts: [String: [String]]` (mã visual → các dòng văn bản của hộp văn bản). `Equatable` để `commit` biết có đổi hay không; ảnh chụp hoàn tác (`LayoutSnapshot`) đã chứa `PageEdit` nên hoàn tác tự có. Visual mới nằm trong `visuals` và `added` (như bản sao của D1), không cần khoá trong `retyped`/`texts`/`queries` (byte `added` đã là kết quả).

## `LayoutEditor` (mở rộng)

- `notice: String?`: thông báo sau thao tác (trường bị bỏ khi đổi loại, khoá `objects` bị bỏ); xoá ở thao tác kế.
- `insertVisual(type:visibleRect:)` → mã visual mới hoặc nil (kèm lý do ở `fieldRefusal`); `changeType(of:to:)` → lý do từ chối hoặc nil; `setText(_:visual:)`.

## `DocumentState` (mở rộng)

- `visibleRect: CGRect?`: vùng nhìn thấy của canvas, toạ độ trang (R6).
- `insertVisual(_:)`, `changeType(_:)`: tiện lợi gọi `layout` kèm `visibleRect`, trang hiện tại, chọn visual mới.

## Biến đổi trạng thái

- Mở file: `retyped`, `texts` rỗng.
- Thêm visual: `PBIRNewVisual.makeJSON` → byte; `LayoutEditor.commit` thêm vào `visuals`, `added`, `createdIDs`; chọn visual mới.
- Đổi loại: `TypeChange.plan` → nếu không bị chặn, `PBIRVisualPatch.setVisualType` + tỉa `objects` + `PBIRQueryPatch.apply` trên byte gốc (hoặc `added[id]`) → phân tích lại → `commit` (`retyped[id]` và `queries[id]` cho visual trong file; `added[id]` cho visual mới).
- Sửa văn bản: `PBIRVisualPatch.setText` → phân tích lại → `commit` (`texts[id]` hoặc `added[id]`).
- Hoàn tác: khôi phục `PageEdit` cũ (mọi bảng).
- Lưu: với mỗi visual có trong file, áp công thức theo thứ tự R10 lên byte trên đĩa; với visual mới, ghi `added[id]` (đã ghép vị trí).
