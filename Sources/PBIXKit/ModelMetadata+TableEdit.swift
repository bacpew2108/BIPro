// Phase F (T016): áp `.addTable`, `.replaceTable`, `.dropTable` lên mô hình hiệu lực (chỉ siêu dữ liệu trong bộ nhớ).
// Dữ liệu ô nằm ở `TableData` phía ứng dụng (nguồn cột chồng, T020); ghi ra `.pbix` là việc của T015, T017, T022.
// Cột mới (Desktop 2.159 nạp CSV, 2026-11-15, `docs/phase-f-evidence/vm-f1/QUAN-SAT.md`): `summarizeBy` 3 (cộng dồn) cho số, 2 (không) cho
// chuỗi/ngày/logic; số có tên kết thúc bằng "ID" là 6 (đếm; Desktop cho OrderID và CustomerID 6 khi chưa có quan hệ, 2 khi cột nằm trong quan hệ).

import Foundation

extension ModelMetadata {
    // MARK: addTable

    func addingTable(_ new: NewTable) throws -> ModelMetadata {
        // Truy vấn tắt "Enable load" không tạo bảng trong mô hình (chỉ nằm trong DataMashup).
        guard new.enableLoad else { return self }
        let name = try validatedTableName(new.name, ignoring: nil)
        try validateNewColumns(new.columns, table: name)
        let tableID = (tables.map(\.id).max() ?? 0) + 1
        let table = Table(id: tableID, name: name, isHidden: false, systemFlags: 0, description: nil,
                          lineageTag: new.lineageTag, dataCategory: nil)
        var nextID = (columns.map(\.id).max() ?? 0) + 1
        let added = new.columns.map { column -> Column in
            defer { nextID += 1 }
            return Self.dataColumn(id: nextID, tableID: tableID, table: name, from: column, keeping: nil)
        }
        var queries = partitionQueries
        queries[name] = new.queryExpression
        return ModelMetadata(copying: self, columns: columns + added, tables: tables + [table], partitionQueries: queries)
    }

    // MARK: replaceTable

    func replacingTable(_ oldName: String, with new: NewTable) throws -> ModelMetadata {
        guard let tableIndex = tables.firstIndex(where: { $0.name == oldName && $0.isUserTable }) else {
            throw ModelEditError("Không có bảng \(oldName)")
        }
        let old = tables[tableIndex]
        let name = try validatedTableName(new.name, ignoring: oldName)
        try validateNewColumns(new.columns, table: name)

        let oldColumns = columns.filter { $0.tableID == old.id }
        let oldData = oldColumns.filter { $0.kind == .data }
        let oldByName = Dictionary(oldData.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let keptNames = Set(new.columns.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) })
        let removed = oldData.filter { !keptNames.contains($0.name) }

        let blockers = usesOfRemovedColumns(removed, in: old.name, survivingIDs: Set(oldData.filter { keptNames.contains($0.name) }.map(\.id)))
        if !blockers.isEmpty {
            throw ModelEditError("Không thể thay bảng \(oldName): " + blockers.joined(separator: "; "))
        }
        if let clash = new.columns.first(where: { column in
            measures.contains { $0.tableName == oldName && $0.name.lowercased() == column.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        }) {
            throw ModelEditError("Cột \(clash.name) trùng tên một measure của bảng \(oldName)")
        }

        var nextID = (columns.map(\.id).max() ?? 0) + 1
        let rebuilt = new.columns.map { column -> Column in
            let trimmed = column.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let previous = oldByName[trimmed]
            let id = previous?.id ?? nextID
            if previous == nil { nextID += 1 }
            return Self.dataColumn(id: id, tableID: old.id, table: name, from: column, keeping: previous)
        }
        let survivingIDs = Set(rebuilt.map(\.id))
        let fixed = rebuilt.map { column -> Column in
            // Cột sắp xếp theo cột đã mất thì bỏ (đã chặn ở trên nếu cột còn lại phụ thuộc).
            guard let sort = column.sortByColumnID, !survivingIDs.contains(sort) else { return column }
            return Column.copy(column, sortByColumnID: .some(nil))
        }
        let rowNumbers = oldColumns.filter { $0.kind == .rowNumber }.map { Column.copy($0, tableName: name) }
        let others = oldColumns.filter { $0.kind != .data && $0.kind != .rowNumber }.map { Column.copy($0, tableName: name) }
        let newList = rowNumbers + fixed + others
        var allColumns = columns.filter { $0.tableID != old.id }
        let position = columns.firstIndex { $0.tableID == old.id }.map { min($0, allColumns.count) } ?? allColumns.count
        allColumns.insert(contentsOf: newList, at: position)

        var newTables = tables
        newTables[tableIndex] = Table(id: old.id, name: name, isHidden: old.isHidden, systemFlags: old.systemFlags,
                                      description: old.description, lineageTag: old.lineageTag, dataCategory: old.dataCategory)
        let renamed = name != oldName
        let newRelationships = !renamed ? relationships : relationships.map {
            Relationship(name: $0.name, fromTable: $0.fromTable == oldName ? name : $0.fromTable, fromColumn: $0.fromColumn,
                         toTable: $0.toTable == oldName ? name : $0.toTable, toColumn: $0.toColumn, isActive: $0.isActive,
                         cardinality: $0.cardinality, crossFilteringBehavior: $0.crossFilteringBehavior)
        }
        let newMeasures = !renamed ? measures : measures.map { $0.tableName == oldName ? Measure.copy($0, tableName: name) : $0 }
        let newHierarchies = !renamed ? hierarchies : hierarchies.map {
            $0.tableName == oldName
                ? Hierarchy(tableName: name, name: $0.name, isHidden: $0.isHidden, displayFolder: $0.displayFolder,
                            lineageTag: $0.lineageTag, levels: $0.levels)
                : $0
        }
        var queries = partitionQueries
        queries[oldName] = nil
        queries[name] = new.queryExpression
        return ModelMetadata(copying: self, columns: allColumns, measures: newMeasures, relationships: newRelationships,
                             tables: newTables, hierarchies: newHierarchies,
                             storage: storage.filter { $0.tableName != oldName }, partitionQueries: queries)
    }

