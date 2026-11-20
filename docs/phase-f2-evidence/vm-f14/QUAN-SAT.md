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

## Bổ sung 2026-11-20 (lưu thật qua giao diện Desktop: `f14-mid-desktop.pbix`, `f14-rle-desktop.pbix`)
- **Bố cục nhiều đoạn (`f14-mid-desktop.pbix`, bảng `mid` 2 500 000 dòng, 3 đoạn 1 048 576 / 1 048 576 / 402 848):**
  - `SegmentMapStorage.Type` = **`1`** cho bảng nhiều đoạn (so với **`3`** cho bảng một đoạn). Đây là nguyên nhân duy nhất khiến tệp nhiều đoạn của BI Pro trước đây bị DBCC báo hỏng.
  - Cấu trúc `.idf` và `.idfmeta` (gồm `<1:CP`, từng `<1:CS`, `<1:SDOs` với `<1:CSDOs` lồng) của các cột dữ liệu BI Pro đã khớp Desktop.
  - Cột `RowNumber`: Desktop mã hoá nén đồng nhất `C123` (lớp phụ `703067`, `base_seg = 0`, `facet = (24, 32, 2, 0)`, 0 từ bit-packing), chỉ **144 byte/đoạn** (432 B cho 3 đoạn, thay vì 6,67 MB).
- **Cỡ tệp thật `f14-rle-desktop.pbix` (`repeat_1m`, 1 000 000 dòng):**
  - Cỡ tệp `.pbix` thật do Desktop lưu: **27 326 985 byte** (~26,1 MB). Ước lượng cũ ~6,7 MB từ DMV không tính hai tệp `.hidx` của cột VALUE (`ID`: 16,78 MB, `Value`: 17,11 MB) và hai tệp `POS_TO_ID` (4 MB mỗi cột), tổng ABF chưa nén ~48,5 MB.
  - Sau khi đổi `RowNumber` sang `C123`, tệp `bipro-f14-rle.pbix` của BI Pro còn **24 724 908 byte** (**90,5 %** cỡ Desktop — nhỏ hơn cả Desktop, vượt xa ngưỡng SC-006 ≤ 125 %). Không cần ghi `.hidx`/VALUE.
