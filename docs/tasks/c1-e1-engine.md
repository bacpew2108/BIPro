Bạn làm việc trong repo Swift "BI Pro", một ứng dụng macOS giống Power BI Desktop. Repo có engine DAX tự viết trong `Sources/DAXEngine`. Bạn đang ở một git worktree riêng, tách từ `main`.

## Mục tiêu (gói E1, Phase C)

Engine phải chạy được các truy vấn DAX mà Power BI Desktop sinh ra cho visual. Đã có 72 truy vấn thật copy từ Performance Analyzer:
- `docs/phase-c-evidence/observe-c1/pa/*.dax` (47 file);
- `docs/phase-c-evidence/observe-c1/interact/*.dax` (17 file);
- `docs/phase-b-evidence/observe2/PA-*.dax` (8 file).

Lưu ý:
- File C1 có xuống dòng CRLF; phải bỏ `\r` trước khi parse, hoặc lexer chấp nhận `\r\n`.
- `PA-D3-1.dax` dòng 49 có dấu `\` lỗi do copy; bỏ dấu đó khi đọc file trong test.

Hiện engine chạy được **0** truy vấn. Đọc trước:
- `docs/phase-c-evidence/C1.md` §2 (nhất là §2.3, §2.5);
- `docs/phase-c-research/notes.md` §3 (ngữ nghĩa từng hàm).

## Chỉ được sửa hoặc tạo các file sau

- Sources/DAXEngine/Functions/VisualFns.swift (mới)
- Sources/DAXEngine/Query/SummarizeColumns.swift
- Sources/DAXEngine/Query/QueryExecutor.swift
- Sources/DAXEngine/Semantic/Binder.swift
- Sources/DAXEngine/Runtime/Evaluator.swift
- Sources/DAXEngine/Functions/FilterFns.swift
- Sources/DAXEngine/Functions/TableFns.swift
- Sources/DAXEngine/Functions/MathFns.swift (CEILING, SQRT)
- Sources/DAXEngine/Functions/Registry.swift (thêm họ VisualFunctions)
- Sources/DAXEngine/Syntax/Parser.swift, Sources/DAXEngine/Syntax/AST.swift, Sources/DAXEngine/Syntax/Lexer.swift (chỉ cho tuple IN và CRLF)
- Sources/DAXEngine/Contracts.swift (CHỈ THÊM: case/kiểu mới; không đổi hoặc xoá chữ ký đang có)
- Tests/DAXEngineTests/VIS/** (mới)

KHÔNG sửa file nào khác. Đặc biệt:
- không sửa `Semantic/Catalog.swift`, vì lead đang sửa;
- không sửa `Runtime/Cache.swift`, `Functions/Calculate.swift`, `Package.swift`;
- không sửa `Sources/BIPro`, `Sources/PBIXKit`, `Sources/ColumnStore`, `docs/`;
- không sửa test cũ ngoài `VIS/`.

Thêm:
- Không commit, không push, không cài package, không tải gì từ mạng.
- Không đọc hay ghi gì trong `~/Downloads`. Chỉ có một ngoại lệ: test nặng tự mở `~/Downloads/Nhom6_Dashboard.pbix` qua `DAXFixtures.nhom6` (chỉ đọc).

## Việc cần làm

Đọc kỹ cách engine hiện làm, rồi mở rộng, không viết lại:
- `Query/SummarizeColumns.swift` đã có SUMMARIZECOLUMNS ở đầu EVALUATE, đã có IGNORE và KEEPFILTERS bảng lọc;
- `Query/QueryExecutor.swift` nhận dạng nó;
- `Semantic/Binder.swift` bind hàm theo `FunctionRegistry`;
- `Runtime/Evaluator.swift` đánh giá.

1. **SUMMARIZECOLUMNS làm biểu thức bảng ở mọi chỗ:** trong `VAR`, làm đối số bảng (`TOPN(…, SUMMARIZECOLUMNS(...))`, `KEEPFILTERS(SUMMARIZECOLUMNS(...))`). Giữ nguyên kết quả của đường hiện có; 30 golden Phase B phải vẫn khớp.
   - Kết quả là bảng có tên cột như khi ở EVALUATE: cột nhóm `'Bảng'[cột]` có lineage; cột measure `[Tên]` không lineage.
   - Đối số bảng lọc là biến (`__DS0FilterTable`) phải chạy được, như ở đầu EVALUATE.
2. **KEEPFILTERS(<bảng>)** làm đối số bảng: của FILTER, của CALCULATETABLE (`KEEPFILTERS(__DS0FilterTable)` trong slicer), của SUMMARIZECOLUMNS. Nghĩa: bảng đó áp như bộ lọc giao (KEEPFILTERS); khi chỉ dùng làm bảng thì trả chính bảng.
3. **ROLLUPADDISSUBTOTAL / ROLLUPGROUP / NONVISUAL** trong SUMMARIZECOLUMNS:
   - các dạng: `ROLLUPADDISSUBTOTAL(cột, "Cờ")`; `ROLLUPADDISSUBTOTAL(ROLLUPGROUP(c1, c2), "Cờ")`; nhiều cặp `ROLLUPADDISSUBTOTAL(c1, "Cờ1", c2, "Cờ2")`; dạng có đối số lọc cấp nhóm `ROLLUPADDISSUBTOTAL(cột, "Cờ", ROLLUPGROUP(...), "Cờ2", NONVISUAL(bảng))` (xem `D1-slicer-nam.dax`);
   - thêm dòng tổng; cột cờ boolean TRUE ở dòng tổng; cột bị gộp là BLANK ở dòng tổng;
   - đối số NONVISUAL(bảng) giới hạn các nhóm cha được mở cấp con, như mở rộng trong slicer. [SUY ĐOÁN] Hãy suy ra từ ví dụ, ghi chú [SUY ĐOÁN] trong code.
4. **Hàm mới** (đăng ký trong `VisualFns.swift`, họ `VisualFunctions`, thêm vào `Registry.swift`):
   - `NATURALLEFTOUTERJOIN(trái, phải)`: nối theo cột cùng tên và cùng lineage. Cột không lineage thì nối theo cùng tên, ví dụ `[IsGrandTotalRowTotal]`.
   - `SUBSTITUTEWITHINDEX(bảng, "Tên", bảngChỉSố, biểuThức, ASC|DESC, …)`: giữ dòng khớp, thay các cột khớp bằng cột chỉ số 0-based theo thứ tự sắp của các khoá.
   - `GROUPBY(bảng, [cột nhóm…], "Tên", biểu thức…)` và `CURRENTGROUP()`: mỗi biểu thức lặp trên CURRENTGROUP (MINX/MAXX/SUMX…). Có thể không có cột nhóm (PA-D1-2) thì ra 1 dòng.
   - `SAMPLE(n, bảng, khoá, thứ tự, …)`: n ≥ số dòng thì trả đủ dòng; nhỏ hơn thì lấy dòng đầu, dòng cuối và các dòng cách đều (notes.md §3); n là biểu thức.
   - `SAMPLEAXISWITHLOCALMINMAX(size, bảng, trục, measure…, minRes, [trống], ALPHABETICAL, ASC, maxRes, maxIter)`: số dòng ≤ size thì trả đủ dòng (Nhom6 luôn như vậy). Vượt thì chia trục thành bin và giữ min/max mỗi bin, ghi [SUY ĐOÁN]. Đối số bỏ trống `, ,` phải parse được.
   - `CEILING(x, bội)`, `SQRT(x)`.
   - `MIN(a, b)` dạng hai vô hướng (kiểm xem đã có chưa).
5. **TOPN:** N là biểu thức (`__DS0TargetSecondaryCount + 1`); nhiều cặp (khoá, 0/1); khoá là cột kết quả không lineage (`[IsGrandTotalRowTotal]`, `[Complaints]`).
6. **SUMMARIZE trên biến bảng**, kể cả nhóm theo cột không lineage (`SUMMARIZE(__DS0Core, 'T'[c], [IsGrandTotalRowTotal])`). `SUMMARIZE(VALUES('Dim_Client'), cột, cột)` trong CALCULATETABLE.
7. **Tuple IN:** `('Dim_Date'[year], 'Dim_Date'[quarter_name]) IN {(2016, "Q1")}` (`interact/slicer3-quy.dax`).
8. **Biến bảng dùng làm bộ lọc trong CALCULATE:** `CALCULATE(COUNTROWS(__DS0Core))` và `CALCULATE(measure, KEEPFILTERS(__H0FilterTable))` với `__H0FilterTable = TREATAS(...)`.
9. **Nhiều EVALUATE** trong một truy vấn: đã có, kiểm lại với các file C1.
10. **Thứ tự cột của kết quả** phải đúng như Power BI. So với `docs/phase-c-evidence/observe-c1/results/*.tsv`: dòng đầu là tên cột; file nhiều bảng có dòng `#RESULT n` trước mỗi bảng.

Hàm nào mà ngữ nghĩa trong notes.md chưa đủ thì làm cho khớp kết quả `.tsv` thật và ghi `[SUY ĐOÁN]` kèm lý do.

## Test bắt buộc

1. **Test thường** (`Tests/DAXEngineTests/VIS/`) trên dữ liệu MiniBank (`Sources/DAXTestSupport/MiniBank*.swift`): mỗi hàm ở mục 4 có ít nhất 2 ca, cùng các ca cho tuple IN, KEEPFILTERS bảng, SUMMARIZECOLUMNS trong VAR, ROLLUPADDISSUBTOTAL (một cặp, ROLLUPGROUP, hai cặp).
   - Giá trị kỳ vọng phải tính tay từ dữ liệu MiniBank và giải thích trong comment.
   - **Không viết cứng kết quả để test qua.** Lead sẽ review từng giá trị.
2. **Test nặng** `VISNhom6Tests` (`Tests/DAXEngineTests/VIS/VISNhom6Tests.swift`), bật khi `BIPRO_HEAVY=1` và có file Nhom6. Dùng lại cách nạp engine và `GoldenComparator`/`GoldenTable` trong `Tests/DAXEngineTests/ORA/ORAGoldenTests.swift` (cùng module test, gọi trực tiếp được).
   - (a) Mọi truy vấn trong 3 thư mục ở trên chạy không lỗi.
   - (b) Truy vấn có file kết quả thì so khớp từng bảng:
     - `observe-c1/results/<tên>.tsv` với `observe-c1/pa/<tên>.dax`;
     - `observe2/PA-*.tsv` với `PA-*.dax`.
     - Nếu `.tsv` chỉ chứa một số bảng (ví dụ PA-D1-1.tsv chỉ có bảng đầu), so đúng các bảng có mặt; tách bảng theo dòng `#RESULT n`.
   - (c) In thời gian từng truy vấn.
   - Truy vấn nào không khớp mà bạn tin là do quy tắc chưa quan sát được: đánh dấu `withKnownIssue` kèm lý do cụ thể, và báo trong phần kết quả.
3. Test cũ phải vẫn xanh. Đặc biệt `ORAGolden` (30 golden Phase B) ở chế độ nặng.

## Lệnh build/test của project

```
swift build --scratch-path .build-wE1
swift test --scratch-path .build-wE1 --filter DAXEngineTests
BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-wE1-rel --filter "VISNhom6|ORAGolden"
```

Nếu test sập SIGBUS sau khi đổi struct dùng chung thì xoá thư mục scratch tương ứng: không dùng được `rm`, nên đổi sang tên scratch mới, ví dụ `.build-wE1b`.

## Tiêu chí xong

- `swift build` xanh.
- `swift test --filter DAXEngineTests` xanh.
- Test nặng `VISNhom6|ORAGolden` xanh: 30/30 golden cũ; mọi truy vấn C1 + PA chạy được; các bảng có `.tsv` khớp, trừ ca đánh dấu known issue có lý do.
- Cuối cùng in:
  - danh sách file đã sửa, mỗi file một dòng tóm tắt;
  - kết quả ba lệnh;
  - bảng: truy vấn, khớp hay lệch, thời gian;
  - các chỗ [SUY ĐOÁN].

## Lệnh shell được phép

Chỉ dùng: swift build, swift test, `BIPRO_HEAVY=1 swift test`, git status/diff/log/show, ls, cat, grep, rg, head, tail, wc, pwd, find, sed -n, sort, uniq, echo, file.

Lệnh khác sẽ bị từ chối và làm dừng cả phiên. Đọc và sửa file thì dùng công cụ đọc/sửa file của bạn.
