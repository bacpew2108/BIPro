# Kết quả gate F-T3 (T010), 2026-11-15

Người làm: Claude lái Desktop trong VM theo cho phép của bạn trong phiên này ("có thể dùng VM"), bằng `vm.sh` (cliclick lên cửa sổ Parallels), chụp bằng `screencapture -l`. Ảnh cắt chỉ giữ hộp thoại (không có địa chỉ tài khoản).

```
Kết quả: lần 1 TRƯỢT trên file W4 gốc; sau 6 vòng sửa (xem bảng dưới) ĐẠT ở lần 4 (2026-11-15 cuối chiều): file BI Pro ghi mở được trong Desktop
Phiên bản Desktop: Power BI Desktop 2.159.1231 (bản Store, x64)
```

## Ba lần mở, ba hộp thoại (nguyên văn)

| Lần | File | Hộp thoại "Something went wrong" | Ảnh |
|---|---|---|---|
| 1 | `tuan6.2_W4_table.pbix` (SHA `376a9a8e…`, bảng `BiProTest` có `Partition.QueryDefinition = ''`, kiểu 4) | `M Engine error: 'Microsoft.Data.Mashup.Preview; Token Literal expected.'` | `w4-lan1-token-literal.png` |
| 2 | như lần 1 nhưng `QueryDefinition` = M hợp lệ `let Source = #table(type table [#"Số lượng" = Int64.Type, #"Đơn giá" = number, #"Thành phố" = text], {}) in Source` | `The data model cannot be loaded because of an invalid enumeration value '0' for member 'Alignment' in object 'Column' with ID '1028'.` | `w4-lan2-alignment.png` |
| 3 | như lần 2 và `Column.Alignment = 1`, `FormatString = '0'` cho cột int64 (như cột Marketing cùng kiểu) | `Database consistency checks (DBCC) failed while checking the data dictionary. The following file is corrupted: Physical file: . Logical file . Database consistency checks (DBCC) failed while checking the data segments. Database consistency checks (DBCC) failed while checking the data segments. Database consistency checks (DBCC) failed while checking the data segments. The 'H$BiProTest (1025)$Số lượng (1028)' system table is missing. The 'H$BiProTest (1025)$Đơn giá (1029)' system table is missing. The 'H$BiProTest (1025)$Thành phố (1030)' system table is missing. An error occurred while loading Vertipaq data objects for multiple tables.` | `w4-lan3-dbcc-htable.png` |

| 4 | `W4_h.pbix`, sau mọi sửa dưới đây | **Mở được.** Bảng `BiProTest` hiện đủ 3 cột, "Table: BiProTest (100 rows)", giá trị đúng, dòng 8 trống, `Marketing` "1,363 rows" | `w4-dat-view-dat-lan4.png`, `w4-sum-so-luong-lan4.png` |

Các vòng sửa giữa lần 3 và lần 4 (mỗi vòng một thông báo khác, mỗi vòng một lỗi ghi): chuỗi "corrupt string store" → `DictionaryStorage.DictionaryFlags` = 3; DBCC "data segments" → bảng 16 run và `.idfmeta` đúng như Desktop; DBCC "data dictionary" → `LastId` 2 và `Size` 144 cho cột RowNumber; "Physical file: . Logical file ." (cột số nguyên) → `IsOperatingOn32` = 1 cho từ điển int 4 byte. Chi tiết trong `docs/phase-f-evidence/vm-f1/QUAN-SAT.md`.

Kiểm bổ sung lần 4: biểu đồ cột "Sum of Số lượng" cao tới khoảng 4K–5K (4950 mong đợi; chưa dùng Card để đọc đúng con số). Chưa nhấn Refresh, chưa lưu lại trong Desktop.

Mỗi lần Desktop mở một cửa sổ "Untitled" trống (lần 1 đến 3) (không nạp được mô hình). Chưa nhấn Refresh, chưa Save As.

## Điều rút ra (có bằng chứng)

1. **Phân vùng không có truy vấn là sai.** Ghi chú cũ trong `TableMetadataWriter` ("Power BI treats it as a stored (Type 4) partition with an empty query") là `[SUY ĐOÁN]` sai: Desktop chạy bộ phân tích M trên mọi phân vùng kiểu 4 và báo `Token Literal expected` với chuỗi rỗng. Phân vùng bảng nạp phải có biểu thức M hợp lệ. Biểu thức bảng rỗng dạng `#table(type table [...], {})` qua được bước này (lần 2 và 3 không còn lỗi M).
2. **Cột phải có `Alignment` = 1** (không phải 0) và số nguyên có `FormatString` = `'0'` như cột Marketing cùng kiểu. Các cột khác của `Column` so với Marketing chỉ khác `SourceColumn` (tên cột), nên không còn lệch hàng nào khác trong bảng `Column`.
3. **Thiếu bảng hệ thống `H$<Bảng> (<id>)$<Cột> (<id>)` cho từng cột.** Desktop kiểm DBCC từng cột dữ liệu và coi thiếu bảng này là "corrupted". Bảng `Marketing` của file gốc có sẵn một bảng `H$…` cho mỗi cột (và `R$…` cho mỗi quan hệ), mỗi bảng gồm: dòng `Table` (`IsHidden=1`, `SystemFlags=1`), hai cột `POS_TO_ID` và `ID_TO_POS` (kiểu 6, `Type=1`, `SystemFlags=1`), một `Partition` (`Type=3`, `Mode=2`, `DataView=3`, `SystemFlags=1`), `PartitionStorage`, `SegmentMapStorage` (`Type=2`, `RecordCount = số giá trị khác nhau + 2`, `SegmentCount=2`), `ColumnPartitionStorage`, `SegmentStorage`, `StorageFile` và hai cặp tệp `…POS_TO_ID.0.idf/.idfmeta`, `…ID_TO_POS.0.idf/.idfmeta` trong thư mục `H$….tbl\<partition>.prt\`. `.idf` của `H$` là mảng u32 xếp hai giá trị mỗi từ 64 bit (không phải RLE như cột thường); `.idfmeta` lớn hơn (316 byte, hai đoạn). Chưa giải xong ý nghĩa từng giá trị (xem `docs/phase-f-evidence/vm-f1/` khi làm T012).

## Quyết định

Xem `QUYET-DINH.md`.
