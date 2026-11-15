import Foundation

extension ModelMetadata {
    /// Bản sao với các danh sách đã sửa; mọi trường khác giữ nguyên.
    init(copying other: ModelMetadata, columns: [Column]? = nil, measures: [Measure]? = nil,
         relationships: [Relationship]? = nil, tables: [Table]? = nil) {
        self.tables = tables ?? other.tables
        self.columns = columns ?? other.columns
        self.measures = measures ?? other.measures
        hierarchies = other.hierarchies
        self.relationships = relationships ?? other.relationships
        storage = other.storage
        partitionQueries = other.partitionQueries
        roles = other.roles
        perspectives = other.perspectives
        cultures = other.cultures
        expressions = other.expressions
        calculationGroups = other.calculationGroups
        functions = other.functions
        culture = other.culture
    }

    /// Mô hình hiệu lực sau khi áp `edits` lên mô hình này. Không đụng ABF. Ném `ModelEditError` khi một thao tác không hợp lệ.
    public func applying(_ edits: ModelEdits) throws -> ModelMetadata {
        if edits.isEmpty { return self }
        var state = self
        for edit in edits.items { state = try state.applying(edit) }
        return state
    }

    private func applying(_ edit: ModelEdit) throws -> ModelMetadata {
        switch edit {
        case .addMeasure(let new):
            let name = new.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let table = new.table.trimmingCharacters(in: .whitespacesAndNewlines)
            try validateMeasureName(name, in: table, ignoring: nil)
            guard !new.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ModelEditError("Biểu thức của measure không được để trống")
            }
            guard !new.expression.contains("\0") else { throw ModelEditError("Biểu thức chứa ký tự NUL") }
            let added = Measure(tableName: table, name: name,
                                expression: new.expression.trimmingCharacters(in: .whitespacesAndNewlines),
                                formatString: new.formatString.flatMap { $0.isEmpty ? nil : $0 },
                                displayFolder: new.displayFolder.flatMap { $0.isEmpty ? nil : $0 },
                                isHidden: new.isHidden, description: new.description.flatMap { $0.isEmpty ? nil : $0 },
                                lineageTag: nil, dataType: new.dataType.flatMap(DataType.init(rawValue:)) ?? .double,
                                state: 1, formatStringDefinition: nil)
            return ModelMetadata(copying: self, measures: measures + [added])

        case .updateMeasure(let table, let name, let patch):
            guard let index = measures.firstIndex(where: { $0.tableName == table && $0.name == name }) else {
                throw ModelEditError("Không có measure \(table)[\(name)]")
            }
            let old = measures[index]
            var newName = old.name
            if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), renamed != old.name {
                try validateMeasureName(renamed, in: table, ignoring: old.name)
                newName = renamed
            }
            if let expression = patch.expression {
                guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ModelEditError("Biểu thức của measure không được để trống")
                }
                guard !expression.contains("\0") else { throw ModelEditError("Biểu thức chứa ký tự NUL") }
            }
            var copy = measures
            copy[index] = Measure(
                tableName: old.tableName, name: newName,
                expression: patch.expression?.trimmingCharacters(in: .whitespacesAndNewlines) ?? old.expression,
                formatString: patch.formatString.resolved(old.formatString),
                displayFolder: patch.displayFolder.resolved(old.displayFolder),
                isHidden: patch.isHidden ?? old.isHidden,
                description: patch.description.resolved(old.description),
                lineageTag: old.lineageTag, dataType: patch.dataType ?? old.dataType, state: old.state,
                formatStringDefinition: old.formatStringDefinition)
            return ModelMetadata(copying: self, measures: copy)

        case .deleteMeasure(let table, let name):
            guard measures.contains(where: { $0.tableName == table && $0.name == name }) else {
                throw ModelEditError("Không có measure \(table)[\(name)]")
            }
            return ModelMetadata(copying: self, measures: measures.filter { !($0.tableName == table && $0.name == name) })

        case .updateRelationship(let name, let patch):
            guard let index = relationships.firstIndex(where: { $0.name == name }) else {
                throw ModelEditError("Không có quan hệ \(name)")
            }
            if let behavior = patch.crossFilteringBehavior, behavior != 1 && behavior != 2 {
                throw ModelEditError("Hướng lọc chéo phải là 1 (một chiều) hoặc 2 (hai chiều)")
            }
            let old = relationships[index]
            // Desktop không cho hai quan hệ hoạt động giữa cùng hai bảng (quan hệ mới thành không hoạt động).
            if patch.isActive == true, !old.isActive,
               relationships.contains(where: {
                   $0.isActive && $0.name != old.name
                       && Set([$0.fromTable, $0.toTable]) == Set([old.fromTable, old.toTable])
               }) {
                throw ModelEditError("Đã có quan hệ hoạt động giữa \(old.fromTable) và \(old.toTable); tắt quan hệ đó trước khi bật quan hệ này")
            }
            var copy = relationships
            copy[index] = Relationship(name: old.name, fromTable: old.fromTable, fromColumn: old.fromColumn,
                                       toTable: old.toTable, toColumn: old.toColumn,
                                       isActive: patch.isActive ?? old.isActive, cardinality: old.cardinality,
                                       crossFilteringBehavior: patch.crossFilteringBehavior ?? old.crossFilteringBehavior)
            return ModelMetadata(copying: self, relationships: copy)

        case .updateTable(let name, let patch):
            guard let index = tables.firstIndex(where: { $0.name == name && $0.isUserTable }) else { throw ModelEditError("Không có bảng \(name)") }
            let old = tables[index]
            var copy = tables
            copy[index] = Table(id: old.id, name: old.name, isHidden: patch.isHidden ?? old.isHidden, systemFlags: old.systemFlags,
                                description: old.description, lineageTag: old.lineageTag, dataCategory: old.dataCategory)
            return ModelMetadata(copying: self, tables: copy)

        case .addRelationship(let new):
            try validate(new)
            let cardinality = (new.fromMany ? "M" : "1") + ":" + (new.toMany ? "M" : "1")
            let added = Relationship(name: new.name, fromTable: new.fromTable, fromColumn: new.fromColumn, toTable: new.toTable,
                                     toColumn: new.toColumn, isActive: new.isActive, cardinality: cardinality,
                                     crossFilteringBehavior: new.crossFilteringBehavior)
            return ModelMetadata(copying: self, relationships: relationships + [added])

        case .deleteRelationship(let name):
            guard relationships.contains(where: { $0.name == name }) else { throw ModelEditError("Không có quan hệ \(name)") }
            return ModelMetadata(copying: self, relationships: relationships.filter { $0.name != name })

        case .updateColumn(let table, let name, let patch):
            guard let index = columns.firstIndex(where: { $0.tableName == table && $0.name == name }) else {
                throw ModelEditError("Không có cột \(table)[\(name)]")
            }
            let old = columns[index]
            var newName = old.name
            if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), renamed != old.name {
                try validateColumnRename(old, to: renamed)
                newName = renamed
            }
            var sortID = old.sortByColumnID
            switch patch.sortBy {
            case .none: break
            case .some(.clear): sortID = nil
            case .some(.set(let target)):
                guard let sort = columns.first(where: { $0.tableName == table && $0.name == target }) else {
                    throw ModelEditError("Không có cột \(table)[\(target)] để sắp xếp theo")
                }
                guard sort.id != old.id else { throw ModelEditError("Cột không thể sắp xếp theo chính nó") }
                sortID = sort.id
            }
            if let summarize = patch.summarizeBy, !(1...8).contains(summarize) {
                throw ModelEditError("Kiểu tổng hợp mặc định không hợp lệ (\(summarize))")
            }
            var copy = columns
            copy[index] = Column(
                id: old.id, tableID: old.tableID, tableName: old.tableName, name: newName, kind: old.kind,
                dataType: old.dataType, isHidden: patch.isHidden ?? old.isHidden, expression: old.expression,
                formatString: patch.formatString.resolved(old.formatString), sortByColumnID: sortID,
                summarizeBy: patch.summarizeBy ?? old.summarizeBy, dataCategory: patch.dataCategory.resolved(old.dataCategory),
                displayFolder: patch.displayFolder.resolved(old.displayFolder), isKey: old.isKey,
                sourceColumn: old.sourceColumn, description: patch.description.resolved(old.description),
                lineageTag: old.lineageTag)
            return ModelMetadata(copying: self, columns: copy)
        }
    }

    /// Quan hệ mới: hai cột có thật, cùng kiểu, khác bảng, chưa có quan hệ nào nối đúng hai cột này, và không thêm quan hệ hoạt động
    /// thứ hai giữa hai bảng (Desktop để quan hệ mới thành không hoạt động).
    private func validate(_ new: NewRelationship) throws {
        guard !new.name.isEmpty else { throw ModelEditError("Quan hệ cần có tên") }
        guard !relationships.contains(where: { $0.name == new.name }) else { throw ModelEditError("Đã có quan hệ tên \(new.name)") }
        guard new.fromTable != new.toTable else { throw ModelEditError("Hai đầu quan hệ phải ở hai bảng khác nhau") }
        guard new.crossFilteringBehavior == 1 || new.crossFilteringBehavior == 2 else { throw ModelEditError("Hướng lọc chéo phải là 1 hoặc 2") }
        guard let from = columns.first(where: { $0.tableName == new.fromTable && $0.name == new.fromColumn && $0.kind != .rowNumber }),
              let to = columns.first(where: { $0.tableName == new.toTable && $0.name == new.toColumn && $0.kind != .rowNumber }) else {
            throw ModelEditError("Không có cột \(new.fromTable)[\(new.fromColumn)] hoặc \(new.toTable)[\(new.toColumn)]")
        }
        guard from.dataType == to.dataType else { throw ModelEditError("Hai cột phải cùng kiểu dữ liệu") }
        guard !(new.fromMany && new.toMany) else { throw ModelEditError("Quan hệ nhiều-nhiều chưa được hỗ trợ") }
        let same = relationships.contains {
            Set(["\($0.fromTable)[\($0.fromColumn)]", "\($0.toTable)[\($0.toColumn)]"]) ==
                Set(["\(new.fromTable)[\(new.fromColumn)]", "\(new.toTable)[\(new.toColumn)]"])
        }
        guard !same else { throw ModelEditError("Đã có quan hệ nối hai cột này") }
        if new.isActive, relationships.contains(where: {
            $0.isActive && Set([$0.fromTable, $0.toTable]) == Set([new.fromTable, new.toTable])
        }) {
            throw ModelEditError("Đã có quan hệ hoạt động giữa \(new.fromTable) và \(new.toTable); quan hệ mới phải ở trạng thái không hoạt động")
        }
    }

    /// Đổi tên cột: tên không rỗng, không trùng cột hoặc measure cùng bảng, và cột không còn là đầu quan hệ hay cấp phân cấp.
    private func validateColumnRename(_ column: Column, to name: String) throws {
        guard !name.isEmpty else { throw ModelEditError("Tên cột không được để trống") }
        guard !name.contains("\0") else { throw ModelEditError("Tên cột chứa ký tự NUL") }
        let key = name.lowercased()
        if columns.contains(where: { $0.tableName == column.tableName && $0.id != column.id && $0.name.lowercased() == key })
            || measures.contains(where: { $0.tableName == column.tableName && $0.name.lowercased() == key }) {
            throw ModelEditError("Bảng \(column.tableName) đã có cột hoặc measure tên \(name)")
        }
        if relationships.contains(where: {
            ($0.fromTable == column.tableName && $0.fromColumn == column.name) || ($0.toTable == column.tableName && $0.toColumn == column.name)
        }) {
            throw ModelEditError("Cột \(column.tableName)[\(column.name)] là đầu của một quan hệ")
        }
        if hierarchies.contains(where: { $0.tableName == column.tableName && $0.levels.contains { $0.columnName == column.name } }) {
            throw ModelEditError("Cột \(column.tableName)[\(column.name)] nằm trong một phân cấp")
        }
    }

    /// Tên measure phải không rỗng, không NUL, bảng có thật, và không trùng measure, cột cùng bảng hoặc tên bảng nào
    /// (không phân biệt hoa thường). `ignoring` là tên cũ khi đổi tên.
    private func validateMeasureName(_ name: String, in table: String, ignoring old: String?) throws {
        guard !name.isEmpty else { throw ModelEditError("Tên measure không được để trống") }
        guard !name.contains("\0") else { throw ModelEditError("Tên measure chứa ký tự NUL") }
        guard userTables.contains(where: { $0.name == table }) else { throw ModelEditError("Không có bảng \(table)") }
        let key = name.lowercased()
        if measures.contains(where: { $0.tableName == table && $0.name.lowercased() == key && $0.name != old }) {
            throw ModelEditError("Bảng \(table) đã có measure tên \(name)")
        }
        if columns.contains(where: { $0.tableName == table && $0.name.lowercased() == key }) {
            throw ModelEditError("Bảng \(table) đã có cột tên \(name)")
        }
        if tables.contains(where: { $0.name.lowercased() == key }) {
            throw ModelEditError("Tên \(name) trùng tên một bảng")
        }
    }
}

