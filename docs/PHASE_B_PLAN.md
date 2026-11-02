# Phase B: DAX engine + DAX Query View — kế hoạch multi-agent (v2)

> **Nguồn:** 3 ghi chú nghiên cứu ở `docs/phase-b-research/` (`scope.md`, `architecture.md`, `oracle-ui.md`), làm ngày 2026-10-31. Chỉ dùng file `.pbix` của bạn, code hiện có và tài liệu công khai (Microsoft Learn, dax.guide, SQLBI). Không decompile Power BI.
>
> **Sửa đổi:** v2 sửa theo một vòng phản biện (19 điểm, 6 mức cao). Mình đã tự kiểm lại các điểm quyết định. Xem §9.
>
> **Test trong Power BI Desktop (VM Windows 11) do bạn tự làm tay.** Mình chuẩn bị file `.dax` và checklist. Bạn chạy, Copy kết quả rồi lưu thành `.tsv`.

## Tiếp tục từ đây (cập nhật 2026-11-02, sau UI2/UI3)

**Engine:** đạt tiêu chí §0. **30/30 golden khớp Power BI** (G0–G6, T1–T5), sau 3 buổi test tay.
- Hiệu năng sau tối ưu lan truyền (chỉ xét bảng tổ tiên của bảng đích trên đồ thị quan hệ):
  - G6f2: 117 s → 8,8 s;
  - 119 measure Nhom6: 21 s → 10,6 s;
  - test nặng: 130 s → 23,5 s.
- `validate()` kiểm cả lỗi tên/bind mà không đánh giá, để làm gạch chân lỗi. Không báo nhầm trên 30 golden.

**DAX Query View:**
- UI1 (chạy, huỷ, lưới, copy) xong.
- UI2/UI3 đã merge vào `main`:
  - thanh trạng thái O6;
  - tooltip measure O14;
  - thanh "Kết quả" ba trạng thái, kéo đổi chiều cao được;
  - lọc/sắp xếp trên lưới theo O13, mở bằng icon;
  - quick query O8, chạy luôn khi chọn;
  - ô Dữ liệu có tab Bảng/Mô hình;
  - menu chuột phải kiểu Power BI, menu con mở sang trái.
- Đang làm (worker agy, worktree `ui4-editor`): gạch chân lỗi, tự hoàn thành, đổi tên tab.

**Còn lại của Phase B:**
1. Review và merge `ui4-editor`.
2. Người dùng, khi tiện mở VM: copy văn bản Power BI sinh ra cho "Define new measure" và "Define all measures in this model". Hiện hai lệnh này đang làm theo [SUY ĐOÁN].

**Sau Phase B:** Phase C (truy vấn visual). Đặc tả là 8 truy vấn Performance Analyzer trong `docs/phase-b-evidence/observe2/PA-*`. Danh sách hàm còn thiếu có trong BUOI2.md.

**Cách làm việc:** git `main`, remote `github.com/bacpew2108/PowerBINative` (private).
- Theo CLAUDE.md, việc lớn được giao cho agy qua Orca: mỗi việc một worktree, tối đa 2 worker.
- Lệnh agy: `agy -p "$(cat brief)" --mode accept-edits --settings <allow-list>`. Danh sách lệnh được phép nằm trong scratchpad `briefs/agy-settings.json`.
- agy chạy headless nên một lệnh bị từ chối là dừng cả phiên. Phải ghi danh sách lệnh được phép vào brief.

## 0. Mục tiêu và tiêu chí xong

1. **119 measure** mà report Nhom6 dùng (95 trực tiếp, 24 phụ thuộc) phải khớp Power BI Desktop ở mọi nhóm golden **G0, G1, G2, G3, G5, G6** có chứa measure đó (§5.2). So khớp theo quy tắc §5.3.
   - G4 (quan hệ inactive) và PA (truy vấn của visual) chỉ để tham khảo, không chặn phase. PA là đặc tả cho Phase C.
2. **DAX Query View** chạy được truy vấn thật: Chạy và Huỷ, lưới kết quả, lỗi có vị trí (dòng, cột), nhiều tab.
3. **Hiệu năng:** đo nhưng không chặn phase. Có hai số đo:
   - `SUMMARIZECOLUMNS(Dim_Date[year], …119 measure)`;
   - `Avg_Account_Balance` (ca nặng nhất trong 119).

   Ngưỡng sẽ chốt sau lần bench đầu ở đợt 4. Mục tiêu "trang dưới 150 ms" thuộc Phase C, vì cần truy vấn visual.

## 1. Phạm vi thực tế (đo trên file của bạn)

| Mục | Số liệu | Hệ quả |
|---|---|---|
| Measure cần khớp | 119/168 (49 không dùng). 50 measure trả về **chuỗi** (nhãn, màu, SVG). 28 chỉ dùng cho định dạng có điều kiện | Engine phải đúng cả chuỗi, `FORMAT`, `SWITCH`, không chỉ số |
| Hàm | **43 hàm** trong 119 (kế hoạch cũ ghi "khoảng 40"), cộng khoảng 6 cấu trúc truy vấn. Toàn bộ DAX của Nhom6 dùng 49 hàm; tính cả Nhóm 2/3 khoảng 56 | Ngoài 119 cần thêm `RANKX`, `ALL`, `USERELATIONSHIP`. Nhóm 2/3 cần thêm `DATEADD`, `QUARTER`, `ALLEXCEPT`, `FLOOR`, `CALENDAR` |
| Hàm phổ biến | `IF` 69 measure, `ISBLANK` 67, `CALCULATE` 47, `DATE` 35, `DIVIDE` 30, `VALUES` 27, `FILTER` 22, `REMOVEFILTERS` 21, `FORMAT` 20. Có 69 measure dùng `VAR`. `COUNT` có trong 2 measure (`Peak Hour Font Color`, `Peak Hour Top10 Icon`) | |
| Họ lớn nhất | **Họ Δ: 17 × 3 = 51/119** (`X Δ`, `X Δ Label`, `X Δ Color`), cùng khuôn `SAMEPERIODLASTYEAR(curDates)` + `REMOVEFILTERS(Dim_Date)`. Họ D4: 8 measure `TREATAS(SUMMARIZE…)` | Làm đúng một khuôn là qua gần nửa mốc |
| Độ khó hiệu dụng (tính cả measure phụ thuộc) | T0 = 15, T1 = 1, T2 = 5, **T3 = 39** (filter context nâng cao), **T4 = 54** (time intelligence), T5 = 5 | Không làm đúng time intelligence thì chỉ được khoảng 60/119. Đây là **cách xếp tầng duy nhất** dùng trong kế hoạch (của `scope.md`) |
| Cột tính toán | 7 cột, **đều đã có dữ liệu lưu sẵn** trong VertiPaq | Không phải tính lại để đọc. Dùng làm oracle O-CC |
| Mô hình | 14 quan hệ M:1 **một chiều**. 1 inactive (`sent_date_key`, chỉ được dùng ngoài 119). `Dim_Date` đã Mark as date table (`full_date`). 4 role RLS. 19 dynamic format string | Lọc hai chiều chỉ cần cho Nhóm 2/3 |
| Filter cấp report | `client_region ≠ 'Unknown'` loại **1 dòng `Dim_Client`** (client_key −1) và **0 dòng fact** (đã kiểm bằng SQL). `year ≠ 9999` không loại dòng nào | Chỉ ảnh hưởng measure đếm trên `Dim_Client` |
| Visual | 134 visual: 50 card, 17 slicer, 22 biểu đồ/bảng. 2 pivot cần hàng tổng. Trang d4 là drill-through (`ISFILTERED` dựa vào 4 field) | Phase C cần `SUMMARIZECOLUMNS` + filter table và `ROLLUPADDISSUBTOTAL` |
| Ca nặng nhất trong 119 | `Avg_Account_Balance`: lặp khoảng 4.500 tài khoản, mỗi vòng 2 `CALCULATE` trên 1 triệu dòng | Cần posting list và cache. Đây là điểm đo hiệu năng số 1 |
| Build debug | Giải mã Fact_Transaction **chậm 34 lần** so với release (19,3 s so với 0,557 s) | Test Nhom6 chạy release (§3.6). Test đơn vị chạy trên MiniBank |

Phần khó không nằm ở số hàm mà ở khoảng **8 cơ chế ngữ nghĩa**:
- filter context và ghi đè;
- context transition;
- BLANK;
- `ALLSELECTED` (shadow context);
- lineage và `TREATAS`;
- `KEEPFILTERS`;
- blank row;
- time intelligence.

