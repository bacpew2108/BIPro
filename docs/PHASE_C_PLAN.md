# Phase C: Report có số liệu và tương tác (kế hoạch v1, 2026-11-02)

> **Nguồn:** report và model Nhom6 của bạn (đọc qua PBIXKit, giải nén phần `Report/` vào scratchpad), 8 truy vấn Performance Analyzer bạn copy ở buổi 2 (`docs/phase-b-evidence/observe2/PA-*`), engine hiện tại, tài liệu công khai (Microsoft Learn, dax.guide, SQLBI). Không decompile Power BI.
>
> **Test trong Power BI Desktop (VM Windows 11) do bạn tự làm tay.** Mình chuẩn bị checklist và file; bạn làm, copy kết quả hoặc chụp màn hình.
>
> **Giao việc:** theo `CLAUDE.md`. Tối đa 3 worker agy cùng lúc, mỗi việc một worktree, tập file không giao nhau, review xong mới báo bạn; không tự merge.

## Trạng thái (cập nhật 2026-11-02)

**Đợt 0 xong.** Kết quả:
- **Hợp đồng** trong `Sources/BIPro/Visuals/`:
  - `Query/DataView.swift`: dữ liệu để vẽ, gồm single, categorical, matrix, slicer;
  - `Query/VisualQuerySpec.swift`;
  - `Format/VisualFormat.swift`: đọc mọi nhóm `objects` Nhom6 dùng, kể cả màu/icon lấy từ measure và gradient;
  - `Format/NumberDisplay.swift`: K/M/bn, giữ ký hiệu tiền tệ;
  - `Interaction/InteractionTypes.swift`: `DataPointID`, `VisualActions`, `VisualRenderContext`;
  - `Fixtures/DataViewSamples.swift`: 12 mẫu, số lấy từ PA khi có.
  - `Tests/BIProTests/VisualContractTests.swift`: 11 test, xanh.
- **Đo hiệu năng:** `dax-run profile` (C1.md §1.5).
  - D2 0,1 s; Chi tiết chi nhánh 1,0 s.
  - D1 36,6 s và D3 12,6 s, do 3 visual (combo thấu chi 34 s, matrix Giờ × Thứ 8 s, combo kênh 12,7 s).
  - Vì vậy thêm gói **E3**.
- **Bảng sở hữu file:** `docs/phase-c-ownership.tsv`. Binder chuyển sang E1, vì SUMMARIZECOLUMNS làm hàm bảng cần binder. E2 chỉ sửa Catalog. E3 chạy ở đợt 2.
- **Tài liệu công khai:** `docs/phase-c-research/notes.md`. Quan sát từ file và PA: `docs/phase-c-evidence/C1.md`.
- **Checklist buổi C1:** `docs/phase-c-oracle/CHECKLIST-C1.md`, chờ bạn làm.

**Buổi C1 xong** (2026-11-02): 64 truy vấn, 11 kết quả, 9 ảnh; quan sát ở `docs/phase-c-evidence/C1.md` §2. Engine chạy được 0/64; danh sách việc của E1 ở C1.md §2.5.

**Đợt 1 đang chạy** (2026-11-02): 3 worker agy E1 ‖ R1 ‖ R2 ở worktree `c1-e1-engine`, `c1-r1-charts`, `c1-r2-cards`. Lead đã xong:
- E2: measure ẩn `_<M> FormatString`; `SELECTEDMEASURE()` thay bằng M.
- Q:
  - `VisualQuerySpecReader` và `DAXQueryBuilder`: văn bản trùng Power BI ở **43/44** visual mặc định. Còn thiếu slicer hierarchy đang mở nút.
  - `DataViewMapper`: thử bằng kết quả thật của Power BI.
  - `VisualDataLoader`.
- `NumberDisplay`: độ chính xác tự động theo định dạng của measure, khớp card D1/D2.

## 0. Mục tiêu và tiêu chí xong

Mở `Nhom6_Dashboard.pbix` trong BI Pro: 3 trang D1–D3 và trang drillthrough "Chi tiết chi nhánh" hiện **số thật** và **tương tác như Power BI**.

Xong khi đạt cả 5 điểm sau:

1. **Số liệu đúng.** Mọi visual có dữ liệu ra cùng giá trị với Power BI ở trạng thái mặc định. Kiểm bằng golden PA (§5.1) và ảnh chụp đặt cạnh nhau (§5.3).
2. **Truy vấn giống Power BI.** Với mọi visual đã copy được truy vấn từ Performance Analyzer, văn bản DAX do BI Pro sinh ra trùng với Power BI sau khi chuẩn hoá khoảng trắng (§5.1).
3. **Tương tác.** Checklist C-I (§5.4) đạt:
   - slicer;
   - Filters pane sửa được;
   - lọc chéo và tô sáng chéo;
   - drill down/up, expand;
   - drillthrough;
   - tooltip;
   - Selection pane;
   - bookmark.
