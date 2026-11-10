# Hợp đồng: ghép byte `queryState`

```swift
PBIRQueryPatch.wells(in json: Data) throws -> [Well]                    // đọc: ô theo thứ tự trong file
PBIRQueryPatch.apply(_ wells: [Well], to json: Data) throws -> Data     // ghi: trạng thái cuối của MỌI ô
PBIRQueryPatch.newElement(kind:entity:property:displayName:role:) -> Element
```

## Đầu vào

`Well` = một ô (`role`) và danh sách `Element` theo thứ tự. `Element` = `field: ReportField` (loại, bảng, tên, `displayName`, `queryRef`, `nativeQueryRef`, `active`) và `source: Data?`:

- `source != nil`: phần tử có trong file; chép nguyên byte của nó. Chỉ khi `field.displayName` khác `displayName` đọc từ `source` thì thay, thêm hoặc bỏ đúng khoá `displayName` trong byte của phần tử (đổi tên); các khoá khác (`active`, khoá lạ) giữ nguyên;
- `source == nil`: phần tử mới, sinh theo mẫu dưới (luôn dạng gọn, một dòng).

`apply` nhận **trạng thái cuối của mọi ô**: ô giống hệt trong file (cùng phần tử, cùng thứ tự, không đổi tên) giữ nguyên byte; ô có trong file mà không còn trong danh sách (hoặc rỗng) bị bỏ khoá (ô còn khoá khác ngoài `projections` thì giữ khoá đó với mảng rỗng); ô mới được thêm vào cuối `queryState`.

## Đầu ra

`visual.json` mới. Mọi byte ngoài các đoạn đã nêu giữ nguyên (khoá khác, khoảng trắng, thứ tự). Mảng `projections` của ô đã đổi được dựng lại với cách trình bày của mảng cũ (gọn hoặc thụt lề).

## Mẫu phần tử mới (R6)

Thứ tự khoá cố định:

```json
{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Bảng"}},"Property":"Cột"}},"queryRef":"Bảng.Cột","nativeQueryRef":"Cột"}
```

Measure thay `Column` bằng `Measure`. Có `displayName` thì thêm `,"displayName":"…"` sau `nativeQueryRef`. Phần tử mới luôn viết gọn (một dòng); dấu phân cách và khoảng trắng quanh các phần tử của mảng giữ kiểu của mảng cũ.

## Ô

- Ô có sẵn: thay đoạn mảng `projections`.
- Ô mới: thêm `"<Ô>":{"projections":[…]}` vào cuối đối tượng `queryState`.
- Ô thành trống: bỏ khoá ô, cùng dấu phẩy kèm theo. [SUY ĐOÁN, VM-D2]
- `visual.query.queryState` không có: lỗi `WriteError.invalid` (D2 không tạo `queryState` cho visual chưa có).

## Kiểm tra sau ghép

Phân tích lại; cấu trúc mong đợi = tài liệu cũ với các ô đã đổi thay bằng danh sách mới (so từng `queryRef` theo thứ tự, và so phần còn lại bằng `NSDictionary.isEqual`). Sai thì `WriteError.verificationFailed("queryState splice changed other content")`.

## Lỗi

`WriteError.invalid` khi: không phải đối tượng JSON; không có `queryState`; `source` không phải đối tượng JSON; phần tử mới thiếu tên bảng hoặc tên; hai phần tử cùng `queryRef` trong một ô; phần tử mới không phải cột hay measure.

## Kiểm tra khi lưu (`DocumentSaver.verifyLayout`)

Mở lại file mới, `loadReport()`, với mỗi visual đã sửa trường: danh sách ô, thứ tự trường, (loại, bảng, tên, `displayName`) khớp `LayoutEditor`; visual không sửa: `visual.json` giống byte với nguồn.
