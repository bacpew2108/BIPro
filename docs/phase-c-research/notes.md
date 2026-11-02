# Phase C: ghi chú tài liệu công khai (đợt 0, 2026-11-02)

Nhãn:
- **[TÀI LIỆU]**: đọc trực tiếp từ trang công khai.
- **[TÀI LIỆU, chưa kiểm]**: lấy qua bản tóm tắt của công cụ đọc web. Mở lại trang trước khi dùng làm luật trong code.
- **[SUY ĐOÁN]**: chưa có nguồn.

Không trang nào dưới đây thay được quan sát trực tiếp ở buổi C1; khi hai nguồn khác nhau thì ưu tiên quan sát.

## 1. Giới hạn điểm dữ liệu

Nguồn [TÀI LIỆU]: Microsoft Learn "Data point limits and strategies by visual type" (`learn.microsoft.com/power-bi/visuals/power-bi-data-points`) và "High density line sampling" (`…/create-reports/desktop-high-density-sampling`).

**Các chiến lược giảm dữ liệu:** Data Windowing, TopN, Simple Sample ("first, last, and N evenly distributed items"), BottomN, High-density sampling.

| Visual | Giới hạn theo tài liệu | Truy vấn thật (PA) |
|---|---|---|
| Bar/column, dạng danh mục | Categories: cửa sổ 500 dòng; Series: Top 60 | `TOPN(1001, …)` (PA-D2-2, D3-2, D4-x); có series thì `TOPN(201, primary)` × `TOPN(62, secondary)` (PA-D3-1) |
| Bar/column, dạng scalar | tối đa 10.000 điểm; Categories: mẫu 500; Series: Top 20 | `SAMPLE(3502, …)` (PA-D2-1: combo theo năm) |
| Combo | như column; phần đường **không** dùng high-density | PA-D2-1, D3-1 |
| Line, trục liên tục | 3.500 điểm; tối đa 60 series; ít nhất 350 điểm mỗi series; mỗi bin giữ max và min | `SAMPLEAXISWITHLOCALMINMAX(3500, …, 350, , ALPHABETICAL, ASC, 105000, 60)` (PA-D1-1) |
| Donut/pie | 3.500 điểm; chỉ Legend: Top 1000; Legend + Details: Top 500 × Top 20 | chờ O-C1 |
| Treemap | 3.500 điểm; Group Top 500, Details Top 20 | chờ O-C1 |
| Matrix | Rows: cửa sổ 500; Columns: Top 100 | `TOPN(102, …)` × `TOPN(102, …)` (PA-D1-2) |
| Table | cửa sổ 500, tối đa 150 cột | không có trong Nhom6 |
| Slicer, multi-row card | cửa sổ 200 | chờ O-C1 |
| Shape map | 1.500 điểm; Categories Top 500 | chờ O-C1 |

Số trong truy vấn PA lớn hơn số trong tài liệu (1001 so với 500, 102 so với 100). [SUY ĐOÁN] Power BI xin thêm 1 dòng để biết còn dữ liệu phía sau, và có thể dùng cửa sổ khác ở Desktop. **Builder lấy số từ truy vấn PA, không lấy từ tài liệu.**

## 2. Tương tác giữa visual

Nguồn [TÀI LIỆU]: Microsoft Learn "Change how visuals interact in a report".

- Mặc định, visual trên một trang **lọc chéo và tô sáng chéo** các visual khác.
- "You can only cross-filter line charts, scatter charts, and maps. You can't cross-highlight them." Nghĩa là line chart và map chỉ bị lọc chứ không bị tô sáng.
- Drill **mặc định không ảnh hưởng** visual khác. Setting "Apply drill down filters to → Entire page" bật điều đó. [SUY ĐOÁN] Trong file, setting này nằm ở `drillFilterOtherVisuals`; Nhom6 có 52 visual mang thuộc tính này, giá trị sẽ kiểm ở gói Q.
- Matrix với trường từ nhiều bảng: chọn nhiều mục ở các cấp khác nhau thì visual khác báo lỗi (giới hạn đã biết của Power BI; không cần bắt chước).
- **Tài liệu không nói:** Ctrl+click, cách bỏ chọn, quy tắc riêng cho slicer/card/table. Các điểm này chờ O-C4 và O-C11.

