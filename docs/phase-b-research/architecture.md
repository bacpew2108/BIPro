# Phase B, nhiệm vụ B: kiến trúc engine DAX và cách chia module

Ngày: 2026-10-31. Chỉ đọc repo `/Users/macprom114/Desktop/PowerBINative`, không sửa gì.
Ký hiệu: **[FACT]** là điều đã đo hoặc đọc trực tiếp trong code/file; **[SUY ĐOÁN]** là ước lượng hoặc giả thuyết cần đo hay đối chiếu oracle; **[DOC]** là ngữ nghĩa lấy từ tài liệu công khai (nguồn ở §11).

---

## 0. Tóm tắt quyết định

1. Thêm 2 target thư viện mới: **`ColumnStore`** (lưu cột, RowSet, chỉ mục quan hệ, lan truyền lọc; phụ thuộc PBIXKit) và **`DAXEngine`** (lexer, parser, binder, evaluator, hàm, truy vấn, định dạng; phụ thuộc ColumnStore). Thêm executable **`dax-run`** (chạy truy vấn, bench, xuất golden) và 2 test target. BIPro chỉ gọi `DAXEngine`.
2. Cột giữ **mã dictionary** như VertiPaq, nhưng đổi quy ước: mã 0 = BLANK, mã k = `dictionary[k-1]`, độ rộng mã theo cardinality (UInt8/UInt16/UInt32). Dictionary có kiểu (mảng `Int64`/`Double`/pool chuỗi UTF-8), không dùng `[CellValue]` (24 byte mỗi phần tử).
3. Lọc được biểu diễn ở 2 tầng: **FilterContext** (danh sách bộ lọc theo cột, theo tuple nhiều cột, theo dòng bảng; giữ đúng ngữ nghĩa ghi đè của CALCULATE) và **RowSet theo bảng** (bitset hoặc danh sách dòng thưa), tính lười và nhớ đệm theo dấu vân tay của context.
4. Quan hệ M:1 có chỉ mục `fkToPK: [Int32]`; dòng trống ảo (blank row) là chỉ số `rowCount` của bảng phía một.
5. Có **chỉ mục ngược (posting list)** theo mã cho cột khoá và cột hay lọc. Đây là thứ giúp các measure "lặp theo tài khoản" như `Closing_Balance` chạy được (§7.3).
6. Mỗi họ hàm nằm trong **một file**, khai báo `static let functions: [FunctionSpec]`. `Registry.swift` do lead viết ở đợt 0, liệt kê sẵn mọi họ, nên không ai phải sửa file chung khi thêm hàm.
7. Cách chia việc đề xuất: **lai, theo đợt**. Đợt 1 chia theo lớp ở phần lá (4 agent). Đợt 2 có lõi evaluator (1 agent, nằm trên đường găng) chạy cùng các họ hàm vô hướng. Đợt 3 chia theo họ hàm cộng UI. Đợt 4 chia theo lát dọc measure, đối chiếu oracle. Tối đa 4 agent mỗi đợt.

---

## 1. Số liệu thực tế [FACT]

| Mục | Giá trị | Nguồn |
|---|---|---|
| Máy | Apple M1 Pro, 8 nhân, 16 GB RAM; Swift 6.1.2 | `sysctl`, `swift --version` |
| Nhom6: bảng / measure / quan hệ | 11 bảng; 168 measure (report dùng trực tiếp 95, closure 119); 14 quan hệ M:1 đều một chiều, 1 inactive (`Fact_CRM_Complaint[sent_date_key]` → `Dim_Date[date_key]`) | `pbix-dump tables/relationships`, `closure.py` |
| Số dòng | Fact_Transaction 1.056.320; Fact_CRM_Complaint 23.419; Dim_Client 5.370; Dim_Account 4.501; Dim_Date 2.922; Fact_Loan 682; các bảng khác ≤ 77 | `pbix-dump tables` |
| Cột tính toán | 7, **đều đã có dữ liệu VertiPaq lưu sẵn** (có DictionaryStorage) → Phase B không phải tính lại để đọc | `metadata.sqlitedb` |
| Bảng ngày | `Dim_Date.DataCategory = 'Time'`, cột khoá `full_date` (`IsKey=1`) → đã "Mark as date table" | `metadata.sqlitedb` |
| Culture model | `en-US` | `Model.Culture` |
| Cột của Fact_Transaction | dictionary: trans_id (1.056.320 giá trị phân biệt), trans_timestamp (1.014.771), date_key (2.191), account_key (4.500), client_key (4.500), trans_type_key (14), trans_hour (10, cột tính toán), trans_count (1); mã hoá theo giá trị (hidx): trans_key, amount (40.400), balance_after (542.739) | `ColumnStorage`, `DictionaryStorage` |
| Thời gian giải mã (release) | Fact_Transaction 0,557 s (một luồng, cả 11 cột); cả 11 bảng cộng lại khoảng 0,86 s; mở file + đọc metadata (`tables`) 0,345 s | `.build/release/pbix-dump decode-all` |
| Thời gian giải mã (debug) | Fact_Transaction **19,3 s**, `decode-all` 23,7 s, tức **chậm hơn release khoảng 34 lần** | `.build/debug/pbix-dump` |
| `MemoryLayout<CellValue>.stride` | 24 byte (size 17) | biên dịch thử trong scratchpad |
| Report Nhom6 | 3 trang hiện 36/32/32 visual, 1 trang ẩn 34 visual | `pbix-dump report` |
| Hàm dùng trong 119 measure của closure | IF 142, ISBLANK 98, CALCULATE 83, INT 68, MOD 68, DATE 52, REMOVEFILTERS 40, MAX 39, YEAR 34, MONTH 34, ISFILTERED 34, SWITCH 32, TRUE 32, VALUES 31, DIVIDE 30, BLANK 30, ABS 29, TREATAS 24, FILTER 22, FORMAT 21, SAMEPERIODLASTYEAR 17, KEEPFILTERS 16, SUMMARIZE 12, ALLSELECTED 9, SELECTEDVALUE 7, COUNT 7, SUM 6, SUMX 4, RELATED 4, DISTINCTCOUNT 3, COALESCE 3, COUNTROWS 2, CROSSJOIN 2, HASONEVALUE 2, AVERAGE 1, TOPN 1, CONCATENATEX 1, PERCENTILEX.INC 1, DATEDIFF 1, MINX 1, MAXX 1, ADDCOLUMNS 1, CALCULATETABLE 1, AVERAGEX 1 | `closure.py` (các tên `M`, `AVG`, `OUTSTANDING` là nhiễu do regex bắt trong chuỗi) |
| Thêm khi tính cả 168 measure | RANKX 2, ALL 1, USERELATIONSHIP 1 | regex trên `measures.nhom6.dax` |
| Nhóm 3 / Nhóm 2 | Cần thêm **DATEADD** (10 và 2 lần), AVERAGE, DISTINCTCOUNT, COUNTROWS, QUARTER, MIN | `pbix-dump measures --dax` |
| FormatString của measure Nhom6 | `#,0` (24), `$#,0` (21), `+0.0%;-0.0%;0.0%` (17), `0.0%` (7), `#,0.0` (3), `0%`, `0`, `0.0`, `0 "tháng"`, `+0.0;-0.0;0.0` | `measures.nhom6.dax` |
| Chuỗi FORMAT trong biểu thức | `"0.0%"`, `"0%"`, `"0.0"`, `"$#,0.0"`, `"#,0"`, `"#,0.0"` | như trên |
| Cú pháp đặc biệt gặp trong file thật | đối số rỗng `RANKX(..., [Loan Amount], , DESC, DENSE)`; số mũ `1e6`; cột ảo `[@c]` sau ADDCOLUMNS; VAR lồng trong đối số của SUMX; chuỗi chứa SVG data-URI dài | `measures.nhom6.dax` dòng 482, 553, 231, 473, 1084 |
| Truy vấn mẫu trong UI | `DAXQueryTab.starter` gọi `[Transaction Count]`, nhưng Nhom6 không có measure này (tên đúng là `[Trans Count]` = `SUM(Fact_Transaction[trans_count])`). Binder phải báo lỗi tên rõ ràng, còn truy vấn mẫu cần sửa | `DocumentState.swift`, `measures.nhom6.dax:690` |
| Test framework | swift-testing (`import Testing`) chạy được chỉ với CLT | `Tests/PBIXKitTests/PBIXKitTests.swift` |
| `scripts/check-ownership.sh` | đường dẫn TSV **cứng** `docs/phase-w-ownership.tsv` → cần thêm tham số hoặc biến môi trường cho Phase B | đọc script |

Hệ quả cho cách làm: test chạy trên Nhom6 phải build bằng `-c release` (hoặc dùng cache cột đã giải mã). Test đơn vị của từng agent chạy trên model nhỏ dựng trong bộ nhớ (§8.4), không mở file 90 MB.

---

## 2. ColumnStore

### 2.1 Biểu diễn cột

Code hiện có: `DecodedColumn.Storage` gồm `.dictionary(codes: [Int32], dictionary: [CellValue])` (mã -1 là null), `.values([Double])` (NaN là null) và `.empty(count:)`. `CellValue.decimal` lưu dạng `Double` đã chia 10⁴. [FACT]

Thiết kế cho engine:

```swift
public enum Codes: Sendable {            // 0 = BLANK, k = dictionary[k-1]
    case u8([UInt8]), u16([UInt16]), u32([UInt32])
}
public enum TypedDictionary: Sendable {
    case integers([Int64]), doubles([Double]), currency([Int64]) /* ×10⁴, số nguyên */,
         dates([Double]) /* ngày OLE */, booleans([Bool]), strings(StringPool)
}
public enum ColumnPayload: Sendable {
    case encoded(Codes, TypedDictionary)
    case dense(DenseValues)              // cột mã hoá theo giá trị, cardinality cao
    case allBlank
}
public enum DenseValues: Sendable {
    case integers([Int64], blanks: RowSet?), doubles([Double]) /* NaN = BLANK */, dates([Double])
}
public struct StringPool: Sendable {     // UTF-8 liền một khối + offset
    public let bytes: [UInt8]; public let offsets: [UInt32]
}
```

