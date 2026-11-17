# VM-F12 (T018): hàm văn bản DAX trong Power BI Desktop

Ngày 2026-11-17, Desktop 2.159 (en-US), Claude lái VM. Tài liệu mới, nạp `build/f2-out/samples/text_cases.csv` qua Text/CSV (Load, không sửa gì): 20 dòng, ID số nguyên, Txt và Nfd chữ, Num số thực.

## Cách đo

- `scripts/f2-samples/vm_f12_queries.py` sinh 286 ca: 48 ca trên cột (`HCol`, 20 dòng mỗi ca) và 238 ca hằng (`HLit1..3`). Các ca được dán vào Table view ▸ New table thành bảng tính toán. Ký tự đặc biệt viết bằng `UNICHAR` để công thức chỉ có ASCII.
- Mỗi kết quả được mã hoá thành chuỗi:
  - `E`: lỗi;
  - `B`: BLANK;
  - `T:<chuỗi>`;
  - `L:<TRUE|FALSE>`;
  - `N:<số & "">`.
  Phép mã hoá là `IF(ISERROR(<e>), "E", VAR v = <e> RETURN …)`.
- Lưu `f12-desktop.pbix` (ngoài git). `scripts/f2-samples/vm_f12_golden.py` đọc bảng qua `pbix-dump rows --escape` và ghi `golden.tsv`.
- `golden.tsv` có 5 cột: Case, Table, ID, Expr, Result. Giá trị thoát `\\`, `\t`, `\n`, `\r`.
- Tổng 1 198 ô; hàm ít nhất là TRIM với 28 ô.
- Surrogate lẻ ghi U+FFFD (xem mục 2).

Ba trở ngại của cách đo, cũng là quan sát:

1. **Bảng lưu chuỗi không phân biệt hoa thường.** Hai chuỗi chỉ khác hoa thường ("FIND-b"/"FIND-B", "T:ABC"/"T:abc") thành một giá trị, giữ cách viết gặp trước.
   - Ngay lúc nạp CSV, dòng 8 "ABC" thành "abc", nên `IN-Txt#8` là `abc`.
   - Vì vậy mỗi R mang tiền tố riêng (tên ca, `#ID`) để không giá trị nào trùng.
   - [CHƯA KIỂM] BI Pro có gộp như vậy khi nạp không. Đây là việc tồn đọng mới, ngoài spec 011.
2. **ISERROR với VAR.** `VAR v = MID("abcdef", 0, 2) RETURN ISERROR(v)` không bắt được lỗi; Desktop báo lỗi cả bảng. Phải viết `ISERROR(MID(...))` trực tiếp.
3. **Lưới DAX query view không hiện được kết quả có surrogate lẻ.**
   - Hộp "Something went wrong" báo: "Unable to translate Unicode character \uD83D at index 1135 to specified code page."
   - Lưới báo: "An exception of type System.Text.EncoderFallbackException occured."
   - Bảng tính toán thì lưu được, nên kết quả lấy từ tệp `.pbix`.
   - Bộ đọc của BI Pro trước đây trả rỗng cả trang từ điển khi gặp surrogate lẻ. Đã sửa: `utf16LEString` giải mã từng đơn vị, test `UTF16LenientTests`.
   - Thông báo lỗi trong query view chỉ là "Failed to move the data reader to the next row."; lỗi chi tiết lấy ở thanh công thức của bảng tính toán (mục 4).

## 1. Quy tắc chung

- **Đối số số được làm tròn tới số nguyên gần nhất**, không cắt:
  - `MID("abcdef", 1.7, 2.6)` = "bcd";
  - `RIGHT(…, 2.9)` lấy 3 ký tự; `REPT("ab", 2.9)` lặp 3 lần;
  - `SUBSTITUTE(…, 1.9)` thay lần thứ 2;
  - `FIXED(1.23456, 2.9)` = "1.235"; `UNICHAR(65.7)` = "B".
- **Đơn vị là UTF-16 code unit**, như .NET:
  - `LEN(emoji)` = 2; `LEN` của "ộ" dạng NFD = 3;
  - `MID("x😀y", 2, 1)` là surrogate cao lẻ, `LEN` của nó = 1;
  - `FIND("y", "😀y")` = 3.
- **Không chuẩn hoá Unicode**:
  - `EXACT("ộ" NFC, "ộ" NFD)` = FALSE;
  - `SUBSTITUTE` trên cột NFD không thay "ộ" NFC;
  - `SEARCH("o", "ộ")` không thấy (−1), tức phân biệt dấu.
