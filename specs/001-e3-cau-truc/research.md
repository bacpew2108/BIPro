# Nghiên cứu: E3-cấu-trúc

Mọi mục dưới đây dựa trên mã hiện tại (`Sources/DAXEngine/`) và `C1.md` §1.5. Mục nào chưa có số đo ghi rõ "cần đo".

## R1. Chi phí của combo thấu chi nằm ở đâu

- **Quan sát [ĐO]**: `Avg_Account_Balance` (`docs/measures.nhom6.dax:958`) lặp qua `VALUES(account_key)` ghi vào `accts`, mỗi tài khoản gọi hai CALCULATE: `MAX(trans_timestamp)`, rồi `MAX(balance_after)` với `trans_timestamp = t`, cả hai kèm `REMOVEFILTERS(Dim_Trans_Type)`. Khoảng 180 nghìn ô (tài khoản × tháng), mỗi CALCULATE khoảng 45 µs CPU (`C1.md` §1.5, vòng 2).
- **Cơ chế [ĐỌC MÃ]**: `Evaluator.iterate` lặp từng dòng của bảng ảo; thân tính `CALCULATE` nên `transitioned` dựng `FilterContext` mới (sao chép, áp bộ lọc dòng), rồi `visibleRows` và `MAX` quét tập dòng. Chi phí rải đều (sao chép ngữ cảnh, dựng tập mã, `visibleRows`, cấp phát), không có điểm nóng đơn lẻ.
- **Hệ quả**: sửa nhỏ đã hết lợi nhuận (vòng 2). Phải bỏ việc "dựng ngữ cảnh mỗi nhóm".

**Quyết định**: tính gộp theo nhóm.

## R2. Điều kiện để gộp mà không đổi kết quả

Gộp hợp lệ khi đồng thời đúng:

1. Bảng lặp là các giá trị riêng của đúng một cột `G` (kết quả của `VALUES(G)`, `DISTINCT(G)` hoặc biến giữ chúng), nên chuyển ngữ cảnh chỉ thành bộ lọc `G = v` (ghi đè bộ lọc cũ của `G`).
2. Thân là `CALCULATE(agg(C), …)` với `agg` thuộc MAX, MIN (đã cài; SUM và COUNT chưa làm vì chưa có nhu cầu, thêm khi cần) và `C` là cột của chính bảng chứa `G` (cột ở bảng khác qua quan hệ chưa hỗ trợ: rơi về đường cũ).
3. Các đối số bộ lọc của CALCULATE không phụ thuộc dòng đang lặp, trừ dạng `C2 = t` với `t` là biến vô hướng đã tính ở cùng dòng bằng chính một CALCULATE theo mẫu này (mẫu "tham số theo nhóm" của `Avg_Account_Balance`).
4. Không có `KEEPFILTERS` hay `USERELATIONSHIP` đổi cách `G = v` đè lên bộ lọc cũ (đường từng dòng giữ nguyên).

Mọi thứ khác rơi về đường cũ. Nhờ vậy khớp byte được bảo đảm bằng thiết kế, và rủi ro dồn vào hàm nhận mẫu.

**Chỗ cần cẩn thận (đưa vào test)**:
- Nhóm không có dòng nào: MAX ra BLANK như đường cũ; `t` BLANK thì `C2 = BLANK` khớp các dòng BLANK. Mẫu 3 rơi về đường cũ khi gặp `t` BLANK, không gộp.
- Cột `trans_timestamp` có thể trùng giá trị: lấy MAX trong số mọi dòng khớp, như đường cũ.
- Bộ lọc cũ trên `G` phải bị đè (không giao): quét dòng với `G` bị bỏ lọc rồi chia theo `G`.
- `ALLSELECTED`/shadow: ngữ cảnh bóng (`pushingShadow`) trong `iterate` phải được xử lý đúng như đường cũ.

## R3. Giới hạn dưới của hướng gộp [ĐO, T004, 2026-11-09]

Đo bằng mã tay trong `Tests/DAXEngineTests/PERF/BatchedSpikeTests.swift` (chưa nối vào engine, không bộ lọc báo cáo). Số liệu đầy đủ ở [measurements.md](measurements.md).

