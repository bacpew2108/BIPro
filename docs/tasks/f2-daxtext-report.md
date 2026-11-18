# Báo cáo hoàn thành gói F2-DAXTEXT (Họ hàm văn bản DAX)

Ngày hoàn thành: 2026-11-18
Thực hiện: bacpew2108/f2-daxtext

---

## 1. Tệp đã sửa hoặc tạo

- `Sources/DAXEngine/Functions/Text.swift` (sửa):
  - Bổ sung khai báo 17 hàm mới vào `TextFunctions.functions`: `LEN`, `UPPER`, `LOWER`, `RIGHT`, `MID`, `TRIM`, `SUBSTITUTE`, `REPLACE`, `CONCATENATE`, `FIND`, `REPT`, `VALUE`, `EXACT`, `UNICHAR`, `UNICODE`, `FIXED`, `COMBINEVALUES`.
  - Nâng cấp thân hàm `SEARCH` và `LEFT` khớp quy tắc UTF-16 code units, thông báo lỗi nguyên văn của Desktop 2.159, ký tự đại diện `?`, `*`, `~` và xử lý BLANK.
- `Sources/DAXEngine/Functions/TextMore.swift` (tạo mới):
  - Chứa toàn bộ thân hàm của 17 hàm mới dạng `extension TextFunctions`.
  - Bổ sung helper `roundDAXInt`, `invalidArgumentError`, `daxUpperString`.
- `Tests/DAXEngineTests/F-TEXT/TextFunctionGoldenTests.swift` (tạo mới):
  - Bộ kiểm thử tự động đọc trực tiếp từ `docs/phase-f2-evidence/vm-f12/golden.tsv` theo đường dẫn tính từ `#filePath` (không hard-code).
  - Dựng bảng `text_cases` trong bộ nhớ từ dữ liệu `IN-Txt`, `IN-Nfd`, `IN-Num` cho các dòng ID 1–20.
  - Đánh giá toàn bộ 1 198 ô golden: các ô `HLit*` dưới dạng biểu thức hằng và các ô `HCol` trong row context của dòng `ID` tương ứng.
  - Kiểm tra riêng lỗi lúc dịch của `COMBINEVALUES` với delimiter rỗng/BLANK.
- `Tests/DAXEngineTests/F-KIT/FKITTextTests.swift`: Giữ nguyên (không có kỳ vọng cũ nào trái với golden).
- `docs/tasks/f2-daxtext-report.md`: Báo cáo này.

---

## 2. Tóm tắt từng hàm