- **Giữ mã dictionary**, vì gom nhóm, lọc theo giá trị, VALUES, DISTINCTCOUNT và lan truyền quan hệ đều làm trên số nguyên. Muốn so sánh hay sắp xếp thì dùng thêm bảng `sortRank[code]` (tính lười, sắp theo collation không phân biệt hoa thường cho chuỗi).
- **Cột mã hoá theo giá trị** (`amount`, `balance_after`, `trans_key`) để dạng `dense`. Lý do: SUM/MIN/MAX trên mảng Double với bitset là nhanh nhất, và cột này hiếm khi được dùng để gom nhóm. Cần lọc theo giá trị (ví dụ `balance_after < 0`) thì quét trực tiếp, khoảng 1 ms cho 1 triệu dòng [SUY ĐOÁN].
- **Kiểu**: `int64` → `.integers`; `double` → `.doubles`; `decimal` → `.currency(Int64)`, đổi từ `CellValue.decimal` bằng `round(v × 10⁴)` để cộng chính xác; `dateTime` → `.dates`; `boolean` → `.booleans`; `string` → `.strings`.
- **BLANK**: mã 0 hoặc NaN. Chuỗi rỗng `""` **khác** BLANK, giữ nguyên như một giá trị dictionary [DOC desktop-data-types].
- **Dòng trống ảo của quan hệ không lưu vào cột.** Nó là chỉ số `rowCount` trong universe RowSet của bảng (§3.2), và `value(at: rowCount)` trả `.blank`.
- **Chỉ mục phụ (lười, mỗi cột):** `sortRank`, `code(of: Value)` (hash ngược giá trị → mã), `postings` (mã → danh sách dòng tăng dần, tổng cộng `rowCount` phần tử `UInt32` + `distinct+1` offset), `uniqueRowOfCode` cho cột khoá phía một.

Bộ chuyển đổi `PBIXColumnSource` (trong target ColumnStore) gọi `VertiPaq.decodeColumn(_:abf:)` cho từng cột (đã `public`) [FACT], rồi đổi mã `-1 → 0`, `k → k+1`, chọn độ rộng theo `dictionary.count + 1`, và đổi `[CellValue]` sang dictionary có kiểu. Không cần sửa PBIXKit. Về sau, nếu muốn bớt một lần cấp phát `[Int32]`, có thể thêm vào PBIXKit một API `decodeColumnCodes` ghi thẳng vào bộ đệm. Việc đó do lead làm, chỉ là tối ưu.

### 2.2 Nạp lười và chia sẻ

- `ColumnStore.column(_:)` nạp đúng một lần cho mỗi cột (khoá theo cột hoặc `OnceCell`), an toàn khi nhiều luồng gọi.
- `prefetch(_ ids: Set<ColumnID>) async`: binder thu tập cột mà truy vấn hay trang report cần, rồi giải mã song song bằng `TaskGroup`. Hiện `Workspace.table(_:)` giải mã **cả bảng** một lần [FACT]; engine nên giải mã theo cột.
- Ước lượng mở Nhom6 [SUY ĐOÁN]: mở + metadata 0,35 s, cộng các cột trang đầu cần (khoảng 6 cột Fact_Transaction và các dim), song song 8 nhân, khoảng 0,15–0,25 s. Chỉ mục quan hệ khoảng 10 ms. **Tổng dưới 1 s** tới khi có số đầu tiên, còn dư so với ngưỡng 2 s. Phải đo bằng `dax-run bench open`.
- **Chia sẻ giữa các cửa sổ:** `ColumnStoreCache.shared` (process-wide) khoá theo (đường dẫn chuẩn hoá, kích thước, mtime, CRC32 của entry `DataModel` trong ZIP), giữ tham chiếu yếu. Hai cửa sổ mở cùng file thì dùng chung store. `ColumnData` là `final class` bất biến, `Sendable`.
- `Workspace` sẽ có `lazy var engine: DAXEngine?`. Việc này lead làm ở đợt 0: một thuộc tính và một stub.

### 2.3 Bộ nhớ ước lượng cho Nhom6

Fact_Transaction, 1.056.320 dòng [số dòng và cardinality là FACT; byte là tính toán]:

| Cột | Biểu diễn hiện tại (`DecodedColumn`) | Biểu diễn đề xuất |
|---|---|---|
| trans_id (chuỗi, 1,06 tr phân biệt) | mã Int32 4,2 MB + `[CellValue]` 25,4 MB | mã u32 4,2 MB + pool khoảng 9,5 MB + offset 4,2 MB = 17,9 MB |
| trans_timestamp (1,01 tr) | 4,2 + 24,4 MB | u32 4,2 + `[Double]` 8,1 MB = 12,3 MB |
| date_key / account_key / client_key | 3 × 4,2 MB | 3 × u16 2,1 MB = 6,3 MB |
| trans_type_key / trans_hour / trans_count | 3 × 4,2 MB | 3 × u8 1,06 MB = 3,2 MB |
| trans_key, amount, balance_after (dense) | 3 × 8,45 MB | 3 × 8,45 MB = 25,3 MB |
| **Cộng** | **khoảng 108 MB** | **khoảng 65 MB** |

- Các bảng khác cộng lại dưới 5 MB.
- Posting list cho 3 khoá FK cộng `account_key`: khoảng 4 × 4,2 MB = 17 MB, chỉ tạo khi cần.
- `fkToPK` cho 4 quan hệ của Fact_Transaction: 4 × 4,2 MB = 17 MB.
- Mỗi bitset Fact_Transaction 132 KB.
- **Tổng engine khoảng 100 MB, chỉ cần hai cột chuỗi khi có truy vấn chạm vào chúng.** `trans_id` và `trans_timestamp` chiếm khoảng 30 MB, nhưng các visual có lẽ không dùng [SUY ĐOÁN].
- Lưới Table view hiện vẫn giữ `[DecodedColumn]` riêng. Về sau nên cho lưới đọc từ ColumnStore để không giữ hai bản dữ liệu (ghi chú cho Phase C/E, không thuộc Phase B).

---

## 3. Quan hệ

### 3.1 Mô hình

```swift
public struct RelationshipSchema: Sendable, Hashable {
    public let id: RelationshipID
    public let many: ColumnID, one: ColumnID      // from = phía nhiều, to = phía một (M:1)
    public let isActive: Bool
    public let crossFilter: CrossFilter           // .single (một→nhiều) | .both
    public let cardinality: Cardinality           // .manyToOne | .oneToOne | .manyToMany
}
```

`ModelMetadata.Relationship` đã có `fromTable/fromColumn/toTable/toColumn/isActive/cardinality ("M:1")/crossFilteringBehavior (1/2)` [FACT]. `ModelSchema.init(metadata:)` ánh xạ sang ID số.

### 3.2 Chỉ mục many→one

```swift
public struct RelationshipIndex: Sendable {
    public let schema: RelationshipSchema
    public let fkToPK: [Int32]        // độ dài = many.rowCount; giá trị = dòng bên one, hoặc one.rowCount (blank row)
    public let hasUnmatched: Bool     // có FK không khớp hoặc FK BLANK
    public let manyPostings: Postings // mã FK → dòng bên many (dùng posting của cột FK)
    public func manyRows(from oneRows: RowSet) -> RowSet   // lan truyền một → nhiều
    public func oneRows(from manyRows: RowSet) -> RowSet   // hai chiều / expanded table
}
```

- **Dựng chỉ mục:** hash giá trị PK → dòng (PK có cardinality bằng số dòng). Sau đó làm mảng `codeToPKRow[codeFK]` trên **dictionary** của FK (date_key chỉ có 2.191 mã), rồi `fkToPK[i] = codeToPKRow[code[i]]`. Tổng là 1 triệu lần tra mảng, khoảng 1–2 ms [SUY ĐOÁN]. So khớp theo giá trị đã ép kiểu: int với int, chuỗi so không phân biệt hoa thường.
- **Một → nhiều:** khi bên một chỉ còn ít dòng (ví dụ lọc 1 tháng, khoảng 30 date_key), hợp các posting list của mã FK tương ứng, chi phí tỉ lệ với số dòng kết quả. Khi bên một còn nhiều dòng, quét `fkToPK` và kiểm tra bit. Chọn theo `cardinality(oneRows) / one.rowCount`.
- **Blank row** [DOC desktop-relationships-understand]: với quan hệ *regular* (M:1 trong cùng nhóm nguồn, import), "khi giá trị bên nhiều không có giá trị khớp bên một, một dòng trống ảo được thêm vào bảng bên một". Quan hệ *limited* (M:M) không thêm. Cài đặt: universe RowSet của mỗi bảng phía một là `rowCount + 1`, bit cuối là blank row và chỉ "tồn tại" khi `hasUnmatched` của một quan hệ regular trỏ vào bảng đó.
  - `VALUES(col)` và `ALL(col)` có giá trị BLANK của blank row; `DISTINCT(col)` và `ALLNOBLANKROW` thì không [DOC values-function-dax, distinct-column-function-dax, allnoblankrow].
  - Tài liệu ghi "Inactive relationships are also expanded". Vì vậy blank row có thể xuất hiện cả khi chỉ quan hệ inactive vi phạm [SUY ĐOÁN, đối chiếu oracle].
- **Active/inactive:** mỗi cặp bảng chỉ có một đường lan truyền active. `USERELATIONSHIP(fk, pk)` trong CALCULATE bật quan hệ inactive. Theo tài liệu về độ ưu tiên đường, nó tăng "weight" của quan hệ đó; lồng càng trong thì weight càng cao. Quan hệ active cũ giữa hai bảng bị tắt trong phạm vi CALCULATE đó [DOC userelationship-function-dax, desktop-relationships-understand §Weight].
- **CROSSFILTER(col1, col2, None|OneWay|Both|OneWay_LeftFiltersRight|OneWay_RightFiltersLeft)** đổi hướng hoặc tắt lan truyền trong phạm vi CALCULATE [DOC crossfilter-function-dax]. Nhom6 không dùng; đưa vào đợt 3 vì rẻ.
- Cả hai được lưu trong `FilterContext.relationshipOverrides: [RelationshipID: RelationshipOverride]`, nên là một phần của khoá cache.
- **Đường mơ hồ:** Nhom6 chỉ có quan hệ một chiều, nên không có mơ hồ [FACT]. Engine cài quy tắc ưu tiên/weight ở mức tối thiểu và báo lỗi `ambiguousPath` khi không quyết được, thay vì đoán.