- Nhom6: 1 056 320 dòng fact, 4 501 tài khoản, 72 tháng.
- Đường cũ cho `Avg_Account_Balance` theo tháng: 1,92–2,29 s. Quét gộp: 4 ms (một lần quét phẳng tháng × tài khoản, hoặc theo tháng một luồng), 1 ms với 8 luồng. Chuẩn bị mảng 5 ms.
- Kết quả khớp đường cũ ở cả 72 tháng (sai số tương đối ≤ 4,8e-15).
- Phần còn lại của combo (các measure khác, bộ lọc năm/vùng) tốn khoảng 0,43 s, nên combo sau gộp dự báo khoảng 0,5–0,6 s [SUY ĐOÁN, chưa tính chi phí nhận mẫu và áp bộ lọc trong engine].
- Cả hai cách gộp (b) và (a) đều đủ nhanh. Chọn theo độ đơn giản khi cài đặt: gộp theo từng nhóm lọc của `SUMMARIZECOLUMNS` (cách a) khớp với cách engine tính từng ô, nên ít đổi cấu trúc hơn.

**Kết luận cổng (ngưỡng ≤ 0,6 s)**: đạt với biên rất lớn ở phần Avg_Account_Balance. Rủi ro còn lại nằm ở chi phí ngoài phép quét: dựng ngữ cảnh lọc cho từng tháng và 0,43 s của các measure khác.

## R4. Matrix Giờ × Thứ [ĐO, T005, 2026-11-09]

Lấy mẫu CPU 12 s (`sample`, file `build/e3-sample/matrix.sample`) khi chạy truy vấn matrix 12 lần liên tiếp (mỗi lần 1,8–2,0 s). Số mẫu dưới đây là tổng bao hàm theo hàm nên chồng nhau, chỉ dùng để xếp hạng; ước lượng thô, chưa phải tỉ lệ chính xác.

- Giả thuyết cũ ("tính lại `grid` cho từng ô") **không phải** nguyên nhân chính: `measureValue` có tổng bao hàm lớn nhưng các hàm hot nằm ở dưới nó, trong lan truyền bộ lọc.
- **Nguyên nhân chính: lan truyền bộ lọc từ bảng chiều sang bảng fact**. `Propagation.visibleRows` (≈12,7 nghìn mẫu bao hàm) → `RelationshipIndex.manyRows(from:restrictedTo:)` (≈8,9 nghìn) → `manyRows(from:strategy:)` (≈5,7 nghìn), trong đó phần lớn là `out.sort()` ở `RelationshipIndex.swift:166`: gộp posting list của nhiều mã rồi sắp lại hàng triệu dòng. Top hàm theo mẫu: `_merge` (sắp xếp) 4007, `RowSet.bits(of:)` 2804, `RowSet.union(disjointLists:)` 2435, `RowSet.forEach` 1640, `Set.insert` 1358.
- Có một pha tuần tự trước các ô song song: `SummarizeColumns.groupCombinations` → `visibleRows` (≈7,2 nghìn bao hàm), vì vậy 8 luồng không giúp được phần này.
- Phần phụ: `FilterContext.values(of:among:)` (≈5,2 nghìn) dựng `Set` bằng cách băm từng giá trị.

**Quyết định (đề xuất, chờ bạn duyệt ở T006)**: matrix không dùng đường gộp của combo. Sửa riêng, giữ nguyên ngữ nghĩa:

1. `RelationshipIndex.manyRows(from:strategy:)` nhánh postings: thay `append + sort()` bằng hợp theo bitset (`RowSet.union(universe:disjointLists:)` đã có và dùng ở vòng 2). Kết quả là cùng một tập dòng đã sắp, nên khớp byte. Đây là thay đổi ở module `ColumnStore` (`Sources/ColumnStore/RelationshipIndex.swift`), ngoài danh sách file của plan, cần bạn đồng ý.
2. Nếu chưa đủ: `FilterContext.values(of:among:)` bỏ `Set` băm (dùng mảng bit theo mã), và xem lại pha `groupCombinations` tuần tự.

## R5. FilterContext ít cấp phát (hướng 2)

- **Quan sát [ĐO]**: vòng 2 thử giảm cấp phát nhỏ (tập mã một giá trị, tách mục cục bộ một lượt), không đo được lợi ích.
- **Quyết định**: chỉ dùng hướng 2 như phần bổ trợ nếu sau hướng 1 matrix còn trên ngưỡng và `sample` chỉ ra cấp phát là nguyên nhân chính. Không đầu tư trước.

## R6. Phương án đã loại

| Phương án | Lý do loại |
|---|---|
| Cache kết quả theo dòng giữa các truy vấn | Chỉ giúp lần chạy sau, không giúp lần đầu mở trang; thêm trạng thái chung giữa truy vấn |
| Viết riêng đường tính cho `Avg_Account_Balance` | Gắn tên measure vào engine; vi phạm nguyên tắc "visual sinh DAX giống Performance Analyzer, không làm đường tính thứ hai" |
| Dùng Metal/GPU | Dữ liệu và truy vấn không hợp, rủi ro cao so với lợi ích |
| Đổi cách lặp sang sinh mã (JIT) | Quá lớn so với mục tiêu, khó bảo đảm khớp byte |

