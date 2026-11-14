# VM-D15: bấm thử app, mặc định thẻ Format, bản đồ hình, bốn loại biểu đồ mới (2026-11-14)

Bạn giao ("Làm cho xong phần này (được sử dụng vm)"): bấm thử trong app (kéo tab trang, Advanced/Bottom N), lấy mẫu thêm mặc định thẻ Format, vẽ chú giải `Series` và màu `Value` của bản đồ hình, thêm loại vùng, ruy-băng, thác nước, phễu. Claude điều khiển VM (ngoại lệ một lần, hiến pháp vẫn giữ). Dùng bản sao `Nhom6_work.pbix` (ở Mac `~/Desktop/vmd15`, trong VM `vmd15`; đã xoá sau khi xong). Ảnh Desktop trong thư mục này đã cắt chỉ giữ phần visual.

## 1. Bấm thử trong app (BI Pro đóng gói mới)

Chụp riêng cửa sổ BI Pro. Kết quả:

- **Kéo tab trang** (Sửa, ⌘E): kéo "D1 · Giao dịch" sang phải D2 → thứ tự D2, D1, D3, tiêu đề "Chưa lưu"; ⌘Z trả lại D1, D2, D3 (⌘Z hụt khi con trỏ đang ở ô tìm kiếm: bấm ra vùng trống trước).
- **Bộ lọc cấp visual, "Loại bộ lọc" = Top N** trên cột Nhóm tuổi: Top/Bottom, N, "Theo giá trị" (measure), nút "Áp dụng bộ lọc". Bottom 3 theo `Avg Complaints per Month` → biểu đồ chỉ còn 3 nhóm tuổi (<25, 25-34, 65+), thẻ ghi "Bottom 3 theo …".
- **Advanced trên measure** ("Số khiếu nại" nhỏ hơn 2000) → biểu đồ đổi ngay, thẻ ghi "nhỏ hơn 2000".
- ⌘S: file có `"type":"TopN"`, `pageOrder` không đổi. **Mở file này trong Power BI Desktop: biểu đồ chỉ còn 3 nhóm tuổi, bộ lọc Advanced cho cùng kết quả như BI Pro.**

## 2. Mặc định thẻ Format (matrix mới, Desktop)

| Thẻ | Mặc định |
|---|---|
| General > Title | Bật; Text rỗng, Heading 3, Segoe UI, cỡ 12, **không đậm**, màu chữ xanh đen, nền không, căn trái, Text wrap Bật |
| Title > Subtitle | **Bật**; Divider **Tắt** |
| General > Effects | Background Bật (trắng, 0%), Visual border Bật, Shadow Tắt (khớp VM-D4) |
| General | Header icons Bật, Tooltips Tắt |
| Visual > Column headers | Segoe UI cỡ 10, +/- icons Bật, Options > Auto expand Tắt |

BI Pro: `FormatCatalog` ghi `defaultOn` cho `title.bold` (tắt) và `subTitle.show` (bật); test `titleAndSubtitleDefaultsSampledFromDesktop`. "Auto-size column width" không thấy ở thẻ Column headers của bản này, chưa lấy.

## 3. Bản đồ hình: chú giải `Series` và màu `Value`

Từ biểu đồ đường D1 đổi sang Shape map trong Desktop (`desktop-shapemap-series-legend.png`, `-colour-saturation.png`, `-colors-card.png`):

- Chỉ có `Series` (chưa có Location): bản đồ Albers USA, **mọi bang xám `#C7C7C7`, viền xám đậm hơn**; **chú giải ở dưới**: chấm màu dữ liệu của theme theo thứ tự và nhãn giá trị Series (ngày, cắt bằng "…"), có mũi tên phân trang. Danh sách chú giải chỉ gồm giá trị có dữ liệu (bắt đầu từ Jan 2013, không phải 2011 của bảng ngày).
- Thêm `Location` = `Dim_District[state_name]` và bỏ chú giải/giá trị: **mọi bang màu dữ liệu đầu của theme**.
- Có `Location` + `Color saturation` (`Loan Amount`): bang có giá trị tô thang màu **Min `#F8E5D8` (đào nhạt) → Max `#D9ECFB` (xanh nhạt)**, tuyến tính từ giá trị nhỏ nhất (318.780) đến lớn nhất (74.345.952, New York); **bang không có giá trị để xám**; mọi bang cùng giá trị thì ra màu Max. Thẻ Format > Colors > Color saturation hiện hai ô Min/Max màu và hai ô Min/Max giá trị.
- Có `Location` + `Legend` (+ `Value`): các bang tô theo series (toàn teal ở mẫu này); BI Pro chưa vẽ trường hợp này (bộ nạp không lấy series khi có Category).

