import Foundation

// Phase E (specs/009-e-mo-hinh-hoa-luu-t2/data-model.md): một thao tác sửa mô hình và danh sách thao tác.
// `ModelMetadata.applying(_:)` cho mô hình hiệu lực; `MetadataWriter.apply(_:)` ghi cùng danh sách vào `metadata.sqlitedb`.

/// Giá trị "đặt hoặc xoá" cho trường tuỳ chọn: `.set(x)` đặt, `.clear` xoá, `nil` ngoài patch nghĩa là giữ nguyên.
public enum Assignment<Value: Sendable & Hashable>: Sendable, Hashable {
    case set(Value)
    case clear
}

/// Sửa measure. Trường `nil` giữ nguyên.
public struct MeasurePatch: Sendable, Hashable {
    public var name: String?
    public var expression: String?
    public var formatString: Assignment<String>?
    public var displayFolder: Assignment<String>?
    public var description: Assignment<String>?
    public var isHidden: Bool?
    public var dataType: ModelMetadata.DataType?

    public init(name: String? = nil, expression: String? = nil, formatString: Assignment<String>? = nil,
                displayFolder: Assignment<String>? = nil, description: Assignment<String>? = nil,
                isHidden: Bool? = nil, dataType: ModelMetadata.DataType? = nil) {
        self.name = name
        self.expression = expression
        self.formatString = formatString
        self.displayFolder = displayFolder
        self.description = description
        self.isHidden = isHidden
        self.dataType = dataType
    }
}

/// Sửa thuộc tính của một quan hệ đã có. Trường `nil` giữ nguyên.
public struct RelationshipPatch: Sendable, Hashable {
    public var isActive: Bool?
    /// 1 = một chiều, 2 = hai chiều (`Relationship.CrossFilteringBehavior`).
    public var crossFilteringBehavior: Int?

    public init(isActive: Bool? = nil, crossFilteringBehavior: Int? = nil) {
        self.isActive = isActive
        self.crossFilteringBehavior = crossFilteringBehavior
    }
}

/// Sửa thuộc tính của một cột (không đụng dữ liệu). Trường `nil` giữ nguyên.
public struct ColumnPatch: Sendable, Hashable {
    public var name: String?
    public var isHidden: Bool?
    public var formatString: Assignment<String>?
    /// AMO AggregateFunction (xem `ModelMetadata.Column.summarizeBy`).
    public var summarizeBy: Int?
    public var dataCategory: Assignment<String>?
    /// Tên cột sắp xếp theo, cùng bảng.
    public var sortBy: Assignment<String>?
    public var displayFolder: Assignment<String>?
    public var description: Assignment<String>?
    /// Chú thích của cột (`Annotation`, ObjectType 4), ví dụ `SummarizationSetBy`, `TemplateId` của cột bảng ngày.
    public var annotations: [String: Assignment<String>]
    /// Cho phép đổi tên cột kể cả khi đang nằm trong quan hệ / phân cấp (Wave 3C Cascade Rename).
    public var cascade: Bool

    public init(name: String? = nil, isHidden: Bool? = nil, formatString: Assignment<String>? = nil,
                summarizeBy: Int? = nil, dataCategory: Assignment<String>? = nil, sortBy: Assignment<String>? = nil,
                displayFolder: Assignment<String>? = nil, description: Assignment<String>? = nil,
                annotations: [String: Assignment<String>] = [:], cascade: Bool = false) {
        self.name = name
        self.isHidden = isHidden
        self.formatString = formatString
        self.summarizeBy = summarizeBy
        self.dataCategory = dataCategory
        self.sortBy = sortBy
        self.displayFolder = displayFolder
        self.description = description
        self.annotations = annotations
        self.cascade = cascade
    }
}

