# Hợp đồng lưu: định dạng vào `.pbix` tầng T1

Cho `PBIRFormatPatch` và `LayoutEditor.makeChanges`/`DocumentSaver`. Quyết định ở [../research.md](../research.md) R1, R2, R10.

## Ghi gì

Chỉ `visual.json` của visual có `PageEdit.formats[id]`; mọi phần khác của file khớp từng byte (trừ `SecurityBindings` và `[Content_Types].xml`, như D1 R13). Visual trong `added` (D3, D1 bản sao) mang định dạng trong byte `added[id]`.

| Thao tác | Ghi |
|---|---|
| Đặt thuộc tính đã có | thay đúng đoạn byte của giá trị (`{"expr":{"Literal":{"Value":"16D"}}}`) |
| Đặt thuộc tính chưa có, mục đã có | chèn `,"<thuộc tính>":<giá trị>` ở cuối `properties` của mục chung |
| Đặt thuộc tính, khoá chưa có | chèn `,"<khoá>":[{"properties":{"<thuộc tính>":<giá trị>}}]` ở cuối khoá phạm vi (với `cardVisual`: thêm `,"selector":{"id":"default"}` sau `properties`) |
| Đặt thuộc tính, phạm vi chưa có | tạo `"objects":{…}` chèn ngay sau `query` (hoặc sau `visualType` nếu không có `query`) và trước `visualContainerObjects`; `"visualContainerObjects":{…}` chèn trước `drillFilterOtherVisuals` (hoặc cuối `visual` nếu không có) |
| Bỏ thuộc tính | bỏ cặp khoá-giá trị; hết thuộc tính thì bỏ mục; hết mục thì bỏ khoá; hết khoá thì bỏ phạm vi |
| Bỏ khoá (đặt lại thẻ) | bỏ cả khoá; hết khoá thì bỏ phạm vi |

Mục có `selector` khác `default` không bị đụng. Khoảng trắng của file giữ nguyên; nội dung chèn viết gọn không khoảng trắng (như Desktop).

## Giá trị

Theo QUAN-SAT mục 1: bool `"true"`/`"false"`; số `"16D"`; số nguyên `"1L"`; chuỗi `'…'` với nháy đơn gấp đôi; màu theme `ThemeDataColor{ColorId, Percent}` (`Percent` là số thực); màu tự chọn `'#RRGGBB'` chữ hoa. Thuộc tính có giá trị cũ giữ đuôi (`D` hoặc `L`) của giá trị cũ.

## Kiểm lúc lưu

1. `PBIRFormatPatch.apply` đọc lại kết quả bằng `JSONSerialization` và so với cấu trúc mong đợi (như `PBIRPatch.setVisualTitle`); lệch thì không ghi.
2. `DocumentSaver.verifyLayout` đọc lại file đã dựng và so từng visual: `objects` và `containerObjects` (giá trị JSON) bằng trạng thái đang sửa.
3. Ghi file đích chỉ khi hai bước trên qua (đường lưu của D1: dựng và kiểm trong bộ nhớ, file đích còn nguyên nếu lỗi).

## Mở lại

BI Pro mở file đã lưu: Format pane và canvas hiện đúng giá trị. Power BI Desktop: mở không báo lỗi, vẽ cùng định dạng (kiểm tay hoặc Claude khi được phép).
