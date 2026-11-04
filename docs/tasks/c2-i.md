Bạn làm việc trong repo Swift "BI Pro", một ứng dụng macOS giống Power BI Desktop. Bạn đang ở một git worktree riêng, tách từ `main`.

## Mục tiêu (gói I, Phase C đợt 2)

Viết phần **logic thuần** của tương tác trên trang report: biến lựa chọn của người dùng (slicer, bấm điểm, drillthrough, drill down) thành các bộ lọc DAX theo đúng khuôn Power BI đã quan sát, và quyết định visual nào bị lọc, tô sáng hay không bị ảnh hưởng. Không có giao diện, không gọi engine, không đọc file; mọi thứ là struct và hàm thuần, kiểm bằng test.

Lead (gói G) sẽ nối kết quả vào `DAXQueryBuilder` và canvas sau khi bạn xong. Hãy làm cho API dễ gọi: một hàm `assemble` nhận trạng thái và trả về danh sách bộ lọc cho một visual.

Hợp đồng đọc trước:
- `Sources/BIPro/Visuals/Query/VisualQuerySpec.swift`: `QueryColumn`, `QueryFilter` (bạn sinh ra `tableExpression`).
- `Sources/BIPro/Visuals/Interaction/InteractionTypes.swift`: `DataPointID`, `SlicerSelection`, `DrillRequest`.
- `Sources/BIPro/Visuals/Query/VisualQuerySpecReader.swift`: hàm `translate(_:)` ở cuối file cho thấy bộ lọc tĩnh đang được dịch thế nào (`FILTER(KEEPFILTERS(VALUES(cột)), vị từ)`), và `literal(_:)`.
- `Sources/BIPro/Visuals/Slicer/SlicerTree.swift` (R2, đã merge): cách chọn nhiều và chọn cấp cha/con trong slicer.
- `Sources/DAXEngine/Contracts.swift`: kiểu `Value`. `dateTime` là số ngày OLE, ngày 0 = 1899-12-30.

## Quan sát Power BI để làm theo

Đọc `docs/phase-c-evidence/C1.md` §2.2 (bộ lọc) và §2.6 (Edit interactions mặc định). Truy vấn thật nằm ở `docs/phase-c-evidence/observe-c1/interact/`:

| File | Cho thấy |
|---|---|
| `slicer1-card.dax`, `slicer2-card.dax` | Slicer chọn 1 giá trị, rồi 2 giá trị, trên cột đã có bộ lọc report: gộp vào **cùng một** bảng lọc, vị từ slicer đứng trước |
| `slicer3-quy.dax` | Slicer phân cấp chọn một phần (2016 › Q1): `SUMMARIZE(VALUES(bảng), cột cấp 0, cột cấp 1)`, vị từ report đứng **trước**, cú pháp tuple `(a, b) IN {(x, y)}` |
| `xf-card.dax`, `dt-card.dax`, `dt-line.dax`, `dt-subtitle.dax` | Lọc chéo và drillthrough: `TREATAS({giá trị}, 'Bảng'[cột])` là bảng lọc **đầu tiên**, rồi các bộ lọc report |
| `xf-combo.dax`, `xf-combo2.dax`, `xf-donut.dax`, `xf-100pct.dax` | Tô sáng chéo: `VAR __H0FilterTable = TREATAS(…)` tách riêng, **không** nằm trong danh sách `__DS0FilterTable`; các bộ lọc report vẫn đánh số `__DS0FilterTable`, `__DS0FilterTable2` |
| `drill-down-2016.dax` | Drill down một điểm: thêm `year IN {2016}` gộp vào bảng lọc cột `year` đã có của report, giống slicer |

Hai bộ lọc report trong các truy vấn trên đều là: `NOT('Dim_Date'[year] IN {9999})` và `NOT('Dim_Client'[client_region] IN {"Unknown"})` (test dùng hai vị từ này làm bộ lọc tĩnh).

## File được sửa hoặc tạo

