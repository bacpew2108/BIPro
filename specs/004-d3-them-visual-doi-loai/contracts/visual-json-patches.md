# Hợp đồng: ghi `visual.json` (D3)

Mọi hàm ghép byte như `PBIRPatch`, `PBIRLayoutPatch`, `PBIRQueryPatch`: phần không chạm giữ nguyên từng byte; kết quả được phân tích lại và so với cấu trúc mong đợi (`WriteError.verificationFailed("… changed other content")` khi lệch); đầu vào sai ném `WriteError.invalid`.

## `PBIRNewVisual` (sinh visual mới)

```swift
PBIRNewVisual.makeJSON(name:type:x:y:width:height:z:schema:) throws -> Data
PBIRNewVisual.defaultSize(for type: String) -> (width: Int, height: Int)?
PBIRNewVisual.schemaURL(from existing: [Data]) -> String        // lấy $schema của visual có sẵn, mặc định 2.13.0
```

Mẫu (một dòng, thứ tự khoá cố định, R3):

```json
{"$schema":"…","name":"<20 hex>","position":{"x":0,"y":0,"z":0,"height":0,"width":0,"tabOrder":0},"visual":{"visualType":"<loại>","drillFilterOtherVisuals":true}}
```

- `textbox`: không `drillFilterOtherVisuals`; thêm `"objects":{"general":[{"properties":{"paragraphs":[{"textRuns":[{"value":"Hộp văn bản"}]}]}}]}`.
- `name` phải thoả `PBIRLayoutPatch.isValidVisualName`; `type` phải có `defaultSize` (loại hỗ trợ), nếu không `WriteError.invalid`; `width`, `height` ≥ 1; `x`, `y` ≥ 0.

## `PBIRVisualPatch` (đổi loại, tỉa định dạng, văn bản)

```swift
PBIRVisualPatch.visualType(in:) throws -> String
PBIRVisualPatch.setVisualType(in json: Data, to type: String, dropObjectKeys: Set<String>) throws -> Data
PBIRVisualPatch.objectKeys(in json: Data) throws -> [String]          // khoá của visual.objects theo thứ tự file
PBIRVisualPatch.paragraphs(in json: Data) throws -> [String]          // văn bản mỗi đoạn (ghép các lượt)
PBIRVisualPatch.setText(in json: Data, lines: [String]) throws -> Data
```

- `setVisualType`: thay chuỗi `visual.visualType`; mỗi khoá trong `dropObjectKeys` có trong `visual.objects` thì bỏ cả khoá lẫn dấu phẩy kèm theo; nếu bỏ hết khoá thì giữ `"objects":{}`; không động tới `visualContainerObjects`, `query`, `position`.
- `setText` (R9): đoạn một lượt → thay `value`; đoạn nhiều lượt → lượt đầu nhận văn bản, bỏ các lượt sau; dòng nhiều hơn đoạn → nhân bản byte đoạn cuối với `value` mới; dòng ít hơn → bỏ đoạn cuối. `value` thoát chuỗi đúng (`"`, `\`, xuống dòng, Unicode). Không có `paragraphs` → `WriteError.invalid`.

## `PBIRQueryPatch` (mở rộng, D2)

`apply(_:to:)` khi `visual.query.queryState` vắng mà có ô có phần tử: chèn `"query":{"queryState":{<ô theo thứ tự>}}` ngay sau giá trị `visualType` (kèm dấu phẩy); `queryState` có mà tất cả ô bị bỏ: giữ `"queryState":{}`. Kiểm tra sau ghép giống D2. `wells(in:)` trả `[]` cho visual không có `queryState` (đã có).

## Thứ tự áp khi lưu một visual có trong file

`setVisualType` (+ tỉa `objects`) → `setText` → `PBIRQueryPatch.apply` → `PBIRLayoutPatch.setPosition`. Mỗi bước nhận kết quả của bước trước; không có thay đổi nào ở một bước thì bỏ qua bước đó.

## Kiểm tra khi lưu (`DocumentSaver.verifyLayout`)

Với mỗi visual của mọi trang: tập mã, khung, `z` (D1), ô và trường (D2) và, mới ở D3, `type` khớp `LayoutEditor`; với hộp văn bản, `paragraphs` đọc lại khớp văn bản của editor.