    // MARK: dropTable

    func droppingTable(_ name: String) throws -> ModelMetadata {
        guard let table = tables.first(where: { $0.name == name && $0.isUserTable }) else {
            throw ModelEditError("Không có bảng \(name)")
        }
        var blockers: [String] = []
        let related = relationships.filter { $0.fromTable == name || $0.toTable == name }.map(\.name)
        if !related.isEmpty { blockers.append("còn quan hệ " + related.joined(separator: ", ")) }
        let hosted = measures.filter { $0.tableName == name }.map(\.name)
        if !hosted.isEmpty { blockers.append("còn chứa measure " + hosted.joined(separator: ", ")) }
        let users = measures.filter { $0.tableName != name && Self.mentionsTable($0.expression, name) }.map(\.name)
        if !users.isEmpty { blockers.append("measure " + users.joined(separator: ", ") + " đang dùng bảng") }
        if !blockers.isEmpty { throw ModelEditError("Không thể xoá bảng \(name): " + blockers.joined(separator: "; ")) }
        var queries = partitionQueries
        queries[name] = nil
        return ModelMetadata(copying: self, columns: columns.filter { $0.tableID != table.id },
                             tables: tables.filter { $0.id != table.id },
                             hierarchies: hierarchies.filter { $0.tableName != name },
                             storage: storage.filter { $0.tableName != name }, partitionQueries: queries)
    }

    // MARK: Kiểm tra