/// Sửa thuộc tính của một bảng. Trường `nil` giữ nguyên.
public struct TablePatch: Sendable, Hashable {
    public var name: String?
    public var isHidden: Bool?
    /// `Table.IsPrivate` (bảng mẫu `DateTableTemplate_…`). Bật cờ này hoặc `showAsVariationsOnly` thì bộ ghi đặt `SystemFlags = 2` cho
    /// phân vùng và các cột của bảng như Desktop (f11, w8.3), nên áp sau khi đã thêm đủ cột.
    public var isPrivate: Bool?
    /// `Table.ShowAsVariationsOnly` (bảng ngày cục bộ `LocalDateTable_…`).
    public var showAsVariationsOnly: Bool?
    /// Chú thích của bảng (`Annotation`, ObjectType 3), ví dụ `__PBI_LocalDateTable`.
    public var annotations: [String: Assignment<String>]

    public init(name: String? = nil, isHidden: Bool? = nil, isPrivate: Bool? = nil, showAsVariationsOnly: Bool? = nil,
                annotations: [String: Assignment<String>] = [:]) {
        self.name = name
        self.isHidden = isHidden
        self.isPrivate = isPrivate
        self.showAsVariationsOnly = showAsVariationsOnly
        self.annotations = annotations
    }
}

/// Quan hệ mới (giai đoạn 2b). Hai đầu theo đúng thứ tự Desktop ghi: `from` là phía nhiều (hoặc một nếu 1:1).
public struct NewRelationship: Sendable, Hashable {
    /// Tên quan hệ (GUID chữ thường có gạch nối, như Desktop ghi).
    public var name: String
    public var fromTable: String
    public var fromColumn: String
    public var toTable: String
    public var toColumn: String
    /// `true`: phía "từ" là nhiều (`FromCardinality` 2). `toMany`: phía "đến" là nhiều.
    public var fromMany: Bool
    public var toMany: Bool
    public var isActive: Bool
    /// 1 = một chiều, 2 = hai chiều.
    public var crossFilteringBehavior: Int
    /// `Relationship.JoinOnDateBehavior`: 1 = so cả ngày giờ (mặc định), 2 = chỉ so phần ngày (quan hệ tới bảng ngày cục bộ của
    /// Auto date/time, `w8.3.pbix`).
    public var joinOnDateBehavior: Int

    public init(name: String = UUID().uuidString.lowercased(), fromTable: String, fromColumn: String, toTable: String,
                toColumn: String, fromMany: Bool = true, toMany: Bool = false, isActive: Bool = true, crossFilteringBehavior: Int = 1,
                joinOnDateBehavior: Int = 1) {
        self.name = name
        self.fromTable = fromTable
        self.fromColumn = fromColumn
        self.toTable = toTable
        self.toColumn = toColumn
        self.fromMany = fromMany
        self.toMany = toMany
        self.isActive = isActive
        self.crossFilteringBehavior = crossFilteringBehavior
        self.joinOnDateBehavior = joinOnDateBehavior
    }
}

/// Một cấp của phân cấp người dùng (đợt tồn đọng sau Phase F, `contracts/model-edits.md`).
public struct HierarchyLevel: Sendable, Hashable {
    public var name: String
    public var column: String
    public init(name: String, column: String) { self.name = name; self.column = column }
}

/// Phân cấp mới (`Hierarchy` + `Level`); chỉ mục `U$` do bộ ghi dựng từ dữ liệu các cột cấp.
public struct NewHierarchy: Sendable, Hashable {
    public var table: String
    public var name: String
    public var levels: [HierarchyLevel]
    public var isHidden: Bool
    /// Chú thích của phân cấp (Auto date/time: `TemplateId = DateHierarchy`).
    public var annotations: [String: String]
    public init(table: String, name: String, levels: [HierarchyLevel], isHidden: Bool = false, annotations: [String: String] = [:]) {
        self.table = table; self.name = name; self.levels = levels; self.isHidden = isHidden; self.annotations = annotations
    }
}

/// Phân cấp theo bảng và tên.
public struct HierarchyRef: Sendable, Hashable {
    public var table: String
    public var name: String
    public init(table: String, name: String) { self.table = table; self.name = name }
}