### 3.3 Lan truyền lọc (tính `visibleRows(T)`)

Gọi `R(T)` là tập dòng thấy được của bảng T trong context F:

```
R(T) = local(T)                                   // AND các bộ lọc trên cột của T
     ∧ ⋀ { manyRows_r( R(O) ) : r active, T = many(r), O = one(r), hướng cho phép }
     ∧ ⋀ { oneRows_r( R'(M) ) : r active hai chiều, T = one(r), M = many(r) }   // R' bỏ qua đường quay về T
     ∧ ⋀ { image của bộ lọc .rows(S, …) qua expanded table nếu T thuộc expanded(S) } // §4.4
```

- Đệ quy theo hướng "về phía một" (star và snowflake). Nhớ đệm từng `R(T)` trong context, và context cũng được cache theo dấu vân tay. Đồ thị có chu trình qua quan hệ hai chiều thì đánh dấu đã thăm để tránh lặp; đường mơ hồ thì báo lỗi.
- Nhiều bộ lọc trên cùng bảng luôn được AND với nhau [DOC desktop-relationships-understand: "it's always an AND operation"].

---

## 4. Filter context, row context, context transition

### 4.1 Biểu diễn

```swift
public struct CodeSet: Sendable, Hashable { /* bitset trên mã dictionary 0…distinct; mã 0 = BLANK */ }
public struct TupleSet: Sendable, Hashable { /* tập tuple mã, dùng hash */ }

public enum FilterItem: Sendable, Hashable {
    case values(ColumnID, CodeSet)              // một cột: slicer, ô SUMMARIZECOLUMNS, col = x, TREATAS 1 cột
    case tuples([ColumnID], TupleSet)           // nhiều cột (TREATAS 2 cột, SUMMARIZE): "arbitrarily shaped"
    case rows(TableID, RowSet)                  // bộ lọc theo bảng (FILTER(Fact, …), biến bảng): lọc expanded table
}
public struct FilterContext: Sendable, Hashable {
    public private(set) var items: [FilterItem]                 // AND; đã chuẩn hoá thứ tự để băm ổn định
    public private(set) var relationshipOverrides: [RelationshipID: RelationshipOverride]
    public var fingerprint: UInt64 { get }                      // khoá cache
}
```

- Cột dense (giá trị) không có mã. Khi bị lọc theo giá trị, engine dựng `CodeSet` ảo bằng cách ánh xạ giá trị → mã qua một dictionary phụ, hoặc lưu `.rows(table, RowSet)` được gắn nhãn là bộ lọc của cột đó (trường `lineageColumns`). Đơn giản nhất: cho phép `.values(col, …)` mang `ValueSet` kiểu `[Value]` khi cột là dense.
- **Ghi đè (CALCULATE không KEEPFILTERS):** với bộ lọc mới trên tập cột C, xoá các bộ lọc cũ trên C. Bộ lọc cũ nhiều cột nào chạm C thì bị **chiếu bỏ** các cột thuộc C (giữ phần còn lại). Đây là cách context "mất hình dạng" [DOC SQLBI arbitrarily-shaped filters; calculate-function-dax].
- **KEEPFILTERS(f):** thêm f mà không xoá gì, tức là giao với cái đang có [DOC keepfilters-function-dax].
- **REMOVEFILTERS/ALL như modifier:**
  - `(col…)`: xoá bộ lọc trên các cột đó (chiếu nếu là bộ lọc nhiều cột).
  - `(T)`: xoá mọi bộ lọc trên **các cột của expanded T**, gồm cả các bảng phía một mà T tới được. Hệ quả: `REMOVEFILTERS(Fact_Transaction)` xoá luôn bộ lọc trên các dim; `REMOVEFILTERS(Dim_Date)` chỉ xoá bộ lọc trên Dim_Date vì Dim_Date không có quan hệ đi ra [DOC SQLBI expanded tables].
  - `()`: xoá hết.
- **ALL như hàm bảng:** trả mọi giá trị hoặc dòng, bỏ qua context, kèm blank row nếu có.
- **TREATAS(table, col1, …, colN):** đổi lineage các cột của bảng kết quả sang các cột đích, rồi dùng như bộ lọc `.values` (1 cột) hoặc `.tuples` (N cột). Giá trị không có trong cột đích thì bị bỏ [DOC treatas-function]. Nhom6 dùng 24 lần, chủ yếu `TREATAS(SUMMARIZE(Dim_District, city, state_name), Dim_Account[branch_city], Dim_Account[branch_state_name])`, tức là tuple 2 cột trên cùng một bảng: lọc dòng Dim_Account có (city, state) thuộc tập.
- **Predicate trong CALCULATE** (`Dim_Date[MonthIndex] > mi - 3`): theo tài liệu, tương đương `FILTER(ALL(Dim_Date[MonthIndex]), …)`, tức là **bỏ qua** bộ lọc hiện có trên cột đó rồi ghi đè. Có KEEPFILTERS thì là `FILTER(VALUES(col), …)` và giao [DOC calculate-function-dax, SQLBI filter-arguments]. Cài: duyệt dictionary của cột (≤ vài nghìn mã), đánh giá predicate với từng giá trị, ra `CodeSet`. Predicate nhiều cột cùng bảng thì ra `.tuples`.

### 4.2 Row context

```swift
public struct RowFrame: Sendable {
    public let table: TableValue         // bảng đang lặp (cơ sở hoặc ảo)
    public let row: Int                  // vị trí trong bảng
}
public struct RowContext: Sendable { public var frames: [RowFrame] }   // ngăn xếp: iterator lồng nhau
```

- `Table[col]` trong row context tra frame **gần nhất** có cột đó (theo lineage hoặc tên cột ảo như `[@c]`). Không có thì báo lỗi "A single value for column … cannot be determined" [DOC].
- `RELATED(D[col])`: từ frame của bảng nhiều, đi theo quan hệ active M:1 (`fkToPK`) để lấy giá trị. `RELATEDTABLE`: hướng ngược lại, bằng context transition rồi trả bảng.
- `EARLIER` không có trong 3 file mẫu [FACT], hoãn lại.

### 4.3 Context transition

Khi gọi measure, `CALCULATE` hoặc `CALCULATETABLE` lúc đang có row context, mỗi frame được đổi thành bộ lọc. Bộ lọc này **được thêm trước** các đối số filter của CALCULATE, nên đối số của CALCULATE ghi đè được nó [DOC SQLBI understanding-context-transition; calculate-function-dax]:

- **Frame của bảng cơ sở T:** lọc mọi cột của T theo giá trị dòng hiện tại. Bảng có cột duy nhất (`Statistics_DistinctStates == rowCount`, hoặc `IsKey`) thì tương đương `.rows(T, {row})` (rẻ). Bảng có dòng trùng thì mọi dòng trùng đều thấy, đúng ngữ nghĩa công khai. Cài đặt: dùng posting list của cột có cardinality cao nhất, rồi lọc bằng so sánh các cột còn lại.
- **Frame của bảng ảo** (VALUES, SUMMARIZE, ADDCOLUMNS, CROSSJOIN): mỗi cột có lineage tạo một `.values(col, {code})`. Cột không có lineage (`"@c"`) bị bỏ qua.
- **Measure luôn có CALCULATE ngầm**, nên `[m]` trong iterator luôn kích hoạt transition.

### 4.4 Expanded table

[DOC SQLBI expanded-tables; desktop-relationships-understand "Table expansion"]: bảng T mở rộng gồm cột của T cộng cột của mọi bảng phía một tới được qua quan hệ regular (kể cả inactive), với ngữ nghĩa LEFT OUTER JOIN (blank row). Hệ quả cho cài đặt:

1. Bộ lọc `.rows(T, S)` (ví dụ `CALCULATE(…, FILTER(Fact_Loan, RELATED(Dim_Loan_Profile[is_active]) = 1))`) lọc cả các cột dim trong expanded T, nên ảnh hưởng tới `VALUES(Dim_Loan_Profile[…])` trong context mới: `R(D) ∧= oneRows_r(S)`.
2. `ALL(T)` / `REMOVEFILTERS(T)` xoá bộ lọc trên mọi cột của expanded T (xem §4.1).
3. `RELATED` được phép vì cột phía một thuộc expanded T.

### 4.5 ALLSELECTED và shadow filter context

[DOC allselected-function-dax; SQLBI definitive-guide-to-allselected]

- Mỗi iterator (SUMX, AVERAGEX, MINX, MAXX, FILTER, ADDCOLUMNS, CONCATENATEX, RANKX, PERCENTILEX.INC, GENERATE, cùng vòng lặp nhóm của **SUMMARIZECOLUMNS**) tạo một **shadow filter context** khi bắt đầu lặp. Shadow là "dòng thấy được lúc bắt đầu lặp", ở trạng thái ngủ và không ảnh hưởng gì nếu không có ALLSELECTED.
- `ALLSELECTED(col)` trả hoặc khôi phục giá trị cột "thấy được trong shadow filter context **gần nhất** có lọc cột đó". Không có shadow nào thì trả mọi giá trị. `ALLSELECTED(T)`: với mỗi cột có shadow, dùng shadow gần nhất; cột không có shadow giữ bộ lọc tường minh. `ALLSELECTED()`: mọi cột.
- ALLSELECTED **không** gỡ bộ lọc do context transition tạo ra. Kết quả "có vẻ gỡ" là vì nó biến shadow thành bộ lọc tường minh và ghi đè lên bộ lọc cùng cột (SQLBI đã đính chính điểm này).

Cài đặt:

```swift
public struct ShadowStack: Sendable {
    public var frames: [FilterContext]       // push khi iterator bắt đầu, pop khi kết thúc
    func lastFilter(on col: ColumnID) -> FilterItem?   // tìm ngược frame gần nhất có lọc col
}
```