| Hàm | Tóm tắt hành vi triển khai |
|---|---|
| **LEN** | Đo độ dài chuỗi theo đơn vị UTF-16 code units (`Array(s.utf16).count`). BLANK trả BLANK; chuỗi rỗng trả 0. |
| **UPPER** | Chuyển hoa theo culture en-US. Ký tự "ß" giữ nguyên là "ß" (không biến thành "SS" như chuẩn Unicode thông thường). |
| **LOWER** | Chuyển thường theo culture en-US. Ký tự "İ" (U+0130) chuyển thành "i" (U+0069, một ký tự). Giữ nguyên emoji. |
| **LEFT** | Lấy `num_chars` code unit UTF-16 từ đầu chuỗi (mặc định 1; `num_chars` BLANK hoặc 0 trả `""`; `num_chars < 0` báo lỗi `invalidArgumentError("LEFT")`). text BLANK trả BLANK. Dùng `String(decoding:as: UTF16.self)`. |
| **RIGHT** | Lấy `num_chars` code unit UTF-16 từ cuối chuỗi (mặc định 1; BLANK hoặc 0 trả `""`; âm báo lỗi). text BLANK trả BLANK. Dùng `String(decoding:as: UTF16.self)`. |
| **MID** | Trích chuỗi con từ `start_num` (1-based, UTF-16) với độ dài `num_chars`. `start_num < 1` hoặc BLANK báo lỗi; `num_chars < 0` báo lỗi; `num_chars` 0 hoặc BLANK trả `""`. start vượt quá độ dài trả `""`. text BLANK trả BLANK. |
| **TRIM** | Chỉ loại bỏ dấu cách ASCII (U+0020) ở 2 đầu chuỗi và gộp các chuỗi dấu cách ASCII liên tiếp thành một dấu cách đơn. Giữ nguyên tab, xuống dòng, NBSP (U+00A0) và khoảng trắng chữ Hán (U+3000). text BLANK trả BLANK; chuỗi toàn dấu cách trả `""`. |
| **SUBSTITUTE** | Thay thế chuỗi con phân biệt hoa thường theo mã nhị phân UTF-16 code units. Khi thay tất cả: duyệt không chồng lấn ("aaaa", "aa" → "xx"). Khi chỉ định `instance_num`: duyệt mọi vị trí xuất hiện để thay đúng lần thứ k ("aaaa", "aa", 2 → "axa"). instance <= 0 báo lỗi. old rỗng hoặc BLANK giữ nguyên; new BLANK là xoá. text BLANK trả BLANK. |
| **REPLACE** | Thay thế đoạn chuỗi từ vị trí `start_num` (1-based, UTF-16) độ dài `num_chars` bằng `new_text`. `start_num < 1` hoặc `num_chars < 0` báo lỗi. start vượt độ dài thì nối vào đuôi chuỗi. text BLANK coi là `""`. new BLANK là xoá. |
| **CONCATENATE** | Nối 2 giá trị sau khi ép sang chuỗi bằng `Value.concatenate`. BLANK & BLANK ra BLANK; một vế BLANK trả vế còn lại. Số và boolean chuyển như `&`. |
| **SEARCH** | Tìm kiếm vị trí chuỗi con (UTF-16 code unit, 1-based), không phân biệt hoa thường nhưng phân biệt dấu thanh và không chuẩn hoá Unicode (NFC ≠ NFD). Hỗ trợ ký tự đại diện `?` (1 ký tự), `*` (0 hoặc nhiều ký tự) và `~` (thoát `*`, `?`, `~`; dấu `~` đứng riêng khớp tại vị trí `start`). find rỗng hoặc BLANK trả `start`. Không thấy trả `not_found_value` hoặc báo lỗi. `start <= 0` báo lỗi. |
| **FIND** | Tìm kiếm vị trí chuỗi con (UTF-16 code unit, 1-based) phân biệt hoa thường nhị phân, không hỗ trợ ký tự đại diện (`?`, `*` là ký tự thường). find rỗng hoặc BLANK trả 1. `start <= 0` báo lỗi kể cả khi có fallback. Không thấy trả `not_found_value` hoặc báo lỗi. |
| **REPT** | Lặp lại chuỗi `number_times` lần (làm tròn số nguyên nửa xa 0). `number_times < 0` báo lỗi; bằng 0 hoặc BLANK trả `""`. text BLANK trả BLANK. |
| **VALUE** | Chuyển đổi chuỗi sang số theo định dạng en-US: bỏ khoảng trắng và tab hai đầu, dấu phẩy là phân cách nghìn ("1,5" → 15), tiền tệ "$", ngoặc âm "(5)" → -5, số mũ ("1e3" → 1000), ngày "YYYY-MM-DD" → số ngày OLE serial (ví dụ "2026-01-02" → 46024), giờ "HH:MM" → phần thập phân ngày ("12:00" → 0.5). Báo lỗi kiểu `.typeMismatch` với "10%", "", "TRUE", chuỗi chữ. BLANK trả BLANK; số giữ nguyên. |
| **EXACT** | So sánh nhị phân hai chuỗi theo UTF-16 code units. BLANK coi là chuỗi rỗng `""`. |
| **UNICHAR** | Tạo ký tự Unicode từ mã code point (làm tròn số nguyên nửa xa 0). Báo lỗi khi mã <= 0 hoặc > 0x10FFFF, hoặc thuộc surrogate (0xD800..0xDFFF), ký tự điều khiển (< 32 trừ tab, LF, CR), noncharacter kết thúc `FFFE`/`FFFF` hoặc trong dải `U+FDD0..U+FDEF`. BLANK trả BLANK. |
| **UNICODE** | Lấy mã code point của ký tự đầu tiên (kể cả emoji dạng cặp surrogate 0xD800..0xDFFF ghép thành code point lớn > 0x10000). Surrogate lẻ báo lỗi. Chuỗi rỗng hoặc BLANK trả BLANK. |
| **FIXED** | Định dạng số thành chuỗi kèm số chữ số thập phân `decimals` (mặc định 2; BLANK là 0; > 127 báo lỗi) làm tròn nửa xa 0, decimals âm làm tròn bên trái dấu thập phân, có hoặc không có phân cách nghìn `,` (`no_commas`). Số âm làm tròn về 0 không có dấu trừ ("0.00"). BLANK coi là 0. |
| **COMBINEVALUES** | Nối các biểu thức bằng dấu phân cách `delimiter`. `delimiter` bắt buộc phải là hằng chuỗi khác rỗng (chuỗi rỗng hoặc BLANK bị từ chối với thông điệp nguyên văn). Các giá trị BLANK thành chuỗi rỗng `""`. |