extension Optional {
    /// `nil` giữ giá trị cũ, `.clear` xoá, `.set(x)` đặt.
    fileprivate func resolved<T: Sendable & Hashable>(_ old: T?) -> T? where Wrapped == Assignment<T> {
        switch self {
        case .none: old
        case .some(.clear): nil
        case .some(.set(let value)): value
        }
    }
}

extension ModelMetadata {
    /// Thao tác đưa `old` thành `new` (measure thêm, sửa, xoá theo `(bảng, tên)`; quan hệ theo tên; cột theo ID). Dùng khi lưu
    /// lần thứ hai trong phiên, khi file trên đĩa (`old`) đã chứa phần đã lưu của lần trước.
    public static func edits(from old: ModelMetadata, to new: ModelMetadata) -> ModelEdits {
        var edits = ModelEdits()
        func key(_ m: Measure) -> String { "\(m.tableName)\u{0}\(m.name)" }
        var oldMeasures = Dictionary(old.measures.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        let newMeasures = Dictionary(new.measures.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        // Quan hệ bị xoá (trước các thao tác khác: tên cột còn nguyên) và quan hệ mới.
        let newRelationshipNames = Set(new.relationships.map(\.name))
        for r in old.relationships where !newRelationshipNames.contains(r.name) { edits.append(.deleteRelationship(name: r.name)) }
        // Measure đổi tên: cùng bảng và cùng `lineageTag` thì là sửa tên (giữ ID, không xoá rồi thêm).
        var renamed: [(old: Measure, new: Measure)] = []
        let unmatchedOld = old.measures.filter { newMeasures[key($0)] == nil }
        for m in new.measures where oldMeasures[key(m)] == nil {
            guard let tag = m.lineageTag else { continue }
            let taken = Set(renamed.map { key($0.old) })
            if let before = unmatchedOld.first(where: { $0.lineageTag == tag && $0.tableName == m.tableName && !taken.contains(key($0)) }) {
                renamed.append((before, m))
            }
        }
        let renamedOld = Set(renamed.map { key($0.old) }), renamedNew = Set(renamed.map { key($0.new) })
        for m in old.measures where newMeasures[key(m)] == nil && !renamedOld.contains(key(m)) {
            edits.append(.deleteMeasure(table: m.tableName, name: m.name))
        }
        for m in new.measures where oldMeasures[key(m)] == nil && !renamedNew.contains(key(m)) {
            edits.append(.addMeasure(NewMeasure(table: m.tableName, name: m.name, expression: m.expression,
                                                formatString: m.formatString, displayFolder: m.displayFolder,
                                                description: m.description, isHidden: m.isHidden, dataType: m.dataType.rawValue)))
        }
        for pair in renamed { oldMeasures[key(pair.new)] = pair.old }
        func assign(_ old: String?, _ new: String?) -> Assignment<String>? {
            old == new ? nil : (new.map { .set($0) } ?? .clear)
        }
        for m in new.measures {
            guard let before = oldMeasures[key(m)] else { continue }
            var patch = MeasurePatch()
            if m.name != before.name { patch.name = m.name }
            if m.expression != before.expression { patch.expression = m.expression }
            patch.formatString = assign(before.formatString, m.formatString)
            patch.displayFolder = assign(before.displayFolder, m.displayFolder)
            patch.description = assign(before.description, m.description)
            if m.isHidden != before.isHidden { patch.isHidden = m.isHidden }
            if m.dataType != before.dataType { patch.dataType = m.dataType }
            if patch != MeasurePatch() { edits.append(.updateMeasure(table: m.tableName, name: before.name, patch: patch)) }
        }
        let oldTables = Dictionary(old.tables.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for t in new.tables where t.isUserTable {
            if let before = oldTables[t.name], before.isHidden != t.isHidden {
                edits.append(.updateTable(name: t.name, patch: TablePatch(isHidden: t.isHidden)))
            }
        }
        let oldRelationships = Dictionary(old.relationships.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for r in new.relationships {
            guard let before = oldRelationships[r.name] else {
                edits.append(.addRelationship(NewRelationship(name: r.name, fromTable: r.fromTable, fromColumn: r.fromColumn, toTable: r.toTable,
                                                              toColumn: r.toColumn, fromMany: r.cardinality.hasPrefix("M"), toMany: r.cardinality.hasSuffix("M"),
                                                              isActive: r.isActive, crossFilteringBehavior: r.crossFilteringBehavior)))
                continue
            }
            var patch = RelationshipPatch()
            if r.isActive != before.isActive { patch.isActive = r.isActive }
            if r.crossFilteringBehavior != before.crossFilteringBehavior { patch.crossFilteringBehavior = r.crossFilteringBehavior }
            if patch != RelationshipPatch() { edits.append(.updateRelationship(name: r.name, patch: patch)) }
        }
        let oldColumns = Dictionary(old.columns.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newColumnNames = Dictionary(new.columns.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        for c in new.columns {
            guard let before = oldColumns[c.id] else { continue }
            var patch = ColumnPatch()
            if c.name != before.name { patch.name = c.name }
            if c.isHidden != before.isHidden { patch.isHidden = c.isHidden }
            patch.formatString = assign(before.formatString, c.formatString)
            if c.summarizeBy != before.summarizeBy { patch.summarizeBy = c.summarizeBy }
            patch.dataCategory = assign(before.dataCategory, c.dataCategory)
            if c.sortByColumnID != before.sortByColumnID {
                patch.sortBy = c.sortByColumnID.flatMap { newColumnNames[$0] }.map { .set($0) } ?? .clear
            }
            patch.displayFolder = assign(before.displayFolder, c.displayFolder)
            patch.description = assign(before.description, c.description)
            if patch != ColumnPatch() { edits.append(.updateColumn(table: before.tableName, name: before.name, patch: patch)) }
        }
        return edits
    }
}