## R7. Cách chứng minh khớp

- Công tắc `BIPRO_BATCH=0` tắt đường gộp. Test chạy cùng một truy vấn hai lần (bật/tắt) và so từng byte trên Nhom6 và trên dữ liệu nhỏ có nhóm rỗng, `t` BLANK, trùng giá trị.
- `e3-loop.sh` so với `build/e3-base/`. Golden Phase B/C không đổi.

## R8. Dữ liệu lớn hơn Nhom6 (suy luận, không đo)

Với N dòng fact đã lọc, G nhóm và K ô của `SUMMARIZECOLUMNS`:

- **Đường cũ**: mỗi ô tốn dựng ngữ cảnh và quét tập dòng của nhóm, tổng cỡ O(K × G) lần dựng cộng O(N) lần đọc dòng; hằng số dựng ngữ cảnh lớn (~45 µs).
- **Đường gộp**: cỡ O(N) mỗi lần quét, hai lần quét, cộng O(G) cho mảng kết quả theo mã nhóm; không còn thành phần K × G.
- **Bộ nhớ thêm**: mảng `GroupedResult` cỡ G giá trị (vài chục nghìn tài khoản ở Nhom6, tức vài trăm KB), cộng tập dòng đã lọc (cỡ N bit hoặc N chỉ số). Tập dòng này đường cũ cũng phải dựng, nên mức tăng bộ nhớ đỉnh dự kiến nhỏ.
- **Kết luận**: đường gộp co giãn tốt hơn đường cũ theo K × G; không có bằng chứng đo trên dữ liệu lớn hơn Nhom6 (không có sẵn). SC-005 chỉ kiểm trên Nhom6.

## R9. Kết quả thực hiện (2026-11-09)

Chẩn đoán ở R1–R4 cần chỉnh lại sau khi đo trên mã thật:

1. **Combo thấu chi**: đường gộp (R2) đúng và cần thiết (2,15 → 0,53 s), nhưng lần chạy đầu của đường gộp lại chậm hơn (3,4 s) vì bước dựng bảng lặp `VALUES(account_key)` mới lộ ra là điểm nghẽn: `FilterContext.values(of:among:)` băm `Set<Int>` từng dòng rồi sắp bằng bộ so sánh gọi `ColumnIndex.sortRank`, mà mỗi lần gọi retain/release một bảng hạng dùng chung nên 8 luồng tranh chấp (riêng 72 ô `VALUES` mất 2–3 s). Sửa: mảng cờ theo mã + duyệt `codesInSortOrder()` (cùng thứ tự kết quả). Bài học: dự báo ở R3 (0,5–0,6 s) chỉ đúng sau khi gỡ điểm nghẽn này; thử nghiệm T004 đo phép quét, không đo bước dựng bảng lặp.
2. **Matrix Giờ × Thứ** (R4): ba điểm nghẽn theo thứ tự, mỗi cái đo lại bằng `sample`:
   - `RelationshipIndex.manyRows` sắp lại cả triệu dòng → hợp bitset (1,66 → 1,06 s; combo kênh 0,72 → 0,13 s);
   - `hasUnmatched(in:)` quét cả bảng nhiều dù đã biết không có dòng lệch → thoát sớm (1,06 → 1,04 s);
   - `SummarizeColumns.groupCombinations` băm `[Value]` cho từng dòng fact thấy được (cột nhóm `trans_hour`) → lấy tổ hợp theo mã (1,04 → 0,42 s).
3. **`Aggregation.extremeOfColumn`** (MAX/MIN cột mã hoá): gọi `sortRank` và `code(atRow:)` từng dòng và không kiểm tra huỷ → đọc bảng hạng một lần, con trỏ, kiểm huỷ theo đợt. Cần để giữ độ trễ huỷ (FR-005).
4. **Test huỷ** `huyTruyVanNangDungNhanh` (ORAGoldenTests): sau tăng tốc, mọi truy vấn golden `G*` xong dưới 0,6 s nên test (huỷ ở 500 ms) báo "nhận nil" vì truy vấn đã xong. Giữ ngưỡng 100 ms và kiểm lỗi `cancelled`, chỉ đổi khối lượng: lặp truy vấn `G1-year__FT` cho tới khi bị huỷ. Trên bản chưa sửa, test cũ qua 6/6; với test mới sau sửa qua 6/6.
5. **Hướng 2 (FilterContext ít cấp phát)** không cần.
