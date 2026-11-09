# Mô hình dữ liệu (nội bộ engine): E3-cấu-trúc

Không có dữ liệu bền vững mới. Dưới đây là các giá trị nội bộ của đường tính gộp, đúng với cài đặt ở `Sources/DAXEngine/Runtime/BatchedIteration.swift` (cập nhật 2026-11-09, T033).

## BatchedShape (kết quả nhận mẫu)

Mô tả một thân vòng lặp đủ điều kiện gộp. Tạo mỗi lần vòng lặp X bắt đầu (nhận mẫu chỉ đọc cây biểu thức đã bind, rẻ).

| Trường | Ý nghĩa |
|---|---|
| `first` | bước đầu: `aggregate` (`.max` hoặc `.min`) và `column` được tổng hợp; cho giá trị `t` khi có bước hai |
| `second` | bước hai tùy chọn, cùng dạng; chỉ xét dòng có `first.column = t` |
| `modifiers` | đối số `REMOVEFILTERS(bảng)` của CALCULATE, giống nhau ở hai bước (so bằng mô tả chuỗi) |

Quy tắc hợp lệ: xem [research.md](research.md) R2. Không đủ điều kiện thì không tạo `BatchedShape` và dùng đường cũ. Chỉ MAX và MIN; SUM và COUNT chưa làm.

## Kiểm tra lúc chạy (sau nhận mẫu)

Đường gộp bỏ cuộc (trả nil, chạy đường cũ) khi một trong các điều kiện sau sai: bảng lặp là `VALUES`, `DISTINCT`, `CALCULATETABLE` hoặc biến bảng ảo; đúng một cột có lineage; cột nhóm kiểu số nguyên, mã hoá, cùng bảng với các cột được tổng hợp; mỗi `REMOVEFILTERS` là một bảng khác bảng nhóm; ở hai bước, cột `first.column` không bị lọc ở ngữ cảnh ngoài; cột tổng hợp là số, ngày hoặc tiền tệ (không phải chuỗi, boolean); mọi giá trị nhóm của bảng lặp là số nguyên hoặc BLANK; với nhóm có dòng mà mọi `first.column` BLANK ở bước hai.

## Kết quả

Mảng `[Value]` cùng thứ tự với các dòng của bảng lặp: giá trị của thân vòng lặp ở từng dòng. Người gọi (`SUMX`, `AVERAGEX`, `MINX`, `MAXX`) đưa các giá trị này vào cùng bộ tích luỹ như đường cũ nên cùng kết quả kể cả thứ tự cộng. Không có thực thể `GroupedResult` riêng.

## Dữ liệu dùng chung (có nhớ)

| Tên | Nội dung | Vòng đời |
|---|---|---|
| Khoá sắp xếp theo cột | `[Int64]` theo dòng, thứ tự bằng `Value.compare`, BLANK là `Int64.min` | nhớ theo (`ColumnStore`, cột) dưới khoá, store giữ yếu |
| Mã nhóm theo dòng | `[Int32]` theo dòng của cột nhóm | như trên |
| Bộ đếm lần gộp thật | đếm theo `ColumnStore` | chỉ để test |
| Ghi đè công tắc | `Bool?` (nil theo `BIPRO_BATCH`) | chỉ để test, toàn cục |

## Quan hệ với cấu trúc có sẵn

- `FilterContext`: lấy ngữ cảnh chung của mọi nhóm (shadow, chuyển ngữ cảnh hàng ngoài, bỏ lọc cột nhóm, REMOVEFILTERS qua `calculatedContext`); không đổi kiểu.
- `Evaluator.visibleRows`: R(T) chung, dùng cache có sẵn.
- `RowSet`, `ColumnData`, `ColumnIndex`: đọc mã nhóm, giá trị cột, thứ hạng sắp xếp.
