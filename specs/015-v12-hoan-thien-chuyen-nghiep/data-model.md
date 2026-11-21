# Mô hình dữ liệu: Đợt 4 (v1.2) — `specs/015-v12-hoan-thien-chuyen-nghiep/`

**Ngày lập:** 2026-11-21
**Tham chiếu:** [spec.md](file:///Users/macprom114/Desktop/PowerBINative/specs/015-v12-hoan-thien-chuyen-nghiep/spec.md), [plan.md](file:///Users/macprom114/Desktop/PowerBINative/specs/015-v12-hoan-thien-chuyen-nghiep/plan.md), [QUAN-SAT.md](file:///Users/macprom114/Desktop/PowerBINative/docs/phase-v12-evidence/vm-v12/QUAN-SAT.md)

---

## 1. PBIXKit — Mô hình RLS & Mark as Date Table

### `ModelMetadata.RoleDefinition` & `TablePermission` (`Sources/PBIXKit/ModelMetadata.swift`)
```swift
public struct TablePermission: Sendable, Hashable {
    public let tableName: String
    public let filterExpression: String
}

public struct RoleDefinition: Sendable, Hashable {
    public let name: String
    public let description: String?
    /// Khớp Desktop 2.159 `Microsoft.AnalysisServices.Tabular.ModelPermission.Read = 2`.
    public let modelPermission: Int
    public let tablePermissions: [TablePermission]
}
```
- `ModelMetadata` giữ nguyên `public let roles: [String]` và bổ sung `public let roleDefinitions: [RoleDefinition]` (đọc từ `SELECT ID, Name, Description, ModelPermission FROM [Role] ORDER BY ID` và `SELECT tp.RoleID, t.Name, tp.FilterExpression FROM [TablePermission] tp JOIN [Table] t ON t.ID = tp.TableID ORDER BY tp.ID`).

### Mở rộng `TablePatch`, `ColumnPatch` & `ModelEdit` (`Sources/PBIXKit/Writing/ModelEdit.swift`)
- `TablePatch`: thêm `public var dataCategory: Assignment<String>? = nil` (ghi `"Time"` khi đánh dấu bảng ngày, `.clear` khi bỏ đánh dấu).
- `ColumnPatch`: thêm `public var isKey: Bool? = nil` (khi đặt `true` trên cột bảng ngày, ghi `IsKey = 1, IsUnique = 1` trong SQLite `[Column]`).
- `ModelEdit`:
  - `case upsertRole(previousName: String?, role: ModelMetadata.RoleDefinition)`
  - `case deleteRole(name: String)`

### Ánh xạ SQLite (`MetadataWriter.swift`)
- `upsertRole`:
  - Nếu `previousName` (hoặc `role.name`) đã có trong `[Role]`: `UPDATE [Role] SET Name = ?, Description = ?, ModelPermission = ?, ModifiedTime = ? WHERE ID = ?`, xoá các hàng cũ trong `[TablePermission] WHERE RoleID = ?`.
  - Nếu mới: `INSERT INTO [Role] (ID, ModelID, Name, Description, ModelPermission, ModifiedTime) VALUES (?, ?, ?, ?, 2, ?)`.
  - Với mỗi `tp` trong `role.tablePermissions` (có `filterExpression` không rỗng): `INSERT INTO [TablePermission] (ID, RoleID, TableID, FilterExpression, ModifiedTime, State, ErrorMessage, MetadataPermission) VALUES (?, ?, ?, ?, ?, 1, NULL, 0)`.
- `deleteRole(name:)`: xoá hàng trong `[TablePermission] WHERE RoleID = ?` rồi xoá hàng trong `[Role] WHERE ID = ?`.

---

## 2. BIPro — Clipboard, Format Painter & Quick Measures

### `VisualClipboardItem` & `FormatPainterPayload` (`Sources/BIPro/Report/Edit/LayoutEditor.swift`)
```swift
struct VisualClipboardItem: Equatable {
    let visual: ReportVisual
    let json: Data
}

struct FormatPainterPayload: Equatable {
    let sourceID: String
    let sourceType: String
    let containerObjectsJSON: Data?
    let compatibleObjects: [String: Data]
}
```
- Các khoá `objects` tương thích khi sao định dạng giữa các visual: `dataPoint`, `labels`, `legend`, `categoryAxis`, `valueAxis`, `values`, `columnHeaders`, `grid`, `general`, `total`.

### `QuickMeasureTemplate` (`Sources/BIPro/Model/QuickMeasureCatalog.swift`)
```swift
enum QuickMeasureTemplate: String, CaseIterable, Identifiable, Sendable {
    case ytdTotal
    case runningTotal
    case rollingAverage
    case percentOfGrandTotal
    case filteredValue
    case weightedAverage
    case yoyPercentChange
    case safeDivision
}
```

### `DAXDefinedMeasure` (`Sources/BIPro/Query/DAXModelSync.swift`)
```swift
struct DAXDefinedMeasure: Identifiable, Equatable, Sendable {
    enum ChangeKind: Equatable, Sendable { case create, update(oldExpression: String) }
    var id: String { "\(table)[\(name)]" }
    let table: String
    let name: String
    let expression: String
    let kind: ChangeKind
}
```

### Trạng thái phiên bổ sung trên `DocumentState` & `ReportInteraction`
- `DocumentState`:
  - `var showDataTableVisualID: String? = nil` (mở `VisualDataTableSheet` từ nút *Xem dữ liệu*)
  - `var showQuickMeasureSheet = false`
  - `var showMarkDateTableSheet = false`
  - `var showManageRolesSheet = false`
  - `var showViewAsRoleSheet = false`
  - `var pendingDAXModelUpdates: [DAXDefinedMeasure]? = nil`
  - `var tmdlHasPendingChanges = false`
  - `var tmdlApplyRequestToken = 0`
- `ReportInteraction`:
  - `var activeRLSRoles: Set<String> = []` (cập nhật tức thời mọi visual qua `rlsVersion` / `modelVersion` mà không làm bẩn `LayoutEditor.isDirty`)