- Sources/BIPro/Visuals/Interaction/FilterState.swift
- Sources/BIPro/Visuals/Interaction/SelectionState.swift
- Sources/BIPro/Visuals/Interaction/FilterTranslator.swift
- Sources/BIPro/Visuals/Interaction/InteractionRules.swift
- Tests/BIProTests/Interaction/** (mới)
- docs/tasks/c2-i-report.md (báo cáo cuối)

Mọi file khác giữ nguyên, gồm `InteractionTypes.swift`, `Drill.swift` (của lead), `Sources/BIPro/Visuals/Query/**`, `Sources/BIPro/Report/**`, `Sources/DAXEngine/**`, `Package.swift`. Hợp đồng thiếu gì thì ghi vào báo cáo cuối.

Một worker khác (gói R3) đang sửa `Visuals/{Charts/DonutChart,Charts/Treemap,Map,Tooltip}` song song.

## API công khai (giữ đúng tên)

```swift
// FilterTranslator.swift
enum FilterScope: Hashable, Sendable { case visual, page, report }

/// Điều kiện tĩnh của report/page/visual trên MỘT cột, đã dịch sang vị từ DAX.
struct StaticFilter: Hashable, Sendable { var column: QueryColumn; var predicate: String; var scope: FilterScope }

struct InteractionTarget: Hashable, Sendable { var visualID: String; var visualType: String }

struct AssembledFilters: Hashable, Sendable {
    var filters: [QueryFilter]      // theo thứ tự __DS0FilterTable, __DS0FilterTable2, …
    var highlight: QueryFilter?     // __H0FilterTable; nil khi không tô sáng
}

enum FilterTranslator {
    static func literal(_ value: Value) -> String
    static func assemble(for target: InteractionTarget, staticFilters: [StaticFilter], state: FilterState) -> AssembledFilters
}

// FilterState.swift
struct SlicerState: Hashable, Sendable {
    var columns: [QueryColumn]          // một cột cho mỗi cấp của slicer (Năm › Quý › Tháng)
    var selection: SlicerSelection
}
struct ColumnValues: Hashable, Sendable { var column: QueryColumn; var values: [Value] }

struct FilterState: Hashable, Sendable {
    var slicers: [String: SlicerState]          // khoá = visualID
    var slicerOrder: [String]                   // thứ tự slicer trên trang; lead điền theo thứ tự visual
    var selection = SelectionState()            // lựa chọn điểm (lọc chéo / tô sáng)
    var drillthrough: [ColumnValues] = []       // tham số drillthrough đã có giá trị
    var drillFilters: [String: [ColumnValues]] = [:]   // visualID → bộ lọc do drill down sinh ra
    var overrides: [InteractionOverride] = []   // Edit interactions của người dùng
    mutating func setSlicer(visualID: String, columns: [QueryColumn], selection: SlicerSelection)
}

// SelectionState.swift
struct CrossColumn: Hashable, Sendable { var queryRef: String; var column: QueryColumn }   // queryRef khớp khoá của DataPointID

struct SelectionState: Hashable, Sendable {
    var sourceVisualID: String? { get }
    var sourceVisualType: String? { get }
    var points: Set<DataPointID> { get }
    var columns: [CrossColumn] { get }          // cấp danh mục rồi series, đúng thứ tự
    mutating func select(_ point: DataPointID?, additive: Bool, from source: InteractionTarget, columns: [CrossColumn])
    mutating func clear()
    /// Điểm đang chọn của CHÍNH visual này (đưa vào `VisualRenderContext.selection`); rỗng nếu visual khác là nguồn.
    func points(forVisual visualID: String) -> Set<DataPointID>
}

// InteractionRules.swift
enum InteractionEffect: Hashable, Sendable { case filter, highlight, none }
struct InteractionOverride: Hashable, Sendable { var sourceID: String; var targetID: String; var effect: InteractionEffect }

enum InteractionRules {
    static func canSelect(visualType: String) -> Bool                 // có phát ra lựa chọn không
    static func supportsHighlight(visualType: String) -> Bool
    static func effect(of source: InteractionTarget, on target: InteractionTarget, overrides: [InteractionOverride] = []) -> InteractionEffect
}
```

## Quy tắc (mỗi quy tắc có test)

**`literal(_:)`**: `.integer(2016)` → `2016`; `.string("a\"b")` → `"a""b"`; `.boolean` → `TRUE`/`FALSE`; `.blank` → `BLANK()`; `.double` → dạng ngắn nhất đọc lại được, không có `e` với số thường gặp; `.currency(n)` → số thập phân `n / 10000`; `.dateTime(d)` (ngày OLE, gốc 1899-12-30, UTC) → `DATE(y, m, d)` khi không có phần giờ, ngược lại `DATETIME(y, m, d, h, mi, s)`.

**Sắp xếp giá trị trong tập `IN {…}` và TREATAS**: tăng dần (số theo số, chuỗi theo thứ tự từ điển, BLANK đứng đầu, số đứng trước chuỗi). [SUY ĐOÁN] Power BI có thể giữ thứ tự chọn; hai file mẫu đều tăng dần nên chưa phân biệt được.

**Slicer, mọi đường dẫn chọn dài 1** (chọn theo cột cấp 0): bảng lọc `FILTER(KEEPFILTERS(VALUES(c0)), c0 IN {v…})`.
- Cột `c0` đã có bộ lọc tĩnh: **gộp vào cùng bảng**, vị từ slicer đứng trước: `AND(c0 IN {…}, <vị từ tĩnh>)`; bảng giữ đúng vị trí của bộ lọc tĩnh (`slicer1-card.dax`, `slicer2-card.dax`).
- Cột chưa có bộ lọc tĩnh: bảng riêng thuộc nhóm "tương tác" (xem thứ tự bên dưới).

**Slicer phân cấp có đường dẫn dài ≥ 2**: `FILTER(KEEPFILTERS(SUMMARIZE(VALUES('Bảng'), c0, c1, …)), vị từ)`; cột dùng là `columns[0 ..< độ dài lớn nhất]`. Vị từ nhóm theo độ dài đường dẫn: độ dài n cho `(c0, …, c(n-1)) IN {(x, …), …}` (n = 1 thì `c0 IN {…}`); nhiều nhóm nối bằng `OR(nhóm1, nhóm2)`. Mọi bộ lọc tĩnh trên các cột đó được gộp vào cùng bảng và đứng **trước**: `AND(<vị từ tĩnh>, <vị từ slicer>)` (`slicer3-quy.dax`). Nhiều vị từ tĩnh thì lồng `AND` hai ngôi. Các cột khác bảng với `c0`: bỏ cột thừa và ghi chú trong báo cáo.

**Slicer không chọn gì** (selection rỗng): không sinh bộ lọc.

**Đích là slicer** chỉ nhận bộ lọc tĩnh (report/page/visual): không nhận lựa chọn của slicer khác, lọc chéo hay drillthrough, và đương nhiên không tự lọc chính nó (`InteractionRules` trả `.none` cho đích là slicer). [SUY ĐOÁN] kiểm ở buổi C2.

**Lọc chéo** (nguồn khác đích, `effect == .filter`): một bảng `TREATAS({v…}, 'Bảng'[cột])` với cột lấy từ **visual nguồn** (`xf-card.dax`). Nhiều điểm cùng một cột: `{a, b}`. Điểm có nhiều cột (cấp danh mục nhiều tầng, hoặc có series): `TREATAS({(a, 1), (b, 2)}, cột1, cột2)` theo thứ tự `columns`. [SUY ĐOÁN] dạng nhiều cột chưa quan sát.

**Tô sáng chéo** (`effect == .highlight`): cùng biểu thức TREATAS như lọc chéo, nhưng đặt vào `AssembledFilters.highlight`; `filters` khi đó **không** chứa nó (`xf-combo.dax`, `xf-donut.dax`).

**Drillthrough**: với mỗi `ColumnValues` có giá trị, một bảng `TREATAS({v…}, 'Bảng'[cột])` (`dt-card.dax`); áp cho mọi visual trên trang, kể cả visual nguồn của lựa chọn.

**Drill down** (`drillFilters[visualID]`): chỉ áp lên visual có `visualID` đó; gộp vào bảng lọc của cột như slicer cấp 0: `AND(year IN {2016}, <vị từ tĩnh>)` (`drill-down-2016.dax`).

**Thứ tự `filters`** [QUAN SÁT: bộ lọc visual và tương tác đứng trước bộ lọc report (`C1.md` §2.2); thứ tự giữa các nhóm còn lại là SUY ĐOÁN]:
1. bộ lọc tĩnh cấp `visual` (kể cả bảng đã gộp slicer/drill),
2. nhóm tương tác: drillthrough, rồi lọc chéo, rồi các slicer chưa gộp (theo `slicerOrder`),
3. bộ lọc tĩnh cấp `page`,
4. bộ lọc tĩnh cấp `report`.
Trong mỗi nhóm giữ nguyên thứ tự đầu vào.

**`SelectionState.select`** (nhấn thường, `additive == false`):
- `point == nil` (bấm chỗ trống) → xoá lựa chọn.
- Điểm chưa được chọn → lựa chọn mới chỉ gồm điểm này, nguồn là visual này (thay thế mọi lựa chọn trước, kể cả của visual khác).
- Điểm đang là điểm chọn duy nhất của chính visual này → bỏ chọn.
- Điểm đang được chọn cùng nhiều điểm khác → chỉ giữ điểm này. [SUY ĐOÁN]

Nhấn kèm Ctrl/⌘ (`additive == true`): cùng visual nguồn thì bật/tắt điểm đó trong tập chọn (tập rỗng thì xoá nguồn); khác visual nguồn thì thay thế như nhấn thường.

**`InteractionRules`** (hành vi mặc định; Nhom6 không có `visualInteractions`). `visualType` theo tên PBIR:
- Có thể phát lựa chọn (`canSelect`): `clusteredBarChart`, `clusteredColumnChart`, `stackedBarChart`, `stackedColumnChart`, `hundredPercentStackedColumnChart`, `lineChart`, `areaChart`, `lineClusteredColumnComboChart`, `lineStackedColumnComboChart`, `donutChart`, `pieChart`, `treemap`, `shapeMap`, `filledMap`, `pivotTable`, `tableEx`. Còn lại (card, slicer, textbox, actionButton, image, shape…) là `false`.
- Đích **tô sáng** (`supportsHighlight`): hai combo, `donutChart`, `pieChart`, `treemap`, và các bar/column/stacked/100% ở trên. [QUAN SÁT: combo, donut, cột 100% (`interactions-D2.png`, `xf-*.dax`); phần còn lại SUY ĐOÁN.]
- Đích **lọc**: `card`, `multiRowCard`, `shapeMap`, `filledMap`, `lineChart`, `areaChart`, `pivotTable`, `tableEx`. [QUAN SÁT: card, shape map (`xf-card.dax`, `dt-card.dax`); phần còn lại SUY ĐOÁN.]
- Đích `.none`: `slicer`, `textbox`, `actionButton`, `image`, `shape`, `basicShape`, và mọi `visualType` lạ.
- Nguồn và đích cùng `visualID` → `.none`. Nguồn không `canSelect` → `.none`.
- `overrides`: khớp theo `sourceID`/`targetID`. Ghi đè `.highlight` lên đích không `supportsHighlight` thì thành `.filter`; `.filter` và `.none` luôn được tôn trọng.

Mọi chỗ [SUY ĐOÁN] ghi bằng comment `// [SUY ĐOÁN]` cạnh code, để lead dễ tìm khi đối chiếu buổi C2.

## Test bắt buộc (`Tests/BIProTests/Interaction/`)

Dùng `import Testing`, `@testable import BIPro`. Không viết cứng kết quả để test qua: đọc văn bản mong đợi từ chính các file `.dax` ở trên (nạp qua `#filePath` đi lên gốc repo tới `docs/phase-c-evidence/observe-c1/interact/`; bỏ `\r`).

**Golden từ truy vấn Power BI** (mỗi file một test; đọc `VAR __DS0FilterTable…`/`__H0FilterTable` từ file, so bằng `DAXQueryBuilder.normalized(_:)` có sẵn):
1. `slicer1-card`: slicer năm `[[2016]]` + 2 bộ lọc report → `filters[0]`, `filters[1]` đúng văn bản.
2. `slicer2-card`: slicer năm `[[2016],[2017]]`.
3. `slicer3-quy`: slicer Năm › Quý với `[[2016, "Q1"]]`, cột `Dim_Date[year]`, `Dim_Date[quarter_name]`.
4. `xf-card`: nguồn `clusteredBarChart` chọn điểm `Fact_Loan.age_group_at_loan = "35-49"`, đích `card` → `[TREATAS, year, region]`, `highlight == nil`.
5. `xf-combo`, `xf-combo2`, `xf-100pct`, `xf-donut`: đích tương ứng (`lineClusteredColumnComboChart`, `hundredPercentStackedColumnChart`, `donutChart`) → `filters == [year, region]` và `highlight` đúng văn bản `__H0FilterTable`.
6. `dt-card`, `dt-line`, `dt-subtitle`: drillthrough New Mexico trên `Dim_District[state_name]`.
7. `drill-down-2016`: `drillFilters` cho đúng visual; visual khác không nhận.

**Hành vi (dữ liệu tự dựng):**
8. `literal`: ít nhất 8 ca (số nguyên, chuỗi có dấu nháy, bool, blank, double, currency, ngày không giờ, ngày có giờ).
9. Sắp xếp giá trị: tập hỗn hợp số/chuỗi/blank cho ra thứ tự đúng.
10. Slicer: selection rỗng → không có bảng lọc; cột chưa có bộ lọc tĩnh → bảng thuộc nhóm tương tác và nằm sau bộ lọc visual, trước bộ lọc page/report; hai slicer trên hai cột khác nhau → thứ tự theo `slicerOrder`; slicer không tự lọc chính nó.
11. Slicer phân cấp: đường dẫn hỗn hợp độ dài 1 và 2 cho `OR(…)`; một cột bị lọc tĩnh thì gộp, đứng trước.
12. Nhiều điểm lọc chéo cùng cột → `{a, b}`; nhiều cột → tuple; nguồn không phải là đích.
13. Thứ tự `filters` đủ bốn nhóm (visual, tương tác, page, report) trong một ca.
14. `SelectionState`: mọi nhánh của quy tắc `select` ở trên (bấm trống, chọn mới, bỏ chọn điểm duy nhất, chọn lại giữa nhiều điểm, Ctrl thêm/bớt, Ctrl từ visual khác, tập rỗng xoá nguồn); `points(forVisual:)` rỗng cho visual không phải nguồn.
15. `InteractionRules.effect`: bảng đầy đủ nguồn × đích cho các `visualType` của Nhom6 (`clusteredBarChart`, `clusteredColumnChart`, `stackedColumnChart`, `hundredPercentStackedColumnChart`, `lineChart`, `lineClusteredColumnComboChart`, `lineStackedColumnComboChart`, `donutChart`, `treemap`, `shapeMap`, `card`, `slicer`, `pivotTable`, `textbox`); ghi đè; tự lọc bản thân → `.none`.
16. `assemble` là hàm thuần: gọi hai lần với cùng đầu vào cho cùng kết quả, `FilterState` không bị đổi.

## Lệnh build/test

```
swift build --scratch-path .build-wI
swift test --scratch-path .build-wI
```
Cả hai xanh trước khi bàn giao; `swift test` chạy toàn bộ test của dự án, không chỉ test mới. Test nào đã có sẵn thì giữ nguyên.

## Tiêu chí xong

- Hai lệnh xanh; 16 nhóm test trên đều có và qua; 7 nhóm golden đọc văn bản từ file Power BI.
- `git status` chỉ có các file trong danh sách được sửa.
- `docs/tasks/c2-i-report.md` có: file đã sửa (mỗi file một dòng), dòng kết quả cuối của hai lệnh, danh sách mọi chỗ đánh dấu [SUY ĐOÁN], điều chưa làm hoặc hợp đồng còn thiếu (ví dụ cần thêm gì ở `VisualQuerySpec` để builder nhận `highlight`).
- Chưa đạt thì tự sửa tiếp; không sửa được thì ghi rõ lý do trong báo cáo thay vì bàn giao như đã xong.

## Lệnh shell được phép (chỉ những lệnh này)

swift build, swift test, git status/diff/log/show/grep, cmp, ls, cat, grep, rg, head, tail, wc, pwd, find, sed -n, sort, uniq, echo, file.

Một lệnh ngoài danh sách sẽ bị từ chối và dừng cả phiên. Đọc và sửa file bằng công cụ đọc/sửa file của bạn. Mỗi lệnh chạy riêng lẻ từ thư mục gốc của worktree (không ghép bằng `&&`, `;`, `|`; không `cd`). Tìm trong code bằng `grep -rn` hoặc `rg`.

Worker không commit, push, cài package hay tải từ mạng, và không đọc hay ghi gì trong `~/Downloads`.