## 2. Kiến trúc (tóm tắt; chi tiết ở `phase-b-research/architecture.md` §2–7)

```
PBIXKit ──► ColumnStore ──► DAXEngine ──► BIPro (DAX Query View), dax-run (CLI)
            cột, RowSet,     lexer, parser, binder, evaluator,
            CodeSet, quan    filter context, hàm, truy vấn, định dạng
            hệ, lan truyền
                 ▲
           DAXTestSupport (MiniBank, đường dẫn fixture, tiện ích golden)
```

- **Cột:** giữ mã dictionary như VertiPaq.
  - Mã 0 là BLANK.
  - Độ rộng mã u8/u16/u32 theo cardinality.
  - Dictionary có kiểu riêng, không dùng `[CellValue]`.
  - Nạp lười theo cột, giải mã song song, dùng chung giữa các cửa sổ.
  - Fact_Transaction ước lượng khoảng 65 MB.
- **Quan hệ:**
  - Chỉ mục `fkToPK: [Int32]`.
  - Blank row ảo là chỉ số `rowCount`.
  - `USERELATIONSHIP` và `CROSSFILTER` được lưu thành `RelationshipOverride`.
- **Bộ lọc:** chia hai tầng.
  - **Tầng ColumnStore:** `CodeSet` (tập mã của một cột) và `TableFilter` (bộ lọc mức bảng). Lan truyền theo `visibleRows(table:localFilters:overrides:)`.
  - **Tầng DAXEngine:** `FilterContext` có đủ ngữ nghĩa CALCULATE (ghi đè, `KEEPFILTERS`, chiếu cột, expanded table, vân tay). Khi cần tính dòng thấy được, nó dịch xuống tầng ColumnStore.

  Nhờ vậy ColumnStore không phải phụ thuộc DAXEngine.
- **`ALLSELECTED`:** dùng shadow stack. `SUMMARIZECOLUMNS` và mọi iterator đẩy shadow vào. Shadow nằm trong khoá cache.
- **Posting list** theo mã cho cột khoá và cột hay lọc. Context transition trong iterator nhờ đó không phải quét lại 1 triệu dòng.
- **Cú pháp thật phải xử lý:** đối số bỏ trống (`RANKX(…, , DESC, DENSE)`), số mũ `1e6`, cột ảo `[@c]`, `VAR` lồng trong đối số, chuỗi SVG dài.

## 3. Cách chia việc cho agent song song

### 3.1 So sánh 4 cách chia (chấm 1–5, tổng 25)

| Cách chia | Đường găng | Xung đột file | Rủi ro ghép | Chi phí context | Test độc lập | Tổng |
|---|---|---|---|---|---|---|
| A. Theo lớp kỹ thuật | 2 (agent làm hàm bị nghẽn) | 4 | 2 | 3 | 3 | 14 |
| B. Theo họ hàm, sau khi lõi xong tuần tự | 2 (lõi tuần tự 2–3 tuần) | 5 | 4 | 4 | 5 | 20 |
| C. Lát dọc theo tầng độ khó | 3 | 1 (mọi tầng đều sửa evaluator) | 2 | 2 | 4 | 12 |
| **D. Lai theo đợt** ✅ | 4 | 5 | 3 | 3 | 5 | **20–21** |

**Chọn D.** Đường găng là:

`Contracts → FilterContext + Propagation → Evaluator/CALCULATE → hàm lọc + SUMMARIZECOLUMNS → đối chiếu ALLSELECTED/time intelligence`

Cách D cho mọi việc khác chạy song song với đường này. Rủi ro ghép được hạ từ 4 xuống 3 so với bản v1, vì `ALLSELECTED` trải trên 5 WP (FC, CORE, QRY, F-FILTER, F-AGG). Có thêm một mốc test tích hợp chung để bù (§3.4, cuối đợt 3).

### 3.2 Cách làm việc (giữ khuôn đã chạy ổn ở Phase W)

- Mỗi agent làm trong **sandbox sao chép** riêng (không cần git) và build bằng `--scratch-path` riêng.
- Quyền sở hữu ghi trong `docs/phase-b-ownership.tsv`:
  - Có cột **đợt**: một file có thể đổi chủ giữa các đợt, nhưng không bao giờ có hai chủ trong cùng một đợt.
  - Mỗi dòng một glob, không dùng `{a,b}`.
- `scripts/check-ownership.sh` được sửa ở đợt 0 để làm ba việc:
  - (a) nhận đường dẫn TSV và đợt làm tham số;
  - (b) **báo lỗi khi hai WP cùng sở hữu một file** trong cùng đợt (bản hiện tại chưa kiểm việc này);
  - (c) kiểm theo cả file, nên không có kiểu sở hữu "một phần file".
- Lead gộp file theo quyền sở hữu. Sau mỗi đợt chạy `swift build`, `swift test` và test nặng (§3.6).
- **File chỉ lead sửa, đóng băng sau đợt 0:**
  - `Package.swift`
  - `Sources/ColumnStore/Contracts.swift`, `Sources/DAXEngine/Contracts.swift`
  - `Syntax/AST.swift`, `Functions/Registry.swift`, `Engine.swift`
  - `Sources/DAXTestSupport/**`
  - `DocumentState.swift`, `Workspace.swift`, `Sources/PBIXKit/ModelMetadata.swift`

  Muốn đổi thì gửi yêu cầu cho lead, tối đa 1 lần mỗi đợt.
- **Bảng hàm không có điểm nóng.** Mỗi họ hàm nằm trong một file và khai báo `static let functions: [FunctionSpec]`. Ở đợt 0, lead khai báo sẵn **chữ ký** (tên và tham số) của khoảng 49 hàm/cấu trúc, phần cài đặt tạm thời ném `unsupportedFunction`. Nhờ vậy binder bind được ngay từ pilot, và agent làm hàm chỉ thay thân hàm trong file của mình.
- `DAXError.Kind` là enum đóng băng. Chi tiết lỗi nằm trong `message`.

### 3.3 Đợt 0 (lead), viết đủ để mọi đợt sau tự kiểm được

| Việc | File |
|---|---|
| Target mới: `ColumnStore`, `DAXEngine`, `DAXTestSupport` (library dùng chung cho test), `dax-run`, `ColumnStoreTests`, `DAXEngineTests`. BIPro phụ thuộc `DAXEngine` | `Package.swift` |
| Contract ColumnStore: `ColumnID`, `TableID`, `RelationshipID`, `DAXType`, `ColumnData` (API đọc), `RowSet`, `CodeSet`, `TableFilter`, `RelationshipOverride`, `ColumnSource`, `ModelSchema`, `RelationshipSchema`, và chữ ký `Propagation.visibleRows(table:localFilters:overrides:) -> RowSet` | `Sources/ColumnStore/Contracts.swift` |
| `ModelSchema(metadata:)`, do **lead** làm ở đợt 0 để LANG và CS không chờ nhau trong pilot | `Sources/ColumnStore/ModelSchema+Metadata.swift` |
| Contract DAXEngine: `DAXError`, `SourceRange` (offset kèm dòng/cột 1-based; cách đếm tab chốt theo O3), `Value` (có Infinity/NaN; không dùng `CellValue` của PBIXKit), `BoundExpr`, `ParamKind`, `FunctionSpec`, `FunctionFamily`, `CallFrame`, `ContextModifier`, `EvalContext`, `TableValue`, `QueryResult` | `Sources/DAXEngine/Contracts.swift`, `Syntax/AST.swift` |
| Registry gồm **11 họ** (tách `Calculate` và `TimeIntel` thành họ riêng), mỗi họ một file stub, với chữ ký khoảng 49 hàm | `Functions/Registry.swift` cùng 11 file stub |
| Façade engine và CLI khung | `Engine.swift`, `Sources/dax-run/main.swift` |
| Mở rộng ModelMetadata: `Table.dataCategory` (bảng ngày), `Model.culture`, `Measure.dataType`/`state`/`formatStringDefinition` | `Sources/PBIXKit/ModelMetadata.swift` |
| **MiniBank** cùng đặc tả đầy đủ (§3.5), đường dẫn fixture của 3 file, `InMemoryColumnSource` | `Sources/DAXTestSupport/**` |
| Móc UI. Tách `QueryWorkspaces.swift` thành `QueryWorkspaces.swift` (bố cục), `QueryTabBar.swift`, `QueryToolbar.swift`. Thêm `DAXQueryState.swift` để lưu trạng thái và kết quả của từng tab, thay vì sửa `DAXQueryTab` trong `DocumentState.swift` đã đóng băng. Sửa truy vấn mẫu: `[Transaction Count]` không tồn tại, tên đúng là `[Trans Count]` | `Sources/BIPro/Query/*`, `DocumentState.swift`, `Workspace.swift` |
| **Hợp đồng UI ↔ engine ở dạng nháp**: `DAXQueryRunning`, `DAXLanguageService`, `FakeQueryRunner`. Chốt sau khi có quan sát O1–O3 (§5.4) | `Sources/DAXEngine/QueryService.swift` |
| **ORA-0: gói oracle cho buổi 1.** Gồm generator, `queries/*.dax` (chỉ 119 measure; thêm cột thăm dò `ISBLANK` cho measure trả về chuỗi), `observe/*.dax` (mỗi quan sát một file), `CHECKLIST.md`. **Làm đầu tiên**, để buổi 1 của bạn diễn ra trong lúc mình làm phần còn lại của đợt 0 | `scripts/oracle/gen-oracle-pack.py`, `docs/phase-b-oracle/**` |
| Ownership TSV theo đợt; sửa `check-ownership.sh` | `docs/phase-b-ownership.tsv`, `scripts/check-ownership.sh` |

