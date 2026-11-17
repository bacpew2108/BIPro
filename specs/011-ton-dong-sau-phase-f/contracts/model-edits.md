# Hợp đồng: `ModelEdit` mới và bộ ghi (US2, US4, US5)

Chủ: lead (`Sources/PBIXKit/Writing/`, `Sources/PBIXKit/ModelMetadata*.swift`).

```swift
public struct NewHierarchy: Sendable, Hashable {
    public var table: String, name: String
    public var levels: [(name: String, column: String)]   // thứ tự cấp
    public var isHidden: Bool
}
public enum ModelEdit {
    // … các case hiện có
    case addHierarchy(NewHierarchy)
    case dropHierarchy(table: String, name: String)
    case addVariation(table: String, column: String, relationship: String, hierarchy: (table: String, name: String))
    case dropVariation(table: String, column: String)
    case setModelAnnotation(name: String, value: String)          // __PBI_TimeIntelligenceEnabled
}
public struct NewRelationship { /* thêm */ public var joinOnDateBehavior: Int = 1 }   // 2 = DatePartOnly
public struct NewTable { /* thêm */ public var isPrivate = false, showAsVariationsOnly = false, annotations: [String: String] = [:] }
public extension ModelMetadata {
    var discourageImplicitMeasures: Bool { get }
    var variations: [Variation] { get }       // cột → bảng ngày cục bộ + phân cấp mặc định
}
```

- `collapsingTableEdits` gộp được các case mới (thêm rồi bỏ trong phiên = không còn gì).
- `MetadataWriter`: `addHierarchy` ghi `Hierarchy`, `Level`, `HierarchyStorage` và tệp `U$` qua `HierarchyIndexWriter` (mới); dựng lại `U$` khi cột cấp đổi dữ liệu; `requireNoIndexes` thay bằng dựng lại `R$`/`U$`/`H$` (US4).
- `VertiPaqWriter.encodeTable`: nhiều đoạn (`RecordsPerSegment` theo VM-F14), RLE; API giữ nguyên, kết quả có `segmentCount > 1`.
- Bất biến: không ghi nửa chừng (ghi tạm + kiểm đọc lại như Phase F); mọi lỗi tiếng Việt kèm tên bảng/cột.
