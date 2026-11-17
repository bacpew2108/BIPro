# VM-F7a (T086): Desktop nạp JSON lồng và Parquet

Ngày 2026-11-16, Power BI Desktop 2.159 trong VM, Claude lái VM (người dùng cho phép). Tệp nguồn: `orders.json` (`scripts/f-samples/make_samples.py`), `sales_2026.parquet` và `types_snappy.parquet` (`scripts/f-samples/make_parquet.py`, pyarrow 24, SNAPPY, từ điển, trang v1). Desktop lưu `f7-desktop.pbix` (để ngoài git, ở thư mục này và `build/f-out/f7/`); số liệu dưới đây đọc từ tệp đó (`metadata.sqlitedb`, VertiPaq).

## JSON (`orders.json`: mảng 100 bản ghi; `Customer` là bản ghi, `Lines` là danh sách bản ghi, `Note` có null)

- Get Data ▸ JSON ▸ hộp Open ▸ **mở thẳng Power Query Editor** (không qua Navigator), truy vấn tên theo tệp (`orders`), đã tự mở rộng hết:

```
let
    Source = Json.Document(File.Contents("C:\Users\Bacpew\f7\orders.json")),
    #"Converted to Table" = Table.FromList(Source, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Expanded Column1" = Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"OrderID", "Customer", "Lines", "Note"}, {"OrderID", "Customer", "Lines", "Note"}),
    #"Expanded Customer" = Table.ExpandRecordColumn(#"Expanded Column1", "Customer", {"Id", "Region"}, {"Customer.Id", "Customer.Region"}),
    #"Expanded Lines" = Table.ExpandListColumn(#"Expanded Customer", "Lines"),
    #"Expanded Lines1" = Table.ExpandRecordColumn(#"Expanded Lines", "Lines", {"Sku", "Qty"}, {"Lines.Sku", "Lines.Qty"}),
    #"Changed Type" = Table.TransformColumnTypes(#"Expanded Lines1",{{"OrderID", Int64.Type}, {"Customer.Id", Int64.Type}, {"Customer.Region", type text}, {"Lines.Sku", type text}, {"Lines.Qty", Int64.Type}, {"Note", type text}})
in
    #"Changed Type"
```

- Quy tắc thấy được: cột `Column1` của bước đổi thành bảng mở rộng **không tiền tố**; cột bản ghi về sau mở rộng với tiền tố `Cột.Trường`; cột danh sách mở rộng thành dòng mới rồi, nếu phần tử là bản ghi, mở rộng tiếp (tên bước trùng thêm số `Expanded Lines1`). Thứ tự theo cột từ trái sang phải. Số JSON nguyên thành `Int64.Type`, chuỗi (kể cả cột có null) `type text`.
- Kết quả 203 dòng, 6 cột (ảnh `q0-json-buoc.png`). Siêu dữ liệu: Int64 (`DataType 6`, `FormatString 0`), text (`2`).
- [SUY ĐOÁN, chưa quan sát] gốc là một bản ghi (không phải mảng), mảng giá trị đơn, lồng sâu hơn hai cấp.

## Parquet

- Get Data ▸ Parquet ▸ hộp hỏi **URL** (Basic/Advanced); dán đường dẫn tệp cục bộ được. Sau đó là cửa sổ xem trước 20 dòng ("The data in the preview has been truncated due to size limits") với Load / Transform Data / Cancel, không có cây Navigator (ảnh `q1-parquet-xem-truoc.png`).
- M chỉ một bước, không có "Changed Type", kiểu lấy từ lược đồ tệp (ảnh `q2-parquet-pq.png`, `q4-parquet-kieu-pq.png`):

```
let
    Source = Parquet.Document(File.Contents("C:\Users\bacpew\f7\sales_2026.parquet"), [Compression=null, LegacyColumnNameEncoding=false, MaxDepth=null])
in
    Source
```

(Đường dẫn trong tệp có dấu cách thừa ở cuối do cách dán trong buổi này; không phải hành vi Desktop.)

- Ánh xạ kiểu (đọc từ `metadata.sqlitedb`):

| Parquet (pyarrow) | Kiểu mô hình Desktop | FormatString / chú thích |
|---|---|---|
| int32, int64 | Int64 (6) | `0` |
| float32, float64 | Double (8) | `PBI_FormatHint {"isGeneralNumber":true}` |
| **decimal128(9,2), decimal128(18,4)** | **Double (8)**, không phải Fixed decimal | như trên |
| bool | Boolean (11) | `"TRUE";"TRUE";"FALSE"` |
| string (UTF-8, có null và chuỗi rỗng) | String (2) | |
| date32 | DateTime (9) | `Long Date`, `UnderlyingDateTimeDataType = Date` |
| timestamp[ms], timestamp[us] | DateTime (9) | `General Date` |

- Số dòng: `sales_2026` 10 000, `types_snappy` 1 000; null giữ nguyên null, chuỗi rỗng giữ rỗng.
- Thời gian: cột timestamp[us] Desktop lưu trong mô hình với độ phân giải khoảng **1/300 giây** (11/12 ô kiểm khớp làm tròn phần trong ngày tới 1/300 s, một ô lệch một bậc; quy tắc chưa rõ). BI Pro giữ µs; test golden so ngày giờ với dung sai 1/300 s.
- Phụ: với Auto date/time bật, Desktop thêm `LocalDateTable` cho mỗi cột ngày và **tự phát hiện quan hệ** `orders[OrderID] → sales_2026[OrderID]` (bảng `R$… AutoDetected`). BI Pro không làm hai việc này (ngoài phạm vi US7).

## Áp vào BI Pro

- JSON: Get Data ▸ JSON mở thẳng Query Editor với chuỗi bước như trên (tự mở rộng bản ghi và danh sách), `Changed Type` theo dò kiểu.
- Parquet: hộp chọn tệp rồi xem trước (Load / Transform Data), M một bước `Parquet.Document(...)` đúng dạng trên; kiểu theo bảng ánh xạ, decimal thành số thực.
