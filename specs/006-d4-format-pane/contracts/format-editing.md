# Hợp đồng hành vi: sửa định dạng trong Format pane

Cho `LayoutEditor` (setFormat, resetFormat) và `FormatPane`. Quyết định ở [../research.md](../research.md); cấu trúc ở [../data-model.md](../data-model.md).

## Điều kiện cho phép

| Điều kiện | Kết quả |
|---|---|
| Chế độ Xem, hoặc báo cáo định dạng cũ (`Report/Layout`) | mờ kèm lý do ("Bật chế độ Sửa" / "Báo cáo định dạng cũ chưa sửa được"); không đổi gì |
| Không chọn, hoặc chọn nhiều visual | hiện "Chọn một visual"; không sửa hàng loạt |
| Visual trong nhóm (`isLockedByGroup`) | từ chối "Visual nằm trong nhóm, chưa sửa được." (như D2) |
| Visual chưa có trường | pane không hiện thẻ ("Thêm trường để bắt đầu định dạng", như Desktop); visual không có truy vấn (hộp văn bản, ảnh, nút) hiện thẻ của loại đó nếu danh mục có |
| Thuộc tính ngoài danh mục, hoặc mục có selector khác `default` | chỉ-đọc kèm lý do |

## Điều khiển và kiểm giá trị

Theo bảng R5. Mọi từ chối: không ghi, không tạo bước hoàn tác, giữ giá trị cũ, hiện lý do (đỏ, bấm để ẩn như `FieldMessages`).

- Số: ngoài khoảng hoặc không phải số → "Nhập số từ A đến B." Ô số kẹp giá trị khi dùng mũi tên.
- Chuỗi `title.text`: rỗng → từ chối ("Muốn bỏ tiêu đề thì tắt công tắc Tiêu đề"); dài hơn 200 ký tự → từ chối.
- Màu hex: không đủ 6 chữ số hex → từ chối; hợp lệ ghi chữ hoa.
- Danh sách: chỉ giá trị trong danh mục.

## Bước hoàn tác

- Mỗi lần đổi thuộc tính hoặc đặt lại là đúng một bước, chung ngăn xếp D1 đến D5.
- Đổi liên tiếp cùng `(visual, phạm vi, khoá, thuộc tính)` gộp thành một bước (khoá gộp, như kéo visual ở D1); đổi thuộc tính khác thì bước mới.
- Giá trị mới bằng giá trị hiện có: không tạo bước, không ghi.
- Hoàn tác trả lại đúng `objects` và `visualContainerObjects` (so cả khoá vắng mặt); `isDirty` về false khi về trạng thái đã lưu.

## Màu theo từng chuỗi và bố cục matrix (bổ sung 2026-11-13, VM-D8 mục 6)

- Thẻ có `seriesProperties` (hiện chỉ `dataPoint` của biểu đồ trục, thuộc tính `fill`) có ô "Áp dụng cho": **Tất cả** hoặc một chuỗi. Chuỗi = measure ở ô `Y`, rồi `Y2` (theo thứ tự trong ô). Chọn một chuỗi: sửa mục riêng `{"properties":{"fill":…},"selector":{"metadata":"<queryRef>"}}`, thêm vào **cuối** mảng; chọn Tất cả: chỉ sửa mục chung (`fillTransparency`), ô màu bị khoá ("Chọn một chuỗi để đổi màu", như Desktop).
- Chuỗi đang tô màu theo công thức hoặc điểm dữ liệu (selector có thêm `data`) hoặc visual có trường ở ô Chú giải: từ chối kèm lý do, không ghi.
- Đổi liên tiếp màu của một chuỗi gộp một bước; chuỗi khác là bước khác. "Đặt lại" ở một chuỗi bỏ `fill` của mục đó (mục rỗng thì bỏ cả mục); "Đặt lại" cả thẻ bỏ mọi mục sửa được (mục chung và mục theo chuỗi).
- Mục theo chuỗi không còn bị liệt kê là chỉ-đọc ở thẻ có `seriesProperties`; thuộc tính lạ trong mục đó vẫn chỉ-đọc.
- Matrix: thẻ "Bố cục" (`general.layout`), ba lựa chọn `'Compact'`, `'Outline'`, `'Tabular'` (VM-D8c: chọn Compact vẫn ghi tường minh). Màu khi biểu đồ có Chú giải ghi `selector.data[0].scopeId.Comparison` (VM-D8c mục 2): BI Pro liệt kê các giá trị Chú giải đã có mục riêng (khoá chuỗi `data:<literal>`, `FormatCatalog.legendValue`) và sửa **tại chỗ** như Desktop; giá trị chưa có mục thì từ chối (cần danh sách giá trị từ truy vấn để thêm), bộ ghép byte không bao giờ tạo mục `data:`; mục chung cạnh mục theo Chú giải chưa quan sát nên từ chối.

## Đặt lại

- "Đặt lại" thẻ: xoá cả khoá (`removeObject`), thẻ hiện lại giá trị mặc định (công tắc tắt hoặc mặc định của danh mục).
- "Đặt lại" một thuộc tính màu: bỏ thuộc tính đó (`removeProperty`).
- Đặt lại khi khoá không có trong file: không làm gì, không tạo bước.

## Thông báo

Đổi sang giá trị mà đường vẽ chưa đọc (`rendered == false`): giữ ghi chú cố định ở hàng điều khiển ("BI Pro chưa vẽ thuộc tính này; Power BI Desktop vẫn vẽ"); không dùng hộp thoại.