4. **Hiệu năng** trên M1 Pro:
   - trang mở lần đầu: visual đầu tiên có số dưới 1 s, cả trang dưới 3 s;
   - đổi slicer: cả trang cập nhật dưới 1,5 s;
   - rê chuột, chọn điểm dữ liệu (không chạy truy vấn): dưới 150 ms.
5. `swift test` xanh; test nặng (golden PA) xanh.

**Ngoài phạm vi** (để Phase D/G):
- sửa visual, Format pane sửa được;
- visual tuỳ biến (custom visual);
- Q&A, AI;
- dự báo (`forecast`) khớp đúng thuật toán của Power BI: Phase C vẽ đường xu hướng thật, còn dự báo chỉ làm gần đúng và ghi [SUY ĐOÁN] (§6).

## 1. Phạm vi đo trên Nhom6

### 1.1 Visual theo trang

| Trang | Visual | Có dữ liệu | Loại có dữ liệu |
|---|---|---|---|
| D1 · Giao dịch | 36 | 22 | 5 slicer (3 cái là hierarchy Năm/Quý/Tháng, Vùng/Bang/Chi nhánh, Loại GD/Nghiệp vụ), 12 card (6 card số + 6 card "Δ Label"), 2 line, 1 donut 3 cấp, 2 matrix, 2 combo cột cụm + đường |
| D2 · Khoản vay | 32 | 21 | 6 slicer, 12 card, 1 combo cột chồng + đường (hierarchy Năm/Quý/Tháng), 1 donut 2 cấp, 1 cột chồng 100%, 1 **shape map** (bang Mỹ), 1 bar cụm, 1 combo cột cụm |
| D3 · Chăm sóc KH | 32 | 21 | 6 slicer, 12 card, 2 combo cột chồng có Series, 1 combo cột cụm (Pareto 2 đường), 2 bar cụm (1 cái có Series), 1 **treemap** 2 cấp |
| Chi tiết chi nhánh (ẩn, drillthrough) | 34 | 17 | 14 card (có Branch Title/Subtitle), 1 line, 1 donut, 1 bar |

Tổng cộng 9 loại visual có dữ liệu:
- `card`;
- `slicer` (cả 17 cái đều ở dạng **Dropdown**);
- `lineChart`;
- `donutChart`;
- `pivotTable` (matrix);
- `clusteredBarChart`;
- `hundredPercentStackedColumnChart`;
- `lineClusteredColumnComboChart` / `lineStackedColumnComboChart`;
- `treemap`, `shapeMap`.

Không có `tableEx`, `kpi` hay `multiRowCard`. Phase C làm đúng 9 loại trên; `tableEx` dùng lại phần lõi của matrix nếu còn thời gian.

### 1.2 Định dạng đang dùng

| Nhóm `objects` | Số visual | Ghi chú |
|---|---|---|
| `labels`, `categoryLabels` (card) | 50 | cỡ chữ, màu, ẩn nhãn danh mục |
| **Màu lấy từ measure** (`solid.color` = `Measure`) | 70 | ví dụ màu chữ của "Δ Label" = measure `… Δ Color`; cột = `NPL Group Color`. Power BI đưa các measure này vào truy vấn dưới dạng `IGNORE(...)` (thấy trong PA-D2-2) |
| `dataPoint` | 9 | màu theo series hoặc danh mục (`'Male'`, `'Female'`, `'Debit'`…) |
| `valueAxis`, `categoryAxis`, `legend` | 9 | |
| `FillRule` (thang màu gradient) | 2 | trong matrix D1 |
| `forecast`, `trend` | 1 | line chart D1: "Dự báo 6 tháng" + đường xu hướng |
| `columnHeaders`, `rowHeaders`, `grid`, `subTotals`, `columnWidth` | 2 | matrix |
| `shape`, `defaultColors` | 1 | shape map dùng `usa.states.topo.json` (117 KB, nằm trong file) |

### 1.3 Bộ lọc và tương tác có trong file

- **Bộ lọc cấp report (2 cái):** `Dim_Date[year]` khác 9999 và `Dim_Client[client_region]` khác "Unknown". Hai bộ lọc này xuất hiện trong mọi truy vấn PA, dưới dạng `__DS0FilterTable`.
- **Bộ lọc cấp visual (1 cái):** matrix D1 có bộ lọc `trans_hour`.
- **Drillthrough:** trang "Chi tiết chi nhánh" có `pageBinding` kiểu Drillthrough, tham số `Dim_Account[branch_city]` và các tham số khác, cùng 4 bộ lọc trang.
- **Bookmark (2 cái):** "Giờ × Thứ" và "Tháng trong năm". Cả hai có `suppressData` và `applyOnlyToTargetVisuals`, nghĩa là chỉ đổi ẩn/hiện của 6 visual (matrix ↔ line, cùng các nút). 4 action button gọi các bookmark này.
- **Drill:**
  - 52 visual có `drillFilterOtherVisuals`;
  - combo D2 có hierarchy Năm/Quý/Tháng, mức đang hiện là "Năm" (`active: true`);
  - 1 matrix có `expansionStates`;
  - 4 visual có `sortDefinition`.