Tự kiểm: `swift build` xanh với stub; `check-ownership.sh` phát hiện được file trùng chủ (có test với TSV cố tình sai). Ước lượng 1,5–2 ngày làm việc.

### 3.4 Gói việc, file sở hữu và đợt

Mọi đường dẫn tương đối với `Sources/DAXEngine/` nếu không ghi rõ. Test của mỗi WP đặt trong `Tests/<Target>Tests/<WP>/`.

| Đợt | WP | Nội dung | File sở hữu | Tự kiểm |
|---|---|---|---|---|
| **1a pilot** | **CS** ColumnStore | RowSet (bitset và thưa), ColumnData, StringPool, posting list, nạp lười song song, bench | `Sources/ColumnStore/{RowSet,ColumnData,StringPool,PBIXColumnSource,ColumnStore}.swift` (mỗi file một dòng TSV), `Sources/dax-run/Bench*.swift` | Distinct count của 11 bảng Nhom6 khớp `verify`; bench release ghi thời gian nạp |
| **1a pilot** | **LANG** | Lexer, Parser, Catalog nhiều lớp (model ← DEFINE), Binder (lỗi tên có vị trí) | `Syntax/Lexer.swift`, `Syntax/Parser.swift`, `Semantic/Catalog.swift`, `Semantic/Binder.swift` | **316/316** biểu thức của 3 file parse được; **bind đủ 119 measure** với chữ ký hàm của đợt 0 và `ModelSchema` của lead |
| **1b** | **REL** | `RelationshipIndex`, `Propagation` (một/hai chiều, inactive, override, blank row) | `Sources/ColumnStore/RelationshipIndex.swift`, `Sources/ColumnStore/Propagation.swift` | Trên MiniBank và Nhom6: số dòng fact dưới bộ lọc dim khớp đếm bằng SQL |
| **1b** | **VAL** | Ép kiểu, số học, so sánh, BLANK, chia 0, `FormatString` | `Runtime/Value+Ops.swift`, `Format/FormatString.swift` | Bảng ép kiểu và BLANK theo Microsoft Learn; định dạng đúng mọi FormatString của Nhom6 |
| **1b** | **ORA-1** | Đọc golden TSV và so khớp (§5.3); oracle sqlite (nạp theo kiểu metadata, **danh sách measure cụ thể** chứ không ghi "T0/T1"); **golden runner** (khung chạy, tự tách theo cột để một measure lỗi không làm hỏng cả file); fixture O-TINY (kỳ vọng từ tài liệu, gắn cờ `pendingPBI`) | `Tests/DAXEngineTests/ORA/**`, `Tests/DAXEngineTests/Golden/**` | SQL khớp số đã biết (Trans Amount 6257793560.3; Weighted Avg Term 44.311067); runner bỏ qua ca chưa hỗ trợ và báo rõ lý do |
| **1b** | **UI** (UI1) | QueryRunner async và huỷ; lưới NSTableView ảo; nhiều kết quả; Copy TSV; Export CSV; pill trạng thái; lỗi `(dòng, cột)` bấm vào thì nhảy tới vị trí | `Sources/BIPro/Query/{QueryRunner,ResultGrid,QueryResultsView,QueryWorkspaces,QueryToolbar,DAXQueryState}.swift` | Chạy trên `FakeQueryRunner`: cuộn 1 triệu ô dưới 16 ms/khung; Huỷ dưới 100 ms; ảnh chụp REA so với `UIdesign/lumen_analytics_dax_query_view` |
| **2** | **FC** | FilterContext (ghi đè, `KEEPFILTERS`, chiếu, expanded table, vân tay), ShadowStack, TableValue và lineage | `Runtime/FilterContext.swift`, `Runtime/Shadow.swift`, `Runtime/TableValue.swift` | O-TINY cho ghi đè, `KEEPFILTERS`, chiếu trên MiniBank |
| **2** | **CORE** ⚠️ đường găng | Evaluator, VAR, tham chiếu measure, **CALCULATE/CALCULATETABLE**, context transition, helper iterator, cache | `Runtime/Evaluator.swift`, `Runtime/Cache.swift`, `Functions/Calculate.swift` | Test CALCULATE và transition trên MiniBank (dùng bộ hàm lõi của F-KIT) |
| **2** | **F-KIT** (hàm vô hướng + **bộ hàm lõi**) | Logical, Math, Text (`FORMAT`), DateTime, cộng bộ hàm lõi mà CORE/QRY cần để test: `SUM`, `COUNTROWS`, `ISBLANK`, `REMOVEFILTERS`, `KEEPFILTERS`, `FILTER`, `VALUES`, `RELATED`, `ROW` | `Functions/{Logical,MathFns,Text,DateTime,Aggregation,Information,FilterFns,TableFns}.swift` (**đổi chủ** sang đợt 3) | Golden theo họ trên MiniBank |
| **2** | **QRY** | `DEFINE`/`EVALUATE`/`ORDER BY`/`START AT`; `SUMMARIZECOLUMNS` (filter table, bỏ dòng BLANK, auto-exist, đẩy shadow) | `Query/QueryExecutor.swift`, `Query/SummarizeColumns.swift` | Truy vấn **viết cho schema MiniBank** chạy đúng |
| **3** | **F-FILTER** | Information (`ISFILTERED`, `HASONEVALUE`, `SELECTEDVALUE`…) và FilterFns (`ALL*`, `ALLSELECTED`, `TREATAS`, `USERELATIONSHIP`, `CROSSFILTER`) | `Functions/Information.swift`, `Functions/FilterFns.swift` | Họ D4 trên MiniBank |
| **3** | **F-AGG+TABLE** | Aggregation đầy đủ (`COUNT`, `DISTINCTCOUNT`, `AVERAGE`, `MIN`, `MAX`), Iterators (`SUMX`, `AVERAGEX`, `MINX`/`MAXX`, `CONCATENATEX`, `PERCENTILEX.INC`), TableFns (`SUMMARIZE`, `ADDCOLUMNS`, `CROSSJOIN`, `TOPN`, `DISTINCT`, `ALLNOBLANKROW`) | `Functions/Aggregation.swift`, `Functions/Iterators.swift`, `Functions/TableFns.swift` | Danh sách measure O-SQL khớp |
| **3** | **F-TIME** | `SAMEPERIODLASTYEAR`, `DATEADD`, YTD/MTD; dùng `Table.dataCategory` để nhận bảng ngày | `Functions/TimeIntel.swift` | Ca cuối tháng và 29/02 theo tài liệu; **họ Δ** trên MiniBank (2 năm ngày liền nhau) |
| **3** | **UI** (UI2+UI3) | Chẩn đoán, gạch chân lỗi, tự hoàn thành, comment theo dòng; đổi tên tab, chạy nền; quick queries mở tab mới và tự chạy; "Định nghĩa và đánh giá" mở tab mới | `Sources/BIPro/Query/{CodeEditor,Completion,EditorDiagnostics,QueryTabBar,QuickQueries}.swift`, `Sources/BIPro/Panes/DataPane.swift`, `Sources/BIPro/Shell/Ribbon.swift` (nhận trọn file) | Gõ dưới 16 ms/phím với truy vấn 500 dòng; văn bản quick query khớp `O8-*.dax` |
| **cuối đợt 3** | **mốc chung** | Test tích hợp `ALLSELECTED` (O-TINY fixture 6) và golden G0/G1/G3 chạy trên engine thật | lead | Báo cáo khớp/lệch theo từng measure |
| **4** | **4 slot cố định** | Sửa lỗi theo golden, giao về chủ nhóm file. **A:** Evaluator, Cache, FilterContext, Shadow, Calculate. **B:** FilterFns, Information. **C:** Aggregation, Iterators, TableFns, TimeIntel, QRY. **D:** O-CC (7 cột tính toán), O-PROP, `DAXFormatter` (UI4), bench và đường nhanh cho `Avg_Account_Balance` | TSV đợt 4 | **Tiêu chí xong §0**. Cần có golden buổi 2 trước khi đóng đợt |