- Là modifier của CALCULATE: `.allSelected(cols)` khi áp vào context thì xoá bộ lọc hiện tại trên `cols`, rồi thêm lại bộ lọc của shadow gần nhất trên từng cột.
- Là hàm bảng: trả `VALUES(col)` được đánh giá trong context dựng từ shadow đó.
- **Truy vấn của visual:** SUMMARIZECOLUMNS đẩy shadow *sau khi* áp các filter table (slicer, bộ lọc trang) và *trước khi* áp bộ lọc của từng ô nhóm. Nhờ vậy `CALCULATE([Trans Count], ALLSELECTED(Dim_Trans_Type))` cho ra tổng của các loại đang chọn trên slicer. Điều này khớp ví dụ NONVISUAL/ALLSELECTED trong tài liệu SUMMARIZECOLUMNS [DOC].
- **Shadow vào khoá cache:** một measure dùng ALLSELECTED (xét cả closure) thì cache theo (context, dấu vân tay shadow). Binder đánh dấu `usesAllSelected` cho mỗi measure.
- Ca khó trong Nhom6 [FACT]:
  - `[Pareto Cum %]`: `ADDCOLUMNS(ALLSELECTED(Dim_CRM_Issue[issue]), "@c", [Complaints])`, sau đó `SUMX(FILTER(tbl, …))` trên biến bảng.
  - `[Peak Hour Color]`: `CROSSJOIN(ALLSELECTED(Fact_Transaction[trans_hour]), ALLSELECTED(Dim_Date[day_name]))`, ALLSELECTED trên cột **của bảng fact**.
  - `[Trans Heat Color]`: `ALLSELECTED(Dim_Account)` theo bảng.

### 4.6 ISFILTERED, HASONEVALUE, SELECTEDVALUE

- `ISFILTERED(col)`: có `FilterItem` **trực tiếp** chứa col (cột nhóm của SUMMARIZECOLUMNS cũng tính). `ISFILTERED(T)`: có cột nào của T bị lọc trực tiếp. `ISCROSSFILTERED`: R(T) khác toàn bộ [DOC isfiltered-function-dax]. Nhom6 dùng ISFILTERED 34 lần để đổi trường; sai chỗ này thì cả nhóm measure `D4 *` sai.
- `HASONEVALUE(col)` ⇔ `COUNTROWS(VALUES(col)) = 1`. `SELECTEDVALUE(col, alt)` tương tự, trả giá trị hoặc `alt`.

---

## 5. Ngôn ngữ

### 5.1 Lexer (`Syntax/Lexer.swift`)

Token:
- định danh trần (`Dim_Date`, `TRUE`, `DESC`) và `'quoted table'` (escape `''`);
- `[cột hoặc measure]` (escape `]]`);
- chuỗi `"…"` (escape `""`);
- số `123`, `0.8`, `1e6`, `.5`;
- toán tử `+ - * / ^ & = == <> < > <= >= && || ,  ( ) { }` và `IN`, `NOT`;
- chú thích `//`, `--`, `/* */`.

Mỗi token mang `SourceRange` (dòng, cột, offset UTF-16 để NSTextView tô lỗi).

### 5.2 Parser và AST (`Syntax/AST.swift`, đóng băng ở đợt 0; `Syntax/Parser.swift`)

Recursive descent kèm bảng ưu tiên toán tử, từ cao xuống thấp [DOC dax-operator-reference]: `^` → dấu một ngôi `-`/`+` → `* /` → `+ -` → `&` → `= == <> < > <= >= IN` → `NOT` → `&&` → `||`.

```swift
public struct SourceRange: Sendable, Hashable { public let start: Int, end: Int }   // offset UTF-16
public indirect enum Expr: Sendable, Hashable {
    case number(Double, isInteger: Bool, SourceRange)
    case string(String, SourceRange)
    case boolean(Bool, SourceRange)
    case columnRef(table: String?, column: String, SourceRange)     // T[c] hoặc [c]
    case bracketRef(name: String, SourceRange)                       // [x]: measure hoặc cột ảo, binder quyết
    case tableRef(String, SourceRange)
    case identifier(String, SourceRange)                             // tên VAR, hoặc từ khoá đối số (DESC, DENSE, YEAR)
    case call(name: String, args: [Expr?], SourceRange)             // nil = đối số bỏ trống (RANKX …, , DESC)
    case unary(UnaryOp, Expr, SourceRange)
    case binary(BinaryOp, Expr, Expr, SourceRange)
    case varBlock(vars: [(name: String, value: Expr)], body: Expr, SourceRange)
    case tableConstructor(rows: [[Expr]], SourceRange)               // {1,2} hoặc {(1,"a"),(2,"b")}
}
public struct Query: Sendable {
    public var defines: [Definition]
    public var statements: [Evaluate]
}
public enum Definition: Sendable {
    case measure(table: String, name: String, Expr)
    case variable(name: String, Expr)
    case column(table: String, name: String, Expr)
    case table(name: String, Expr)
}
public struct Evaluate: Sendable {
    public var table: Expr
    public var orderBy: [(Expr, ascending: Bool)]
    public var startAt: [Expr]
}
public enum ParseResult { case expression(Expr), query(Query) }
public func parseExpression(_ text: String) throws(DAXError) -> Expr
public func parseQuery(_ text: String) throws(DAXError) -> Query
```

Hai lưu ý từ dữ liệu thật [FACT]: đối số rỗng (`, ,`) và VAR lồng trong đối số hàm.

`(String, Expr)` không tự `Hashable`, nên Contracts dùng `struct VarBinding: Hashable { name; value }`.

### 5.3 Binder (`Semantic/Binder.swift`, `Semantic/Catalog.swift`)

- **Tra tên không phân biệt hoa thường** cho bảng, cột, measure, hàm và VAR.
- **`[x]` không có bảng:**
  1. Nếu có measure tên x (trong model hoặc `DEFINE MEASURE`), đó là measure. Tên measure là duy nhất trong model.
  2. Nếu không, tìm cột ảo hoặc cột của bảng trong row context theo phạm vi tĩnh. Với `ADDCOLUMNS(..., "@c", …)`, binder biết tên cột ảo của bảng nhờ suy kiểu bảng.
- **`T[c]`:** cột của T, cột `DEFINE COLUMN`, hoặc measure `T[m]` (DAX cho phép viết measure kèm tên bảng).
- **Kiểm tra từng hàm theo `FunctionSpec.params`** (§8.3): số đối số, đối số nào phải là tham chiếu cột hoặc bảng (ALL, VALUES, TREATAS đích, USERELATIONSHIP), đối số nào được đánh giá lười.
- **Lỗi có vị trí:** `unknownTable`, `unknownColumn`, `unknownMeasure`, `unknownFunction` (thông báo "hàm chưa hỗ trợ: X", đúng mục rủi ro trong BIPRO_BUILD_PLAN §7), `arity`, `expectedColumnRef`, `circularMeasure` (phát hiện chu trình measure ngay khi bind).
- **Kết quả bind:** `BoundExpr` với ID số (`ColumnID`, `MeasureID`, `slot` cho VAR, `FunctionID`), kèm `referencedColumns` để prefetch và cờ `usesAllSelected`/`usesShadow`.
- **Bind lười cho measure của model:** chỉ bind khi lần đầu cần, rồi cache. Measure lỗi không làm hỏng cả model.

### 5.4 Evaluator (`Runtime/Evaluator.swift`)

```swift
public struct EvalContext: Sendable {
    public unowned(unsafe) let engine: EngineCore   // hoặc let, vì EngineCore là class Sendable
    public var filter: FilterContext
    public var rows: RowContext
    public var shadows: ShadowStack
    public var vars: VarFrame                        // slot → Value | TableValue (bất biến, lười)
}
public protocol Evaluating {
    func scalar(_ e: BoundExpr, _ ctx: EvalContext) throws(DAXError) -> Value
    func table(_ e: BoundExpr, _ ctx: EvalContext) throws(DAXError) -> TableValue
    func calculate(_ e: BoundExpr, modifiers: [BoundExpr], _ ctx: EvalContext) throws(DAXError) -> Value
}
```

- Tree-walking trên `BoundExpr`, vì đơn giản trước. VAR được đánh giá **lười một lần** trong context lúc khai báo (đúng ngữ nghĩa: biến bắt context tại chỗ định nghĩa) [DOC var-dax].
- `TableValue`:
  - `.base(TableID, RowSet)`: view lười trên bảng cơ sở.
  - `.columns([TableColumn], rows: ColumnarRows)`: vật chất hoá; mỗi cột có `lineage: ColumnID?`, `name`, `type`, lưu mã khi có lineage và lưu `Value` khi không.
  - `.rowsOf(TableID, [Int32])`.
- **Thứ tự trong CALCULATE** [DOC calculate-function-dax]:
  1. Đánh giá các đối số filter trong context **ban đầu**, cả row context.
  2. Context transition.
  3. Áp modifier: REMOVEFILTERS/ALL/ALLSELECTED/USERELATIONSHIP/CROSSFILTER.
  4. Áp đối số filter: ghi đè, hoặc giao nếu có KEEPFILTERS.
  5. Đánh giá biểu thức.

### 5.5 Kiểu, ép kiểu, BLANK, lỗi

```swift
public enum Value: Sendable, Hashable {
    case blank, integer(Int64), double(Double), currency(Int64) /* ×10⁴ */, string(String), boolean(Bool), dateTime(Double)
}
```

Các quy tắc dưới đây lấy từ tài liệu [DOC desktop-data-types "Handling blanks…" và "Implicit and explicit data type conversion"; dax-operator-reference]. **Mọi dòng phải có test đối chiếu oracle**, vì tài liệu không đủ chi tiết:

- **Số học:**
  - integer ⊕ integer → integer (`+ - *`); `/` luôn ra double.
  - Có double thì ra double. currency với integer ra currency; currency với double ra double [SUY ĐOÁN, cần oracle].
  - Chuỗi trong phép số học được ép sang số (`"1" + 1 = 2`), không ép được thì báo lỗi.