    /// Tên bảng đã cắt khoảng trắng: không rỗng, không NUL, không trùng bảng hay measure nào (không phân biệt hoa thường).
    private func validatedTableName(_ raw: String, ignoring old: String?) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ModelEditError("Tên bảng không được để trống") }
        guard !name.contains("\0") else { throw ModelEditError("Tên bảng chứa ký tự NUL") }
        let key = name.lowercased()
        if tables.contains(where: { $0.name.lowercased() == key && $0.name != old }) {
            throw ModelEditError("Tên bảng \(name) trùng một bảng đã có (không phân biệt hoa thường)")
        }
        if measures.contains(where: { $0.name.lowercased() == key }) {
            throw ModelEditError("Tên bảng \(name) trùng tên một measure")
        }
        return name
    }

    private func validateNewColumns(_ list: [NewTableColumn], table: String) throws {
        guard !list.isEmpty else { throw ModelEditError("Bảng \(table) cần có ít nhất một cột") }
        var seen: [String: String] = [:]
        for column in list {
            let name = column.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw ModelEditError("Tên cột không được để trống (bảng \(table))") }
            guard !name.contains("\0") else { throw ModelEditError("Tên cột \(name) chứa ký tự NUL (bảng \(table))") }
            if let first = seen[name.lowercased()] {
                throw ModelEditError("Bảng \(table) có hai cột tên \(first) (không phân biệt hoa thường)")
            }
            seen[name.lowercased()] = name
        }
    }

    /// Chỗ dùng của các cột sắp mất: quan hệ, phân cấp, cột sắp xếp theo, biểu thức measure và cột tính toán nhắc `Bảng[Cột]`.
    private func usesOfRemovedColumns(_ removed: [Column], in table: String, survivingIDs: Set<Int>) -> [String] {
        var lines: [String] = []
        for column in removed {
            var uses: [String] = []
            let rels = relationships.filter {
                ($0.fromTable == table && $0.fromColumn == column.name) || ($0.toTable == table && $0.toColumn == column.name)
            }.map(\.name)
            if !rels.isEmpty { uses.append("quan hệ " + rels.joined(separator: ", ")) }
            let hier = hierarchies.filter { $0.tableName == table && $0.levels.contains { $0.columnName == column.name } }.map(\.name)
            if !hier.isEmpty { uses.append("phân cấp " + hier.joined(separator: ", ")) }
            let sorted = columns.filter { $0.sortByColumnID == column.id && survivingIDs.contains($0.id) }.map(\.name)
            if !sorted.isEmpty { uses.append("cột sắp xếp theo: " + sorted.joined(separator: ", ")) }
            let measureUses = measures.filter { Self.mentionsColumn($0.expression, table: table, column: column.name) }.map(\.name)
            if !measureUses.isEmpty { uses.append("measure " + measureUses.joined(separator: ", ")) }
            let calculated = columns.filter { $0.expression.map { Self.mentionsColumn($0, table: table, column: column.name) } ?? false }.map(\.name)
            if !calculated.isEmpty { uses.append("cột tính toán " + calculated.joined(separator: ", ")) }
            if !uses.isEmpty { lines.append("cột \(column.name) đang được dùng bởi " + uses.joined(separator: " và ")) }
        }
        return lines
    }

    private static func mentionsColumn(_ expression: String, table: String, column: String) -> Bool {
        let text = expression.lowercased()
        let t = table.lowercased(), c = column.lowercased()
        return text.contains("'\(t)'[\(c)]") || text.contains("\(t)[\(c)]")
    }

    /// Biểu thức DAX nhắc tên bảng: dạng có nháy `'Bảng'` hoặc tên trần đứng riêng. Thận trọng: chuỗi chữ trùng tên cũng tính.
    private static func mentionsTable(_ expression: String, _ table: String) -> Bool {
        let text = expression.lowercased(), t = table.lowercased()
        if text.contains("'\(t)'") { return true }
        let pattern = "(?<![\\w'\\[])" + NSRegularExpression.escapedPattern(for: t) + "(?![\\w'])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: Dựng cột

    private static func dataColumn(id: Int, tableID: Int, table: String, from column: NewTableColumn, keeping old: Column?) -> Column {
        let name = column.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sameType = old.map { $0.dataType == column.dataType } ?? false
        let defaultSummarize = column.dataType.isNumeric ? (column.name.lowercased().hasSuffix("id") ? 6 : 3) : 2
        return Column(id: id, tableID: tableID, tableName: table, name: name, kind: .data, dataType: column.dataType,
                      isHidden: old?.isHidden ?? false, expression: nil, formatString: sameType ? old?.formatString : nil,
                      sortByColumnID: old?.sortByColumnID, summarizeBy: sameType ? (old?.summarizeBy ?? defaultSummarize) : defaultSummarize,
                      dataCategory: old?.dataCategory, displayFolder: old?.displayFolder, isKey: old?.isKey ?? false,
                      sourceColumn: name, description: old?.description, lineageTag: old?.lineageTag)
    }
}

extension ModelMetadata.Column {
    /// Bản sao đổi một vài trường (`sortByColumnID: .some(nil)` là xoá).
    fileprivate static func copy(_ c: ModelMetadata.Column, tableName: String? = nil, sortByColumnID: Int?? = nil) -> ModelMetadata.Column {
        ModelMetadata.Column(id: c.id, tableID: c.tableID, tableName: tableName ?? c.tableName, name: c.name, kind: c.kind,
                             dataType: c.dataType, isHidden: c.isHidden, expression: c.expression, formatString: c.formatString,
                             sortByColumnID: sortByColumnID ?? c.sortByColumnID, summarizeBy: c.summarizeBy,
                             dataCategory: c.dataCategory, displayFolder: c.displayFolder, isKey: c.isKey,
                             sourceColumn: c.sourceColumn, description: c.description, lineageTag: c.lineageTag)
    }
}

extension ModelMetadata.Measure {
    fileprivate static func copy(_ m: ModelMetadata.Measure, tableName: String) -> ModelMetadata.Measure {
        ModelMetadata.Measure(tableName: tableName, name: m.name, expression: m.expression, formatString: m.formatString,
                              displayFolder: m.displayFolder, isHidden: m.isHidden, description: m.description,
                              lineageTag: m.lineageTag, dataType: m.dataType, state: m.state,
                              formatStringDefinition: m.formatStringDefinition)
    }
}
