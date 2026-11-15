# VM-E3: tạo quan hệ trong Desktop và thử file không có chỉ mục (2026-11-14)

Bạn cho phép dùng VM. Bản sao `Nhom6_work.pbix` trong VM, đã xoá cả trên VM lẫn Mac. Chuột và phím điều khiển trong VM (xem `vm.sh`), không đụng cửa sổ Mac.

## 1. Kéo cột trong Model view tạo quan hệ

Kéo `Dim_Client[client_key]` (duy nhất) thả lên `Fact_Loan[loan_count]` (trùng) bằng chuột kéo từng bước nhỏ trong VM: mở hộp thoại **New relationship**: From table / To table kèm bản xem trước cột, **Cardinality** tự dò "One to many (1:\*)", **Cross-filter direction** Single, ô **"Make this relationship active" không tick** (đã có quan hệ hoạt động giữa `Fact_Loan` và `Dim_Client`), "Assume referential integrity" mờ. Bấm Save và Ctrl+S, so metadata (dòng đầy đủ ở `rows-new-relationship.txt`):

- `Relationship`: `ID` = `MAXID`+1, `Name` = GUID chữ thường có gạch nối, `IsActive` 0, `Type` 1, `CrossFilteringBehavior` 1, `JoinOnDateBehavior` 1, `RelyOnReferentialIntegrity` 0, **đầu "từ" = phía nhiều** (`Fact_Loan` / `FromCardinality` 2) và đầu "đến" = phía một (`Dim_Client` / `ToCardinality` 1): Desktop chuẩn hoá lại thứ tự hai cột kéo; `State` 1, `RelationshipStorageID`, `RelationshipStorage2ID` 0, `ModifiedTime`, `RefreshedTime`, `SecurityFilteringBehavior` 1.
- `RelationshipStorage` (`Name` = GUID bằng dấu cách + ` (<ID quan hệ>)`) và `RelationshipIndexStorage` (`IndexType` 1, `RecordCount` = số giá trị phân biệt của cột phía nhiều, `SystemTableID` = bảng `R$`).
- Một **bảng hệ thống ẩn** `R$<bảng nhiều> (<id>)$<guid> (<id quan hệ>)` (`SystemFlags` 1) có một cột `INDEX` (Int64) và các dòng lưu trữ đủ bộ: `Partition`, `Column`, `TableStorage` (cả bảng nhiều: một dòng `TableStorage` mới cho bảng nguồn), `ColumnStorage`, `DictionaryStorage`, `PartitionStorage`, `SegmentMapStorage`, `ColumnPartitionStorage`, `SegmentStorage`, hai `StorageFolder`, hai `StorageFile`; và trong ABF hai tệp `...INDEX.0.idf` (24 byte với 4 giá trị) và `.idfmeta` (176 byte).
- Tác dụng phụ: 7 cột đổi `SummarizeBy` kèm `Annotation 'SummarizationSetBy'='Automatic'` (như VM-E1), `Model.ModifiedTime`, bốn `DBPROPERTIES`, `MAXID` tăng 25.

## 2. File có dòng `Relationship` nhưng không có chỉ mục (spike S1, phương án i)

File do BI Pro dựng: thêm một dòng `Relationship` (`RelationshipStorageID` 0, không bảng `R$`) và xoá một quan hệ khác (xoá dòng `Relationship`, `RelationshipStorage`, `RelationshipIndexStorage`, để mồ côi bảng `R$` và tệp ABF). Desktop **không mở được**: hộp thoại "Something went wrong": `An unexpected error occurred (file 'TMProxyObjects.cpp', line 18871, function 'TMProxyRelationship::GetStorageID'). An error occurred while parallel loading Vertipaq data objects for multiple relationships.` rồi rơi về báo cáo trống "Untitled". Kết luận: **mỗi quan hệ phải có `RelationshipStorage` và chỉ mục**; không thể chỉ thêm dòng metadata. Chưa tách được lỗi do thêm quan hệ hay do để mồ côi bảng `R$` khi xoá (cả hai thao tác trong cùng một file).

## 3. Hệ quả

Tạo quan hệ cần ghi đủ chỉ mục như Desktop (phương án iii của R7): bảng hệ thống + tệp `INDEX.idf`/`.idfmeta`. Cấu trúc đã đọc được từ VM-E3; còn phải giải mã ngữ nghĩa giá trị `INDEX` (xem `research.md` R7).