/// Một cột của bảng mới (Phase F). `dataType` là kiểu trong mô hình; `values` là dữ liệu đã mã hoá cho `VertiPaqWriter` (T014 mở rộng
/// kiểu), `nil` khi dữ liệu nằm ở `TableData` phía ứng dụng (kiểu tiền tệ, ngày, logic chưa có trong `Values`).
public struct NewTableColumn: Sendable, Equatable {
    public var name: String
    public var dataType: ModelMetadata.DataType
    public var values: VertiPaqWriter.Values?

    public init(name: String, values: VertiPaqWriter.Values) {
        self.name = name
        self.dataType = values.dataType
        self.values = values
    }

    public init(name: String, dataType: ModelMetadata.DataType) {
        self.name = name
        self.dataType = dataType
        self.values = nil
    }
}

/// Tên và kiểu một cột kết quả (bảng tính toán, T082).
public struct ColumnSignature: Sendable, Hashable {
    public var name: String
    public var dataType: ModelMetadata.DataType
    /// Tên cột kết quả trong biểu thức như Desktop ghi ở `Column.SourceColumn` của bảng tính toán (VM-F9b): `Bảng[Cột]` khi cột giữ
    /// nguồn gốc một cột của mô hình (`DISTINCT(Fact_Loan[x])`), `[Tên]` khi là cột mới (`CALENDAR`, `ADDCOLUMNS`). Nil thì `[name]`.
    public var sourceColumn: String?
    public init(name: String, dataType: ModelMetadata.DataType, sourceColumn: String? = nil) {
        self.name = name; self.dataType = dataType; self.sourceColumn = sourceColumn
    }
}

/// Bảng nạp từ truy vấn (Phase F, T3). Là lớp tham chiếu: dữ liệu có thể hàng triệu dòng nên `ModelEdit` so sánh và băm
/// theo định danh, không theo nội dung, và các ảnh chụp hoàn tác dùng chung một bản dữ liệu.
public final class NewTable: Hashable, Sendable {
    public let name: String
    public let columns: [NewTableColumn]
    /// Biểu thức M của truy vấn nạp bảng (`Partition.QueryDefinition`); `nil` cho bảng chỉ có dữ liệu.
    public let queryExpression: String?
    /// Cờ "Enable load" của truy vấn.
    public let enableLoad: Bool
    /// `Table.LineageTag`, sinh một lần cho mỗi bảng để mô hình hiệu lực ổn định khi áp dụng lại (khoá của `DiagramLayout`).
    public let lineageTag: String
    /// Dữ liệu ô do ứng dụng gắn kèm (BIPro gắn `TableData`); PBIXKit không đọc. Cùng đời với bảng nên các ảnh chụp hoàn tác dùng chung.
    public let attachment: (any Sendable)?
    /// `Table.IsPrivate` (bảng mẫu `DateTableTemplate_…` của Auto date/time).
    public let isPrivate: Bool
    /// `Table.ShowAsVariationsOnly` (bảng ngày cục bộ `LocalDateTable_…`).
    public let showAsVariationsOnly: Bool
    /// Chú thích của bảng (`Annotation`, ObjectType 3), ví dụ `__PBI_LocalDateTable`.
    public let annotations: [String: String]

    public init(name: String, columns: [NewTableColumn], queryExpression: String? = nil, enableLoad: Bool = true,
                attachment: (any Sendable)? = nil, lineageTag: String? = nil, isPrivate: Bool = false,
                showAsVariationsOnly: Bool = false, annotations: [String: String] = [:]) {
        self.name = name
        self.columns = columns
        self.queryExpression = queryExpression
        self.enableLoad = enableLoad
        self.lineageTag = lineageTag ?? UUID().uuidString.lowercased()
        self.attachment = attachment
        self.isPrivate = isPrivate
        self.showAsVariationsOnly = showAsVariationsOnly
        self.annotations = annotations
    }

