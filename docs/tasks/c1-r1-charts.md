Bạn làm việc trong repo Swift "BI Pro", một ứng dụng macOS (SwiftUI/AppKit, macOS 15) giống Power BI Desktop. Bạn đang ở một git worktree riêng, tách từ `main`.

## Mục tiêu (gói R1, Phase C)

Viết renderer cho biểu đồ trục XY, vẽ từ dữ liệu đã chuẩn bị sẵn. Renderer **không biết DAX, không gọi engine**.

Các loại visual cần hỗ trợ:
- `clusteredBarChart`: thanh ngang, cụm;
- `clusteredColumnChart`: cột, cụm;
- `stackedColumnChart`, `hundredPercentStackedColumnChart`;
- `lineChart`;
- `lineClusteredColumnComboChart`: cột cụm + đường trên trục Y2;
- `lineStackedColumnComboChart`: cột chồng theo Series + đường trên trục Y2.

**Hợp đồng có sẵn, đọc kỹ trước, KHÔNG sửa:**
- `Sources/BIPro/Visuals/Query/DataView.swift`: `CategoricalData`, `DataCell`, `FieldInfo`. Chú ý quy ước `values[m][s][c]`, và measure không chia theo series có chiều `s` = 1.
- `Sources/BIPro/Visuals/Format/VisualFormat.swift`: nhãn, trục, legend, `dataPoint`, `analytics.trendShow`.
- `Sources/BIPro/Visuals/Format/NumberDisplay.swift`: mọi chữ số trên biểu đồ phải đi qua đây.
- `Sources/BIPro/Visuals/Interaction/InteractionTypes.swift`: `VisualRenderContext`, `VisualActions`, `DataPointID`.
- `Sources/BIPro/Visuals/Fixtures/DataViewSamples.swift`: mẫu `comboLoansByYear`, `barNPLByAge`, `lineMonthlyAmount`, `stackedComplaintsByChannel`, `percentStackedStatus`.
- `Sources/BIPro/Formatting.swift`: `ReportTheme.color(_:)`, `dataColor(_:)`, `Color(hex:)`.

Ảnh Power BI để làm theo, trong `docs/phase-c-evidence/observe-c1/shots/`:
- `page-D1.png`, `page-D2.png`, `page-D3.png`;
- `xf-D2.png`: tô sáng chéo;
- `tooltip-bar.png`.

Đọc thêm `docs/phase-c-evidence/C1.md` §2.4.

## Chỉ được sửa hoặc tạo các file sau