## 3. Hàm DAX dùng trong truy vấn visual

Nguồn [TÀI LIỆU, chưa kiểm]: dax.guide.

- **SAMPLE**(Size, Table, OrderBy [, Order] …):
  - lấy dòng đầu, dòng cuối và các dòng cách đều ở giữa; kết quả xác định (không ngẫu nhiên);
  - Size ≤ 0 thì trả bảng rỗng;
  - ví dụ của trang: {2,4,4,4,5,5,7,9}, Size 3 → vị trí 1, 5, 8 → 2, 5, 9. Trang tự mâu thuẫn ở một chú thích, nên cần kiểm bằng VM nếu số dòng vượt ngưỡng; Nhom6 không vượt.
- **SAMPLEAXISWITHLOCALMINMAX**(Size, Table, Axis, Measure…, MinResolution [, DynamicSeries…] [, DynamicSeriesSelectionCriteria] [, Order] [, MaxResolution] [, MaxDynamicSeries] [, MaxIterations]):
  - Microsoft không có tài liệu; dax.guide ghi "not recommended", chỉ mô tả tham số;
  - BI Pro: số dòng ≤ Size thì trả đủ dòng (đúng với Nhom6, vì trục tháng chỉ có 72 dòng). Thuật toán chia bin khi vượt ngưỡng là [SUY ĐOÁN]: chia trục thành bin đều, mỗi bin giữ điểm min và max.
- **SUBSTITUTEWITHINDEX**(Table, Name, SemiJoinIndexTable, Expression, [Order] …):
  - giữ các dòng có giá trị khớp trong SemiJoinIndexTable (như inner join);
  - các cột dùng để nối được thay bằng một cột chỉ số bắt đầu từ 0, đánh theo thứ tự của các Expression;
  - cột khớp nhau khi cùng lineage, hoặc cùng không có lineage và cùng tên; không khớp cột nào thì báo lỗi.
- **ROLLUPADDISSUBTOTAL**([GrandtotalFilter,] cột…, Name [, GroupLevelFilter] …):
  - chỉ dùng trong SUMMARIZECOLUMNS;
  - thêm dòng tổng; cột cờ `Name` là TRUE ở dòng tổng, FALSE ở dòng chi tiết; cột bị gộp là BLANK ở dòng tổng;
  - nhiều cặp thì mỗi cặp có cờ riêng; thứ tự các cặp quan trọng.
  - **ROLLUPGROUP** gộp nhiều cột thành một cấp tổng (PA-D1-2: tuổi và thứ tự tuổi).
- **IGNORE**(expr): chỉ dùng trong SUMMARIZECOLUMNS. Dòng bị loại khi mọi biểu thức **không** IGNORE đều BLANK, bất kể biểu thức IGNORE có giá trị hay không.
- **NATURALLEFTOUTERJOIN**(Left, Right):
  - nối theo các cột cùng tên và cùng lineage;
  - cùng tên mà khác lineage thì báo lỗi;
  - một dòng trái khớp nhiều dòng phải thì ra nhiều dòng; dòng trái không khớp giữ một lần, phần phải BLANK;
  - không bảo đảm thứ tự; không ép kiểu (1 ≠ 1.0).
- **GROUPBY**(Table, cột…, Name, Expression…): mỗi biểu thức phải lặp trên `CURRENTGROUP()`; không được dùng CALCULATE trong vòng lặp đó.

## 4. Dự báo trên line chart

- Trang Microsoft Learn về forecasting trả 404 (2026-11-02). Chưa có nguồn công khai về thuật toán.
- Trong file: `forecast.transform.parameters` gồm `Unit = 7`, `ForecastLength = 6`, `IgnoreLast = 0`, `ConfidenceLevel = 0.95`.
- Quyết định (PHASE_C_PLAN §6): vẽ trend tuyến tính đúng. Dự báo dùng Holt-Winters cộng tính và ghi [SUY ĐOÁN]. Muốn khớp hẳn thì để Phase G.
