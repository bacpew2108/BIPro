# VM-D8c: ba mục còn lại của D4/D3b (2026-11-13)

Bạn cho phép dùng VM. Claude điều khiển Desktop (bản sao `Nhom6_work.pbix` trong VM, đã xoá; chỉ thao tác giao diện, lưu, đọc diff các part). Mẫu JSON: `json/`.

## 1. matrix `general.layout`

Thẻ Layout > "Matrix layout" > ô Layout có ba lựa chọn: Compact (mặc định lúc mở, kèm ô Indentation 10), Outline (kèm công tắc "Repeat row headers", tổng chuyển lên đầu), Tabular.
Chọn lần lượt: ghi `objects.general[0].properties.layout` = `'Outline'` rồi `'Compact'` (literal chuỗi, `{"expr":{"Literal":{"Value":"'Outline'"}}}`). Chọn Compact khi file chưa có khoá vẫn ghi tường minh `'Compact'`, không bỏ khoá. Mẫu `json/matrix-compact.visual.json`.

## 2. Màu khi biểu đồ có Chú giải (Legend)

Thẻ Bars > "Apply settings to" > Series: danh sách là **giá trị của trường Chú giải** (Female, Male), không phải measure. Chọn Female rồi đổi màu (theme màu 4) sửa **tại chỗ** mục `dataPoint[0]` có sẵn (không thêm mục):

`{"properties":{"fill":{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":4,"Percent":0}}}}}},"selector":{"data":[{"scopeId":{"Comparison":{"ComparisonKind":0,"Left":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Client"}},"Property":"sex"}},"Right":{"Literal":{"Value":"'Female'"}}}}}]}}`

Khác màu theo measure (`selector.metadata`). Với Series = All ô màu vẫn sửa được (đặt màu mặc định `dataPoint` không `selector`). File Nhom6 đã có sẵn hai mục dạng này (Female `#6A1B9A`, Male `#CE93D8`). Mẫu `json/datapoint-chu-giai.visual.json`. Hiện BI Pro coi mục `selector.data` là chỉ-đọc; làm được thì cần danh sách giá trị Chú giải từ truy vấn và literal theo kiểu cột.

## 3. Sắp xếp mặc định khi visual có cột nhóm

Visual cột mới (`clusteredColumnChart`), thêm Net_Cashflow: `sortDefinition` giảm dần theo measure, `isDefaultSort:true`. Thêm tiếp cột chữ `Dim_Client[sex]` (Category) hoặc cột số `Dim_Date[year]`: **`sortDefinition` không đổi** (vẫn measure giảm dần), cột nhận `"active":true`. Khớp cách BI Pro đang làm; không cần sửa. Mẫu `json/cot-moi-measure-va-cot.visual.json`. Chưa quan sát: cột ngày/phân cấp ngày, đường sang cột.
