# Gate VM-F12 (T023): kết quả

Buổi 2026-11-19, Power BI Desktop 2.159 trên VM Windows 11 (Claude lái VM, người dùng cho phép). Thư mục thử trong VM: `C:\Users\bacpew\f12g` (đã xoá sau buổi).

## Kết luận

**Đạt.** Desktop mở `bipro-f12.pbix` không lỗi (`g1-mo-file.png`), bảng `text_cases` có đủ 16 cột tính toán dùng hàm văn bản. Giá trị BI Pro lưu trùng giá trị Desktop tự lưu (golden `golden.tsv`, test `F2TextCalcTests`).

`bipro-f12.pbix` do test `F2TextCalcTests` sinh: nạp `text_cases.csv`, thêm 16 cột tính toán, lưu.

## 1. Công thức

`INFO.VIEW.COLUMNS()` (`t023-congthuc.dax`): 16 cột `Calculated`, công thức và kiểu đúng như BI Pro ghi. Ví dụ `MID([Txt], 2, 3)` kiểu Text, `LEN([Txt])` Integer, `EXACT([Txt], [Nfd])` True/False.

## 2. Giá trị đã lưu so với biểu thức tính lại

Truy vấn `t023-lech.dax` đếm dòng mà giá trị đã lưu khác biểu thức tính lại ngay trong DAX query. Cột chữ so bằng `EXACT`, cột số so bằng `<>`.

- 14/16 cột: 0 dòng lệch.
- `MID-2-3` và `REPLACE-2-3`: mỗi cột 1 dòng lệch, đều là dòng ID 14 (`😀 emoji`).

Dòng 14 lệch do cách Desktop lưu chuỗi, không phải lỗi BI Pro:
- `MID` từ vị trí 2 cắt đôi cặp surrogate của 😀, còn lại nửa sau U+DE00.
- Khi lưu vào cột, Desktop thay nửa surrogate lẻ bằng U+FFFD. Golden Desktop tự lưu là `T:\uFFFD e` và `T:\uFFFD__moji`.
- Khi tính lại lúc truy vấn, Desktop giữ nguyên nửa surrogate, nên `EXACT` ra FALSE.
- BI Pro lưu đúng `\uFFFD e` và `\uFFFD__moji` như Desktop.

## 3. Cách chạy truy vấn

Ở buổi này, chuột từ Mac không tới được VM: cửa sổ Parallels nhận `cliclick` nhưng Windows không thấy cả rê chuột lẫn bấm. Truy vấn DAX được chạy thẳng vào engine Analysis Services của Desktop:

- `build/vm-tools/daxq.ps1` (ngoài git) tìm cổng của `msmdsrv.exe` bằng `Get-NetTCPConnection`.
- Script nạp `Microsoft.PowerBI.AdomdClient.dll` trong thư mục `bin` của Desktop, chạy truy vấn và ghi kết quả TSV.

Không bấm trong VM bằng PowerShell.

Đã thử thêm TMSL `refresh calculate`. Giá trị sau khi chạy trùng giá trị trước khi chạy, nhưng bước này có thể không tính lại cột đã có dữ liệu, nên không tính là bằng chứng.
