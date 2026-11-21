# Quan sát VM-V12 — Power BI Desktop 2.159.1231.0 (RLS, Mark as Date Table & Ribbon Actions)

**Ngày quan sát:** 2026-11-21
**Nguồn:** Trích xuất trực tiếp từ `metadata.sqlitedb` của `Nhom6_Dashboard_chiase.pbix` (chỉ đọc) và nạp reflection `Microsoft.AnalysisServices.Server.Tabular.dll` của Power BI Desktop 2.159.1231.0 trên VM Windows 11.

## 1. Mark as Date Table (`Dim_Date` trong `Nhom6_Dashboard_chiase.pbix`)

Truy vấn thực tế bảng `[Table]`, `[Column]` và `[Annotation]` của `Dim_Date` (`ID = 19`, `full_date` `ID = 90`):

- `[Table]`: `DataCategory = 'Time'` (khi bỏ đánh dấu: `NULL`).
- `[Column]` (cột khoá ngày `full_date`): `IsKey = 1`, `IsUnique = 1`, `DataCategory = NULL`; mọi cột khác trong cùng bảng `IsKey = 0`.
- `[Annotation]`: **không có** chú thích bổ sung nào trên `ObjectID = 19` hoặc `ObjectID = 90`.

## 2. Row-Level Security (`[Role]` và `[TablePermission]`)

### Lược đồ bảng SQLite (`metadata.sqlitedb`)
```sql
CREATE TABLE [Role](
    [ID] INTEGER,
    [ModelID] INTEGER,
    [Name] TEXT,
    [Description] TEXT,
    [ModelPermission] INTEGER,
    [ModifiedTime] INTEGER,
    PRIMARY KEY("ID" ASC)
);

CREATE TABLE [TablePermission](
    [ID] INTEGER,
    [RoleID] INTEGER,
    [TableID] INTEGER,
    [FilterExpression] TEXT,
    [ModifiedTime] INTEGER,
    [State] INTEGER,
    [ErrorMessage] TEXT,
    [MetadataPermission] INTEGER,
    PRIMARY KEY("ID" ASC)
);
```

### Giá trị hằng số trích trực tiếp từ `Microsoft.AnalysisServices.Server.Tabular.dll` (Desktop 2.159)
- `ModelPermission`: `None = 1`, **`Read = 2`** (vai trò xem RLS chuẩn Power BI Desktop), `ReadRefresh = 3`, `Refresh = 4`, `Administrator = 5`.
- `ObjectState`: **`Ready = 1`**, `NoData = 3`, `CalculationNeeded = 4`, `SemanticError = 5`, `EvaluationError = 6`.
- `MetadataPermission`: **`Default = 0`**, `None = 1`, `Read = 2`.
- `ObjectType`: `Role = 34`, `TablePermission = 36`.