Không đợt nào có quá 4 agent cùng lúc.

### 3.5 MiniBank (đặc tả đợt 0, đặt trong `DAXTestSupport`)

- **`Dim_Date`:** 2 năm liền nhau (2023–2024, có 29/02/2024). Khoá `date_key` dạng yyyymmdd, `full_date`. Đã đánh dấu là bảng ngày. Có cột `year`, `month`, `MonthIndex`.
- **`Dim_Client`:** 6 dòng, có 1 dòng `Unknown` (khoá −1) giống Nhom6. **`Dim_Account`:** 5 dòng. **`Dim_District`:** 3 dòng, **không có quan hệ với `Dim_Account`**, để thử `TREATAS` 2 cột (họ D4).
- **`Fact_Trans`:** 40 dòng, trải đủ 2 năm. Có **1 FK không khớp** để sinh blank row.
- **`Fact_Complaint`:** 12 dòng, có `received_date_key` (active) và `sent_date_key` (inactive).
- **Measure model** (đủ để thử context transition và họ Δ):
  - `Trans Amount = SUM(...)`
  - `Trans Count`
  - `Avg Balance` (lặp theo tài khoản)
  - một measure `X Δ` theo đúng khuôn Nhom6
- **Cột tính toán:** 1 cột dùng `RELATED`, có **giá trị lưu sẵn** để thử O-CC.
- **Kết quả kỳ vọng:** tính bằng tay, ghi kèm trong file.

### 3.6 Lệnh test

- **Thường:**

  ```
  swift test --scratch-path .build-<wp>
  ```

  Chạy trên MiniBank, mất vài giây.
- **Nặng** (Nhom6, golden):

  ```
  BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-<wp>-rel
  ```

  Mọi test hiện có đều dùng `@testable import`, nên khi build release bắt buộc phải có `-enable-testing`.

### 3.7 Thử cách chia (pilot đợt 1a: CS + LANG)

| Chỉ số | Ngưỡng đạt (giống Phase W) |
|---|---|
| Sửa file ngoài phần sở hữu | 0 |
| Build/test sau khi gộp | xanh ngay lần đầu |
| Đổi contract | ≤ 1 lần |
| Thời gian thực so với ước lượng | ≤ 1,5 lần |

- **Đạt:** mở rộng lên 4 agent ở đợt 1b.
- **Trượt vì contract:** lead sửa contract, chạy lại pilot một lần.
- **Trượt vì xung đột:** các họ F-* chạy tuần tự (cách B).

Để so sánh: ở Phase W có 5 agent chạy qua 3 đợt, 0 vi phạm sau khi sửa một lỗi trong bảng quyền, và mỗi lần gộp đều xanh ngay.

### 3.8 Thời gian (ngày làm việc)

| Đợt | Ngày |
|---|---|
| 0 | 1,5–2 |
| 1a | 3–4 |
| 1b | 3–4 |
| 2 | 6–8 |
| 3 | 6–8 |
| 4 | 7–10 |
| **Tổng** | **27–36 ngày làm việc ≈ 5,5–7 tuần**, khớp khung 6–7 tuần của kế hoạch tổng |

Có hai mốc phụ thuộc vào bạn, cả hai nằm trên đường găng: **buổi 1** phải xong trước đợt 1b (UI cần O1–O3), và **buổi 2** phải xong trước khi đóng đợt 4.

## 4. Kiến trúc theo đợt: ai cần gì, lúc nào

```
Đợt 0 ─ LEAD: contracts, Registry (chữ ký), ModelSchema, MiniBank, ORA-0 ──► [Buổi 1 của bạn: O1–O9, golden G0/G1/G3]
  │
Đợt 1a ─ CS ║ LANG                                   (pilot, §3.7)
  │
Đợt 1b ─ REL ║ VAL ║ ORA-1 ║ UI(1)                   (UI chốt hợp đồng theo O1–O3)
  │
Đợt 2 ─ FC ║ CORE ⚠️ ║ F-KIT ║ QRY
  │
Đợt 3 ─ F-FILTER ║ F-AGG+TABLE ║ F-TIME ║ UI(2+3) ──► mốc chung: ALLSELECTED + G0/G1/G3
  │                                                     [Buổi 2 của bạn: G2, G5, G6, PA, tiny]
Đợt 4 ─ slot A ║ B ║ C ║ D  (sửa theo golden)  ──► 119/119 ở G0–G3, G5, G6 = xong
```

## 5. Oracle và kiểm thử

### 5.1 Năm loại oracle

| Mã | Oracle | Ai chạy | Phủ được |
|---|---|---|---|
| **O-PBI** | Golden từ DAX Query View của Power BI Desktop | **bạn, làm tay** | Mọi measure, mọi ngữ cảnh. Đây là chuẩn cuối cùng |
| **O-SQL** | Tính lại bằng sqlite từ dữ liệu đã giải mã | agent, tự động | Một danh sách measure cụ thể (tổng hợp đơn giản và CALCULATE đơn giản), do ORA-1 chốt theo tên |
| **O-CC** | Engine tính lại 7 cột tính toán của Nhom6, so với giá trị Power BI đã lưu | agent, tự động | Ngữ cảnh dòng: `RELATED`, `IF`, `SWITCH`, `HOUR`, `DATE`… Đây là golden thật của Power BI, có sẵn |
| **O-PROP** | Test thuộc tính và metamorphic, ví dụ `CALCULATE([m], ALL(t))` bằng tổng | agent | Bất biến ngữ nghĩa |
| **O-TINY** | Bảng tí hon với kỳ vọng lấy từ tài liệu công khai (bảng Sales 12 dòng của Microsoft Learn; `SAMEPERIODLASTYEAR` 27–28/2/2009 → 27–29/2/2008) | agent viết; bạn xác nhận một lần | Từng hàm khó và ca biên |

Ghi chú:
- O-CC cho Nhóm 2 (6 cột) là **suy đoán**, vì chưa chạy `verify` trên file đó. Mục này không thuộc tiêu chí Phase B. Đợt 4 sẽ chạy `pbix-dump verify` trên Nhóm 2 để biết.
- Dữ liệu phải nạp theo kiểu trong metadata. Nạp CSV để tự đoán kiểu từng làm `Weighted Avg Term` ra 44 thay vì 44,311067.

### 5.2 Gói golden cho bạn

**Đường dẫn duy nhất:**
- Đầu vào `.dax` nằm ở `docs/phase-b-oracle/queries/`.
- Bạn lưu kết quả vào `~/Downloads/bipro-golden/nhom6/` qua thư mục chia sẻ Parallels.
- Lead chép vào `Tests/DAXEngineTests/Golden/nhom6/`.
- Golden của bộ tí hon nằm ở `Tests/DAXEngineTests/Golden/tiny/`.

| Nhóm | Nội dung | Số file | Thuộc tiêu chí? |
|---|---|---|---|
| G0-total | `ROW(...)`, không filter | 4 | ✅ |
| G1-year | `SUMMARIZECOLUMNS('Dim_Date'[year], …)` | 4 | ✅ |
| G2-region | Theo `Dim_Client[client_region]` | 4 | ✅ |
| G3-rf-year | Như G1, cộng 2 filter cấp report | 4 | ✅ |
| G5-month | Theo tháng: `HASONEVALUE`, cửa sổ MonthIndex | 1 | ✅ |
| G6-visual | 6 truy vấn theo ngữ cảnh visual (`ALLSELECTED`, `SELECTEDVALUE`, `ISFILTERED`, `TREATAS`, `TOPN` + `CONCATENATEX`) | 6 | ✅ |
| G4-inactive | Biến thể `USERELATIONSHIP(sent_date_key)` | 1 | tham khảo |
| PA | Performance Analyzer: Copy query của khoảng 8 visual rồi chạy lại | 8 cặp | tham khảo (đặc tả Phase C) |

