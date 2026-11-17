Bạn làm việc trong repo Swift "BI Pro" (ứng dụng macOS giống Power BI Desktop, macOS 15), trong một git worktree riêng tách từ `main`. Gói của bạn, **F2-DAXTEXT**: 18 hàm văn bản DAX trong engine (`Sources/DAXEngine`), khớp **kết quả thật của Power BI Desktop 2.159** ghi trong golden `docs/phase-f2-evidence/vm-f12/golden.tsv`. Chỉ dùng framework hệ thống; không thêm package, không tải gì từ mạng; không commit, không push.

## Đọc trước (giữ nguyên, không sửa)

- `docs/phase-f2-evidence/vm-f12/QUAN-SAT.md`: quy tắc Desktop đã quan sát. Mục 1 là quy tắc chung, mục 2 bảng từng hàm, mục 4 thông báo lỗi nguyên văn. Đây là đặc tả của bạn.
- `docs/phase-f2-evidence/vm-f12/golden.tsv`: 1 198 ô, cột Case, Table, ID, Expr, Result.
  - Result: `E` lỗi, `B` BLANK, `T:<chuỗi>`, `L:TRUE|FALSE`, `N:<số>`.
  - Giá trị thoát `\\`, `\t`, `\n`, `\r`.
  - Table `HCol`: biểu thức chạy trong row context của bảng `text_cases` tại dòng có `ID`. Table `HLit*`: biểu thức hằng.
  - Các ca `IN-Txt`, `IN-Nfd`, `IN-Num` là dữ liệu vào của `text_cases`: ID số nguyên 1–20, Txt và Nfd là chuỗi (ô trống là chuỗi rỗng, không phải BLANK), Num số thực.
- `Sources/DAXEngine/Functions/Text.swift`: `TextFunctions.functions` đã có `FORMAT`, `CONTAINSSTRING`, `CONTAINSSTRINGEXACT`, `SEARCH`, `LEFT`. Mẫu khai báo `FunctionSpec`, `CallFrame` (`scalar(i)`, `isBlankArgument(i)`), `DAXError`.
- `Sources/DAXEngine/Functions/Registry.swift` đã gộp `TextFunctions.functions`; trùng tên giữa các họ là lỗi.
- `Sources/DAXEngine/Runtime/Value+Ops.swift`: `Value.asText()` (đổi sang chuỗi như `&`, đã khớp golden), `Value.concatenate` (`&`; BLANK & BLANK = BLANK), `asDouble()`, `isBlank`. **Dùng chúng** khi đổi kiểu đối số.
- Mẫu test có bảng trong bộ nhớ: `Tests/DAXEngineTests/F-AGG/FAggSupport.swift` (`FAggKho`: `ModelSchema`, `InMemoryColumnSource`, `ColumnBuilder`, `Catalog`, `Evaluator`, `Binder.bind(parseExpression(…))`). Row context: xem cách `Sources/DAXEngine/Functions/Iterators.swift` gọi `frame.iterateArgument`.

## Tệp được sửa hoặc tạo (không sửa gì ngoài danh sách)

- `Sources/DAXEngine/Functions/Text.swift`: thêm khai báo vào `TextFunctions.functions`; sửa `SEARCH`, `LEFT` cho khớp golden.
- `Sources/DAXEngine/Functions/TextMore.swift` (tạo mới): thân hàm, dạng `extension TextFunctions`.
- `Tests/DAXEngineTests/F-TEXT/**` (tạo mới): `TextFunctionGoldenTests.swift` và test đơn vị khác nếu cần.
- `Tests/DAXEngineTests/F-KIT/FKITTextTests.swift`: chỉ khi một kỳ vọng cũ trái golden. Ghi từng chỗ sửa vào báo cáo.
- `docs/tasks/f2-daxtext-report.md`: báo cáo cuối.

Mọi tệp khác giữ nguyên. Gồm `Registry.swift`, `Iterators.swift` (lead đã sửa `CONCATENATEX`), `Value+Ops.swift`, `Package.swift`, golden và mọi test khác.

Nếu thấy lõi engine (Evaluator, Binder, `Value+Ops`) sai hoặc thiếu thứ bạn cần thì không sửa. Ghi vào báo cáo, mục "Đề xuất cho lead", rồi làm tiếp phần còn lại.

## Hàm

`LEN`, `UPPER`, `LOWER`, `MID`, `RIGHT`, `TRIM`, `SUBSTITUTE`, `REPLACE`, `CONCATENATE`, `FIND`, `REPT`, `VALUE`, `EXACT`, `UNICHAR`, `UNICODE`, `FIXED`, `COMBINEVALUES` (mới), cộng `SEARCH` và `LEFT` (sửa). `CONCATENATEX` không thuộc gói: nó ở `Iterators.swift`; đừng khai báo lại.

Quy tắc chung, đã quan sát (chi tiết ở QUAN-SAT mục 1–2):