- **BLANK:**
  - `BLANK + 5 = 5`, `BLANK − 5 = −5`, `BLANK × 5 = BLANK`, `BLANK / 5 = BLANK`, `5 / BLANK = ∞`, `0 / BLANK = NaN`, `BLANK / BLANK = BLANK`.
  - `BLANK && TRUE = FALSE`, `BLANK || TRUE = TRUE`.
  - `BLANK = 0` là TRUE và `BLANK = ""` là TRUE; `ISBLANK(0)` là FALSE.
  - `&` biến BLANK thành `""`.
- **Chia 0:** `/` cho ra `±∞` hoặc NaN, không báo lỗi. `DIVIDE(a, b[, alt])` trả `alt` (mặc định BLANK) khi b = 0 hoặc b BLANK [DOC divide-function-dax]. Nhom6 dùng DIVIDE 30 lần.
- **So sánh:**
  - Số so với số; ngày được coi như số.
  - Chuỗi so theo collation **không phân biệt hoa thường** của model.
  - So chuỗi với số thì **báo lỗi** ("DAX comparison operations do not support comparing values of type Text with values of type Integer").
  - BLANK được coi như 0, `""` hoặc FALSE, tuỳ vế bên kia.
- **Lỗi:** `DAXError` lan ra ngoài. `IFERROR`/`ISERROR` không có trong 3 file mẫu [FACT], làm sau.
- **Hàm ngày:**
  - `DATE(y, m, d)` cho phép tràn tháng và ngày (DATE(2018, 13, 1) = 2019-01-01) [DOC date-function-dax].
  - `INT` làm tròn xuống. `MOD` có dấu theo số chia [DOC mod-function-dax].
  - Nhom6 dùng INT/MOD/DATE để tách `date_key` dạng yyyymmdd (68/68/52 lần).

### 5.6 Định dạng số (`Format/FormatString.swift`)

Một bộ máy dùng cho cả `FORMAT()`, ô kết quả của DAX Query View và nhãn visual (Phase C):

- **Định dạng tùy biến** [DOC custom-numeric-formats-for-the-format-function]:
  - tối đa 3 phần, phân tách bằng `;` (dương, âm, 0);
  - `0` và `#`, `.`;
  - `,` để phân nhóm hàng nghìn, và `,` cuối để chia 1000;
  - `%` nhân 100;
  - literal trong `"…"` hoặc sau `\`;
  - `$`, `+`, `-` và khoảng trắng là literal;
  - `E+0`.
- **Định dạng đặt tên** [DOC pre-defined-numeric-formats]: `General Number`, `Currency`, `Fixed`, `Standard`, `Percent`, `Scientific`, `Yes/No`, `True/False`, `On/Off`.
- **Định dạng ngày cơ bản:** `d dd ddd dddd m mm mmm mmmm yy yyyy h hh nn ss AM/PM`.
- **Culture:** model `en-US` [FACT], nên dấu thập phân là `.` và phân nhóm là `,`. Contract nhận `Culture` để sau này hỗ trợ `vi-VN`.
- **Kiểm thử:** bảng golden cho 10 FormatString thật của Nhom6 (§1), với giá trị âm, 0, BLANK, ∞, và giá trị nằm đúng ngưỡng làm tròn 0,5.
- **Làm tròn:** ghi nhận là rủi ro (§10). VB/OLE dùng làm tròn nửa xa 0 hay làm tròn kiểu ngân hàng? Cần oracle [SUY ĐOÁN].
- BLANK qua FORMAT ra `""`.

---

## 6. Truy vấn

- **`EVALUATE <table expr>`:** nhiều câu EVALUATE trả nhiều bảng kết quả. Hàng đầu là tên cột, viết `Table[col]` cho cột có lineage, `[name]` cho cột ảo [DOC dax-queries].
- **`DEFINE MEASURE T[m] = …`:** ghi đè hoặc thêm measure **trong phạm vi truy vấn**, nhờ catalog nhiều lớp (model ← query). Dùng cho tính năng "Định nghĩa và đánh giá" đã có ở UI.
  - `VAR` toàn truy vấn.
  - `COLUMN T[c] = …`: cột tính toán tạm, tính theo row context của T và vật chất hoá lười.
  - `TABLE t = …`: bảng tính toán tạm.
- **`ORDER BY e [ASC|DESC], …`:** sắp theo giá trị; BLANK đứng đầu khi ASC [SUY ĐOÁN, oracle]; chuỗi không phân biệt hoa thường. Cột có `sortByColumnID` (ví dụ `month_name` → `month_num` [FACT từ Phase A]) **không** tự sắp theo cột kia trong DAX query; đó là việc của visual (Phase C).
- **`START AT v1, …`:** bỏ các dòng đứng trước bộ giá trị theo thứ tự ORDER BY [DOC dax-queries].
- **SUMMARIZECOLUMNS** [DOC summarizecolumns-function-dax]:
  1. Tách đối số thành groupBy (tham chiếu cột), filterTable (biểu thức bảng) và cặp (tên, biểu thức).
  2. Áp filterTable vào context (ghi đè; có `KEEPFILTERS` thì giao), rồi đẩy shadow (§4.5).
  3. Tạo tổ hợp nhóm. Cột cùng bảng thì **auto-exist** (chỉ lấy tổ hợp tồn tại; hiện thực bằng tuple mã phân biệt trên dòng thấy được). Cột khác bảng thì crossjoin.
  4. Đánh giá biểu thức cho từng ô với bộ lọc `.values(col, {code})` của từng cột nhóm.
  5. Bỏ những dòng mà **mọi** biểu thức (trừ `IGNORE`) đều BLANK. Không có biểu thức nào thì chỉ trả tổ hợp nhóm.
  6. `ROLLUPADDISSUBTOTAL`, `ROLLUPGROUP`, `NONVISUAL`: tuỳ chọn, để đợt 4. Ngữ nghĩa "SelfValue" bản 06/2024 (bộ lọc từ bảng khác không lọc cột nhóm) ghi vào bộ test.
  - Tối ưu theo nhóm: §7.2.
- **TOPN(n, table, orderBy, [order], …):** giữ cả các dòng hoà ở vị trí cuối (có thể trả nhiều hơn n dòng) [DOC topn-function-dax].
- **Kết quả cho UI:**

```swift
public struct QueryResult: Sendable {
    public struct Column: Sendable { public let name: String; public let type: DAXType; public let formatString: String? }
    public let tables: [ResultTable]          // mỗi EVALUATE một bảng
    public let elapsed: Duration
    public let diagnostics: [DAXDiagnostic]   // cảnh báo không chặn
}
public struct ResultTable: Sendable {
    public let columns: [QueryResult.Column]
    public let rowCount: Int
    public subscript(row: Int, column: Int) -> Value { get }   // lưu theo cột
    public func formatted(row: Int, column: Int) -> String     // dùng FormatString của measure
}
```

Lưới kết quả nên dùng NSTableView (quyết định §4.4 của BIPRO_BUILD_PLAN) và đọc thẳng `ResultTable` theo kiểu ảo, không chép ra `[[String]]`.

---

## 7. Thực thi và tối ưu

### 7.1 Đơn giản trước

- **Tổng hợp:** `SUM(T[c])` = duyệt `R(T)` (bitset hoặc thưa) cộng cột. Cột encoded dùng `dictionary[code]`, kèm bảng cộng sẵn theo mã khi tập dòng lớn: đếm số dòng theo mã rồi nhân, chỉ đáng khi cardinality nhỏ. Cột dense dùng vòng lặp SIMD-friendly.
- **Đếm:**
  - COUNTROWS(T) là popcount.
  - DISTINCTCOUNT là bitset trên mã.
  - COUNT(col) đếm giá trị không BLANK.
  - Kết quả là `.integer`.
- **Chọn biểu diễn RowSet:** dense bitset khi mật độ trên 1/32; dưới mức đó dùng mảng `[UInt32]` đã sắp. Giao và hợp làm trực tiếp giữa hai dạng.

### 7.2 Gom nhóm (SUMMARIZECOLUMNS, hoặc truy vấn visual ở Phase C)

- **Đường chung:** mỗi ô nhóm là một lần đánh giá measure với context riêng. Cache measure (§7.4) chặn tính trùng.
- **Đường nhanh "tổng hợp đơn giản":**
  - Điều kiện: biểu thức là `SUM/COUNT/COUNTROWS/MIN/MAX/DISTINCTCOUNT` của một cột fact, và chỉ đi qua các modifier không phụ thuộc ô.
  - Cách làm: một lần quét `R(fact)` của context gốc, tính khoá nhóm từ `fkToPK` và mã cột nhóm, cộng dồn vào bảng băm theo nhóm. Đây là kiểu "storage engine" của VertiPaq: một lần quét cho mọi ô, thay vì N lần.
  - Phạm vi: 14 trên 168 measure là "tổng hợp đơn giản hoặc DIVIDE của hai measure" theo regex thô [FACT], nhưng các measure khác thường quy về các measure gốc này qua cache [SUY ĐOÁN]. Làm ở đợt 4, sau khi đã đúng.
- **Song song:** chia tổ hợp nhóm thành khối và đánh giá bằng `TaskGroup`. `EvalContext` là kiểu giá trị; cache dùng chung có khoá phân mảnh (lock striping). Các visual của một trang cũng chạy song song.

### 7.3 Ca nặng có thật trong Nhom6 [FACT biểu thức; SUY ĐOÁN chi phí]

| Measure | Hình dạng | Chi phí ngây thơ | Cách giảm |
|---|---|---|---|
| `Closing_Balance`, `Avg_Account_Balance` | `SUMX(VALUES(Fact_Transaction[account_key]) /*4.500*/, CALCULATE(MAX(trans_timestamp)) rồi CALCULATE(MAX(balance_after), trans_timestamp = t))` | 4.500 × 2 lần quét 1 triệu dòng = 9·10⁹ phép cho **mỗi ô** | Transition trên `account_key` dùng posting list (khoảng 235 dòng mỗi tài khoản), giao với R(fact) của ô. `trans_timestamp = t` dùng posting của timestamp. Tổng khoảng 1 triệu phép mỗi ô. Biểu đồ theo tháng (72 ô) mất khoảng 70–150 ms trên một nhân, nên cần song song và cache. **Điểm đo số 1.** |
| `Pareto Cum %` | ADDCOLUMNS trên các issue (58), mỗi issue gọi [Complaints] một lần, sau đó FILTER cộng dồn; visual có 58 ô | 58 × 58 = 3.364 lần đánh giá measure | Biến `tbl` được cache theo context của ô. `[Complaints]` theo issue được cache chung giữa các ô có cùng shadow |
| `Peak Hour Color`, `Trans Count (k)` grid | CROSSJOIN 10 giờ × 7 thứ = 70 ô, mỗi ô của heatmap 70 ô lặp lại cả lưới | 70 × 70 = 4.900 lần đánh giá [Trans Count] | Cache: chỉ 70 context phân biệt, nên tới khoảng 70 lần tính thật |
| `Complaints Δ` và 17 measure SAMEPERIODLASTYEAR | YTD hiện tại và cùng kỳ năm trước, đều có REMOVEFILTERS(Dim_Date) | 2 lần lọc Dim_Date (2.922 dòng) cộng 2 lần tổng hợp | Rẻ; rủi ro nằm ở ngữ nghĩa, không phải tốc độ |

### 7.4 Cache

- **`MeasureCache`:** khoá là `(MeasureID, filter.fingerprint, usesShadow ? shadows.fingerprint : 0)` → `Value`. Có giới hạn kích thước (LRU khoảng 100k mục), sống theo `EngineCore`, và bị xoá khi model đổi (Phase E).
- **`RowSetCache`:** khoá `(TableID, filter.fingerprint)` → `RowSet`, cộng thêm `(ColumnID, CodeSet hash)` → `RowSet` cục bộ.
- **Vân tay:** băm có thứ tự chuẩn của các item (sắp theo ColumnID). CodeSet băm theo nội dung bitset, tính một lần lúc tạo.
- **Đúng đắn:** measure phụ thuộc row context mà không có transition, ví dụ `Table[col]` trần trong measure, thì báo lỗi. Vì vậy cache theo filter context là an toàn.

### 7.5 Điểm cần đo (`dax-run bench`, build release)

1. Mở file: tới lúc có metadata, rồi tới lúc prefetch xong các cột trang D1 (mục tiêu dưới 2 s, kỳ vọng dưới 1 s).
2. Giải mã từng cột và chuyển đổi sang `ColumnData` (MB/s).
3. Dựng `RelationshipIndex` cho 14 quan hệ.
4. `visibleRows(Fact_Transaction)` dưới các bộ lọc: 1 năm, 1 tháng, 1 tài khoản, có TREATAS.
5. Thời gian từng visual và cả trang D1/D2/D3 (36/32/32 visual), cả lạnh (cache trống) lẫn nóng, mục tiêu dưới 150 ms. Kèm tỉ lệ trúng cache.
6. RSS bộ nhớ sau khi mở và sau khi duyệt 3 trang.
7. 119 measure × lưới `SUMMARIZECOLUMNS(Dim_Date[year], …)`: tổng thời gian, và 10 measure chậm nhất.

---

## 8. Chia module để nhiều agent làm song song

### 8.1 Target SwiftPM

Lead sửa `Package.swift` một lần ở đợt 0:

```swift
.target(name: "ColumnStore", dependencies: ["PBIXKit"]),
.target(name: "DAXEngine", dependencies: ["ColumnStore"]),
.executableTarget(name: "dax-run", dependencies: ["DAXEngine"]),
.testTarget(name: "ColumnStoreTests", dependencies: ["ColumnStore"]),
.testTarget(name: "DAXEngineTests", dependencies: ["DAXEngine"]),
// BIPro: dependencies: ["PBIXKit", "DAXEngine"]
```

Lý do tách 2 target, không làm một target lớn:
- (a) Ép hướng phụ thuộc: ColumnStore không biết cú pháp DAX.
- (b) Agent làm ColumnStore build và test được mà không cần phần DAX.
- (c) Thời gian biên dịch tăng dần.

Hai target mới dùng Swift 6 language mode (strict concurrency). Riêng BIPro vẫn để v5 [FACT `Package.swift`].

### 8.2 Danh sách file và người sở hữu

```
Sources/ColumnStore/
  Contracts.swift            LEAD  ID, DAXType, Value, ColumnPayload, RowSet API, ColumnSource, ModelSchema, RelationshipSchema
  RowSet.swift               CS    bitset + thưa, giao/hợp/đếm, forEach
  ColumnData.swift           CS    payload, value(at:), sortRank, code(of:), postings
  StringPool.swift           CS
  PBIXColumnSource.swift     CS    DecodedColumn → ColumnData (chỉ đọc PBIXKit)
  ColumnStore.swift          CS    nạp lười, prefetch song song, ColumnStoreCache.shared
  ModelSchema+Metadata.swift CS    ModelSchema.init(metadata:)
  RelationshipIndex.swift    REL   fkToPK, blank row, manyRows/oneRows
  Propagation.swift          REL   R(T) theo §3.3, override USERELATIONSHIP/CROSSFILTER, lỗi đường mơ hồ
  InMemoryColumnSource.swift LEAD  nguồn cột dựng tay cho test (mọi agent dùng)
