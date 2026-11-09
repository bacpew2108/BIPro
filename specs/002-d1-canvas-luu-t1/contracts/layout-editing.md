# Hợp đồng: sửa bố cục

Hành vi mà `LayoutGeometry` và `LayoutEditor` phải đáp ứng. Là nguồn cho test thuần. Hằng số [SUY ĐOÁN] tập trung ở `LayoutGeometry`.

## Hằng số

| Tên | Giá trị | Nguồn |
|---|---|---|
| `grid` | 8 | kế hoạch dự án; [SUY ĐOÁN] so với Power BI |
| `minSize` | 16 | [SUY ĐOÁN] |
| `nudge` | 1 (Shift: 8) | [SUY ĐOÁN] |
| `duplicateOffset` | (16, 16) | [SUY ĐOÁN] |
| `zStep` | 1000 | quan sát Nhom6 |
| `idLength` | 20 hex thường | quan sát Nhom6 |

## Hình học (hàm thuần, không phụ thuộc giao diện)

- `snap(v) = round(v / grid) * grid`; `snap` không áp dụng khi giữ Option.
- `move(frame, dx, dy, page, snap)`: `x' = clamp(snap(x + dx), 0, page.width − w)`, tương tự `y`. Cỡ không đổi. Với nhóm chọn: tính `dx, dy` hiệu dụng từ visual chọn dẫn đầu (đã kẹp theo cả khung bao của nhóm), áp cùng một độ dời cho mọi visual, nên vị trí tương đối giữ nguyên.
- `resize(frame, handle, to point, page, snap)`: 8 tay nắm `n, s, e, w, ne, nw, se, sw`. Chỉ cạnh đang kéo đổi; cạnh đó bám lưới; kết quả kẹp trong trang và `w, h ≥ minSize` (cạnh đối diện đứng yên, không đảo chiều khi kéo vượt qua). Mọi giá trị là số nguyên.
- `boundingBox(frames)`.
- `hit(point, visuals)`: visual hiện thấy, `z` lớn nhất chứa điểm; visual ẩn bị bỏ qua.
- `marquee(rect, visuals)`: các visual hiện thấy mà khung của nó **giao** khung chọn (hành vi Power BI [SUY ĐOÁN]: giao, không phải chứa hẳn).

## Vùng chọn

- Bấm visual: chọn riêng nó. Shift-bấm: thêm hoặc bỏ khỏi vùng chọn. Bấm vùng trống của trang: bỏ chọn tất cả. Khung chọn trên vùng trống: thay vùng chọn (Shift: thêm).
- Vùng chọn thuộc về trang hiện tại; đổi trang xoá vùng chọn.
- `DocumentState.visualID` = visual chọn cuối, hoặc `nil` nếu không chọn gì (các pane cũ chỉ thấy một visual).

## Thao tác và hoàn tác

| Thao tác | Số bước hoàn tác | Ghi chú |
|---|---|---|
| Kéo thân (một cử chỉ liên tục) | 1 | `commit` khi thả chuột; không tạo bước nếu vị trí cuối bằng vị trí đầu |
| Kéo tay nắm | 1 | như trên |
| Phím mũi tên | 1 mỗi lần nhấn; nhấn giữ liên tục gộp thành 1 bước (cùng nhóm chọn, trong 0,5 s) | |
| Xoá | 1 | vùng chọn trống sau khi xoá |
| Nhân bản | 1 | vùng chọn chuyển sang các bản sao |

- `undo()` khôi phục toàn bộ trạng thái sửa của trang liên quan (bố cục + vùng chọn + tập đã xoá/đã thêm) và chuyển tới trang đó nếu đang xem trang khác.
- Thao tác mới sau `undo()` xoá `redo`.
- `isDirty == (undo.count != cleanMark)`. `markSaved()` đặt `cleanMark = undo.count`.
- Giới hạn lịch sử: 200 bước; vượt thì bỏ bước cũ nhất và (nếu `cleanMark` nằm trong phần bị bỏ) đặt `cleanMark = −1` (luôn chưa lưu).

## Xoá

- Bỏ visual khỏi `edited[page]`; nếu visual có trong file gốc thì ghi vào `deletedByPage`; nếu là bản sao chưa lưu thì bỏ khỏi `addedByPage`.
- Xoá không đụng tới trạng thái drill/lọc/bookmark của phiên ngoài việc visual biến mất.
- Hoàn tác trả lại đúng chỗ trong thứ tự lớp (`z` được giữ trong snapshot).

## Nhân bản

- Mã mới: 20 ký tự hex, sinh ngẫu nhiên, kiểm không trùng với **mọi** mã trong báo cáo và mọi mã đã sinh trong phiên (kể cả sau hoàn tác); trùng thì sinh lại.
- `visual.json` bản sao = byte của bản gốc với `name` và `position` thay; mọi trường khác (query, objects, filterConfig) giữ nguyên.
- Vị trí: bản gốc + `duplicateOffset`, kẹp trong trang; `z = tabOrder = max(z trang) + zStep` (+ thêm `zStep` cho mỗi bản kế tiếp khi nhân bản nhiều).
- Nhân bản nhiều visual một lần: giữ vị trí tương đối giữa các bản sao.

## Đọc lại (round-trip)

`PBIXFile(data:).loadReport()` của file đã lưu phải cho: cùng tập mã visual theo từng trang như `LayoutEditor` (trang đã sửa), cùng `x, y, z, width, height` cho mỗi visual, `raw` của visual không sửa bằng bản gốc.