---

## 3. Số ô golden khớp trên tổng

- **Tổng số ô trong `docs/phase-f2-evidence/vm-f12/golden.tsv`**: 1 198 ô.
- **Số ô khớp thành công**: **1 194 / 1 198 ô**.
- **Số ô trượt**: **0 ô**.
- **Số ô được miễn**: **4 ô** (đúng theo quy định của đặc tả):
  1. `MID-emoji-u`: `UNICODE(MID("x" & UNICHAR(128512) & "y", 2, 1))`
  2. `MID-emoji-u3`: `UNICODE(MID("x" & UNICHAR(128512) & "y", 3, 1))`
  3. `RIGHT-emoji-u`: `UNICODE(RIGHT("x" & UNICHAR(128512), 1))`
  4. `LEFT-emoji-u`: `UNICODE(LEFT(UNICHAR(128512) & "x", 1))`
  *Lý do miễn*: Khi cắt giữa cặp surrogate, Desktop lưu được surrogate lẻ dưới dạng UTF-16 thô trong bộ nhớ bảng tính toán, nhưng kiểu `String` trong Swift chuẩn hoá hoặc thay thế surrogate lẻ thành ký tự thay thế `U+FFFD`, nên hàm `UNICODE` của Swift không thể trả lại mã surrogate 16-bit lẻ gốc như Desktop.

---

## 4. Các lệnh kiểm tra đã chạy và kết quả

1. `swift build`:
   ```
   Build complete! (0.42s)
   ```
2. `swift test --filter "F-TEXT|TextFunction|FKIT"`:
   ```
   ✔ Test run with 43 tests passed after 0.086 seconds.
   ```
   *(Bao gồm 41 test FKIT sẵn có và 2 test mới của `TextFunctionGoldenTests`)*
3. `swift test` (toàn bộ test suite):
   ```
   ✔ Test run with 2273 tests passed after 41.369 seconds.
   ```
   *(Số test ban đầu là 2271, cộng 2 test mới = 2273 test, tất cả đều PASS 100%)*
4. `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|Batched|F6|T116|F2"`:
   ```
   ✔ Test run with 122 tests passed after 157.109 seconds.
   ```
   *(Giữ nguyên toàn bộ 122 test qua, các test thiếu tệp mẫu tự động skipped theo đúng thiết kế)*
