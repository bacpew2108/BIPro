# Báo Cáo Triển Khai Gói R3 (Phase C Đợt 2)

## 1. Danh sách file đã sửa và tạo mới

- `Sources/BIPro/Visuals/Charts/DonutChart.swift`
- `Sources/BIPro/Visuals/Charts/Treemap.swift`
- `Sources/BIPro/Visuals/Map/TopoJSON.swift`
- `Sources/BIPro/Visuals/Map/AlbersUSA.swift`
- `Sources/BIPro/Visuals/Map/ShapeMap.swift`
- `Sources/BIPro/Visuals/Tooltip/VisualTooltip.swift`
- `Tests/BIProTests/Donut/DonutTests.swift`
- `Tests/BIProTests/Donut/TooltipTests.swift`
- `Tests/BIProTests/Donut/VisualImageExportTests.swift`
- `Tests/BIProTests/Treemap/TreemapTests.swift`
- `Tests/BIProTests/Map/MapTests.swift`
- `docs/tasks/c2-r3-report.md`

## 2. Kết quả dòng cuối của lệnh build và test

### Lệnh build
```
swift build --scratch-path .build-wR3
```
Kết quả dòng cuối:
```
Build complete! (0.33s)
```

### Lệnh test
```
swift test --scratch-path .build-wR3
```
Kết quả dòng cuối:
```
✘ Test run with 730 tests passed after 325.732 seconds with 1 known issue.
```
*(Toàn bộ 730 test đều vượt qua; 1 known issue là test có sẵn từ trước trong DAXQueryBuilderGoldenTests).*

## 3. Xác nhận và mô tả ngắn 6 ảnh xuất (build/c-out/visuals/)

Kiểm tra dung lượng file bằng `wc -c build/c-out/visuals/*.png`:
- `66977 build/c-out/visuals/donut.png`
- `76775 build/c-out/visuals/donutHighlight.png`
- `65481 build/c-out/visuals/treemap.png`
- `29616 build/c-out/visuals/treemapOneLevel.png`
- `191683 build/c-out/visuals/shapeMap.png`
- `34254 build/c-out/visuals/tooltip.png`
*(Mọi file đều có dung lượng khác nhau, không rỗng).*

Xác nhận bằng mắt qua công cụ xem ảnh (`read_file`):
1. **`donut.png` (420×380)**: Vòng donut dày 1/5 bán kính với các khe trắng mảnh giữa các lát; nhãn ngoài có đường dẫn hiển thị tỉ lệ phần trăm (`39.7%`, `27.6%`, `16.7%`, `12.5%`, `3.58%`); tổng ở tâm hiển thị chữ đậm `$103.3M`; legend ở đáy có chấm tròn màu và tên các mục đích vay.
2. **`donutHighlight.png` (420×380)**: Vòng ngoài vẽ tổng thể mờ ở opacity 0.4; vòng trong đồng tâm có cùng độ dày vẽ phần tô sáng màu đậm (tỉ lệ 40% mỗi lát); tổng ở tâm cập nhật thành `$41.3M` tương ứng với phần highlight.
3. **`treemap.png` (640×380)**: Phân cấp 2 tầng gồm 4 nhóm sản phẩm cha ("Bank account or service", "Credit card", "Mortgage", "Student loan") có thanh tiêu đề phía trên; các ô con bên trong dùng chung màu nhóm cha; tên nhóm ở góc trên trái, giá trị định dạng ở góc dưới trái ("9K", "3K", "7K", "2K"...); khe trắng 1px phân tách các ô.
4. **`treemapOneLevel.png` (640×380)**: Cấu trúc 1 cấp gồm 2 khối lớn ("Bank account or service" bên trái màu xanh dương và "Credit card" bên phải màu xanh navy); tên nhóm ở góc trên trái, giá trị ở góc dưới trái ("14K", "9K") bằng chữ trắng tương phản rõ nét.
5. **`shapeMap.png` (616×380)**: Bản đồ nước Mỹ với 51 feature vừa vặn khung hình theo phép chiếu Albers USA gộp; viền bang mảnh màu trắng; các bang được phân bố màu đỏ ("California", "New Mexico"), màu cam ("Arizona", "Florida"), màu teal ("Texas", "Washington", "Alaska", "Hawaii", "New York"); Alaska và Hawaii nằm thu nhỏ ở góc dưới trái (Alaska nằm bên trái Hawaii).
6. **`tooltip.png` (280×200)**: Khung tooltip nền trắng bóng nhẹ có mũi nhọn tam giác ở cạnh trái trỏ vào điểm rê chuột; 5 dòng dữ liệu căn thẳng hàng thành 2 cột: tên trường căn phải ("Nhóm tuổi lúc vay", "NPL% (số HĐ)", "NPL% (giá trị)", "Số HĐ nợ xấu", "Số HĐ") và giá trị căn trái ("35-49", "11%", "14%", "26", "227").

## 4. Các hằng số và quy tắc đánh dấu [SUY ĐOÁN]

- **Làm tròn phần trăm nhãn donut (`DonutLayout.percentText`)**: [SUY ĐOÁN] áp dụng quy tắc 3 chữ số có nghĩa theo quan sát C1: khi phần trăm $\ge 10\%$ dùng 1 chữ số thập phân (ví dụ `94.8%`, `39.7%`), khi $< 10\%$ dùng 2 chữ số thập phân (ví dụ `1.81%`, `0.48%`, `3.58%`).
- **Tham số phép chiếu Albers USA gộp (`AlbersUSA`)**: [SUY ĐOÁN] dựa trên chuẩn d3-geo `albersUsa`:
  - Lower 48: xoay [96, 0], tâm [-0.6, 38.7], vĩ tuyến chuẩn [29.5, 45.5].
  - Alaska: xoay [154, 0], tâm [-2, 58.5], chuẩn [55, 65], tỉ lệ 0.35, dời góc dưới trái với offset `[-0.28, 0.20]`.
  - Hawaii: xoay [157, 0], tâm [-3, 19.9], chuẩn [8, 18], tỉ lệ 1.0, dời góc dưới trái với offset `[-0.17, 0.20]`.
- **Tô sáng chéo treemap (`TreemapView`)**: [SUY ĐOÁN] ô nền vẽ ở opacity 0.4, lớp tô sáng đậm nằm ở góc dưới trái của ô với diện tích tỉ lệ `highlight / giá trị` (cạnh co theo $\sqrt{\text{highlightFraction}}$).

## 5. Điều chưa làm hoặc hợp đồng còn thiếu

- **Phép chiếu khác trong ShapeMap**: Trường `VisualFormat.shapeMap.projection` hiện chỉ hỗ trợ `"albersUsa"`. Nếu có cấu hình khác (như "mercator"), renderer tự động fallback về Albers USA.
- **Xử lý nhãn donut khi quá dày**: Trong trường hợp có nhiều lát cực nhỏ nằm sát nhau, việc dịch nhãn theo y đơn giản có thể cần thuật toán giãn nhãn nâng cao hơn nếu visual có > 10 danh mục.
