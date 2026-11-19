# VM-F14 (T053): Desktop lưu bảng lớn (2026-11-19)

Power BI Desktop 2.159 trong VM, không bấm chuột: nạp bằng TMSL (bảng phân vùng M `Parquet.Document`/`Csv.Document`, `refresh full`) vào engine của
Desktop, đọc bố cục qua DMV `$SYSTEM.DISCOVER_STORAGE_TABLE_COLUMN_SEGMENTS`, `DISCOVER_STORAGE_TABLE_COLUMNS`. Nạp `big_10m.parquet` mất 191 s.

## Đoạn dữ liệu
- `big_10m` (10 000 000 dòng): **10 đoạn**, 9 đoạn 1 048 576 dòng (2^20) và đoạn cuối 562 816.
- `repeat_1m` (1 000 000 dòng): một đoạn. Nhom6 `Fact_Transaction` 1 056 320 dòng cũng một đoạn: phần lẻ nhỏ gộp vào đoạn trước
  (`[SUY ĐOÁN]` ngưỡng).
- RowNumber: mỗi đoạn `USED_SIZE` 128, không có dữ liệu bit-packing.

## Mã hoá cột
- VALUE (`COLUMN_ENCODING` 2, từ điển 144 byte): `ID` (tăng dần), `Amount` (2 chữ số thập phân), `Value` (số ngẫu nhiên tới 1e9).
- HASH: `CustomerID` (50 giá trị), `Qty`, `Price`, `Region`, `Batch`, `Flag`, `OrderTime` (ngày giờ), `Code` (số ngẫu nhiên tới 2^31).
- Cột VALUE có thêm tệp `.hidx` trong bảng `H$` (bảng băm: 32 ô với 77 giá trị, các cặp mã dữ liệu/vị trí; hàm băm chưa giải) và `H$` chỉ có
  `POS_TO_ID`; `DictionaryStorage` Type 2, BaseId = min × magnitude − 3 (Nhom6).

## Sắp lại dòng
`repeat_1m[Status]` (3 giá trị ngẫu nhiên) chỉ còn 136 byte: Desktop sắp lại dòng để dồn run. `Batch` 4 120 byte.

## Cỡ
Ước lượng phần dữ liệu `repeat_1m` của Desktop khoảng 6,7 MB (`ID` 2,67 MB, `Value` 4 MB, còn lại vài KB). Tệp BI Pro 27,4 MB vì `ID`, `Value`
ghi HASH (mỗi cột thêm từ điển 4 MB) và không sắp lại dòng. Chưa lưu được tệp `.pbix` do Desktop tự ghi (Ctrl+S gửi qua `prlctl` không vào
giao diện, engine chạy Diskless nên không Backup được).
