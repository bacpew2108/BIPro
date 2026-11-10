# Mô hình dữ liệu: D4, Format pane sửa được

Giá trị thuần (struct/enum), không phụ thuộc giao diện, để test không cần cửa sổ. Quyết định ở [research.md](research.md).

## PBIXKit

### `FormatScope`

`objects` (phạm vi Visual, khoá `visual.objects`) hoặc `container` (phạm vi Chung, khoá `visual.visualContainerObjects`).

### `FormatEdit`

Một thay đổi định dạng của một visual.

| Trường | Ý nghĩa |
|---|---|
| `scope: FormatScope` | phạm vi |
| `object: String` | khoá trong file (ví dụ `labels`, `title`) |
| `action` | `set(property: String, value: String)` (`value` là chuỗi JSON của giá trị, ví dụ `{"expr":{"Literal":{"Value":"16D"}}}`), `removeProperty(String)`, `removeObject` |
| `selectorDefault: Bool` | khi tạo mục mới: ghi `selector:{id:"default"}` sau `properties` (chỉ `cardVisual`) |

Quy tắc gộp (`FormatEdit.merging`): mỗi `(scope, object, property)` có một `set` cuối; `removeObject` xoá mọi edit con của khoá và đứng đầu danh sách; `removeProperty` huỷ `set` cùng khoá.

### `PBIRFormatPatch`

- `apply(_ edits: [FormatEdit], to json: Data) throws -> Data`: ghép byte (R2); ném `WriteError.invalid` khi cấu trúc không như mong đợi (không có `visual`, mục chung là mảng rỗng, …), `WriteError.verificationFailed` khi kiểm sau ghép lệch.
- Không có hàm đọc riêng: `LayoutEditor` đọc mục chung từ `ReportVisual.raw` bằng `FormatCatalog.isEditable` (đã làm, bỏ `entries`).

## BIPro

### `FormatKind`

`bool`, `number(min: Double, max: Double, step: Double, tail: NumberTail)` (`NumberTail` = `.d` hoặc `.l`), `choice([FormatChoice])` (`FormatChoice`: nhãn Việt + giá trị JSON), `color`, `text(maxLength: Int, allowsEmpty: Bool)`.

### `FormatProperty`

| Trường | Ý nghĩa |
|---|---|
| `key: String` | tên thuộc tính trong file |
| `title: String` | tên Việt |
| `kind: FormatKind` | điều khiển và giá trị cho phép |
| `isCardSwitch: Bool` | là công tắc đầu thẻ (`show`, `areaShow`, …) |
| `observed: String` | nguồn quan sát (`Nhom6`, `VM-D4 mục N`), bắt buộc không rỗng |
| `rendered: Bool` | đường vẽ có đọc (R9); `false` thì điều khiển ghi chú "BI Pro chưa vẽ" |
| `addable: Bool` | có thêm được khi chưa có trong file (R4: `subTotals`, `actionButton` chỉ sửa có sẵn) |

### `FormatCard`

`scope`, `objectKey`, `title` (Việt), `properties: [FormatProperty]`, `appliesTo: Set<String>` (loại visual, rỗng = mọi loại).

### `FormatCatalog`

`cards(for type: String, scope: FormatScope) -> [FormatCard]`, `readOnlyKeys(in visual) -> [(object, property)]` (khoá có trong file mà danh mục không phủ, kể cả mục có selector).

### `FormatValue`

Giá trị đọc ra từ JSON để hiển thị: `bool`, `number(Double, tail)`, `choice(String)` (chuỗi/số thô), `color(.theme(id, percent) | .hex(String))`, `text(String)`, `unsupported(reason)`. API: `init?(json: JSONValue, kind: FormatKind)`, `json(kind:) throws -> String` (dựng chuỗi JSON giá trị, chuẩn hoá: hex hoa, nháy đơn gấp đôi, đuôi D/L), `validate(kind:) -> String?` (lý do từ chối hoặc nil).

### `FormatTarget` (khoá gộp bước)

`(visualID, scope, object, property)`; `coalesceKey` = chuỗi `"format:<visualID>:<scope>.<object>.<property>"`.

### Mở rộng `PageEdit` và `LayoutEditor`

- `PageEdit.formats: [String: [FormatEdit]]` (mã visual → edit đã gộp). Chỉ có khoá cho visual đã sửa định dạng.
- `LayoutEditor.setFormat(_ target:, value: FormatValue, visual:) -> String?` (lý do từ chối hoặc nil), `resetFormat(card:visual:)`, `resetFormat(property:card:visual:)`, `formatState(of visual:) -> [CardState]` (cho giao diện: giá trị hiện tại, thẻ có trong file không).
- Trạng thái chuyển: `không có khoá` ↔ `có khoá với giá trị` qua `set`/`removeObject`; mỗi chuyển là một bước hoàn tác (gộp theo khoá).

## Kiểu thực tế trong mã (sau D4)

- `FormatCardState { card, isPresent, isEditable, values }`, `FormatState { visualID, type, objects, container, readOnly, blocker }` (`LayoutEditor+Format.swift`).
- `FormatReadOnlyItem { scope, object, property?, reason }`, `FormatProperty` có thêm `defaultOn: Bool?` (mặc định bật/tắt đã quan sát khi file chưa có thuộc tính) (`FormatCatalog.swift`).
- `FormatEdit.merging(_:adding:)` gộp lệnh; `FormatScope` có `CaseIterable` (`PBIRFormatPatch.swift`).
- `LayoutEditor`: `setFormat`, `resetFormat`, `formatState`, `formatEditingBlocker`, `jsonBeforeFormats`, `withFormats`; `DocumentState`: `formatEditingBlocker`, `formatState`, `setFormat`, `resetFormat`.