**Cách làm mỗi file:**
1. Mở `.dax`, Ctrl+A, Ctrl+C.
2. Trong Power BI, mở DAX Query View, tạo tab mới, dán, Run.
3. Copy kết quả, dán vào Notepad, lưu thành `<tên>.tsv` (UTF-8).

Ghi `manifest.tsv` gồm phiên bản Power BI, Windows regional format và số dòng. Truy vấn lỗi thì dán thông báo vào `<tên>.error.txt`.

**Thời gian:**
- Gói tối thiểu G0 + G1 + G3 (12 file): khoảng 25 phút.
- Toàn bộ: khoảng 1,5 giờ, chia 2 buổi.

Mỗi nhóm được chia thành 4 phần để không chạm giới hạn của DAX Query View (1.000.000 giá trị, 15 MB mỗi truy vấn).

### 5.3 Quy tắc so khớp (chép đủ từ `oracle-ui.md` §1.7)

- **Số nguyên:** khớp tuyệt đối.
- **Số thực:** sai số tương đối 1e-9. Currency so đến 4 chữ số thập phân.
- **BLANK:** BLANK khác 0, và BLANK khác chuỗi rỗng. Ô rỗng trong TSV không phân biệt được BLANK với `""`, nên generator thêm cột thăm dò `ISBLANK([m])` cho measure trả về chuỗi.
- **Infinity/NaN:** theo cách Power BI hiển thị (quan sát O1).
- **Ngày giờ:** sai lệch tối đa 3,34 ms (độ phân giải ngày giờ của Power BI).
- **Chuỗi:** chuẩn hoá `\r\n` thành `\n`. Measure trả về chuỗi do `FORMAT` tạo thì so nguyên chuỗi.
- **Cột và dòng:** cột so theo tên. Không có `ORDER BY` thì so dòng như multiset.
- **Lỗi:** so theo loại và vị trí (dòng, cột).
- **Locale:** đọc theo `manifest.tsv` (chốt bằng O2).

### 5.4 Quan sát Power BI trước khi làm (quy tắc của dự án)

Bạn làm trong VM theo `docs/phase-b-oracle/observe/` (mỗi quan sát một file, để Ctrl+A, Ctrl+C từng cái) và `CHECKLIST.md`. Đủ 18 mục O1–O18 ở `phase-b-research/oracle-ui.md` §2.4. Mỗi WP chỉ chốt phần đặc tả liên quan sau khi đã có quan sát tương ứng:

| Quan sát | Dùng cho | Phải có trước |
|---|---|---|
| **O1/O2** Định dạng lưới và định dạng khi Copy (dấu thập phân, ngày, BLANK, Infinity) theo Windows regional format | Đọc golden, `Value` | **Rủi ro số 1.** Trước khi chạy hàng loạt golden và trước ORA-1 |
| **O3** Thông báo lỗi và cách đếm (dòng, cột), kể cả khi có tab | `SourceRange`, UI1 | Trước khi chốt hợp đồng UI (đợt 1b) |
| **O4/O12** Giới hạn dòng hiển thị và thông báo cắt; Huỷ | UI1 | Đợt 1b |
| **O5** Nhiều `EVALUATE` trong một tab | Gói golden, UI1 | Buổi 1 |
| **O7** Tab truy vấn DAX được lưu ở đâu trong `.pbix` (bạn tạo 2 tab, Save As; mình so file bằng `pbix-dump`/REA) | Phase D không làm mất tab | Buổi 1 |
| **O8** Văn bản quick query | UI3 | Đợt 3 |
| **O9** Kết quả Format query | UI4 | Đợt 4 |
| **O10** IntelliSense | UI2 | Đợt 3 |

### 5.5 Lịch của bạn

- **Buổi 1** (khoảng 1 giờ, ngay khi ORA-0 xong ở đầu đợt 0): O1, O2, O3, O4, O5, O7, O8, O9, O10, O12, cộng golden tối thiểu G0/G1/G3.
- **Buổi 2** (cuối đợt 3, khoảng 1 giờ): G2, G5, G6, G4, PA, bộ tí hon, các quan sát còn lại (O6, O11, O13–O18).

## 6. Rủi ro

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| `ALLSELECTED` và shadow context (trải trên 5 WP) | **Cao**, cả về ngữ nghĩa lẫn ghép | Mô hình shadow stack theo SQLBI và Microsoft Learn; mốc tích hợp chung cuối đợt 3; golden G6 có slicer. Kỳ vọng O-TINY cho `ALLSELECTED`/`ISFILTERED` là suy đoán cho tới khi bạn xác nhận |
| Time intelligence (54 measure phụ thuộc) | Cao | F-TIME là WP riêng. Làm `SAMEPERIODLASTYEAR` = `DATEADD(-1, YEAR)` trước. Có ca cuối tháng và 29/02. Gặp ca chưa rõ thì **báo lỗi, không trả số sai** |
| Hiệu năng iterator trên fact 1 triệu dòng (`Avg_Account_Balance`) | Cao | Posting list, cache, chạy song song; bench release ở slot D |
| Locale khi Copy golden | Cao | Chốt bằng O1/O2 ở buổi 1, trước khi chạy hàng loạt |
| CORE nghẽn đường găng | Trung bình | Bộ hàm lõi giao cho F-KIT; hàm đặc biệt gọi helper công khai của `CallFrame`, không sửa evaluator |
| Độ chính xác số thực | Trung bình | Sai số 1e-9; cộng Kahan/pairwise; SUM số nguyên giữ Int64; currency là Int64 ×10⁴ |
| Build debug chậm 34 lần | Trung bình | Test đơn vị trên MiniBank; Nhom6 chạy release (§3.6) |
| Hành vi thay đổi theo phiên bản Power BI | Trung bình | Ghi phiên bản Power BI trong `manifest.tsv` |
| Nhom6 có toàn vẹn tham chiếu hoàn hảo | Thấp | Không thử được blank row trên dữ liệu thật; dựa vào MiniBank, O-TINY, PA |

## 7. Ranh giới

- Không decompile và không dịch ngược Power BI Desktop / Analysis Services. Ngữ nghĩa lấy từ tài liệu công khai, có ghi nguồn (`phase-b-research/architecture.md` §11). Không chép code.
- Không chạy pbixray hay oracle Python tải từ mạng. DAX Studio chỉ dùng nếu bạn tự cài.
- Agent không điều khiển VM.
- Chưa làm AI/Copilot trong DAX Query View.
- RLS (4 role), calculation group và `ROLLUPADDISSUBTOTAL` (Phase C) không thuộc Phase B.

## 8. Cần bạn quyết định / chuẩn bị

**Đã chốt (2026-11-01, theo thiết kế, không chờ thêm):**
- Tên cột manifest: `file`, `sha1_dax`, `ngày`, `phiên bản Power BI (Help → About)`, `Windows regional format`, `số dòng`, `ghi chú lỗi` (theo `oracle-ui.md` §1.3).
- Locale: không chốt trước. Bộ đọc golden đọc theo cột `Windows regional format` của manifest, và quyết định cuối cùng do O1/O2 ở buổi 1.
- Phím Format query (Shift+Alt+F trên Windows): không giả định. O9 xác nhận trên màn hình.
- Quan sát: thư mục `docs/phase-b-oracle/observe/` thay cho một file `observe.dax`.
- Buổi 1: gói đã sẵn sàng, bạn hẹn thời điểm khi có VM.

1. Duyệt cách chia D, pilot CS + LANG, và 4 slot cố định ở đợt 4.
2. Lịch **buổi 1**, khoảng 1 giờ, ngay đầu đợt 0. Mình chuẩn bị file trước tiên.
3. Windows trong VM đang để regional format nào (en-US hay vi-VN)? Câu trả lời ảnh hưởng trực tiếp tới cách đọc golden.

## 9. Đối chiếu ghi chú và sửa so với v1