- **Không visual nào sửa `visualInteractions`**, nên tất cả dùng tương tác mặc định của Power BI. Mặc định này phải quan sát ở buổi C1.

### 1.4 Engine hôm nay chạy 8 truy vấn PA được bao nhiêu?

Lead đã thử chạy (dax-run, bản release mới build): **0/8 chạy được**. Các chỗ còn thiếu:

| Thiếu | Gặp ở |
|---|---|
| `SUMMARIZECOLUMNS` làm biểu thức bảng trong `VAR` (hiện chỉ chạy được ngay sau EVALUATE) | cả 8 |
| `KEEPFILTERS(<bảng>)` làm đối số bảng của FILTER (hiện báo "KEEPFILTERS không trả về bảng") | cả 8 |
| `IGNORE` | D1-1, D2-2, D3-1, D3-2, D4-1, D4-2 |
| measure định dạng động `'T'[_M FormatString]` (measure ẩn sinh từ `formatStringDefinition`) | D2-2, D3-1, D3-2, D4-2 |
| `ROLLUPADDISSUBTOTAL`, `ROLLUPGROUP` | D1-2 (matrix) |
| `NATURALLEFTOUTERJOIN`, `SUBSTITUTEWITHINDEX` | D1-2, D3-1 |
| `GROUPBY`, `CURRENTGROUP` | D1-2 |
| `SAMPLE` | D2-1 |
| `SAMPLEAXISWITHLOCALMINMAX` | D1-1 (line) |
| `TOPN` nhiều khoá sắp xếp, `SUMMARIZE` trên biến bảng có cột `[IsGrandTotal…]` | D1-2, D2-2, D3-1 |

Khi bỏ KEEPFILTERS và chạy thẳng phần lõi SUMMARIZECOLUMNS, engine ra **đúng** kết quả PA-D2-1 (6 dòng, 0,025 s). 6 card số của D1 tính trong **1,05 s**, nên hiệu năng là rủi ro số 1 (§6).

`PA-D3-1.dax` dòng 49 có dấu `\` ở cuối dòng. Khả năng cao đây là lỗi khi copy; cần xác nhận ở buổi C1 (O-C9).

## 2. Kiến trúc

### 2.1 Quyết định: sinh văn bản DAX giống Power BI

Đường đi của dữ liệu:

```
visual.json ─► VisualQuerySpec ─► DAXQueryBuilder ─► văn bản DAX ─► DAXEngine.execute ─► QueryResult
                    ▲                                                             │
     FilterState (report/page/visual filter, slicer,                              ▼
     lọc chéo, drill, drillthrough)                                 DataViewMapper ─► DataView ─► renderer