Sources/DAXEngine/
  Contracts.swift            LEAD  DAXError, BoundExpr, FunctionSpec, CallFrame, FilterItem, FilterContext API, ContextModifier, TableValue, EvalContext, QueryResult
  Syntax/AST.swift           LEAD  (đóng băng đợt 0)
  Syntax/Lexer.swift         LANG
  Syntax/Parser.swift        LANG
  Semantic/Catalog.swift     LANG  catalog nhiều lớp (model ← DEFINE)
  Semantic/Binder.swift      LANG
  Runtime/Value+Ops.swift    VAL   ép kiểu, số học, so sánh, BLANK
  Format/FormatString.swift  VAL
  Runtime/FilterContext.swift FC   ghi đè/KEEPFILTERS/REMOVEFILTERS/chiếu, vân tay, visibleRows (gọi Propagation)
  Runtime/Shadow.swift       FC    ShadowStack, ALLSELECTED resolve
  Runtime/TableValue.swift   FC    bảng ảo, lineage, distinct
  Runtime/Evaluator.swift    CORE  dispatch, VAR, measure ref, CALCULATE, context transition, iterator helper
  Runtime/Cache.swift        CORE  MeasureCache, RowSetCache
  Functions/Registry.swift   LEAD  liệt kê mọi họ (đợt 0, không ai sửa nữa)
  Functions/Logical.swift    F-SCALAR  IF SWITCH AND OR NOT TRUE FALSE COALESCE IFERROR
  Functions/MathFns.swift    F-SCALAR  ABS INT MOD ROUND DIVIDE …
  Functions/Text.swift       F-SCALAR  FORMAT CONCATENATE LEN UPPER …
  Functions/DateTime.swift   F-SCALAR  DATE YEAR MONTH DAY HOUR DATEDIFF TODAY …
  Functions/Information.swift F-FILTER ISBLANK ISFILTERED ISCROSSFILTERED HASONEVALUE SELECTEDVALUE
  Functions/FilterFns.swift  F-FILTER CALCULATE* ALL ALLSELECTED ALLNOBLANKROW REMOVEFILTERS KEEPFILTERS TREATAS USERELATIONSHIP CROSSFILTER
  Functions/Aggregation.swift F-AGG  SUM COUNT COUNTROWS DISTINCTCOUNT AVERAGE MIN MAX
  Functions/Iterators.swift  F-AGG   SUMX AVERAGEX MINX MAXX CONCATENATEX RANKX PERCENTILEX.INC
  Functions/TableFns.swift   F-TABLE FILTER VALUES DISTINCT SUMMARIZE ADDCOLUMNS CROSSJOIN TOPN CALCULATETABLE RELATED RELATEDTABLE
  Functions/TimeIntel.swift  F-TIME  SAMEPERIODLASTYEAR DATEADD DATESYTD TOTALYTD …
  Query/QueryExecutor.swift  QRY     DEFINE/EVALUATE/ORDER BY/START AT
  Query/SummarizeColumns.swift QRY
  Engine.swift               LEAD    façade công khai DAXEngine (execute, evaluateMeasure)
Sources/dax-run/main.swift   LEAD
Sources/BIPro/Query/QueryWorkspaces.swift  UI   (nút Chạy, lưới kết quả, lỗi tô trong editor)
Sources/BIPro/Query/DAXQueryState.swift    UI   (@Observable: kết quả, đang chạy, huỷ)
Sources/BIPro/Query/ResultGrid.swift       UI   (NSTableView ảo)
Sources/BIPro/DocumentState.swift          LEAD (thêm 1 dòng `let dax = DAXQueryState()`, sửa starter query)
Sources/BIPro/Workspace.swift              LEAD (thêm `lazy var engine`)
Tests/ColumnStoreTests/<Agent>*.swift       mỗi agent một tiền tố
Tests/DAXEngineTests/<Family>*.swift        mỗi họ một tiền tố; golden ở Tests/DAXEngineTests/Golden/<Family>/
docs/phase-b-ownership.tsv                  LEAD
```

### 8.3 Contract chính (`DAXEngine/Contracts.swift`)

```swift
public struct DAXError: Error, Sendable, Hashable {
    public enum Kind: Sendable { case syntax, unknownName, unsupportedFunction, arity, typeMismatch,
                                 expectedColumnRef, circularDependency, ambiguousPath, multipleValues, runtime, cancelled }
    public let kind: Kind; public let message: String; public let range: SourceRange?
}

public struct MeasureID: Hashable, Sendable { public let raw: Int32 }
public struct FunctionID: Hashable, Sendable { public let raw: Int32 }

public indirect enum BoundExpr: Sendable {
    case literal(Value)
    case column(ColumnID)                         // cần row context
    case virtualColumn(name: String)              // cột ảo của bảng đang lặp
    case table(TableID)
    case measure(MeasureID)
    case variable(slot: Int)
    case call(FunctionID, [BoundExpr?])           // nil = đối số bỏ trống
    case unary(UnaryOp, BoundExpr)
    case binary(BinaryOp, BoundExpr, BoundExpr)
    case varBlock(slots: [Int], values: [BoundExpr], body: BoundExpr)
    case tableConstructor(columns: Int, rows: [[BoundExpr]])
    case keyword(String)                          // DESC, DENSE, YEAR, MONTH …
}

