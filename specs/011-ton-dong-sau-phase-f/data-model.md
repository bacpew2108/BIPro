# Mô hình dữ liệu (Giai đoạn 1): Tồn đọng sau Phase F

Chỉ ghi phần mới hoặc đổi. Kiểu hiện có (`ModelMetadata`, `ModelEdit`, `TableData`, `VisualQuerySpec`) giữ nguyên trừ chỗ nêu dưới đây. Các trường có `[SUY ĐOÁN]` được xác nhận ở buổi VM tương ứng.

## Trường gộp ngầm (US1)

`ImplicitAggregation` gồm `table`, `column` và `function: AggregateFunction`.

- **`AggregateFunction`**: `sum`, `average`, `min`, `max`, `count`, `countDistinct`, `median`, `standardDeviation`, `variance`. Mã số PBIR `[SUY ĐOÁN]` 0, 1, 3, 4, 2, 5, 6, 7, 8 (R1).
- **Mặc định** lấy từ `Column.SummarizeBy` của cột: Sum → `sum`, Count → `count`, None → không gộp (cột vào ô danh mục). Cột chữ và cột ngày theo VM-F10.
- **Nhãn hiển thị** tiếng Việt: "Tổng của X", "Trung bình của X", "Nhỏ nhất của X", "Lớn nhất của X", "Số lượng của X", "Số lượng (riêng biệt) của X", "Trung vị của X", "Độ lệch chuẩn của X", "Phương sai của X".
- **Trong file**: `{"Aggregation": {"Expression": {"Column": …}, "Function": n}}`, với `queryRef` `Sum(Table.Column)` (`[SUY ĐOÁN]`). Không có tên hiển thị tiếng Việt nào được ghi vào file.
- **Quy tắc**:
  - Chỉ cho dùng khi `ModelMetadata.discourageImplicitMeasures == false`. Cờ này đọc mới, từ `Model.DiscourageImplicitMeasures`.
  - Cùng cột có thể xuất hiện hai lần với hai phép gộp; tên kết quả phải khác nhau theo cách Desktop đặt.

## Bảng Enter Data (US2)

`EnterDataTable` gồm `name` (mặc định "Table", tránh trùng tên bằng ` (2)`), `columns: [String]` và `rows: [[String?]]`.

- **Giới hạn**: ≤ 3 000 ô trong clipboard, đếm cả dòng tiêu đề (VM-F11a).
- **Dữ liệu**: mọi ô là chuỗi, ô trống là `""` (VM-F11a). Kiểu cột ở bước `Changed Type`: cột toàn số (bỏ qua ô trống) là `type number`, còn lại `type text`.
- **Khi lưu**: thành `NewTable` (T3) với `QueryDefinition` là M Enter Data (R2).
- **Khi đọc lại**: nhận ra M Enter Data, giải nén ra lưới để sửa.

## Bảng ngày cục bộ (US2)

- **`DateTableTemplate_<guid>`**: một bảng cho mỗi mô hình khi có ít nhất một cột ngày.
  - Bảng tính toán ẩn, `IsPrivate = 1`, chú thích `__PBI_TemplateDateTable = true`.
  - Cột và phân cấp chép theo `w8.3.pbix`, đã đối chiếu với VM-F11 (`F2AutoDateGoldenTests`). Chú thích bảng thêm `DefaultItem = DateHierarchy`.
- **`LocalDateTable_<guid>`**: một bảng cho mỗi cột ngày hoặc ngày giờ không ẩn của bảng người dùng.
  - Bảng tính toán ẩn, `ShowAsVariationsOnly = 1`, chú thích `__PBI_LocalDateTable = true`.
  - Biểu thức: `Calendar(Date(Year(MIN('T'[c])), 1, 1), Date(Year(MAX('T'[c])), 12, 31))`.
  - Cột: `Date`, `Year`, `MonthNo`, `Month`, `QuarterNo`, `Quarter`, `Day`. Tên và biểu thức lấy theo `w8.3.pbix`.
  - Phân cấp `Date Hierarchy` với các cấp `Year`, `Quarter`, `Month`, `Day`.
- **Quan hệ**: `T[c]` (nhiều) → `LocalDateTable[Date]` (một), `JoinOnDateBehavior = 2`, hoạt động, lọc một chiều.
- **`Variation`**: `ColumnID = T[c]`, `RelationshipID` của quan hệ trên, `DefaultHierarchyID = Date Hierarchy`, `IsDefault = 1`, `Name = "Variation"`.
- **Vòng đời**:
  - Cột ngày được thêm (nạp bảng, thay bảng, thêm cột tính toán kiểu ngày): sinh bộ bảng, quan hệ và variation.
  - Cột bị bỏ, hoặc bảng bị xoá: xoá bộ đó.
  - Bảng mẫu bị xoá khi không còn bảng ngày cục bộ nào.
  - Tắt tuỳ chọn: xoá tất cả và đặt chú thích về 0. Bật lại: dựng lại.