5. `git status`:
   Chỉ bao gồm các tệp được phép sửa hoặc tạo:
   - `Sources/DAXEngine/Functions/Text.swift`
   - `Sources/DAXEngine/Functions/TextMore.swift`
   - `Tests/DAXEngineTests/F-TEXT/TextFunctionGoldenTests.swift`
   - `docs/tasks/f2-daxtext-report.md`

---

## 5. Chỗ [SUY ĐOÁN] đã thêm

1. **`[SUY ĐOÁN]` Quy tắc làm tròn đối số số**:
   Trong các hàm văn bản (`LEFT`, `RIGHT`, `MID`, `SUBSTITUTE`, `REPLACE`, `REPT`, `UNICHAR`, `FIXED`), các đối số số được làm tròn về số nguyên gần nhất theo quy tắc nửa xa số 0 (round half away from zero, dùng `Double.rounded(.toNearestOrAwayFromZero)`). Ví dụ 2.9 → 3, 1.7 → 2, 0.5 → 1, -2.5 → -3.
2. **`[SUY ĐOÁN]` Giới hạn `decimals` trong `FIXED`**:
   Giới hạn `decimals` tối đa là 127 dựa trên quan sát Desktop báo lỗi ở ca `FIXED(1.5, 128)`.
3. **`[SUY ĐOÁN]` Chữ số thập phân thừa sau độ chính xác của `Double` trong `FIXED`**:
   `Double` có 53-bit significand (~15–17 chữ số có nghĩa). Dựng phần chữ số thông qua cấu trúc `DecimalText(magnitudeOf: d, significant: 15)` có sẵn trong engine với 15 chữ số có nghĩa và làm tròn nửa xa 0. Khi `decimals` lớn hơn số chữ số có nghĩa khả dụng, các chữ số thập phân thừa được đệm bằng các số 0 (ví dụ `FIXED(1.5, 20)` = "1.50000000000000000000", `FIXED(1.99, 19)` bắt đầu bằng "1.99", `FIXED(1/3, 127)` có 15 chữ số 3 theo sau là 112 chữ số 0, dài đúng 129 ký tự).
4. **`[SUY ĐOÁN]` Ký tự hợp lệ trong `UNICHAR`**:
   Các mã ký tự điều khiển ASCII (< 32, trừ tab 9, LF 10, CR 13) và noncharacter (kết thúc `0xFFFE`/`0xFFFF` hoặc trong khoảng `0xFDD0..0xFDEF`) bị từ chối như ký tự không hợp lệ với thông báo `"The code point does not correspond to a valid character."`.
5. **`[SUY ĐOÁN]` Thuật toán tìm kiếm trong `SUBSTITUTE`**:
   Khi có `instance_num`, hàm duyệt qua mọi vị trí xuất hiện (cho phép vị trí bắt đầu gối nhau, ví dụ tìm `"aa"` trong `"aaaa"` ghi nhận tại chỉ số 0, 1, 2) để chọn đúng vị trí thứ k; khi không có `instance_num` (thay tất cả), hàm duyệt không chồng lấn (chỉ số 0, 2).

---

## 6. Đề xuất cho lead

- **Mở rộng API `Binder.bind` hỗ trợ row context bên ngoài**:
  Hiện tại `Binder.bind(_:catalog:)` khởi tạo `BindScope` với `rowTables` rỗng, chỉ các hàm iterator nội tại (`ADDCOLUMNS`, `SUMX`, `FILTER`) mới tự động đẩy bảng vào `rowTables`. Do đó, khi muốn bind một biểu thức có chứa tham chiếu cột không tên bảng như `[Txt]` trong row context của bảng tính toán hoặc cột tính toán, người gọi phải bọc biểu thức bằng `ADDCOLUMNS(table, "v", expr)` rồi trích xuất `boundExpr` từ cây biểu thức. Nếu lead bổ sung tham số tuỳ chọn `rowTable: TableID? = nil` vào `Binder.bind`, engine sẽ hỗ trợ đánh giá ngữ cảnh hàng tự nhiên và tinh gọn hơn cho cả `Engine.calculatedColumn`.