- Sources/BIPro/Visuals/Charts/CartesianChart.swift
- Sources/BIPro/Visuals/Charts/ComboChart.swift
- Sources/BIPro/Visuals/Charts/ChartAxis.swift
- Sources/BIPro/Visuals/Charts/ChartLegend.swift
- Sources/BIPro/Visuals/Charts/DataLabels.swift
- Sources/BIPro/Visuals/Charts/TrendLine.swift
- Tests/BIProTests/Charts/** (mới)

KHÔNG sửa file nào khác, kể cả các file hợp đồng ở trên, `Package.swift`, `Sources/BIPro/Report/**`, `Sources/DAXEngine/**`. Nếu thấy hợp đồng thiếu gì thì ghi vào báo cáo cuối; đừng tự sửa.

Hai worker khác đang làm song song:
- một người sửa `Sources/DAXEngine`;
- một người sửa `Sources/BIPro/Visuals/{Cards,Slicer,Matrix}`.

Thêm:
- Không commit, không push, không cài package, không tải từ mạng.
- Không đọc hay ghi gì trong `~/Downloads`.
- Chỉ dùng SwiftUI, Swift Charts, AppKit. Không thêm thư viện.

## API công khai cần có (tên giữ đúng)

```swift
enum CartesianKind: Hashable, Sendable {
    case clusteredBar, clusteredColumn, stackedColumn, hundredPercentStackedColumn, line, comboClustered, comboStacked
    init?(visualType: String)   // tên visualType ở trên → case; khác thì nil
}

struct CartesianChartView: View {
    init(data: CategoricalData, kind: CartesianKind, context: VisualRenderContext)
}
```

Hàm thuần dùng cho test (đặt trong file tương ứng, `static`, không phụ thuộc View):
- `ChartAxis.niceTicks(min: Double, max: Double, targetCount: Int) -> [Double]`: vạch "đẹp" (bước 1, 2, 2.5, 5 × 10^k), bao trọn [min, max] và bắt đầu từ 0 khi min ≥ 0.
- `ChartAxis.labels(ticks: [Double], units: DisplayUnits, precision: Int?, formatString: String?) -> [String]`:
  - mọi vạch cùng một đơn vị, chọn theo giá trị tuyệt đối lớn nhất;
  - chữ số thập phân vừa đủ để các vạch khác nhau;
  - ví dụ:
    - (0…30M, `$#,0`) → `["$0M","$10M","$20M","$30M"]`;
    - (0…1bn bước 0.5bn) → `["$0.0bn","$0.5bn","$1.0bn"]`;
    - định dạng `0%` → `["0%","5%","10%","15%"]`.
- `StackLayout.segments(...)`: tính đoạn chồng (dương chồng lên trên, âm chồng xuống dưới) và chuẩn hoá 100%.
- `TrendLine.linearFit(_ points: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double)?`: bình phương tối thiểu; ít hơn 2 điểm thì nil.
- `ComboChart.secondaryScale(...)`: quy đổi giá trị Y2 về toạ độ khung vẽ chung theo dải vạch Y2 riêng.

## Hành vi hiển thị (theo ảnh Power BI)

- **Nền** trong suốt (container đã vẽ nền). Đường lưới ngang xám rất nhạt, không có đường trục. Nhãn trục Y bên trái, Y2 bên phải, nhãn danh mục ở dưới. Cỡ chữ mặc định 9 pt, hoặc `categoryAxis.fontSize`.
- **Thanh ngang** (`clusteredBar`): danh mục là trục dọc, từ trên xuống theo thứ tự dữ liệu.
- **Màu:**
  - mặc định `theme.dataColor(i)`: theo series nếu có Series, không thì theo measure;
  - ghi đè theo thứ tự ưu tiên: `DataCell.fillColor` (màu lấy từ measure, theo từng điểm) > `format.dataPoint.fillByValue` (theo giá trị danh mục/series; so `ScopedValue.column` với `queryRef` của trường) > `format.dataPoint.fillByMeasure[queryRef]` > `defaultFill`.
- **Combo:** cột dùng các measure role "Y", đường dùng role "Y2". Trục Y2 có vạch và nhãn riêng ở bên phải. Đường mượt như ảnh D2: dùng `.interpolationMethod(.catmullRom)`.
- **Line trục liên tục** (`categoryAxis.axisType == "Scalar"`): danh mục là chuỗi "yyyy-MM" hoặc ngày. Nhãn trục X chỉ hiện năm (`2013 … 2019`) như ảnh D1. Nếu `analytics.trendShow == true`, vẽ đường xu hướng nét đứt màu tối.
  - **Không** vẽ dự báo (`forecast`); lead sẽ làm sau.
- **Nhãn dữ liệu:** hiện khi `dataLabels.show == true`, đặt ở cuối thanh/cột, số qua `NumberDisplay.text(cell, units:, precision:)`. Cột 100% hiện phần trăm với 2 chữ số thập phân (`15.00%`, như ảnh D2).
- **Legend:** hiện khi có Series hoặc nhiều hơn một measure, trừ khi `legend.show == false`. Mỗi mục là chấm tròn màu và tên. Vị trí theo `legend.position`: Top/Bottom/TopCenter/…; mặc định Top, căn trái.
- **Ô BLANK:** không vẽ.
- **Chọn (selection):** `context.selection` khác rỗng thì điểm không nằm trong đó vẽ opacity 0,4.
- **Tô sáng chéo:** `data.highlights != nil` thì vẽ giá trị đầy đủ ở opacity 0,4, rồi phần tô sáng đè lên với màu đậm, cùng gốc 0 (ảnh `xf-D2.png`, combo và cột 100%).
- **Tương tác** (gọi `context.actions`):
  - bấm một cột/thanh/điểm → `select(DataPointID, additive: ⌘ hoặc Ctrl đang giữ)`;
  - bấm vào chỗ trống → `select(nil, false)`;
  - rê chuột → `hover(point, location)`; rời khỏi → `hover(nil, …)`;
  - chuột phải → `contextMenu`.
  - `DataPointID` gồm `queryRef` của mọi cấp danh mục cùng series, với giá trị của điểm.
  - Tooltip không do renderer vẽ.
- **Không có dữ liệu** (0 danh mục): hiện chữ xám nhỏ "Không có dữ liệu" ở giữa.
- **Hiệu năng:** 72 tháng × 2 measure, hoặc 12 × 6 series, phải vẽ mượt. Không tính lại layout trong `body` mỗi lần rê chuột; tách phần tính thành struct thuần, có thể cache.

## Test bắt buộc (`Tests/BIProTests/Charts/`)

- `niceTicks`, `labels`: ít nhất 6 ca, gồm 3 ví dụ ở trên.
- `StackLayout`: chồng dương/âm, chuẩn hoá 100% với cột có BLANK.
- `TrendLine.linearFit`: điểm thẳng hàng; 1 điểm (nil); dữ liệu `lineMonthlyAmount` (slope > 0).
- `CartesianKind(visualType:)` cho đủ 7 loại, cùng một chuỗi lạ (nil).
- Thứ tự ưu tiên màu (hàm thuần trả hex/literal cho một điểm).
- **Xuất ảnh:** một test `@MainActor` render mỗi mẫu (5 mẫu ở trên + mẫu `barNPLByAge` có `highlights` giả lập) bằng `ImageRenderer` cỡ 640×380 ra PNG ở `build/c-out/visuals/<tên>.png`. Thư mục tính từ `#filePath`: đi lên tới gốc repo, rồi `build/c-out/visuals`; tự tạo thư mục bằng FileManager. Test chỉ kiểm ảnh khác rỗng. Lead sẽ xem ảnh bằng mắt khi review.
- Test có tạo View/AppKit phải đánh dấu `@MainActor`.
- **Không viết cứng kết quả để test qua.**

## Lệnh build/test của project

```
swift build --scratch-path .build-wR1
swift test --scratch-path .build-wR1 --filter BIProTests
```

## Tiêu chí xong

- Cả hai lệnh xanh.
- Ảnh PNG được tạo cho mọi mẫu.
- Cuối cùng in:
  - danh sách file đã sửa, mỗi file một dòng tóm tắt;
  - kết quả hai lệnh;
  - đường dẫn các ảnh;
  - điều gì chưa làm hoặc thấy hợp đồng thiếu.

## Lệnh shell được phép

Chỉ dùng: swift build, swift test, git status/diff/log/show, ls, cat, grep, rg, head, tail, wc, pwd, find, sed -n, sort, uniq, echo, file.

Lệnh khác sẽ bị từ chối và làm dừng cả phiên. Đọc và sửa file thì dùng công cụ đọc/sửa file của bạn.