- **Đối số chữ nhận số và logic** (đổi sang chuỗi như `&`):
  - `LEN(123.45)` = 6; `LEN(TRUE())` = 4; `LOWER(TRUE())` = "true";
  - `MID(12345, 2, 2)` = "23"; `SUBSTITUTE(1000, 0, 9)` = "1999";
  - `UNICODE(TRUE())` = 84.
- **Số đổi sang chuỗi**:
  - tối đa 15 chữ số có nghĩa: `1/3` → "0.333333333333333";
  - `1E+20` → "1E+20"; `0.000001` → "0.000001"; `-2.50` → "-2.5";
  - `1234567890123` giữ nguyên;
  - ngày `DATE(2026,1,2)` → "1/2/2026".
- **Cột chữ từ CSV**: ô trống nạp thành chuỗi rỗng, không phải BLANK (`IN-Txt#5` = `T:`).

## 2. Từng hàm (giá trị đầy đủ ở `golden.tsv`)

| Hàm | Hành vi quan sát |
|---|---|
| LEN | BLANK → BLANK; "" → 0. |
| UPPER/LOWER | BLANK → BLANK. Đổi đúng chữ Việt (ĐÀ NẴNG ↔ đà nẵng, NFD cũng đổi). `UPPER("ß")` = "ß"; `LOWER("İ")` = "i" (một ký tự U+0069). Emoji giữ nguyên. |
| MID | start < 1 hoặc BLANK → lỗi. length < 0 → lỗi; length 0 hoặc BLANK → "". start vượt độ dài → "". text BLANK → BLANK. |
| RIGHT, LEFT | n mặc định 1; n < 0 → lỗi; n = 0 hoặc BLANK → ""; n vượt độ dài → cả chuỗi. text BLANK → BLANK. |
| TRIM | Chỉ bỏ dấu cách ASCII (U+0020) ở hai đầu và gộp chuỗi dấu cách giữa các từ thành một. Tab, xuống dòng, NBSP (U+00A0) và U+3000 giữ nguyên, nhưng dấu cách cạnh chúng vẫn được gộp hoặc bỏ: `TRIM(" a\t b ")` = "a\t b". BLANK → BLANK; chuỗi toàn dấu cách → "". |
| SUBSTITUTE | Phân biệt hoa thường. Không chồng lấn: "aaaa", "aa" → "xx"; lần 2 → "axa". instance 0 hoặc âm → lỗi. instance vượt số lần xuất hiện → giữ nguyên. old "" hoặc BLANK → giữ nguyên. new BLANK → xoá. text BLANK → BLANK. |
| REPLACE | start < 1 → lỗi; length < 0 → lỗi. start vượt độ dài → nối vào cuối ("abcdefX"). text BLANK → coi là "" ("X"). new BLANK → xoá. |
| CONCATENATE, `&` | BLANK & BLANK → BLANK; "a" & BLANK → "a". TRUE → "TRUE". |
| CONCATENATEX | Thiếu delimiter → nối liền. Thiếu thứ tự → tăng dần ("a-b-c"). Bảng rỗng → BLANK. Phần tử BLANK → chuỗi rỗng giữa hai dấu phân cách ("a,,c"). Số và logic đổi như `&`. |
| SEARCH | Không phân biệt hoa thường, phân biệt dấu. `?` và `*` là ký tự đại diện. `~` thoát `*`, `?`, `~`; một `~` đứng riêng khớp ở vị trí 1. find "" hoặc BLANK → start. Không thấy: không có giá trị dự phòng thì lỗi, có thì trả giá trị đó (kể cả BLANK). start 0 (không dự phòng) → lỗi. start > độ dài → lỗi (cả `SEARCH("", "abc", 4)`), có dự phòng thì trả dự phòng. within BLANK → không thấy. |
| FIND | Như SEARCH nhưng phân biệt hoa thường và không có ký tự đại diện (`?`, `*` là chữ thường). `FIND("", "abc", 3)` = 1 (khác SEARCH). start 0 → lỗi kể cả có dự phòng; start 4 hoặc 5 với dự phòng → −1. |
| REPT | n < 0 → lỗi; n = 0 hoặc BLANK → "". text BLANK → BLANK. |
| VALUE | Theo culture en-US: "1,5" = 15; "1,234.5"; " 12 " và "\t5" bỏ khoảng trắng; "1e3" = 1000; "$5" = 5; "(5)" = −5; "+7"; "007" = 7. "2026-01-02" → 46024 (số ngày); "12:00" → 0.5. Lỗi: "10%", "", "TRUE", chữ. BLANK → BLANK. Số → giữ nguyên. |
| EXACT | So nhị phân, phân biệt hoa thường và dấu cách. BLANK = "" = BLANK. Số và logic đổi sang chuỗi ("1" = 1, "TRUE" = TRUE()). |
| UNICHAR | 0, âm, surrogate (55357), 1114111, 1114112 → lỗi (`UNICODE(UNICHAR(1))` cũng lỗi, chưa tách lỗi thuộc hàm nào). Emoji → cặp surrogate. Đối số chữ "66" được đổi sang số. BLANK → BLANK. |
| UNICODE | Mã của ký tự đầu (code point, emoji = 128512). Surrogate lẻ → lỗi. "" và BLANK → BLANK. |
| FIXED | Mặc định 2 chữ số, có dấu phân cách nghìn ",". Làm tròn nửa xa số 0 (0.5 → "1", −2.5 → "−3"). Số chữ số âm làm tròn trái dấu thập phân (1234.567, −2 → "1,200"; 123456, −7 → "0"). no_commas TRUE → không phân cách. −0.001, 2 → "0.00" (không có dấu trừ). BLANK → "0.00"; decimals BLANK → 0 chữ số. Chữ số > 127 (thử 128) → lỗi. Text "12.3" → đổi sang số. |
| COMBINEVALUES | BLANK → "" ("a\|"; BLANK, BLANK → "\|"). Số và ngày đổi như `&`. Delimiter "" hoặc BLANK → lỗi lúc dịch; delimiter số `0` được nhận ("a0b"). |