BI Pro: `VisualDataLoader` lấy giá trị Series qua truy vấn của visual (bỏ giá trị mà measure `Value` trống) khi chưa có Category; `ShapeMapView` vẽ chú giải, nền xám và viền xám khi file không đặt `defaultColors`, thang màu Min/Max mặc định (`saturationColor`), bang trống giá trị thì xám; vai `Value` nay được đọc vào truy vấn. Test: `banDoHinhChiCoSeriesLayGiaTriChuGiai`, `thangMauSaturationMacDinhCuaDesktop`. Kiểm bằng ảnh: `bipro-shapemap-legend.png`, `bipro-shapemap-saturation.png` cùng hình với Desktop. Sửa kèm: ô "Chú thích công cụ" của bản đồ hình hiện hai lần trong Build pane (test `everyWellRoleAppearsOnce`).

## 4. Vùng, vùng xếp chồng, ruy-băng, thác nước, phễu

Hình mẫu Desktop (Category `Dim_Date[year]`, `Total_Credit_Inflow`, Legend `client_region`) ở `desktop-*.png`.

| Loại | Quan sát |
|---|---|
| Vùng (`areaChart`) | Các series chồng lên nhau, mỗi series một đường (nét ≈ 2) và phần tô mờ ≈ 0,43 của màu series, trục Y bắt đầu từ 0, nội suy trơn |
| Vùng xếp chồng (`stackedAreaChart`) | Cộng dồn các series, mỗi lớp tô mờ và có đường ở mép trên |
| Ruy-băng (`ribbonChart`) | Cột xếp chồng, series lớn nhất trên cùng (xếp lại theo từng danh mục); dải nối cùng tông nhạt hơn (≈ 0,62) giữa hai cột liền nhau, đường cong chữ S, viền trắng mảnh; cột rộng ≈ 0,42 ô |
| Thác nước (`waterfallChart`) | Cột trôi từ mức cộng dồn, tăng = `good` của theme, giảm = `bad`, cột Total ở cuối từ 0 (màu dữ liệu đầu); chú giải Increase, Decrease, Total (Desktop thêm Other khi có Breakdown); vạch nối mảnh. Ô Breakdown (Category rồi các phần con) chưa vẽ |
| Phễu (`funnel`) | Thanh ngang căn giữa, rộng theo giá trị so với thanh lớn nhất, sắp giá trị giảm dần, nhãn danh mục bên trái, giá trị trắng giữa thanh, "100%" trên thanh đầu, phần trăm của thanh cuối so với thanh đầu ở dưới (12.5%) |

Ô (từ VM-D12 và hình mới): vùng và ruy-băng có Category, Y, Series (Legend), Tooltips (vùng thêm Y2 "Secondary y-axis"); thác nước Category, Breakdown, Y; phễu Category (nhiều cấp), Values (`Y`), Tooltips.

BI Pro: `CartesianKind` thêm `.area`, `.stackedArea` (vẽ như đường kèm `AreaMark`, trục từ 0, cộng dồn lớp); view mới `WaterfallChartView`, `FunnelChartView`, `RibbonChartView`; `ChartPlotSupport` (trục, lưới, thưa nhãn); `ReportTheme.good/neutral/bad`; thư viện: `VisualTypes` (thêm được, đổi tới được), `WellRules`, `PBIRNewVisual.defaultSize`, `FormatCatalog.axisCharts`, phễu mặc định sắp giá trị giảm dần; đổi loại: `TypeChange` bỏ `trend` khi sang thác nước, phễu, đường+cột xếp chồng, phễu giữ `categoryAxis`, `PBIRVisualPatch.removingCategoryAxisType` (thác nước và phễu bỏ `axisType`), `defaultSortRole` có `areaChart`. **Heavy test `doiDuongSangVungRuyBangThacNuocPheuNhuDesktop`: đổi biểu đồ đường D1 sang năm loại này ra đúng từng khoá `visual.json` Desktop ghi ở VM-D12.** `themBoLoaiMoiLuuVaMoLai` thêm năm loại vào D1, lưu và mở lại; **Desktop mở `Nhom6_d15.pbix` bình thường** và vẽ năm visual (phễu thấy đúng).

Chưa khớp: nhãn trục dày (BI Pro bỏ nhãn cách đều, Desktop xoay/thưa theo cách riêng), vùng nhiều series có hover theo series, thác nước có Breakdown, ruy-băng: tooltip theo dải, `100%` xếp chồng vùng (chưa là loại thêm được). Xem thêm bảng ở STATE.