public enum ParamKind: Sendable {
    case scalar            // đánh giá sẵn thành Value (eager)
    case lazyScalar        // hàm tự gọi frame.scalar(i, ctx) (IF, SWITCH, iterator body)
    case table             // biểu thức bảng
    case columnRef         // phải là tham chiếu cột (ALL, VALUES, TREATAS đích, USERELATIONSHIP)
    case tableOrColumnRef
    case filter            // đối số filter của CALCULATE
    case keyword([String]) // ASC/DESC, DENSE/SKIP, DAY/MONTH/YEAR
}
public struct Param: Sendable { public let name: String; public let kind: ParamKind; public let optional: Bool; public let repeats: Bool }

public struct CallFrame: Sendable {
    public let args: [BoundExpr?]
    public let ctx: EvalContext
    public let eval: any Evaluating
    public func scalar(_ i: Int) throws(DAXError) -> Value
    public func scalar(_ i: Int, in ctx: EvalContext) throws(DAXError) -> Value
    public func table(_ i: Int) throws(DAXError) -> TableValue
    public func column(_ i: Int) throws(DAXError) -> ColumnID
    public func keyword(_ i: Int) -> String?
    public func iterate(_ t: TableValue, _ body: (EvalContext) throws(DAXError) -> Void) throws(DAXError)  // đẩy shadow + row frame
}

public struct FunctionSpec: Sendable {
    public enum Impl: Sendable {
        case scalar(@Sendable (CallFrame) throws(DAXError) -> Value)
        case table(@Sendable (CallFrame) throws(DAXError) -> TableValue)
        case modifier(@Sendable (CallFrame) throws(DAXError) -> [ContextModifier])   // REMOVEFILTERS, USERELATIONSHIP…
    }
    public let name: String            // chữ hoa
    public let params: [Param]
    public let impl: Impl
}
public protocol FunctionFamily { static var functions: [FunctionSpec] { get } }

public enum ContextModifier: Sendable {
    case filter(FilterItem, keep: Bool)
    case removeColumns([ColumnID])
    case removeExpandedTable(TableID)
    case removeAll
    case allSelected(columns: [ColumnID]?)           // nil = ALLSELECTED()
    case useRelationship(RelationshipID)
    case crossFilter(RelationshipID, CrossFilterMode)
}