## 3. Ca trên cột (bảng `HCol`)

- Khớp các quy tắc trên.
- `SEARCH("A?C", [Txt])` thấy ở "abc" (vị trí 1).
- `SEARCH("*b", …)` = 1 khi có "b".
- `VALUE([Txt])` ra số ở 4 dòng ("1,5" → 15; "1.5"; " 12 "; "-3.75"); các dòng khác lỗi.
- `REPT("ab", [ID] − 10)` lỗi khi âm.
- `MID([Txt], [ID] − 5, 4)` lỗi khi start ≤ 0.
- `CONCATENATEX(FILTER(text_cases, ID ≤ i), ID, ",", ID, DESC)` cho "3,2,1".

## 4. Thông báo lỗi nguyên văn (thanh công thức của bảng tính toán)

| Biểu thức | Thông báo |
|---|---|
| `MID("abcdef", 0, 2)`, `MID(…, BLANK(), 2)` | An argument of function 'MID' has the wrong data type or has an invalid value. |
| `RIGHT("abc", -1)`; `LEFT("abc", -1)`; `SUBSTITUTE("aaa", "a", "b", 0)`; `REPLACE("abcdef", 0, 2, "X")`; `SEARCH("b", "abc", 0)`; `FIND("b", "abc", 0, -1)`; `REPT("ab", -1)`; `FIXED(1.5, 128)`; `UNICODE(<surrogate lẻ>)` | Cùng mẫu: An argument of function '<TÊN>' has the wrong data type or has an invalid value. |
| `SEARCH("x", "abc")` | The search Text provided to function 'SEARCH' could not be found in the given text. |
| `FIND("B", "abc")` | The search Text provided to function 'FIND' could not be found in the given text. |
| `VALUE("abc")`, `VALUE("10%")`, `VALUE("")` | Cannot convert value 'abc' of type Text to type Number. (tương tự với '10%', '') |
| `UNICHAR(0)` | An argument of function 'UNICHAR' has the wrong data type or the result is too large or too small. |
| `UNICHAR(55357)`, `UNICHAR(1114111)` | The code point does not correspond to a valid character. |
| `COMBINEVALUES("", …)`, `COMBINEVALUES(BLANK(), …)` | The delimiter value in the 'COMBINEVALUES' function can only be a constant non empty string. (lỗi lúc dịch, ISERROR không bắt) |
| (DAX query view, mọi lỗi lúc chạy) | Failed to move the data reader to the next row. |

## 5. Dọn

Desktop tắt không lưu, xoá `C:\Users\bacpew\f12` và `f10` trong VM. Ảnh không lưu (chỉ xem tạm, đã xoá). `f12-desktop.pbix` để ở `build/f2-out/f12/` và bản sao ở thư mục này, ngoài git.
