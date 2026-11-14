# VM-D16: phần còn sót của VM-D15 (2026-11-14)

Bạn yêu cầu làm cho xong các mục chưa trọn ở VM-D15 (mẫu mặc định thẻ Format, chú giải bản đồ hình khi có Location, thác nước có Breakdown, vùng 100%, hover theo series, nhãn trục). Claude điều khiển VM (ngoại lệ một lần). Dùng bản sao `Nhom6_work.pbix` (`~/Desktop/vmd16`, trong VM `vmd16`; đã xoá). Ảnh Desktop chỉ giữ phần pane/visual, không có địa chỉ tài khoản.

## 1. Mẫu mặc định thẻ Format (Desktop, biểu đồ cột mới có Legend, matrix mới)

| Thẻ | Mặc định |
|---|---|
| X-axis > Values | Bật; Segoe UI **10,5**, màu xám; Maximum height 50%; Concatenate labels Tắt; Auto expand Bật; Title Tắt |
| Y-axis | Range Minimum/Maximum "Auto"; Logarithmic Tắt, Invert Tắt, **Round range Bật**; Values Bật; Title Tắt |
| Legend | Bật; **Position "Bottom left"**; Text Segoe UI **10**, màu xám; Title Tắt |
| Gridlines | **Horizontal Bật** (xám nhạt, trong suốt 0%, Solid, 1 px) |
| Zoom slider, Data labels | Tắt (Data labels: Orientation Horizontal; Apply settings to Series = All) |
| Columns | Màu theo series, trong suốt 0%, Border Tắt |
| Plot area background | Không ảnh (Browse), Image fit Fit, trong suốt 0% |
| Matrix > Grid | Horizontal gridlines Tắt, Vertical gridlines Tắt; Options: **Row padding 4**, **Global font size 10** |
| Matrix > Values | Segoe UI 10, chữ và nền xen kẽ cùng màu chữ/nền chính, Text wrap Bật, Options "Switch values to rows" Tắt |
| Matrix > Column headers | Segoe UI 10, Text wrap Bật, +/- icons Bật, Options > Auto expand Tắt |

**"Auto-size column width"** (khoá `autoSizeColumnWidth` của Nhom6) **không có trong giao diện Format của matrix ở bản Desktop này** (Column headers, Values, Grid đều không có công tắc đó), nên không lấy được mặc định; BI Pro vẫn đọc và ghi khoá khi file có.

BI Pro: `ChartDefaults` (`legendPosition = "BottomLeft"`, `legendFontSize = 10`, `axisFontSize = 10.5`) dùng khi file không đặt riêng ở `CartesianChartView`, `ChartLegendView`, thác nước, ruy-băng. Sửa kèm: `ChartLegendView` xếp chú giải **ngang** cho vị trí góc (`BottomLeft`, `TopRight`…), chỉ `Left`/`Right`/`LeftCenter`/`RightCenter` mới xếp dọc.

## 2. Bản đồ hình: chú giải khi có cả Location và Series

Quan sát ở VM-D15: có `Location` + `Legend` thì các bang tô theo series (mẫu: toàn màu dữ liệu đầu của theme), không theo thang Color saturation. `VisualDataLoader.load` nay lấy giá trị Series cho cả hai trường hợp (có hay chưa có `Category`) qua truy vấn của visual; `ShapeMapView` bỏ màu theo thang khi có chú giải. Test `banDoHinhCoCaViTriLanSeriesVanCoChuGiai`.

## 3. Thác nước có Breakdown (`desktop-waterfall-breakdown.png`)

Ô: `Category`, `Breakdown`, `Y`, `Tooltips` (JSON: vai `Breakdown`, mặc định `sortDefinition` theo measure giảm dần, `isDefaultSort: true`). Cách Desktop vẽ (Category = `client_region`, Breakdown = `sex`, Total_Credit_Inflow: Northeast 0,82 + 0,90 = 1,72 tỉ; South 0,33 + 0,33; West 0,27 + 0,27; Midwest 0,15 + 0,16):

- Mỗi danh mục là một cột **Total** từ 0 đến tổng các phần tử Breakdown; danh mục xếp theo giá trị giảm dần (mặc định).
- Giữa hai danh mục liền nhau, mỗi phần tử Breakdown có một cột **chênh lệch** = giá trị ở danh mục kế − giá trị ở danh mục này, trôi từ tổng danh mục này đúng đến tổng danh mục kế (Northeast→South: Female −0,49, Male −0,57; South→West: −0,06 và −0,06; West→Midwest: Male −0,11 rồi Female −0,12). Chênh lệch xếp **giảm dần**. Danh mục cuối chỉ có cột Total.
- Chú giải thêm "Other" khi có Breakdown. Không có Breakdown (Category một mình): cột trôi từ 0 và cột Total cuối, chú giải 3 mục (như VM-D15).
- 72 danh mục (`desktop-waterfall-72-categories.png`): **không bỏ nhãn**, xoay −45° và thu nhỏ chữ cho vừa; nhãn dữ liệu bé; danh mục xếp theo giá trị giảm dần, Total ở cuối.

BI Pro: `WaterfallLayout.bars(values:categoryNames:breakdownNames:)`, `WaterfallChartView` có Breakdown, vai `Breakdown` vào truy vấn (`VisualQuerySpecReader`), mặc định sắp giá trị giảm dần cho thác nước (như phễu), ô Breakdown ở Build pane và `WellRules`; nhãn trục xoay và thu nhỏ chữ thay vì bỏ nhãn. Test `thacNuocCoBreakdownLaTotalRoiChenhLechTungPhanTu` dùng đúng số liệu trên (10 cột, đúng thứ tự); ảnh `bipro-waterfall-breakdown.png` (`NewChartsImageTests`).

## 4. Vùng xếp chồng 100% và hover theo series

- **Vùng 100%** (`hundredPercentStackedAreaChart`): đã có ở VM-D12 (JSON). BI Pro: `CartesianKind.hundredPercentStackedArea` (cộng dồn rồi chuẩn hoá mỗi danh mục về 1, trục 0% đến 100%), vào thư viện (thêm được, đổi tới được, luật ô, định dạng). Heavy test đổi đường D1 sang loại này ra đúng JSON Desktop. Ảnh: `bipro-hundred-percent-area.png`.
- **Ruy-băng: hover và chọn theo dải**: trỏ vào dải thì lấy điểm của series đó ở cột bên trái dải (thử trong app: dải giữa Fax và Phone hiện tooltip của Fax); vùng vẽ bị cắt trong khung khi miền trục do người dùng đặt nhỏ hơn dữ liệu.
- **Hover theo series ở vùng**: vùng xếp chồng lấy lớp chứa giá trị y của con trỏ; vùng chồng lên nhau lấy vùng phủ phía trên con trỏ có đỉnh thấp nhất (`CartesianChartView.areaSeriesIndex`). Thử trong app: trỏ vào dải Phone hiện tooltip "Kênh Phone" (`bipro-stacked-area-hover-series.png`).

## Còn lại (chưa làm, không có mẫu Desktop)

Thác nước: sắp xếp theo thứ tự tuỳ chọn của người dùng cho phần tử Breakdown, nhãn dữ liệu mặc định bật (chưa kiểm). Y-axis "Round range" và "Logarithmic scale" chưa vẽ.