- **Chú thích mô hình**: `__PBI_TimeIntelligenceEnabled` bằng 1 khi bật, 0 khi tắt.
- **Dòng lưu trữ** (f11, T031): bảng, phân vùng và mọi cột của bảng ngày có `SystemFlags = 2`; cột `Date` có `ExplicitDataType` = `InferredDataType` = 9; `RelationshipStorage.DefinitionType` 2 cho quan hệ chỉ so phần ngày (0 cho quan hệ thường); `Variation.DefaultColumnID` 0, `Description` NULL.
- **Thứ tự thao tác** (T031, dùng ở T032): `addCalculatedTable` (cột `Date`) → `addCalculatedColumn` × 6 → `updateColumn` × 7 (ẩn, định dạng, tổng hợp 2, DataCategory, sắp theo, chú thích) → `updateTable` (ẩn, cờ, chú thích) → `addHierarchy` → `addRelationship` (`joinOnDateBehavior` 2) → `addVariation`. Bỏ: `dropVariation` → `deleteRelationship` → `dropHierarchy` → `dropTable`.

## Quan hệ tự phát hiện (US2)

Dùng lại `NewRelationship`, với tên `AutoDetected_<guid>` (theo `w8.3.pbix`) và các thuộc tính theo VM-F11c. Kết quả của `RelationshipDetector` là `[NewRelationship]`, thứ tự ổn định (theo thứ tự bảng nạp, rồi thứ tự cột).

## Phân cấp người dùng và chỉ mục `U$` (US2, US4)

- **`NewHierarchy`** gồm `table`, `name`, `levels: [(name, column)]`, `isHidden`. Phần `HierarchyStorage` và tệp `U$` do bộ ghi dựng từ dữ liệu các cột cấp.
- **`ModelEdit` mới**: `addHierarchy(NewHierarchy)`, `dropHierarchy(table:name:)`, `addVariation(table:column:relationship:hierarchy:)`, `dropVariation(table:column:)`.
- **Khi lưu lại**: sửa giá trị một cột là cấp phân cấp thì `U$` của phân cấp đó được dựng lại (US4).
- **Định dạng `U$`** (T030, đọc từ f11, Nhom6, `w8.3`; bộ ghi trùng từng byte):
  - Mỗi nút một dòng, xếp theo tầng; con của một nút xếp theo thứ tự `H$` của cột cấp, hoặc của cột "sắp theo".
  - Bốn cột nén bit 32 như `R$`: `MULTI_LEVEL_ID` = mã dữ liệu giá trị cấp; `PARENT_POS`, `FIRST_CHILD_POS` = vị trí + 1 (0 = không có); `CHILD_COUNT` = số con + 1 (0 = lá).
  - `LevelDefinition` = `$<tên lưu trữ cột>$<vị trí đầu tầng>$…`.
  - `StructureType` 1 khi mỗi giá trị cấp chỉ có một cha, còn lại 2.
  - Phân cấp có chú thích (`NewHierarchy.annotations`, ObjectType 9) cho `TemplateId = DateHierarchy`.

## Cột tính toán còn được dùng (US4)

Mở rộng `usesOfRemovedColumns` và `indexUses(of:)` thành ba loại phụ thuộc: quan hệ, cấp phân cấp, cột sắp xếp. Trước khi xoá, giao diện hỏi và liệt kê các mục bị bỏ kèm theo.

| Loại phụ thuộc | Khi sửa công thức | Khi xoá cột |
|---|---|---|
| Quan hệ | Xoá rồi thêm lại quan hệ cùng tên, `R$` theo dữ liệu mới. Đầu "một" không còn duy nhất thì làm theo VM-F13. | Xoá quan hệ |
| Cấp phân cấp | Dựng lại `U$` | Bỏ cấp; phân cấp hết cấp thì bỏ phân cấp |
| Cột sắp xếp | Dựng lại `H$` của cột được sắp | Xoá `SortByColumnID` của cột được sắp |

## Đoạn dữ liệu và RLE (US5)

- **`VertiPaqWriter.Segment`** gồm `rowRange`, `encoding: .bitPacked | .rle(runs) | .hybrid`, `stats` (min, max, đếm NULL).
- **`SegmentMapStorage`**: `SegmentCount` lớn hơn 1, `RecordsPerSegment` theo Desktop.
- **Thứ tự dòng** đọc lại phải bằng thứ tự nguồn, trừ khi VM-F14 cho thấy Desktop sắp lại dòng.

## Nguồn (US6)

- **Kiểu M từ nguồn**: `TableColumn` có thêm `sourceType: MSourceType?`, gồm `time`, `duration`, `dateTimeZone`, `binary`, `list`, `record`, để Query Editor hiện đúng kiểu và M ghi đúng `Changed Type`. Giá trị đưa vào mô hình theo quy tắc Desktop (R8); kiểu nào Desktop không cho nạp thì báo như Desktop.
- **Lựa chọn driver ODBC**: một chuỗi lưu ở `UserDefaults["bipro.sqlite.odbcDriver"]`, mặc định "Devart ODBC Driver for SQLite".
- **Parquet lồng**: cột struct cho ô `record`, cột list cho ô `list` của `TableData.structured`. Độ sâu đến 3; sâu hơn thì báo "Chưa hỗ trợ" kèm tên cột.