| Điểm | Kết luận | Cách kiểm |
|---|---|---|
| Filter `client_region` có lọc fact không | 1 dòng `Dim_Client`, 0 dòng fact. `scope.md` nói "lọc mọi fact" là sai; `oracle-ui.md` đúng về fact | SQL trên dữ liệu đã giải mã |
| Họ Δ là 17 hay 13 | **17 × 3 = 51** (`oracle-ui.md` ghi 13 là sai) | Đếm trong danh sách closure |
| `COUNT` có trong 119 không | Có, trong 2 measure. `scope.md` nói chỉ có ở Nhóm 2 là sai | Quét biểu thức (bỏ qua chuỗi) |
| Ca nặng `Closing_Balance` | Nằm **ngoài** 119. Đổi điểm đo sang `Avg_Account_Balance` | Danh sách 49 measure không dùng |
| Tầng độ khó | Chỉ dùng cách xếp của `scope.md`. Con số "35 T0/T1" của O-SQL được thay bằng danh sách measure cụ thể | |
| Phụ thuộc ngược ở đợt 2 | Thêm bộ hàm lõi (F-KIT); O-CC chuyển sang đợt 4; test của QRY viết cho MiniBank | |
| Pilot không bind được | Lead khai báo chữ ký hàm và làm `ModelSchema` ở đợt 0 | |
| MiniBank, oracle, quyền sở hữu UI, contract trước quan sát, test release, sửa ModelMetadata | Đã đưa vào §3.3–3.6 và §5.4 | |
| Kế hoạch tổng | Đã cập nhật mục Phase B trong `BIPRO_BUILD_PLAN.md` (43 hàm, không dùng pbixray, DAX Studio tuỳ chọn) | |

## Kết quả thử cách chia

### Pilot đợt 1a (CS ‖ LANG), 2026-11-01

| Chỉ số | Ngưỡng | Kết quả | Đạt |
|---|---|---|---|
| Sửa file ngoài phần sở hữu | 0 | 0 (so sandbox với repo: chỉ file thuộc glob của WP) | Đạt |
| Build/test sau khi gộp | xanh ngay lần đầu | build xanh; cảnh báo "unhandled resources" của test target sửa bằng `exclude` trong Package.swift; test 164 pass, 3 test nặng pass ở release | Đạt |
| Đổi contract | ≤ 1 | 0 | Đạt |
| Thời gian thực so với ước lượng | ≤ 1,5 | hai agent chạy song song khoảng 17 phút wall-clock (ước lượng 3–4 ngày); số liệu không so trực tiếp được vì ước lượng là ngày làm việc của người | Đạt (suy đoán) |
| Câu hỏi agent hỏi lại lead | ≤ 2 | 0 | Đạt |

Số liệu kỹ thuật (CS): Nhom6 `bench --verify` ở release: 110 cột, 0 lệch; mở file 0,46 s; nạp tuần tự 1,83 s; nạp song song 0,65 s; 80 cột mã hoá, 30 cột dense, khoảng 59 MB.

Lệch cần ghi nhận:
- LANG: 312/316 biểu thức có thân parse được. 4 khối trong `n3` không có biểu thức (thân rỗng hoặc chỉ có chú thích). Tiêu chí 316/316 ghi nhầm; con số đúng là 312 + 4 khối rỗng. Không coi là lỗi parse.
- `measures-119.tsv` bị cắt ở 300 ký tự ở 50 dòng và có khác biệt xuống dòng. Đã dựng lại cột biểu thức từ metadata Nhom6 (nguồn chuẩn), tên, bảng và tier giữ nguyên.
- Chưa làm (chuyển sang đợt sau): `ColumnStoreCache.shared`; `prefetch` đồng bộ (chưa async/TaskGroup); phát hiện chu trình measure (`circularDependency`); DEFINE VAR bên trong measure chưa có khung slot riêng (binder bắt đầu slot từ 0).
- Cần quyết định trước QRY (ORDER BY chuỗi): `sortRank` hiện so theo chữ thường Unicode, chưa đúng collation của model (ví dụ "Đà" đang đứng sau "TP"). Quyết định ở đợt 2, sau khi có quan sát.
- `RowSet.rows` ở dạng bitset phải giải nén, O(n). Engine dùng `forEach`/`contains` trong vòng lặp.
- Cách đếm cột (tab = 1 cột) chờ O3.

Quyết định sau pilot: mở rộng 1b theo plan (4 agent), nhưng ORA-1 và UI1 chờ buổi 1 (O1–O3), đúng yêu cầu của plan §4. REL và VAL chạy trước.


_(ghi sau pilot đợt 1a)_

## Trạng thái (cập nhật 2026-11-01)

**Đợt 0: xong, trừ hai mục đánh dấu hoãn.**
- Xong: `Package.swift` (target mới), contract ColumnStore và DAXEngine, AST, 11 họ hàm với chữ ký, façade `DAXEngine`, `QueryService` (`DAXQueryRunning`, `DAXLanguageService`, `FakeQueryRunner`), khung `dax-run`, `ModelSchema(metadata:)`, mở rộng `ModelMetadata`, `InMemoryColumnSource` và `ColumnBuilder`, `RowSet` tối thiểu.
- Xong: MiniBank (`Sources/DAXTestSupport/MiniBank*.swift`, 8 test). Đáp án được tính bằng Python stdlib, độc lập với Swift.
- Xong: ORA-0 (`docs/phase-b-oracle/`, `scripts/oracle/gen-oracle-pack.py`), công cụ kiểm quyền sở hữu (`docs/phase-b-ownership.tsv`, `scripts/check-ownership.sh`).
- Xong: tách UI (`QueryWorkspaces.swift` 150 → 91 dòng, thêm `QueryTabBar.swift`, `QueryToolbar.swift`, `DAXQueryState.swift`). Hành vi giữ nguyên, chưa kiểm tra trên màn hình.
- Xong: sửa truy vấn mẫu thành `[Trans Count]` trong `DocumentState.swift`.
- Hoãn sang đợt 1a: `lazy var engine` trong `Workspace.swift` (cần `PBIXColumnSource` của CS). Hoãn sang UI1 (1b): nối `DAXQueryState` vào `DocumentState`, vì `DAXQueryState` hiện chưa được UI dùng.
- Kiểm tra: `swift build` xanh; `swift test` 79/79 pass (71 cũ + 8 MiniBank).

**Việc tiếp theo:** pilot đợt 1a (CS ‖ LANG), sau khi bạn duyệt cách chia và có buổi 1 (xem mục 8).

**Ghi chú lệch so với plan:**
- MiniBank có 40 dòng `Fact_Trans` theo §3.5. `architecture.md` §8.4 ghi 20; chọn §3.5.
- `Avg Balance` lấy `VALUES(Fact_Trans[account_key])` theo mẫu Nhom6, gồm cả khoá 99. Cần đối chiếu với oracle.

### Đợt 1b (REL ‖ VAL), 2026-11-01

- Đã gộp: REL (`RelationshipIndex.swift`, `Propagation.swift`, test `REL/`), VAL (`Value+Ops.swift`, `FormatString.swift`, test `VAL/`). ORA-1 và UI1 chưa chạy, chờ buổi 1.
- Kiểm: build xanh; `swift test` 258 test pass; test Nhom6 nặng (REL và CS) pass ở release (6/6); lint đợt 1b: 0 vi phạm.
- Không đổi contract. Lỗi lan truyền dùng `PropagationError` (không thêm case vào `ColumnStoreError`).

**Giả định cần lead xác nhận:**
- Mọi quan hệ được coi là M:1 (contract không có cardinality). Quan hệ 1:1 và M:M cần bổ sung khi có dữ liệu.
- Lan truyền ngược (nhiều → một, quan hệ hai chiều) chỉ áp khi bên nhiều đã bị lọc. Cách đọc này khác công thức §3.3 viết thẳng, vì công thức đó làm ẩn dòng bên một ngay cả khi bảng fact không lọc (MiniBank cho 24 dòng thay vì 40). Cần xác nhận khi có O-quan sát.
- Lan truyền mơ hồ chỉ kiểm từ bảng có bộ lọc; USERELATIONSHIP tắt các quan hệ khác cùng cặp bảng.
- Khoá khớp: nguyên và currency được gộp; chuỗi không phân biệt hoa thường; khoá trùng giữ dòng đầu.

**Giả định VAL cần đối chiếu với O1, O2, O15:**
- Làm tròn nửa xa 0 trên 15 chữ số có nghĩa; ∞ và NaN hiển thị "∞", "-∞", "NaN"; ngày khi chuyển chuỗi theo "M/d/yyyy h:mm:ss AM" giờ UTC.
- Chuỗi so không phân biệt hoa thường bằng `lowercased()`, chưa theo collation của model (xem mục sắp xếp chuỗi ở pilot).
- Tên kiểu trong thông báo lỗi ngoài "Text" và "Integer" là phỏng đoán.
- Số mẫu FORMAT trong Nhom6 là 12 mẫu khác nhau (không phải 19 như ghi cũ; 19 là số dynamic format string đếm theo measure).