    public static func == (lhs: NewTable, rhs: NewTable) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Một thao tác sửa mô hình.
public enum ModelEdit: Sendable, Hashable {
    case addMeasure(NewMeasure)
    case updateMeasure(table: String, name: String, patch: MeasurePatch)
    case deleteMeasure(table: String, name: String)
    case updateRelationship(name: String, patch: RelationshipPatch)
    case updateColumn(table: String, name: String, patch: ColumnPatch)
    case addRelationship(NewRelationship)
    case deleteRelationship(name: String)
    case updateTable(name: String, patch: TablePatch)
    // Phase F (T3): bảng và cột tính toán. Khung hợp đồng, chưa áp dụng được cho đến T016, T084.
    case addTable(NewTable)
    case replaceTable(name: String, NewTable)
    case dropTable(name: String)
    /// Truy vấn không nạp (Enable load tắt, VM-F8): dòng `Expression` có M nguyên văn. `setQuery` thêm hoặc sửa, `dropQuery` bỏ.
    case setQuery(name: String, expression: String)
    case dropQuery(name: String)
    /// Cột tính toán (T082): `dataType` do ứng dụng suy ra khi tạo (đánh giá biểu thức). Giá trị không nằm trong thao tác: engine của phiên
    /// tính lại theo thứ tự thao tác, và khi lưu ứng dụng đưa giá trị đã tính qua `PBIXChanges.calculatedData`.
    case addCalculatedColumn(table: String, name: String, expression: String, dataType: ModelMetadata.DataType)
    /// Bảng tính toán (T082): `columns` là tên và kiểu các cột kết quả.
    case addCalculatedTable(name: String, expression: String, columns: [ColumnSignature])
    /// Sửa công thức cột tính toán (T116, VM-F9): giữ ID và thuộc tính cột, giá trị tính lại; `dataType` suy lại từ biểu thức mới.
    case updateCalculatedColumn(table: String, name: String, expression: String, dataType: ModelMetadata.DataType)
    /// Xoá cột tính toán (T116): bỏ cột cùng dữ liệu lưu trữ. Bảng tính toán xoá bằng `dropTable`.
    case deleteCalculatedColumn(table: String, name: String)
    /// Sửa công thức bảng tính toán (T116): cột kết quả mới; cột cùng tên giữ ID và thuộc tính.
    case updateCalculatedTable(name: String, expression: String, columns: [ColumnSignature])
    // Đợt tồn đọng sau Phase F (`specs/011-ton-dong-sau-phase-f/contracts/model-edits.md`): khung hợp đồng, áp dụng ở US2 (T030–T032).
    /// Thêm phân cấp người dùng (Auto date/time: "Date Hierarchy").
    case addHierarchy(NewHierarchy)
    case dropHierarchy(table: String, name: String)
    /// Dòng `Variation`: cột ngày hiện phân cấp mặc định của bảng ngày cục bộ qua quan hệ `relationship`.
    case addVariation(table: String, column: String, relationship: String, hierarchy: HierarchyRef)
    case dropVariation(table: String, column: String)
    /// Chú thích của mô hình (ObjectType 1), ví dụ `__PBI_TimeIntelligenceEnabled`.
    case setModelAnnotation(name: String, value: String)

    /// Thao tác thuộc Phase F cần tầng T3.
    /// Thao tác nhắm vào bảng `lowercasedName` (thêm/sửa/xoá measure, cột, bảng, cột tính toán của nó).
    func mentionsTable(_ lowercasedName: String) -> Bool {
        switch self {
        case .addMeasure(let m): m.table.lowercased() == lowercasedName
        case .updateMeasure(let t, _, _), .deleteMeasure(let t, _), .updateColumn(let t, _, _), .addCalculatedColumn(let t, _, _, _),
             .updateCalculatedColumn(let t, _, _, _), .deleteCalculatedColumn(let t, _):
            t.lowercased() == lowercasedName
        case .updateTable(let t, _), .replaceTable(let t, _), .dropTable(let t), .updateCalculatedTable(let t, _, _): t.lowercased() == lowercasedName
        case .addTable(let t): t.name.lowercased() == lowercasedName
        case .addCalculatedTable(let t, _, _): t.lowercased() == lowercasedName
        case .addHierarchy(let h): h.table.lowercased() == lowercasedName
        case .dropHierarchy(let t, _), .addVariation(let t, _, _, _), .dropVariation(let t, _): t.lowercased() == lowercasedName
        default: false
        }
    }