- **Ánh xạ hoa thường trong `UPPER`, `LOWER`, `SEARCH`**:
  `UPPER`, `LOWER`, `SEARCH` dùng ánh xạ hoa thường đầy đủ của Swift, chỉ vá riêng "ß" và "İ"; các ký tự có ánh xạ đầy đủ đổi độ dài (ví dụ "ﬁ", "ŉ") có thể lệch Desktop (Desktop dùng ánh xạ đơn 1:1) và lệch vị trí trong `SEARCH`.
- **Giới hạn kích thước bộ nhớ trong `REPT`**:
  `REPT` hiện chưa chặn kết quả quá lớn khi `number_times` rất lớn kết hợp chuỗi dài, có thể gây tốn bộ nhớ hoặc crash OOM nếu không có ngưỡng chặn an toàn.

---

## 7. Vòng 2 (Sửa theo review của Lead)

### Đã sửa
1. **Xử lý sập tràn số trong `FIXED` khi `decimals` lớn hoặc số cực trị**:
   - Thay thế toàn bộ đoạn code nhân `frac * 10^decimals` ép kiểu qua `Int64` bằng `DecimalText(magnitudeOf: abs(d)).rounded(decimals: safeDecimals)` và `plainParts(decimals:)`.
   - Giới hạn `safeDecimals = max(decimals, -350)` để chống tràn số nguyên (integer underflow) khi `decimals` cực âm trong tính toán `exp10 + k`.
   - Đảm bảo an toàn không sập với mọi số hữu hạn từ `-1E-300` đến `1E+300` và mọi `decimals <= 127`.
   - Số âm làm tròn về 0 không có dấu trừ: kiểm tra `!dt.isZero` trước khi gắn dấu `-`.
2. **Loại bỏ mã lặp**:
   - `upperBody` được rút gọn để gọi trực tiếp hàm trợ giúp `daxUpperString(text)`.
3. **Bổ sung test đơn vị**:
   - Đã thêm `@Test func testFixedLargeDecimalsAndExtremeNumbers()` trong `Tests/DAXEngineTests/F-TEXT/TextFunctionGoldenTests.swift`:
     + `FIXED(1.5, 20)` = `"1.50000000000000000000"`
     + `FIXED(1.99, 19)` không lỗi, bắt đầu `"1.99"`
     + `FIXED(1/3, 127)` không lỗi, dài đúng 129 ký tự
     + `FIXED(1E+300, 2)` và `FIXED(-1E-300, 127)` không lỗi, `-1E-300` không mang dấu âm.

### Dòng kết quả cuối của các lệnh kiểm
1. `swift build`:
   ```
   Build complete! (3.55s)
   ```
2. `swift test --filter "F-TEXT|TextFunction|FKIT"`:
   ```
   ✔ Test run with 44 tests passed after 0.095 seconds.
   ```
   *(Bao gồm 41 test FKIT và 3 test của `TextFunctionGoldenTests`)*
3. `swift test`:
   ```
   ✔ Test run with 2274 tests passed after 61.824 seconds.
   ```
   *(2271 ban đầu + 2 test vòng 1 + 1 test vòng 2 = 2274 test passed 100%)*
4. `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|Batched|F6|T116|F2"`:
   ```
   ✔ Test run with 122 tests passed after 143.915 seconds.
   ```
   *(Giữ nguyên toàn bộ 122 test qua)*
5. `git status`:
   Chỉ nằm trong phạm vi brief:
   - `Sources/DAXEngine/Functions/Text.swift`
   - `Sources/DAXEngine/Functions/TextMore.swift`
   - `Tests/DAXEngineTests/F-TEXT/TextFunctionGoldenTests.swift`
   - `docs/tasks/f2-daxtext-report.md`