### Đợt 2a (FC ‖ F-KIT vô hướng), 2026-11-01

- Đã gộp: FC (`FilterContext.swift`, `Shadow.swift`, `TableValue.swift`, test `FC/`), F-KIT scalar (`Logical`, `MathFns`, `Text`, `DateTime`, `Information` chỉ ISBLANK; test `F-KIT/`).
- Kiểm: build xanh; `swift test` 324 test pass; lint đợt 2: 0 vi phạm. Không đổi contract.
- API FC chốt: `FilterContext.bound(to:)` (gắn lược đồ cho expanded table), `applying(_:)`, `applying(_:keep:)`, `applying(rows:keep:)`, `removingColumns/ExpandedTable/All`, `pushingShadow/poppingShadow`, `values(for:)`, `visibleRows(in:table:overrides:)`, `fingerprint`.
- Việc mở ra cho contract (lead quyết định, chưa làm): `ContextModifier` chưa có dạng bộ lọc theo bảng (CORE dùng `applying(rows:keep:)`); `EvalContext` không có lược đồ (gốc phải gọi `bound(to:)`).
- Cảnh báo mục sắp xếp chuỗi và collation vẫn chưa xử lý: nằm trong danh sách cần quyết định trước QRY ORDER BY chuỗi.

### Đợt 2b (CORE ‖ QRY), 2026-11-01

- Đã gộp: CORE (`Runtime/Evaluator.swift`, `Runtime/Cache.swift`, `Functions/Calculate.swift`, test `CORE/`); QRY (`Query/QueryExecutor.swift`, `Query/SummarizeColumns.swift`, test `QRY/`).
- Engine (lead): `DAXEngine.execute` chạy `parseQuery` → `QueryExecutor.execute` với `Evaluator`; `evaluate(measure:)` đi qua catalog và Evaluator; `validate` báo lỗi cú pháp. Thêm init `DAXEngine(store:catalog:culture:)`. Init cũ giữ nguyên.
- Kiểm: build xanh; `swift test` 385 test pass; lint đợt 2: 0 vi phạm.
- Test smoke cũ `engineStubsThrowUntilImplemented` đã thay bằng hai test thật (ROW không bảng; measure của model qua catalog). Measure MiniBank `Trans Count` chưa kiểm được ở đây vì COUNTROWS chưa có; chuyển sang đợt 2c.

**Đề xuất đổi contract (chưa làm; quyết định khi giao đợt 3):**
1. `ContextModifier` cần dạng bộ lọc theo bảng (`.rows(RowsFilter, keep:)`) và dạng bộ lọc tuple (TREATAS nhiều cột). Hiện CORE dùng `applying(rows:keep:)` của FC cho bộ lọc bảng; TREATAS nhiều cột báo lỗi runtime. Ảnh hưởng: F-FILTER đợt 3.
2. `Evaluating` thiếu `store`. CORE đang ép kiểu `CallFrame.eval` sang `Evaluator` để lấy store. Chấp nhận tạm; nên thêm vào protocol khi đổi contract lần sau.
3. `EvalContext` không mang frame VAR và shadow. Hiện ở trong Evaluator và FilterContext, không ảnh hưởng đúng đắn; ghi nhận.
4. `TableValue` không mang tập dòng vật lý. CORE có `iterateArgument(i)` để lặp bảng vật lý không materialize; F-AGG và F-TABLE dùng hàm này.

### Đợt 2c (F-KIT lõi), 2026-11-01

- Đã gộp: `Functions/Aggregation.swift` (SUM, COUNTROWS), `Functions/FilterFns.swift` (REMOVEFILTERS, KEEPFILTERS), `Functions/TableFns.swift` (FILTER, VALUES, RELATED); test `F-KIT/FKCore*`.
- Sửa lỗi REL (lead, phát hiện qua known issue của F-KIT): dòng BLANK ảo của bảng chỉ thấy được khi có quan hệ **đang hoạt động** trỏ vào bảng và có dòng bên nhiều **đang thấy** mà khoá không khớp (§3.3). Trước đó quy tắc chỉ nhìn `hasUnmatched` của toàn quan hệ, nên dòng BLANK lọt qua dưới bộ lọc năm 2023. Thêm `RelationshipIndex.hasUnmatched(in:)`. Test known issue chuyển thành kiểm tra thường.
- Kiểm: build xanh; `swift test` 425 pass, không còn known issue; Nhom6 nặng (REL, CS) 6/6 pass ở release; lint đợt 2: 0 vi phạm.
- Smoke test của lead đổi từ SUM sang AVERAGE (SUM đã cài).
- Đã cài, trong đợt 2 tổng cộng: LOGIC/MATH/TEXT/DATE scalar; ISBLANK; SUM; COUNTROWS; REMOVEFILTERS; KEEPFILTERS; FILTER; VALUES; RELATED. Còn `.pending` cho đợt 3: ALL, ALLSELECTED, ALLNOBLANKROW, ALLEXCEPT, TREATAS, USERELATIONSHIP, CROSSFILTER, AVERAGE, COUNT, DISTINCTCOUNT, MIN, MAX, SUMX…, DISTINCT, SUMMARIZE, ADDCOLUMNS, CROSSJOIN, TOPN, RELATEDTABLE, SAMEPERIODLASTYEAR, DATEADD, ISFILTERED, ISCROSSFILTERED, HASONEVALUE, SELECTEDVALUE.

**Quyết định về đề xuất đổi contract (đợt 3):** không đổi contract. TREATAS nhiều cột thực hiện bằng cách đổi tập tuple thành tập dòng của bảng đích, rồi áp qua `RowsFilter` đã có (`applying(rows:keep:)`). Lý do: thay đổi contract tốn chi phí ở mọi WP đang dùng `ContextModifier`, còn cách này dùng API FC đã chốt.

### Đợt 3 (F-FILTER ‖ F-AGG ‖ F-TABLE ‖ F-TIME), 2026-11-01

- Đã gộp: F-FILTER (ALL, ALLSELECTED, ALLNOBLANKROW, ALLEXCEPT, TREATAS, USERELATIONSHIP, CROSSFILTER; ISFILTERED, ISCROSSFILTERED, HASONEVALUE, SELECTEDVALUE); F-AGG (AVERAGE, COUNT, DISTINCTCOUNT, MIN, MAX; SUMX, AVERAGEX, MINX, MAXX, CONCATENATEX, PERCENTILEX.INC, RANKX); F-TABLE (DISTINCT, SUMMARIZE, ADDCOLUMNS, CROSSJOIN, TOPN, RELATEDTABLE); F-TIME (DATEADD, SAMEPERIODLASTYEAR).
- Không đổi contract trong đợt 3.
- Kiểm sau khi gộp: build xanh; `swift test` 533 pass với 2 known issue; lint đợt 3: 0 vi phạm. Mọi hàm đã có thân (không còn `.pending(`).
- Sửa đáp án `Avg Balance` (lead): kiểu `.currency(265716333)` thay vì `.double`, vì engine trả currency.
- Smoke test `pendingFunctionReportsUnsupported` kiểm trực tiếp `FunctionSpec.pending` (không còn hàm nào pending).

**Ba lỗi tích hợp (sửa ở đợt 3b):**
1. FC: lọc theo giá trị trên cột dense (`Dim_Date[full_date]`) chưa được hỗ trợ. Hệ quả: hai known issue của F-TIME. Đây là chặn chính của Δ.
2. CORE: CALCULATE chưa gọi `treatasRowFilter` cho TREATAS nhiều cột; `ALL` vật chất hoá khi lặp (chưa dùng `physicalRows`).
3. LANG: `ArgumentMatcher` gán sai đối số của SUMMARIZE dạng có cặp tên/biểu thức.

**Chưa làm trong đợt 3:** YTD/MTD (DATESYTD, TOTALYTD, ...) không có trong registry; cần đổi registry (contract đóng băng), lead quyết định. Lịch TimeIntel đang là bản riêng, có thể gộp với DateTime sau. UI2 và UI3 vẫn chờ UI1 (và buổi 1).

### Đợt 3b (sửa lỗi tích hợp), 2026-11-01

