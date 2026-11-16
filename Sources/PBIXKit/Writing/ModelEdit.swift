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

    public init(name: String? = nil, isHidden: Bool? = nil, formatString: Assignment<String>? = nil,
                summarizeBy: Int? = nil, dataCategory: Assignment<String>? = nil, sortBy: Assignment<String>? = nil,
                displayFolder: Assignment<String>? = nil, description: Assignment<String>? = nil) {
        self.name = name
        self.isHidden = isHidden
        self.formatString = formatString
        self.summarizeBy = summarizeBy
        self.dataCategory = dataCategory
        self.sortBy = sortBy
        self.displayFolder = displayFolder
        self.description = description
    }
}

/// Sửa thuộc tính của một bảng (chỉ ẩn/hiện). Trường `nil` giữ nguyên.
public struct TablePatch: Sendable, Hashable {
    public var isHidden: Bool?

    public init(isHidden: Bool? = nil) { self.isHidden = isHidden }
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

    public init(name: String = UUID().uuidString.lowercased(), fromTable: String, fromColumn: String, toTable: String,
                toColumn: String, fromMany: Bool = true, toMany: Bool = false, isActive: Bool = true, crossFilteringBehavior: Int = 1) {
        self.name = name
        self.fromTable = fromTable
        self.fromColumn = fromColumn
        self.toTable = toTable
        self.toColumn = toColumn
        self.fromMany = fromMany
        self.toMany = toMany
        self.isActive = isActive
        self.crossFilteringBehavior = crossFilteringBehavior
    }
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

    public init(name: String, columns: [NewTableColumn], queryExpression: String? = nil, enableLoad: Bool = true,
                attachment: (any Sendable)? = nil, lineageTag: String? = nil) {
        self.name = name
        self.columns = columns
        self.queryExpression = queryExpression
        self.enableLoad = enableLoad
        self.lineageTag = lineageTag ?? UUID().uuidString.lowercased()
        self.attachment = attachment
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
    case addCalculatedColumn(table: String, name: String, expression: String)
    case addCalculatedTable(name: String, expression: String)

    /// Thao tác thuộc Phase F cần tầng T3.
    var needsData: Bool {
        switch self {
        case .addTable, .replaceTable, .dropTable, .addCalculatedColumn, .addCalculatedTable: true
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
        var added: [String: Int] = [:]   // tên (chữ thường) → vị trí addTable trong `out`
        for edit in items {
            switch edit {
            case .addTable(let table):
                added[table.name.lowercased()] = out.count
                out.append(edit)
            case .replaceTable(let name, let table):
                if let at = added.removeValue(forKey: name.lowercased()) {
                    out[at] = .addTable(table)
                    added[table.name.lowercased()] = at
                } else { out.append(edit) }
            case .dropTable(let name):
                if let at = added.removeValue(forKey: name.lowercased()) { out[at] = nil } else { out.append(edit) }
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