public final class DAXEngine: Sendable {
    public init(store: ColumnStore, culture: String = "en-US")
    public func execute(_ query: String) async throws(DAXError) -> QueryResult            // có hỗ trợ Task cancellation
    public func evaluate(measure: String, table: String?, filters: [FilterItem]) async throws(DAXError) -> Value
    public func validate(_ expression: String) -> [DAXError]                              // cho editor
}
```

`Functions/Registry.swift` (lead, đợt 0):

```swift
enum FunctionRegistry {
    static let families: [any FunctionFamily.Type] = [
        LogicalFunctions.self, MathFunctions.self, TextFunctions.self, DateTimeFunctions.self,
        InformationFunctions.self, FilterFunctions.self, AggregationFunctions.self,
        IteratorFunctions.self, TableFunctions.self, TimeIntelligenceFunctions.self,
    ]
    static let byName: [String: FunctionSpec] = …   // gộp; trùng tên thì báo lỗi khi test
}
```

Ở đợt 0 mỗi file họ đã có sẵn `enum XFunctions: FunctionFamily { static let functions: [FunctionSpec] = [] }`. Agent chỉ thêm phần tử vào mảng trong file của mình. Không có đăng ký động, không có file chung nào phải sửa.

### 8.4 Điểm nóng dùng chung và cách tránh xung đột

| Điểm nóng | Cách xử lý |
|---|---|
| `Package.swift` | Lead, đợt 0; không ai sửa sau đó |
| `Contracts.swift` (2 file), `AST.swift` | Lead đóng băng ở đợt 0. Muốn đổi thì gửi yêu cầu cho lead; mỗi đợt tối đa 1 lần đổi (cùng ngưỡng với Phase W) |
| Bảng đăng ký hàm | `Registry.swift` liệt kê họ từ đầu; mỗi họ một file, một mảng tĩnh |
| `DAXError.Kind` | Enum đóng băng, chi tiết đặt trong `message`, nên không ai phải thêm case |
| `Evaluator.swift` | Chỉ CORE sửa. Hàm cần hành vi đặc biệt (CALCULATE, iterator) thì gọi helper công khai của `CallFrame`, không sửa evaluator |
| Fixture test | Lead viết `InMemoryColumnSource` và một model nhỏ chung (`MiniBank`: Fact 20 dòng, 3 dim, 1 quan hệ inactive, 1 FK không khớp để có blank row, 1 bảng ngày đã đánh dấu). Agent tự thêm fixture vào file test có tiền tố riêng |
| Golden oracle | Mỗi họ một thư mục `Golden/<Family>/`. File oracle do người dùng xuất từ Power BI Desktop/DAX Studio trong VM nằm ở `docs/phase-b-oracle/` (lead quản lý) |
| `DocumentState.swift`, `Workspace.swift` | Lead thêm điểm móc ở đợt 0; UI agent làm việc trong file mới của mình |
| `scripts/check-ownership.sh` | Lead thêm tham số TSV (hiện đường dẫn bị viết cứng) |
| `.build` | Mỗi sandbox dùng `--scratch-path .build-<agent>`, cách đã chạy ổn ở Phase W |

---

## 9. So sánh cách chia việc cho agent

Chấm điểm 1–5 (5 là tốt nhất). Số tuần là ước lượng thời gian thực tới khi 119 measure khớp oracle [SUY ĐOÁN].

| Cách chia | Mô tả | Đường găng | Xung đột file | Rủi ro ghép | Chi phí context | Test độc lập | Tổng |
|---|---|---|---|---|---|---|---|
| **A. Theo lớp kỹ thuật** | 4–5 agent: ColumnStore, Parser/Binder, Evaluator + FilterContext, Query, Functions | 2: mọi hàm phụ thuộc evaluator; agent "Functions" bị nghẽn, khoảng 7 tuần | 4 | 2: ngữ nghĩa CALCULATE trải trên FilterContext, Evaluator và FilterFns, nên chỉ lộ lỗi khi ghép | 3 | 3: lớp dưới test được, lớp hàm thì không | 14 |
| **B. Theo họ hàm** | Sau khi lõi xong (tuần tự), mỗi agent một họ: scalar, filter, aggregation/iterator, table, time | 2: lõi tuần tự 2–3 tuần rồi mới song song, khoảng 6 tuần | 5: mỗi họ một file | 4: Registry cố định | 4: mỗi agent chỉ cần đọc contract và tài liệu họ hàm | 5: MiniBank cộng golden theo họ | 20 |
| **C. Lát dọc theo measure / tầng khó** | Tầng 1 (SUM/IF/DIVIDE/FORMAT), tầng 2 (CALCULATE/REMOVEFILTERS/KEEPFILTERS/USERELATIONSHIP), tầng 3 (TREATAS/ALLSELECTED/SAMEPERIODLASTYEAR/iterator); mỗi agent làm một tầng chạy suốt | 3: chạy được sớm, nhưng các tầng chồng nhau | 1: mọi tầng đều sửa evaluator và FilterContext | 2 | 2: mỗi agent phải hiểu cả hệ | 4: kiểm bằng measure thật | 12 |
| **D. Lai theo đợt** ✅ | Đợt 1 theo lớp ở phần lá; đợt 2 lõi cùng họ vô hướng; đợt 3 theo họ hàm cộng UI; đợt 4 lát dọc đối chiếu oracle, sửa theo chủ file | 4: phần lá chạy song song với nhau; lõi là việc tuần tự duy nhất; khoảng 5–5,5 tuần | 5: bảng sở hữu, mỗi họ một file | 4: contract đóng băng; MiniBank chung; pilot | 3: mỗi đợt nạp context mới | 5 | **21** |

**Chọn D.**

- **Lý do:**
  - Đường găng là `Contracts → FilterContext + Propagation → Evaluator/CALCULATE → FilterFns + SummarizeColumns → đối chiếu ALLSELECTED/time intelligence`. D cho mọi việc khác chạy cạnh đường này.
  - Ngữ nghĩa khó (CALCULATE, transition, shadow) tập trung vào **hai chủ**: FC và CORE, nên ít rủi ro ghép.
  - Đợt 4 vẫn giữ ưu điểm của C (bám measure thật), nhưng mỗi lỗi được giao về **chủ file của họ hàm** nên không phát sinh xung đột.

### 9.1 Lịch đợt (tối đa 4 agent đồng thời)

| Đợt | Agent (WP) | Việc | Tự kiểm | Ước lượng |
|---|---|---|---|---|
| **0** (lead, tuần tự) | LEAD | Package.swift; 2 Contracts; AST; Registry cùng stub 10 họ; InMemoryColumnSource + MiniBank; Engine façade stub; `dax-run` khung; móc Workspace/DocumentState; `phase-b-ownership.tsv`; sửa check-ownership để nhận TSV | `swift build` xanh; check-ownership chạy được | 1–1,5 ngày |
| **1a pilot** | CS, LANG | ColumnStore (RowSet, ColumnData, PBIXColumnSource, nạp lười) · Lexer/Parser/Binder (parse đủ 168 + 125 + 23 measure của 3 file và các truy vấn mẫu) | CS: giải mã Nhom6 ra ColumnData, distinct count khớp `verify`, bench release. LANG: 316/316 biểu thức parse được; bind đủ 119 measure của closure Nhom6 | 3–4 ngày |
| **1b** | + REL, VAL | REL: RelationshipIndex + Propagation (cả USERELATIONSHIP, CROSSFILTER, blank row) · VAL: Value+Ops + FormatString | REL: trên MiniBank và Nhom6, R(Fact) dưới bộ lọc dim khớp đếm bằng tay. VAL: bảng golden ép kiểu, BLANK và định dạng | 3–4 ngày |
| **2** | FC, CORE, F-SCALAR, QRY | FC: FilterContext (ghi đè, KEEPFILTERS, chiếu, expanded, vân tay) + Shadow + TableValue · CORE: Evaluator, CALCULATE, transition, VAR, cache · F-SCALAR: Logical/Math/Text/DateTime · QRY: Query executor + SUMMARIZECOLUMNS + ORDER BY/START AT | FC và CORE có test ngữ nghĩa trên MiniBank, viết theo ví dụ trong tài liệu công khai | 6–8 ngày (CORE là đường găng) |
| **3** | F-FILTER, F-AGG, F-TABLE, UI | Information + FilterFns · Aggregation + Iterators · TableFns + TimeIntel · DAX Query View (Chạy, huỷ, lưới, lỗi có vị trí, "Định nghĩa và đánh giá") | Golden theo họ; UI: chụp màn hình bằng REA so với `UIdesign/dax_query_view` | 6–8 ngày |
| **4** | tối đa 4 (theo lỗi) | Đối chiếu 119 measure với oracle theo tầng; mỗi lỗi giao chủ file. Song song: đường nhanh gom nhóm + bench §7.5; ROLLUPADDISSUBTOTAL nếu còn thời gian; F-TIME DATEADD cho Nhóm 2/3 | 119/119 khớp; trang D1 dưới 150 ms (release) | 7–10 ngày |

Cộng khoảng **5–6 tuần**, vừa với khung 6–7 tuần của BIPRO_BUILD_PLAN [SUY ĐOÁN].

**Pilot đợt 1a (CS + LANG)** dùng cùng ngưỡng với Phase W §4.2: 0 vi phạm sở hữu, build xanh ngay khi gộp, sửa contract tối đa 1 lần, thời gian tối đa 1,5 lần ước lượng. Đạt thì mở rộng lên 4 agent. Trượt vì contract thì lead sửa rồi chạy lại một lần. Trượt vì xung đột thì chuyển F-* sang chạy tuần tự.

**Oracle:** người dùng xuất kết quả trong VM, theo BIPRO_BUILD_PLAN; agent không tự động hoá VM. Lead sinh sẵn `docs/phase-b-oracle/queries/*.dax`, mỗi measure một truy vấn:
- `EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "v", [m])`;
- thêm một truy vấn tổng;
- với measure dùng ALLSELECTED/ISFILTERED, thêm một truy vấn có filter table, để người dùng chạy hàng loạt trong DAX Studio.

---

## 10. Rủi ro kỹ thuật lớn nhất

| Rủi ro | Mức | Vì sao | Giảm thiểu |
|---|---|---|---|
| **ALLSELECTED / shadow context** | Cao | Ngữ nghĩa chỉ được mô tả đầy đủ ở SQLBI, chính SQLBI từng đính chính, và Microsoft Learn chỉ có vài câu. Nhom6 dùng 9 lần trong closure, có ca lồng trong ADDCOLUMNS/CROSSJOIN rồi gọi measure | Cài đúng mô hình shadow stack (§4.5); test theo ví dụ AdventureWorks trong tài liệu ALLSELECTED và SUMMARIZECOLUMNS/NONVISUAL, viết lại trên MiniBank; truy vấn oracle riêng có slicer; shadow nằm trong khoá cache |
| **Time intelligence** | Cao | Ngoài phạm vi Nhom6 (SAMEPERIODLASTYEAR trên tập ngày liên tục), DATEADD có quy tắc cuối tháng, khoảng không liên tục và giới hạn trong dải ngày của bảng. Bảng ngày đã đánh dấu có thể tự thêm `ALL(bảng ngày)` khi lọc cột ngày [DOC SQLBI, desktop-date-tables]. Nhóm 3 gọi `DATEADD(dim_date[date_key], -1, MONTH)` trên cột khoá | Làm SAMEPERIODLASTYEAR = DATEADD(-1, YEAR) trước (Nhom6 luôn kèm `REMOVEFILTERS(Dim_Date)` [FACT]); golden có 29/02, 31/03 → 28/02, tháng thiếu; dùng `Table.DataCategory`/`IsKey` để biết bảng ngày; gặp trường hợp chưa rõ thì báo lỗi, không trả số sai |
| **Độ chính xác số thực và làm tròn khi định dạng** | Trung bình | Cộng Double theo thứ tự khác VertiPaq lệch khoảng 1e-12; FORMAT/FormatString có thể làm tròn kiểu khác ở các giá trị 0,5 | So oracle với sai số tương đối 1e-9 và so **chuỗi đã định dạng**; currency là Int64 ×10⁴; integer SUM giữ Int64; dùng pairwise/Kahan summation cho double; thêm golden ở các giá trị 0,5 |
| **Hiệu năng của iterator gọi measure trên bảng lớn** | Cao | `Closing_Balance`: 4.500 tài khoản × 2 CALCULATE trên fact 1 triệu dòng (§7.3) | Posting list cho transition và lọc theo giá trị; cache; song song; bench là điểm đo số 1; cuối cùng là đường nhanh gom nhóm |
| **Build debug chậm 34 lần** | Trung bình | Test trên Nhom6 ở debug mất hơn 20 s chỉ để giải mã | Test đơn vị chạy trên MiniBank; test Nhom6 gắn tag và chạy `swift test -c release`; có thể cache ColumnData xuống đĩa (`.build-cache/nhom6.cols`) |
| **Ngữ nghĩa ghi đè và chiếu của bộ lọc nhiều cột (TREATAS 2 cột, 24 lần)** | Trung bình | Sau khi ghi đè một cột, bộ lọc "mất hình dạng"; ISFILTERED đổi theo | Test đúng mẫu `D4 *` của Nhom6; truy vấn oracle có lọc `Dim_District[city]` |
| **Blank row và quan hệ inactive** | Thấp–TB | Tài liệu nói quan hệ inactive cũng được mở rộng; ảnh hưởng tới VALUES/COUNTROWS của dim | MiniBank có FK không khớp; oracle `COUNTROWS(VALUES(Dim_Date[date_key]))` |
| **Thay đổi hành vi theo phiên bản Power BI** (SUMMARIZECOLUMNS "SelfValue" 06/2024, ValueFilterBehavior) | Trung bình | Kết quả phụ thuộc phiên bản Desktop dùng làm oracle | Ghi phiên bản Desktop trong VM vào mỗi file oracle; làm theo hành vi hiện tại |
| **Strict concurrency Swift 6** | Thấp | `final class` cache dùng chung | `Mutex`/khoá phân mảnh; ColumnData bất biến; `@unchecked Sendable` chỉ dùng ở 2 class cache, có comment |

---

## 11. Nguồn công khai

Chỉ đọc tài liệu để hiểu ngữ nghĩa, không chép code.

- Quan hệ, blank row, expanded table, ưu tiên/weight đường, USERELATIONSHIP: https://learn.microsoft.com/power-bi/transform-model/desktop-relationships-understand (đã đọc 2026-10-31)
- ALLSELECTED: https://learn.microsoft.com/dax/allselected-function-dax (đã đọc) · https://www.sqlbi.com/articles/the-definitive-guide-to-allselected/ (đã đọc) · https://dax.guide/allselected/
- SUMMARIZECOLUMNS (bỏ dòng BLANK, auto-exist, IGNORE, NONVISUAL, ROLLUPADDISSUBTOTAL, SelfValue): https://learn.microsoft.com/dax/summarizecolumns-function-dax (đã đọc)
- CALCULATE và đối số filter: https://learn.microsoft.com/dax/calculate-function-dax · https://www.sqlbi.com/articles/filter-arguments-in-calculate/
- Context transition: https://www.sqlbi.com/articles/understanding-context-transition/
- Expanded tables: https://www.sqlbi.com/articles/expanded-tables-in-dax/
- Arbitrarily shaped filters: https://www.sqlbi.com/articles/understanding-arbitrarily-shaped-filters-in-dax/
- KEEPFILTERS: https://learn.microsoft.com/dax/keepfilters-function-dax · https://www.sqlbi.com/articles/using-keepfilters-in-dax/
- TREATAS / lineage: https://learn.microsoft.com/dax/treatas-function · https://www.sqlbi.com/articles/understanding-data-lineage-in-dax/
- USERELATIONSHIP, CROSSFILTER: https://learn.microsoft.com/dax/userelationship-function-dax · https://learn.microsoft.com/dax/crossfilter-function-dax
- VALUES/DISTINCT và blank row: https://learn.microsoft.com/dax/values-function-dax · https://www.sqlbi.com/articles/blank-row-in-dax/
- Auto-exist: https://www.sqlbi.com/articles/understanding-dax-auto-exist/
- Kiểu dữ liệu, ép kiểu, bảng xử lý BLANK: https://learn.microsoft.com/power-bi/connect-data/desktop-data-types
- Toán tử và độ ưu tiên: https://learn.microsoft.com/dax/dax-operator-reference
- DAX queries (EVALUATE, DEFINE, ORDER BY, START AT): https://learn.microsoft.com/dax/dax-queries
- DIVIDE: https://learn.microsoft.com/dax/divide-function-dax · TOPN: https://learn.microsoft.com/dax/topn-function-dax
- FORMAT và định dạng số: https://learn.microsoft.com/dax/format-function-dax · https://learn.microsoft.com/dax/custom-numeric-formats-for-the-format-function · https://learn.microsoft.com/dax/pre-defined-numeric-formats-for-the-format-function
- Time intelligence và bảng ngày: https://learn.microsoft.com/dax/sameperiodlastyear-function-dax · https://learn.microsoft.com/dax/dateadd-function-dax · https://learn.microsoft.com/power-bi/transform-model/desktop-date-tables · https://www.sqlbi.com/articles/time-intelligence-in-power-bi-desktop/
- VAR: https://learn.microsoft.com/dax/var-dax

Ba trang ghi "đã đọc" được mở trong phiên này để kiểm tra trích dẫn. Các URL còn lại là trang tham khảo chuẩn, agent phụ trách phải đọc lại khi cài đặt phần tương ứng.