    var needsData: Bool {
        switch self {
        case .addTable, .replaceTable, .dropTable, .addCalculatedColumn, .addCalculatedTable,
             .updateCalculatedColumn, .deleteCalculatedColumn, .updateCalculatedTable, .addHierarchy: true
        default: false
        }
    }
}

/// Lý do một thao tác không hợp lệ.
public struct ModelEditError: Error, Equatable, CustomStringConvertible {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var description: String { reason }
}

/// Danh sách thao tác theo thứ tự thực hiện.
public struct ModelEdits: Sendable, Hashable {
    public private(set) var items: [ModelEdit]

    public init(_ items: [ModelEdit] = []) { self.items = items }

    public var isEmpty: Bool { items.isEmpty }

    public mutating func append(_ edit: ModelEdit) { items.append(edit) }

    /// Gộp bảng thêm rồi thay hoặc xoá trong cùng đợt: `addTable(A)` rồi `replaceTable(A, A')` thành `addTable(A')`, rồi `dropTable(A)` thì
    /// bỏ cả hai. Thay hoặc xoá bảng đã có trong file thì giữ nguyên (bộ ghi từ chối, chưa hỗ trợ). Dùng khi ghi, vì file chỉ cần kết quả cuối.
    public func collapsingTableEdits() -> ModelEdits {
        var out: [ModelEdit?] = []
        var added: [String: Int] = [:]   // tên (chữ thường) → vị trí addTable/addCalculatedTable trong `out`
        var updatedTables: [String: Int] = [:]   // bảng tính toán có sẵn → vị trí updateCalculatedTable gần nhất
        // Cột tính toán (T116), khoá "bảng\0cột" chữ thường: vị trí thêm trong đợt, hoặc vị trí sửa công thức gần nhất (cột có sẵn).
        var addedColumns: [String: Int] = [:], updatedColumns: [String: Int] = [:]
        var formerNames: [String: Set<String>] = [:]   // cột thêm trong đợt: khoá hiện tại → mọi khoá cũ (đổi tên)
        func columnKey(_ table: String, _ name: String) -> String { table.lowercased() + "\u{0}" + name.lowercased() }
        for edit in items {
            switch edit {
            case .addTable(let table):
                added[table.name.lowercased()] = out.count
                out.append(edit)
            case .addCalculatedTable(let name, _, _):
                added[name.lowercased()] = out.count
                out.append(edit)
            case .replaceTable(let name, let table):
                if let at = added.removeValue(forKey: name.lowercased()) {
                    out[at] = .addTable(table)
                    added[table.name.lowercased()] = at
                } else { out.append(edit) }
            case .updateCalculatedTable(let name, let expression, let columns):
                // Bảng thêm trong đợt: thành bảng thêm với công thức mới. Bảng có sẵn: chỉ cần lần sửa cuối.
                if let at = added[name.lowercased()], case .addCalculatedTable = out[at] {
                    out[at] = .addCalculatedTable(name: name, expression: expression, columns: columns)
                } else {
                    if let previous = updatedTables[name.lowercased()] { out[previous] = nil }
                    updatedTables[name.lowercased()] = out.count
                    out.append(edit)
                }
            case .addCalculatedColumn(let table, let name, _, _):
                addedColumns[columnKey(table, name)] = out.count
                out.append(edit)
            case .updateCalculatedColumn(let table, let name, let expression, let dataType):
                let key = columnKey(table, name)
                if let at = addedColumns[key] {
                    out[at] = .addCalculatedColumn(table: table, name: name, expression: expression, dataType: dataType)
                } else {
                    if let previous = updatedColumns[key] { out[previous] = nil }
                    updatedColumns[key] = out.count
                    out.append(edit)
                }
            case .deleteCalculatedColumn(let table, let name):
                let key = columnKey(table, name)
                if let previous = updatedColumns.removeValue(forKey: key) { out[previous] = nil }
                guard let at = addedColumns.removeValue(forKey: key) else { out.append(edit); continue }
                // Cột chưa từng có trong file: bỏ lần thêm và mọi sửa thuộc tính (kể cả đổi tên) của nó ở giữa.
                let names = (formerNames.removeValue(forKey: key) ?? []).union([key])
                for index in at..<out.count {
                    guard let item = out[index] else { continue }
                    if case .updateColumn(let t, let c, _) = item, names.contains(columnKey(t, c)) { out[index] = nil }
                }
                out[at] = nil
            case .updateColumn(let table, let name, let patch):
                out.append(edit)
                // Đổi tên cột tính toán: các khoá theo tên mới.
                if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), renamed != name {
                    let old = columnKey(table, name), new = columnKey(table, renamed)
                    if let at = addedColumns.removeValue(forKey: old) {
                        addedColumns[new] = at
                        formerNames[new] = (formerNames.removeValue(forKey: old) ?? []).union([old])
                    }
                    if let at = updatedColumns.removeValue(forKey: old) { updatedColumns[new] = at }
                }
            case .dropTable(let name):
                let key = name.lowercased()
                guard let at = added.removeValue(forKey: key) else {
                    // Bảng có sẵn: sửa công thức trước đó không còn nghĩa (và giá trị của chúng không còn trong mô hình hiệu lực).
                    for index in 0..<out.count {
                        guard let item = out[index] else { continue }
                        switch item {
                        case .updateCalculatedTable(let t, _, _) where t.lowercased() == key: out[index] = nil
                        case .updateCalculatedColumn(let t, _, _, _) where t.lowercased() == key: out[index] = nil
                        case .addCalculatedColumn(let t, _, _, _) where t.lowercased() == key: out[index] = nil
                        default: break
                        }
                    }
                    updatedTables[key] = nil
                    addedColumns = addedColumns.filter { !$0.key.hasPrefix(key + "\u{0}") }
                    updatedColumns = updatedColumns.filter { !$0.key.hasPrefix(key + "\u{0}") }
                    out.append(edit)
                    continue
                }
                // Bảng chưa từng có trong file: bỏ cả mọi thao tác nhắc tới nó ở giữa (measure, cột, quan hệ…), không thì bộ ghi
                // áp chúng lên bảng không tồn tại (lỗi T096).
                var relationships = Set<String>()
                var variations = Set<String>()   // "bảng\0cột" chữ thường của variation trỏ vào bảng này (bảng ngày cục bộ, T032)
                for index in at..<out.count {
                    guard let item = out[index] else { continue }
                    if case .addRelationship(let r) = item, r.fromTable.lowercased() == key || r.toTable.lowercased() == key {
                        relationships.insert(r.name)
                        out[index] = nil
                    } else if case .addVariation(let t, let c, let r, let h) = item, relationships.contains(r) || h.table.lowercased() == key {
                        variations.insert(columnKey(t, c))
                        out[index] = nil
                    } else if case .dropVariation(let t, let c) = item, variations.contains(columnKey(t, c)) {
                        variations.remove(columnKey(t, c))
                        out[index] = nil
                    } else if item.mentionsTable(key) {
                        out[index] = nil
                    } else if case .updateRelationship(let r, _) = item, relationships.contains(r) {
                        out[index] = nil
                    } else if case .deleteRelationship(let r) = item, relationships.contains(r) {
                        out[index] = nil
                    }
                }
                addedColumns = addedColumns.filter { !$0.key.hasPrefix(key + "\u{0}") }
                updatedColumns = updatedColumns.filter { !$0.key.hasPrefix(key + "\u{0}") }
            default:
                out.append(edit)
            }
        }
        return ModelEdits(out.compactMap { $0 })
    }