- FC: lọc theo giá trị trên cột dense qua quét cột thành `RowsFilter` (dòng BLANK và NaN khớp BLANK). Test `FCDense*`.
- CORE: CALCULATE gọi `treatasRowFilter` cho TREATAS nhiều cột; `iterateExpr` không vật chất hoá ALL, ALLSELECTED, ALLNOBLANKROW, ALLEXCEPT (đã kiểm đếm `materializedRowCount`). Test `COREIntegrationTests`.
- LANG: Binder của SUMMARIZE bind đúng cặp (tên, biểu thức). Test `LANGSummarizeBindTests`.
- Lead: hai known issue F-TIME chuyển thành test thường; bật lại hai test `.disabled` (MAX, SUMX đã có). Đáp án `Avg Balance` là `currency`.

**Kiểm:** build xanh; `swift test` 571 pass, không còn known issue; lint đợt 3: 0 vi phạm; test Nhom6 nặng ở release: 20/20 pass.

**Việc còn mở (không chặn đợt 3):**
- Lan truyền từ cột dense: FC chỉ lan qua cột mã hoá của bảng. Bảng chỉ có cột dense hoặc khoá dense sẽ không lan sang bảng khác. Cần `Propagation` nhận tập dòng theo bảng; là quyết định contract (lead).
- YTD/MTD (DATESYTD, TOTALYTD…) chưa có trong registry; cần đổi registry (contract đóng băng).
- Thứ tự chuỗi (collation) vẫn là xấp xỉ theo `lowercased()`. Chờ O17, O18.
- Bộ lọc dense mỗi lần quét cột, chưa có chỉ mục giá trị → dòng; có thể thêm ở CS nếu benchmark chậm.
- UI1, UI2, UI3, ORA-1 vẫn chờ buổi 1 (O1–O3).

### Tối ưu chạy 119 measure trên Nhom6 (2026-11-01)

- Nguyên nhân chậm: `Avg_Account_Balance` lặp qua mọi giá trị khác nhau của cột dense `trans_timestamp` (khoảng 9.000 lần gọi), mỗi lần quét lại cột và dựng tập 1 triệu bit.
- Sửa: chỉ mục sắp theo giá trị cho cột dense (`ColumnData`, lười); `RelationshipIndex.manyRows(from:restrictedTo:)`; `Propagation` lọc theo số dòng khớp ít hơn và bỏ intersection toàn bảng; `Calculate` có đường nhanh cho `cột = hằng`; huỷ theo `Task.isCancelled` trong vòng lặp của Evaluator.
- `measures-run` (dax-run): in từng dòng có fflush, giới hạn thời gian từng measure (`--per-measure-timeout`, mặc định 60 s).
- Kết quả (release, Nhom6): 119/119 OK, 0 lỗi, 0 timeout, tổng 21,0 s (trước: 115 OK, 4 timeout, > 400 s). 115 measure cũ giống hệt về trạng thái, kiểu và giá trị. Bốn measure `Avg_Account_Balance` trước đây TIMEOUT nay khớp phép tính độc lập (43811.6572; Δ 0.1555296361557252).
- Kiểm: `swift test` 571 pass; test Nhom6 nặng (release) 20/20 pass; lint đợt 3: 0 vi phạm.
- Còn lại: Δ family khoảng 5,6 s mỗi measure (khoảng 9.000 lần `visibleRows` dưới lọc ngày); mỗi measure dùng `EngineCache` riêng, chạy trong cùng một phiên sẽ nhanh hơn (chưa đo).
- Lệnh `occ-cc` (O-CC) chỉ nằm trong sandbox cũ; chưa chép vào repo.

### Buổi 1 và đối chiếu golden đầu tiên (2026-11-01)

- Chi tiết: `docs/phase-b-evidence/BUOI1.md`. Golden ở `Tests/DAXEngineTests/Golden/nhom6/`; quan sát ở `docs/phase-b-evidence/observe/`.
- **G0, G1, G3: 12/12 file khớp, 0 ô lệch; cả 119 measure khớp Power BI.**
- Lead sửa engine theo golden: (1) COUNTROWS/COUNT/DISTINCTCOUNT trên tập rỗng trả BLANK; (2) `Propagation.visibleRows` thêm overload nhận `TableFilter`, FC truyền bộ lọc theo dòng xuống thay vì chiếu tập mã; (3) DATEADD/SAMEPERIODLASTYEAR: ngày cuối tháng cho thêm mọi ngày còn lại của tháng đích; (4) SUMMARIZECOLUMNS nhận `KEEPFILTERS(bảng)`. Bảy test đơn vị giả định "đếm rỗng = 0" được sửa theo golden.
- Công cụ: `dax-run query` (ô dạng KIỂU:giá trị) và `scripts/oracle/compare-golden.py` (quy tắc §5.3 và định dạng O2).
- Kiểm: `swift test` 571 pass; Nhom6 nặng 20/20; lint 0 vi phạm.
- Quan sát chốt: O2 (Copy không phụ thuộc locale), O3 (tab = 1 cột, vị trí đếm từ 1; khớp LANG), O5 (một EVALUATE lỗi thì không có kết quả nào), O7 (tab lưu ở `DAXQueries/*.dax` và `DAXQueries/.pbi/daxQueries.json`).
- **Mở khoá:** UI1 (đủ O1–O5, O7, O12) và ORA-1 (đưa so khớp golden vào test Swift). Còn chờ buổi 2: G2, G5, G6 (tiêu chí xong), G4, PA.

### UI1, ORA-1 và gói buổi 2 (2026-11-01, lead làm trực tiếp)

**ORA-1 (golden runner):** `Tests/DAXEngineTests/ORA/ORAGoldenTests.swift`.
- `ORAGoldenNhom6Tests` chạy 12 golden G0/G1/G3 trên Nhom6 và so theo §5.3 và định dạng O2; tất cả khớp (khoảng 30 s ở release). Thêm golden mới bằng cách thêm tên vào `goldenNhom6Names`.
- `ORAGoldenComparatorTests` (lượt test thường) kiểm chính bộ so khớp.
- `ORACancelLatencyTests`: truy vấn nặng (G1-year__FT) dừng trong vòng 100 ms sau khi huỷ.
- Thu hẹp so với plan gốc: O-SQL không cần nữa vì đã có golden thật; O-TINY được thay bằng bộ ca nhỏ T1–T4 chạy trên Nhom6 (gói buổi 2).

**UI1 (DAX Query View chạy thật):**
- `Workspace.daxEngine()` tạo engine lười từ file đang mở (dùng chung giữa các tab).
- `DocumentState`: `daxRuns` (trạng thái theo tab), `daxTasks` (để huỷ), `daxEditorSelection`, `daxCursorRequest`.
- `QueryRunner.swift`: chạy nền, chạy vùng chọn nếu có, huỷ bằng `Task.cancel()`.
- `QueryResultsView.swift`: pill trạng thái, chọn kết quả i/n, Copy (TSV giống Power BI), Xuất CSV, Huỷ; lỗi dạng `Query (dòng, cột) thông báo` có nút đi tới vị trí.
- `ResultGrid.swift`: `NSTableView` có cột `#`, số căn phải, sắp xếp theo cột; định dạng lưới theo O1, định dạng Copy theo O2.
- `CodeEditor`: thêm binding vùng chọn và yêu cầu đặt con trỏ (tuỳ chọn, TMDL không đổi). Thanh công cụ và ribbon: Chạy (⌘↵), Huỷ (⌘.).
- Test `Tests/BIProTests/ResultFormatTests.swift`: Copy của BI Pro **giống từng byte** với `O1-copy.tsv` copy từ Power BI; định dạng lưới khớp ảnh O1.
- Kiểm trên app thật (ảnh chụp): truy vấn mẫu chạy, lưới 6 dòng, pill "Thành công · 6 dòng · 0,15 s".
- Chưa làm (để UI2/UI3): gạch chân lỗi khi gõ, tự hoàn thành, đổi tên tab, biểu tượng trạng thái trên tab, quick queries. Chưa đo "cuộn 1 triệu ô dưới 16 ms/khung".

**Gói buổi 2:** `scripts/oracle/gen-buoi2-pack.py` sinh `docs/phase-b-oracle/queries-buoi2/` (G4, G5, G6a–f, T1–T4) và `manifest-buoi2.template.tsv`; checklist `docs/phase-b-oracle/CHECKLIST-buoi2.md`; thêm `observe/O11-run-selection.dax`. Engine chạy được cả 17 truy vấn (gồm G2). G6f2 chậm (khoảng 116 s), cần tối ưu sau.

**Kiểm:** `swift test` 583 pass; test nặng (Nhom6, ORA) 26/26 pass ở release; lint 0 vi phạm.