- **Đơn vị là UTF-16 code unit**: `LEN(emoji)` = 2; vị trí trong `MID`, `FIND`, `SEARCH` đếm theo code unit. Làm việc trên `Array(s.utf16)`, không dùng `Character`/`count` của Swift.
  - Cắt giữa cặp surrogate cho surrogate lẻ. Swift `String` không giữ được surrogate lẻ: dựng kết quả bằng `String(decoding: units, as: UTF16.self)`, surrogate lẻ thành U+FFFD. Golden ghi U+FFFD ở các ô đó.
- **Đối số số làm tròn tới số nguyên gần nhất** (2.9 → 3, 1.7 → 2), không cắt. [SUY ĐOÁN] Nửa (x.5) làm tròn xa số 0.
- **Đối số chữ nhận số và logic**, đổi bằng `asText()`. BLANK ở đối số chữ: xem bảng từng hàm (nhiều hàm trả BLANK khi text là BLANK, `REPLACE` thì coi là "").
- **So sánh**:
  - `FIND`, `SUBSTITUTE`, `EXACT` so nhị phân theo code unit.
  - `SEARCH` không phân biệt hoa thường nhưng phân biệt dấu (`SEARCH("o", "ộ")` không thấy).
  - Không chuẩn hoá Unicode (NFC ≠ NFD).
- **Lỗi**: `throw DAXError(...)` với thông điệp nguyên văn Desktop ở QUAN-SAT mục 4, ví dụ "An argument of function 'MID' has the wrong data type or has an invalid value.". Chọn kind `.runtime`, hoặc `.typeMismatch` cho `VALUE`.
- **`COMBINEVALUES`**: delimiter phải là hằng chuỗi khác rỗng. `""` và `BLANK()` bị Desktop từ chối lúc dịch; hằng số `0` được nhận ("a0b").
  - Kiểm được lúc bind thì tốt; không thì ném lỗi lúc chạy với thông điệp "The delimiter value in the 'COMBINEVALUES' function can only be a constant non empty string.".
  - Test riêng ca này, vì nó không có trong golden.
- **`VALUE`**: đọc theo en-US.
  - Dấu phẩy là phân cách nghìn ("1,5" → 15); `$`, ngoặc âm "(5)" → −5, "+7", mũ "1e3", khoảng trắng hai đầu (cả tab).
  - Chuỗi ngày "2026-01-02" → số ngày 46024; giờ "12:00" → 0.5.
  - Lỗi: "10%", "", "TRUE", chữ.
  - Kết quả là số; khớp golden theo `asText()`.
- **`FIXED(number, [decimals], [no_commas])`**:
  - Làm tròn nửa xa số 0, decimals âm làm tròn bên trái.
  - Mặc định 2 chữ số và có phân cách nghìn ",". Số âm làm tròn ra 0 thì không có dấu trừ ("0.00").
  - BLANK → "0.00"; decimals BLANK → 0; decimals 128 → lỗi ([SUY ĐOÁN] giới hạn 127).

## Test (viết test đỏ trước, rồi cài cho xanh, từng hàm một)

`Tests/DAXEngineTests/F-TEXT/TextFunctionGoldenTests.swift`:

- Đọc `golden.tsv` theo đường dẫn tính từ `#filePath`. Không chép giá trị vào code, không hard-code.
- Dựng bảng `text_cases` trong bộ nhớ từ các ca `IN-*`.
- Mỗi ô `HLit` được đánh giá như một biểu thức vô hướng.
- Mỗi ô `HCol` được đánh giá trong row context của dòng `ID` đó. Lỗi ở một dòng chỉ làm ô đó thành `E`.
- Mã hoá kết quả của engine giống golden, rồi so chuỗi:
  - lỗi `DAXError` → `E`;
  - `.blank` → `B`;
  - chuỗi → `T:…`;
  - logic → `L:…`;
  - số → `N:` + `asText()`.
- **Bốn ô được miễn** là `MID-emoji-u`, `MID-emoji-u3`, `RIGHT-emoji-u`, `LEFT-emoji-u` (`UNICODE` của surrogate lẻ). Swift không giữ được surrogate lẻ nên không khớp được; liệt kê chúng trong test như danh sách miễn có lý do.
- Mọi ô còn lại phải khớp 100%.
- Khi trượt, in Case, ID, Expr, mong đợi và thực tế để dễ sửa.

## Lệnh kiểm (đều phải qua trước khi bàn giao)

1. `swift build`
2. `swift test --filter "F-TEXT|TextFunction|FKIT"`
3. `swift test` toàn bộ: phải qua hết. Số test hiện tại 2271, cộng test mới của bạn.
4. Golden nặng: `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|Batched|F6|T116|F2"`. Phải giữ nguyên 122 test qua. Thiếu tệp mẫu thì test tự bỏ qua; ghi điều đó vào báo cáo.
5. `git status` chỉ có tệp trong danh sách ở trên.

Chưa đạt thì tự sửa tiếp. Không sửa được thì ghi rõ lý do trong báo cáo, không bàn giao như đã xong.

## Báo cáo `docs/tasks/f2-daxtext-report.md`

- Tệp đã sửa.
- Tóm tắt từng hàm.
- Số ô golden khớp trên tổng.
- Lệnh đã chạy kèm dòng kết quả cuối ("Test run with N tests passed…").
- Chỗ `[SUY ĐOÁN]` đã thêm.
- Mục "Đề xuất cho lead".