    /// Tầng lưu tối thiểu: có thao tác nào thì phải ghi `metadata.sqlitedb`.
    public var tier: SaveTier { isEmpty ? .report : (items.contains { $0.needsData } ? .data : .metadata) }
}

// MARK: - Gộp thao tác liền kề

extension MeasurePatch {
    /// Phủ `other` lên `self` (trường của `other` thắng).
    func overlaid(by other: MeasurePatch) -> MeasurePatch {
        MeasurePatch(name: other.name ?? name, expression: other.expression ?? expression,
                     formatString: other.formatString ?? formatString, displayFolder: other.displayFolder ?? displayFolder,
                     description: other.description ?? description, isHidden: other.isHidden ?? isHidden,
                     dataType: other.dataType ?? dataType)
    }

    /// Tên sau khi áp patch lên tên `name`.
    func resultingName(from name: String) -> String { self.name ?? name }
}

extension RelationshipPatch {
    func overlaid(by other: RelationshipPatch) -> RelationshipPatch {
        RelationshipPatch(isActive: other.isActive ?? isActive,
                          crossFilteringBehavior: other.crossFilteringBehavior ?? crossFilteringBehavior)
    }
}

extension ColumnPatch {
    func overlaid(by other: ColumnPatch) -> ColumnPatch {
        ColumnPatch(name: other.name ?? name, isHidden: other.isHidden ?? isHidden,
                    formatString: other.formatString ?? formatString, summarizeBy: other.summarizeBy ?? summarizeBy,
                    dataCategory: other.dataCategory ?? dataCategory, sortBy: other.sortBy ?? sortBy,
                    displayFolder: other.displayFolder ?? displayFolder, description: other.description ?? description)
    }
}

