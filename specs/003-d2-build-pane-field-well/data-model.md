# Mô hình dữ liệu: D2

Các kiểu mới hoặc mở rộng. Tên Swift là gợi ý; hợp đồng hành vi ở `contracts/`.

## `ReportField` (mở rộng, PBIXKit)

Thêm `nativeQueryRef: String?` và `active: Bool?` (đọc từ `projections[]`; nil khi file không có). Mọi chữ ký hiện có giữ nguyên.

## `FieldRef` (BIPro, mới)

Một trường lấy từ pane Dữ liệu, dùng khi kéo thả và thêm bằng menu.

| Thuộc tính | Ý nghĩa |
|---|---|
| `kind` | `column` hoặc `measure` (cấp hierarchy không thêm được ở D2) |
| `entity` | tên bảng |
| `property` | tên cột hoặc measure |
| `dataType` | kiểu dữ liệu của cột (số, văn bản, ngày, logic); measure: nil |
| `summarizeBy` | phép gộp mặc định của mô hình (D2b) |

`Codable`; kéo thả qua `NSItemProvider` dạng văn bản (tiền tố `bipro-field:` rồi JSON); trường đang nằm trong ô kéo bằng `bipro-well:<chỉ số>:<ô>` (`BuildDrop`).

## `Projection` (BIPro, mới)

Một trường trong một ô của một visual đang sửa.

| Thuộc tính | Ý nghĩa |
|---|---|
| `field` | `ReportField` (loại, bảng, tên, tên hiển thị, `queryRef`, `nativeQueryRef`, `active`) |
| `source` | `Data?`: byte gốc của phần tử trong `visual.json` nếu trường có sẵn trong file; nil nếu trường mới |

Phần tử có `source` được chép nguyên byte khi ghi (trừ thay `displayName` nếu đổi tên).

## `QueryEdit` (BIPro, mới)

Cấu hình trường đã sửa của một visual: danh sách ô theo thứ tự, mỗi ô là danh sách `Projection`. Bất biến: mỗi ô nằm trong `WellRules` của loại visual; số trường không vượt tối đa của ô; không có hai `Projection` cùng `queryRef` trong cùng ô.

## Cầu nối BIPro → PBIXKit (`PBIRQueryPatch.Well`/`Element`)

`PBIRQueryPatch` (PBIXKit) dùng `Well` (ô, danh sách `Element`) và `Element` (`ReportField` + `source: Data?`). `QueryEdit` của BIPro chính là `[Well]` theo thứ tự: `Projection` ở trên tương ứng `Element`. `source != nil` = phần tử có trong file (chép nguyên byte), `source == nil` = phần tử mới. Không cần chuyển đổi: `LayoutEditor` giữ `[PBIRQueryPatch.Well]` trong `PageEdit.queries`, gọi `apply` để có `visual.json` mới, rồi phân tích lại byte để có `ReportField` mới (chiều ngược lại).

## `PageEdit` (mở rộng, D1)

Thêm `queries: [String: QueryEdit]` (mã visual → cấu hình đã sửa). Chỉ có khoá cho visual đã sửa trường. `Equatable` để `commit` biết có đổi hay không. Ảnh chụp hoàn tác (`LayoutSnapshot`) đã chứa `PageEdit` nên hoàn tác tự có.

## `WellRule` (BIPro, mới)

| Thuộc tính | Ý nghĩa |
|---|---|
| `visualType` | loại visual (khớp theo `VisualCatalog.matches`) |
| `role` | khoá ô trong `queryState` (`Category`, `Y`, `Y2`, `Series`, `Tooltips`, `Values`, `Rows`, `Columns`, `Group`) |
| `label` | nhãn tiếng Việt |
| `accepts` | tập loại trường nhận được (`column`, `measure`) |
| `maxCount` | số trường tối đa (1 hoặc nhiều) |
| `status` | `observed` (có trong Nhom6 hoặc VM-D2) hoặc `unverified` |

## `FieldReference` (BIPro, mới)

Một chỗ trong `visual.json` nhắc tới một trường: `sort`, `filter` hoặc `format(metadata)`, kèm mô tả để báo người dùng.

## Biến đổi trạng thái

- Mở file: `PageEdit.queries` rỗng.
- Thao tác sửa trường (thêm, bỏ, đổi thứ tự, chuyển ô, đổi tên): `commit` tạo `QueryEdit` mới từ cấu hình hiện tại (lần đầu: đọc từ `visual.raw`), áp thao tác, rồi `PBIRQueryPatch.apply` để có `visual.json` mới và cập nhật `ReportVisual.raw`/`fields`.
- Hoàn tác: khôi phục `PageEdit` cũ (cả `queries` lẫn `visuals`).
- Lưu: với mỗi `queries[id]`, `apply` trên `visual.json` đang có trên đĩa; sau đó kiểm khớp qua `loadReport()`.