```

**Chọn cách sinh văn bản DAX** (thay vì gọi thẳng API Swift của engine), vì 4 lý do:

1. **So khớp từng ký tự** với truy vấn PA. Đây là cách mạnh nhất để biết BI Pro làm giống Power BI, đúng quy tắc của dự án.
2. **Gỡ lỗi được:** có thể dán truy vấn của bất kỳ visual nào vào DAX Query View của BI Pro. Có thể làm thêm nút "Sao chép truy vấn" như Performance Analyzer.
3. Dùng lại engine đã khớp 30/30 golden, không phải viết đường thứ hai.
4. Chi phí parse không đáng kể (dưới 1 ms mỗi truy vấn), có thể cache plan theo văn bản.

Các hàm giảm dữ liệu (`TOPN 1001`, `SAMPLE`, `SAMPLEAXISWITHLOCALMINMAX`, cửa sổ 102×102 của matrix) được cài vào **engine**, không xử lý trong Swift. Như vậy DAX Query View cũng chạy được truy vấn copy từ Power BI.

### 2.2 Thành phần

| Thành phần | Vị trí | Vai trò |
|---|---|---|
| `VisualQuerySpec` | `Sources/BIPro/Visuals/Query/VisualQuerySpec.swift` | mô tả trung gian, tách khỏi JSON và khỏi DAX. Gồm: các trục nhóm (primary, secondary cho series hoặc cột matrix), mỗi trục có cột hoặc cấp hierarchy cùng cột sort-by kèm theo (ví dụ `age_group_order`); measure (có `ignore`); totals; sắp xếp; kiểu giảm dữ liệu (`.top(n)`, `.sample(n)`, `.binnedLine(…)`, `.window(102, 102)`) |
| `VisualQuerySpecReader` | `…/Query/VisualQuerySpecReader.swift` | đọc `queryState`, `sortDefinition`, `objects` (gom các measure dùng để tô màu, tooltip, measure định dạng động); chọn mức hierarchy đang `active`; tự thêm cột sort-by lấy từ `ModelMetadata.Column.sortByColumnID` |
| `DAXQueryBuilder` | `…/Query/DAXQueryBuilder.swift` | sinh văn bản theo đúng khuôn PA: `__DS0FilterTable…`, `__DS0Core`, `__DS0PrimaryWindowed`, `__DS0Secondary`, `__DS0BodyLimited`, `__ScopedCore…`, đặt tên cột như `Loan_Count2` và `v_…_FormatString`, tab và xuống dòng |
| `FilterTranslator` | `…/Interaction/FilterTranslator.swift` | `ReportFilter` (Categorical/Advanced/TopN), lựa chọn trên slicer, lọc chéo, drillthrough → biểu thức bảng lọc DAX, theo khuôn quan sát ở C1 |
| `FilterState`, `SelectionState` | `…/Interaction/*.swift` | trạng thái theo trang: lựa chọn của từng slicer, điểm đang chọn, mức drill, expand, bookmark đang áp dụng, visual bị ẩn |
| `VisualDataLoader` | `…/Query/VisualDataLoader.swift` | actor: chạy truy vấn ngoài main thread, giới hạn số truy vấn song song (bằng số nhân hiệu năng), cache theo (văn bản DAX), huỷ lượt cũ khi FilterState đổi, ưu tiên visual đang nằm trong màn hình |
| `DataView` | `…/Query/DataView.swift` | struct thuần, renderer chỉ đọc cái này: `.single`, `.categorical` (danh mục nhiều cấp, series, các cột giá trị, giá trị tô sáng, chuỗi định dạng mỗi ô, màu từ measure), `.matrix` (cây hàng, cây cột, ô, tổng), `.slicer` (giá trị phân cấp) |
| `DataViewMapper` | `…/Query/DataViewMapper.swift` | `QueryResult` (nhiều EVALUATE) → `DataView` (nối các bảng Secondary, BodyLimited, `ColumnIndex`) |
| `VisualFormat` | `…/Format/VisualFormat.swift` | đọc `objects` một lần thành struct có kiểu (nhãn, trục, legend, màu điểm dữ liệu, gradient, màu lấy từ measure) |
| Renderer | `…/Charts`, `…/Cards`, `…/Slicer`, `…/Matrix`, `…/Map` | SwiftUI + Swift Charts (macOS 15 có `SectorMark`); các phần Swift Charts không hỗ trợ (trục Y2 của combo, treemap, shape map) vẽ bằng `Canvas` |
| Ghép vào canvas | `Sources/BIPro/Report/ReportCanvas.swift` | `VisualContentView` gọi renderer thật. Placeholder hiện có (`DataPlaceholders.swift`) giữ làm khung chờ khi đang tải |

Nguyên tắc tách: renderer **không biết DAX**. Mỗi renderer chỉ nhận `DataView` cùng `VisualFormat`, nên worker có thể làm với dữ liệu mẫu mà không cần engine hay file Nhom6.

### 2.3 Engine (thêm, không đổi hợp đồng cũ)

- `SUMMARIZECOLUMNS` dùng được như hàm bảng ở mọi chỗ (VAR, đối số bảng). Hiện nó chỉ là query form. Giữ đường nhanh hiện có ở EVALUATE.
- `IGNORE(expr)`: cột vẫn được tính nhưng không dùng để quyết định dòng nào bị loại vì toàn BLANK.
- `ROLLUPADDISSUBTOTAL(cột…, "cờ")`, `ROLLUPGROUP(...)`: dòng tổng, cột cờ kiểu boolean.
- `KEEPFILTERS(<bảng>)` làm đối số bảng.
- Measure định dạng động: binder hiểu `'T'[_M FormatString]` là biểu thức `formatStringDefinition` của measure M, đánh giá trong cùng ngữ cảnh.
- `NATURALLEFTOUTERJOIN`, `SUBSTITUTEWITHINDEX`, `GROUPBY` + `CURRENTGROUP`, `SAMPLE`, `SAMPLEAXISWITHLOCALMINMAX`.
  - Với hai hàm sample: nếu số dòng ≤ ngưỡng thì trả đủ dòng. Điều này chắc chắn đúng với Nhom6, vì trục tháng chỉ có 72 dòng.
  - Thuật toán chia bin khi vượt ngưỡng ghi [SUY ĐOÁN]: dax.guide chỉ mô tả tham số, không mô tả thuật toán.
- `TOPN` nhiều cặp (khoá, chiều); `SUMMARIZE` trên biến bảng.

## 3. Quan sát cần làm trước khi code (buổi C1 của bạn)

Theo quy tắc "quan sát trước": các mục dưới đây được ghi vào `docs/phase-c-evidence/C1.md` trước khi giao việc cho phần liên quan. Đánh dấu ★ là việc phải có trước đợt 1.

| Mã | Làm gì trong Power BI Desktop | Lưu |
|---|---|---|
| O-C1 ★ | Performance Analyzer → Start → Refresh visuals ở D1, D2, D3 (trạng thái mặc định) → **Copy query** của **mọi** visual có dữ liệu (khoảng 60 cái; card thì copy 2 cái mỗi trang là đủ) | `observe-c1/<trang>-<tên visual>.dax` |
| O-C2 ★ | Với các truy vấn có matrix/ROLLUP, SUBSTITUTEWITHINDEX, SAMPLE, treemap, donut 3 cấp, shape map: dán vào DAX query view, chạy, Copy kết quả | `.tsv` cùng tên |
| O-C3 | Slicer D1: chọn Năm = 2016 (1 giá trị), rồi Ctrl+chọn thêm 2017 → copy query của 1 card và 1 chart | `slicer-*.dax` |
| O-C4 | Bấm 1 cột của bar D2 "Nhóm tuổi lúc vay" → copy query của donut, combo, line, card (để biết visual nào bị tô sáng, visual nào bị lọc); chụp màn hình cả trang | `xfilter-*.dax`, ảnh |
| O-C5 | Combo D2: bật drill mode → bấm cột 2016 → copy query; Drill up; "Expand all down one level" → copy query | `drill-*.dax` |
| O-C6 | Chuột phải 1 điểm có `branch_city` → Drillthrough → "Chi tiết chi nhánh" → copy query của Branch Title và của line | `drillthrough-*.dax`, ảnh |
| O-C7 | Rê chuột lên 1 cột (tooltip mặc định, có trường Tooltips) → chụp | ảnh |
| O-C8 | Mỗi trang D1–D3 ở trạng thái mặc định: chụp ảnh ở zoom 100% (Fit to page), dùng làm ảnh đối chiếu | `page-D1.png`… |
| O-C9 | Mở lại PA-D3-1, copy lại query, kiểm tra dấu `\` ở dòng 49 có thật hay không | ghi chú |
| O-C10 | View → Selection pane, Bookmarks pane ở D1: bấm 2 nút bookmark, chụp | ảnh |
| O-C11 | Format → Edit interactions ở D2: chọn bar → chụp các icon lọc/tô sáng/none trên các visual khác | ảnh |
| O-C12 | Matrix D1 "Vùng/Bang/Chi nhánh": bấm + mở 1 vùng → copy query | `matrix-expand.dax` |

Thời gian ước lượng: 60–75 phút. Mình sẽ làm `docs/phase-c-oracle/CHECKLIST-C1.md` từng bước (tên visual, vị trí, thứ tự bấm, tên file lưu), giống checklist buổi 3.

Song song, lead đọc tài liệu công khai về:
- tương tác mặc định;
- data reduction ("Data point limits & strategies" trên Microsoft Learn);
- `SAMPLEAXISWITHLOCALMINMAX`, `SUBSTITUTEWITHINDEX` trên dax.guide.

Ghi vào `docs/phase-c-research/notes.md`. Phần nào chưa có quan sát thì ghi rõ là [TÀI LIỆU] hoặc [SUY ĐOÁN].

## 4. Chia việc

### 4.1 So sánh cách chia (chấm 1–5)

| Cách | Mô tả | Song song | Xung đột file | Rủi ro ghép | Hợp quy tắc quan sát | Kết luận |
|---|---|---|---|---|---|---|
| A. Theo trang (D1/D2/D3) | mỗi worker một trang | 4 | 1 (cả ba đều sửa builder, mapper, renderer dùng chung) | 1 | 3 | loại |
| B. Theo loại visual từ đầu đến cuối | worker làm cả đọc spec, builder lẫn renderer cho từng loại | 4 | 2 (builder là một file chung) | 2 | 3 | loại |
| C. **Theo lớp, có hợp đồng trước** ✅ | C0 lead chốt `DataView`, `VisualQuerySpec`, `VisualFormat`; worker làm engine / nhóm renderer; lead giữ builder và ghép | 4 | 5 | 4 (renderer test bằng dữ liệu mẫu, builder test bằng PA) | 5 | **chọn** |
| D. Tuần tự | lead làm hết | 1 | 5 | 5 | 5 | dự phòng |

Cách C giống khuôn đã chạy ổn ở Phase B: hợp đồng ở đợt 0, rồi mỗi worker sở hữu một nhóm file riêng. Builder và mapper là phần cần hiểu sâu ngữ cảnh Power BI, nên lead làm; CLAUDE.md cũng không cho giao loại việc này.

### 4.2 Gói việc và file sở hữu

Mỗi file chỉ thuộc một gói. Bảng đầy đủ sẽ ghi ở `docs/phase-c-ownership.tsv` (đợt 0).

| Gói | Ai | File sở hữu | Tự kiểm |
|---|---|---|---|
| **C0 Hợp đồng** | lead | `Visuals/Query/{VisualQuerySpec,DataView}.swift`, `Visuals/Format/VisualFormat.swift` (khung), `Visuals/Fixtures/DataViewSamples.swift` (dữ liệu mẫu cho renderer), `docs/phase-c-ownership.tsv`, `docs/phase-c-evidence/C1.md` | `swift build` xanh |
| **E1 Engine hàm visual** | worker | `Functions/VisualFns.swift` (mới), `Query/SummarizeColumns.swift`, `Query/QueryExecutor.swift`, `Semantic/Binder.swift` (SUMMARIZECOLUMNS làm hàm bảng cần binder), `Runtime/Evaluator.swift` (CURRENTGROUP), `Functions/FilterFns.swift` (KEEPFILTERS bảng), `Functions/TableFns.swift` (TOPN nhiều khoá), `Functions/Registry.swift`, `Contracts.swift` (chỉ thêm), `Tests/DAXEngineTests/VIS/**` (mới) | test MiniBank cho từng hàm; 8 PA chạy được; golden PA ở test nặng |
| **E2 Định dạng động** | lead | `Semantic/Catalog.swift` (thêm measure ẩn `_<M> FormatString` từ `formatStringDefinition`, cùng bảng với M), `Tests/DAXEngineTests/VIS-FMT/**` | các cột `v_…_FormatString` của PA khớp |
| **E3 Hiệu năng engine** (đợt 2, sau khi E1 merge vì cùng `Evaluator.swift`) | lead | `Runtime/Evaluator.swift`, `Runtime/Cache.swift`, `Functions/Calculate.swift`, `Tests/DAXEngineTests/PERF/**` | 3 visual chậm (C1.md §1.5) dưới 1 s; golden Phase B vẫn 30/30 |
| **Q Builder + mapper + loader** | lead | `Visuals/Query/{VisualQuerySpecReader,DAXQueryBuilder,DataViewMapper,VisualDataLoader}.swift`, `Tests/BIProTests/VisualQuery/**` | builder sinh trùng văn bản PA (chuẩn hoá khoảng trắng); mapper từ golden PA ra DataView đúng |
| **R1 Biểu đồ trục XY** | worker | `Visuals/Charts/{CartesianChart,ComboChart,ChartAxis,ChartLegend,DataLabels,TrendLine}.swift`, `Tests/BIProTests/Charts/**` | các hàm thuần: chia vạch trục "đẹp", rút gọn số (K/M/bn), xếp cột cụm/chồng/100%, quy đổi trục Y2, hồi quy tuyến tính; ảnh PNG từ `ImageRenderer` cho từng mẫu |
| **R2 Card + slicer + matrix** | worker | `Visuals/Cards/CardVisual.swift`, `Visuals/Slicer/{DropdownSlicer,SlicerTree}.swift`, `Visuals/Matrix/{MatrixVisual,MatrixLayout,MatrixGradient}.swift`, `Tests/BIProTests/{Card,Slicer,Matrix}/**` | dựng cây hàng/cột và tổng; gradient FillRule; cây slicer có tìm kiếm và chọn nhiều; ảnh PNG |
| **R3 Donut + treemap + shape map + tooltip** | worker (đợt 2) | `Visuals/Charts/{DonutChart,Treemap}.swift`, `Visuals/Map/{TopoJSON,ShapeMap}.swift`, `Visuals/Tooltip/VisualTooltip.swift`, `Tests/BIProTests/{Donut,Treemap,Map}/**` | thuật toán squarify; giải mã TopoJSON (arc, quantize) ra path; phép chiếu Albers USA; ảnh PNG |
| **I Tương tác** | worker (đợt 2) | `Visuals/Interaction/{FilterState,SelectionState,FilterTranslator,InteractionRules}.swift`, `Tests/BIProTests/Interaction/**` | dịch filter/slicer/lựa chọn sang DAX theo khuôn O-C3/O-C4; quy tắc lọc hay tô sáng theo loại visual (O-C11) |
| **P Pane tương tác** | worker (đợt 3) | `Panes/ReportPanes.swift` (Filters pane sửa được, Selection pane ẩn/hiện, Bookmarks pane áp dụng), `Panes/FilterEditor.swift` (mới), `Tests/BIProTests/Panes/**` | áp dụng bookmark ra đúng tập visual ẩn; sửa Basic filter |
| **G Ghép + drill + drillthrough** | lead | `Report/ReportCanvas.swift`, `Report/ReportWorkspace.swift`, `Report/DataPlaceholders.swift`, `Visuals/Interaction/Drill.swift`, `DocumentState.swift`, `Workspace.swift` | chạy app trên Nhom6; checklist C-I |

### 4.3 Đợt

| Đợt | Worker (≤ 3) | Lead làm song song | Điều kiện vào đợt |
|---|---|---|---|
| **0** (1,5 ngày) | — | C0; dax-run thêm `--profile` (thời gian từng visual); lập `CHECKLIST-C1.md`; đọc tài liệu | — |
| **Buổi C1** (bạn) | — | — | có checklist |
| **1** (4–5 ngày) | E1 ‖ R1 ‖ R2 | E2, rồi Q (builder so với PA-*; sau buổi C1 so với observe-c1); đo từng measure chậm cho E3 (chỉ đo, chưa sửa Evaluator) | C0 đã commit, `git status` sạch |
| **2** (4–5 ngày) | R3 ‖ I | E3 (hiệu năng engine), G: ghép card, chart, slicer, matrix vào canvas với số thật | đợt 1 đã review và merge; có O-C3/C4/C11 |
| **Buổi C2** (bạn) | — | — | 3 trang có số; mình gửi ảnh BI Pro đặt cạnh ảnh Power BI |
| **3** (4–5 ngày) | P (một mình, hoặc cùng việc sửa từ buổi C2 nếu tách được file) | G: drill, drillthrough, bookmark trên canvas, tooltip, format theo measure, gradient; sửa lỗi buổi C2 | đợt 2 đã merge |
| **Buổi C3** (bạn) | — | — | checklist C-I đầy đủ |
| **4** (2–3 ngày) | — | sửa lỗi buổi C3, hiệu năng, cập nhật tài liệu | — |

Tổng: khoảng 4,5–5 tuần, khớp ước lượng 5 tuần trong `BIPRO_BUILD_PLAN.md`.

Mỗi đợt giao việc làm đúng quy trình CLAUDE.md:
- trước khi giao: `git status` sạch;
- mỗi worker một worktree;
- chờ nền, chờ tất cả worker xong rồi mới review;
- review: `git diff --stat` (chỉ file được giao), đọc diff, build/test;
- chưa đạt thì giao lại **một lần** kèm phản hồi cụ thể; vẫn chưa đạt thì báo bạn;
- không tự merge, không tự xoá worktree.

Brief của mỗi worker có: mục tiêu, danh sách file, câu "không sửa gì ngoài danh sách", hợp đồng (`DataView`…), dữ liệu mẫu, lệnh build/test, tiêu chí xong, danh sách lệnh shell được phép, và các lỗi hay gặp lần trước (`@objc`, `isReleasedWhenClosed`, popover sáng, không viết cứng kết quả để test qua).

## 5. Kiểm thử

### 5.1 Golden truy vấn (tự động)

- **Văn bản:** với mỗi visual có file `.dax` từ PA (8 cái hiện có, khoảng 60 cái sau buổi C1), `DAXQueryBuilder(spec từ visual.json)` phải ra văn bản trùng file PA. Trước khi so: bỏ dòng `// DAX Query`, gộp khoảng trắng.
  - Fixture: `visual.json` của các visual đó (trích từ file của bạn) đặt ở `Tests/BIProTests/Fixtures/phaseC/`. Test này chạy nhanh, không cần model.
- **Kết quả:** engine chạy file PA trên Nhom6 phải khớp `.tsv` của Power BI, theo quy tắc so khớp §5.3 của Phase B. Đây là test nặng, `BIPRO_HEAVY=1`, filter `VIS`.

### 5.2 Renderer (tự động)

- Kiểm các hàm bố cục thuần: chia vạch trục, squarify, góc của donut, cây matrix, xếp nhãn.
- Kiểm định dạng số: dùng `FormatString` của engine, cùng quy tắc rút gọn "Auto" (K/M/bn) của trục và nhãn dữ liệu. Quy tắc lấy từ ảnh O-C8.
- `ImageRenderer` xuất PNG mỗi mẫu ra `build/c-out/visuals/`; lead xem bằng mắt khi review.

### 5.3 Đặt cạnh ảnh Power BI

BI Pro xuất ảnh từng trang (1920×1080) ra `build/c-out/pages/`. Mình dựng một trang HTML đặt ảnh BI Pro cạnh ảnh O-C8 của bạn. Tiêu chí:
- bố cục lệch dưới 4 px;
- số giống hệt;
- màu đúng theme.

### 5.4 Checklist tương tác C-I (bạn làm ở buổi C2/C3, đồng thời so với Power BI)

1. Slicer dropdown: mở, tìm kiếm, chọn một giá trị, Ctrl để chọn nhiều, mở hierarchy (Năm › Quý › Tháng), "Select all", xoá lựa chọn. Card và chart cập nhật đúng số.
2. Filters pane: thấy 2 bộ lọc report và bộ lọc visual của matrix; sửa Basic filter thì visual cập nhật.
3. Bấm một cột: visual khác tô sáng hoặc lọc giống O-C4/O-C11. Ctrl+bấm chọn nhiều; bấm vào chỗ trống thì bỏ chọn.
4. Drill: drill mode, drill down/up, "Show next level", "Expand all down one level"; matrix +/−.
5. Drillthrough sang "Chi tiết chi nhánh": tiêu đề Branch Title đúng chi nhánh; nút quay lại.
6. Tooltip mặc định: có các trường Tooltips, định dạng số đúng.
7. Selection pane: ẩn/hiện visual.
8. Bookmarks: 2 nút "Giờ × Thứ" / "Tháng trong năm" đổi được matrix ↔ line; Bookmarks pane cũng áp dụng được.
9. Màu theo measure: chữ "Δ Label" xanh/đỏ đúng; cột NPL theo `NPL Group Color`; gradient trong matrix.
10. Hiệu năng (§0.4), đo bằng `--profile` và log của app.

## 6. Rủi ro

| Rủi ro | Mức | Cách xử lý |
|---|---|---|
| **Hiệu năng measure:** đã đo ở đợt 0 (C1.md §1.5). D1 36,6 s và D3 12,6 s, do 3 visual tính lại cùng một biểu thức con ở mọi ô | cao | Gói E3 ở đợt 2: cache biểu thức con không phụ thuộc ô. Gom card cùng ngữ cảnh lọc vào một SUMMARIZECOLUMNS, như Power BI vẫn gửi mỗi card một query; việc gom chỉ là tối ưu riêng của BI Pro, golden văn bản vẫn so theo từng visual. Chạy song song theo số nhân; cache kết quả theo (văn bản DAX); đo và tối ưu 10 measure chậm nhất (cache biến bảng trong CALCULATE, memo các ngữ cảnh lọc trùng). Ngưỡng ở §0 sẽ đo lại sau đợt 2 |
| Swift Charts không có trục Y thứ hai | trung bình | Combo vẽ 2 lớp: cột bằng Swift Charts, đường quy đổi theo thang Y2 rồi vẽ chung khung, trục Y2 tự vẽ. Có hàm thuần để test |
| Thuật toán dự báo của Power BI không công khai chi tiết | thấp | Phase C chỉ vẽ trend tuyến tính đúng. Dự báo dùng Holt-Winters cộng tính, có ghi chú [SUY ĐOÁN] khi rê chuột; có thể bật/tắt. Để khớp hẳn thì đưa sang Phase G |
| Khuôn truy vấn của lọc chéo/tô sáng chưa quan sát | trung bình | Đợt 2 mới làm tương tác, sau buổi C1. Nếu buổi C1 trễ thì đợt 1 vẫn chạy (renderer, engine không phụ thuộc) |
| Matrix (cửa sổ 102, `SUBSTITUTEWITHINDEX`, expand) phức tạp | trung bình | Engine theo PA-D1-2; layout tách thành `MatrixLayout` thuần. Ưu tiên 2 matrix của Nhom6 |
| Shape map: TopoJSON + phép chiếu | thấp | Chỉ cần `usa.states.topo.json`; Albers USA có công thức công khai |
| Lỗi "SIGBUS" khi đổi struct dùng chung | thấp | Đã biết cách: xoá `.build` (đã ghi trong CLAUDE.md) |

## 7. Ranh giới

- Không decompile Power BI Desktop hay Analysis Services; chỉ dùng file của bạn, tài liệu công khai và những gì bạn tự làm trong VM.
- Không thêm thư viện ngoài. Swift Charts, SwiftUI, AppKit là API của hệ thống.
- Worker không commit, push, cài package hay tải từ mạng.
- File gốc trong `~/Downloads` chỉ đọc. File ra nằm trong `build/c-out/`, ảnh chụp ở `docs/phase-c-evidence/`.
- Hàm hay quy tắc nào chưa có quan sát hoặc tài liệu thì ghi [SUY ĐOÁN] trong code và trong `C1.md`.

## 8. Cần bạn

1. **Duyệt plan này.** Nếu duyệt, mình commit plan rồi làm đợt 0 ngay.
2. **Buổi C1** (khoảng 60–75 phút trong VM), theo `CHECKLIST-C1.md` mình sẽ gửi sau đợt 0. Phần ★ (O-C1, O-C2) cần có trước khi lead bắt đầu Q; các phần khác cần trước đợt 2.
3. Khi tiện, xử lý hai việc còn lại của Phase B:
   - copy văn bản "Define new measure" / "Define all measures in this model";
   - cho phép xoá worktree `ui4-editor`.