extension NewMeasure {
    /// Measure mới sau khi áp một patch (đổi tên, biểu thức, ... trước khi lưu).
    func applying(_ patch: MeasurePatch) -> NewMeasure {
        var copy = self
        if let name = patch.name { copy.name = name }
        if let expression = patch.expression { copy.expression = expression }
        switch patch.formatString {
        case .none: break
        case .some(.clear): copy.formatString = nil
        case .some(.set(let value)): copy.formatString = value
        }
        switch patch.displayFolder {
        case .none: break
        case .some(.clear): copy.displayFolder = nil
        case .some(.set(let value)): copy.displayFolder = value
        }
        switch patch.description {
        case .none: break
        case .some(.clear): copy.description = nil
        case .some(.set(let value)): copy.description = value
        }
        if let hidden = patch.isHidden { copy.isHidden = hidden }
        if let type = patch.dataType { copy.dataType = type.rawValue }
        return copy
    }
}

extension ModelEdits {
    /// Thêm một thao tác; gộp với thao tác liền trước nếu cùng một đối tượng (hai lần sửa thành một, sửa measure vừa thêm
    /// thành thêm, thêm rồi xoá thành không có gì). Không gộp thao tác không liền kề.
    public func appending(_ edit: ModelEdit) -> ModelEdits {
        var list = items
        guard let last = list.last else { return ModelEdits([edit]) }
        switch (last, edit) {
        case let (.updateMeasure(table, name, previous), .updateMeasure(table2, name2, next))
            where table == table2 && previous.resultingName(from: name) == name2:
            list[list.count - 1] = .updateMeasure(table: table, name: name, patch: previous.overlaid(by: next))
        case let (.addMeasure(new), .updateMeasure(table, name, patch)) where new.table == table && new.name == name:
            list[list.count - 1] = .addMeasure(new.applying(patch))
        case let (.addMeasure(new), .deleteMeasure(table, name)) where new.table == table && new.name == name:
            list.removeLast()
        case let (.updateMeasure(table, name, previous), .deleteMeasure(table2, name2))
            where table == table2 && previous.resultingName(from: name) == name2:
            list[list.count - 1] = .deleteMeasure(table: table, name: name)
        case let (.updateRelationship(name, previous), .updateRelationship(name2, next)) where name == name2:
            list[list.count - 1] = .updateRelationship(name: name, patch: previous.overlaid(by: next))
        case let (.updateTable(name, previous), .updateTable(name2, next)) where name == name2:
            list[list.count - 1] = .updateTable(name: name, patch: TablePatch(isHidden: next.isHidden ?? previous.isHidden))
        case let (.updateColumn(table, name, previous), .updateColumn(table2, name2, next))
            where table == table2 && (previous.name ?? name) == name2:
            list[list.count - 1] = .updateColumn(table: table, name: name, patch: previous.overlaid(by: next))
        default:
            list.append(edit)
        }
        return ModelEdits(list)
    }
}
