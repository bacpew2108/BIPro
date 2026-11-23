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

    // MARK: Cột và bảng tính toán (T082)

    /// Thêm cột tính toán (`Column.Type = 2`) vào bảng người dùng. Tên không trùng cột hay measure của bảng; biểu thức không trống.
    /// Cột chưa có dữ liệu lưu trữ (`storage`): engine của phiên tính giá trị.
    func addingCalculatedColumn(table: String, name rawName: String, expression: String, dataType: DataType) throws -> ModelMetadata {
        guard let owner = tables.first(where: { $0.name == table && $0.isUserTable }) else { throw ModelEditError(lt("Không có bảng \(table)", "There is no table \(table)")) }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ModelEditError(lt("Tên cột không được để trống", "The column name can't be empty")) }
        guard !name.contains("\0"), !expression.contains("\0") else { throw ModelEditError(lt("Tên hoặc biểu thức chứa ký tự NUL", "The name or expression contains a NUL character")) }
        let body = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw ModelEditError(lt("Biểu thức của cột \(name) không được để trống", "The expression of column \(name) can't be empty")) }
        let key = name.lowercased()
        if columns.contains(where: { $0.tableID == owner.id && $0.kind != .rowNumber && $0.name.lowercased() == key }) {
            throw ModelEditError(lt("Bảng \(table) đã có cột \(name)", "Table \(table) already has a column \(name)"))
        }
        if measures.contains(where: { $0.name.lowercased() == key }) { throw ModelEditError(lt("Tên cột \(name) trùng tên một measure", "The column name \(name) matches a measure name")) }
        guard [.int64, .double, .decimal, .string, .dateTime, .boolean].contains(dataType) else {
            throw ModelEditError(lt("Cột tính toán \(name) không có kiểu dữ liệu xác định", "The calculated column \(name) has no determined data type"))
        }
        let id = (columns.map(\.id).max() ?? 0) + 1
        let added = Column(id: id, tableID: owner.id, tableName: owner.name, name: name, kind: .calculated, dataType: dataType,
                           isHidden: false, expression: body, formatString: nil, sortByColumnID: nil,
                           summarizeBy: Int(TableMetadataWriter.summarizeBy(dataType, name: name, isRowNumber: false)),
                           dataCategory: nil, displayFolder: nil, isKey: false, sourceColumn: nil, description: nil, lineageTag: nil)
        return ModelMetadata(copying: self, columns: columns + [added])
    }

    /// Thêm bảng tính toán (phân vùng DAX, cột `Type = 4`), như bảng `Ngày` của w8.3 (`SystemFlags = 2`).
    func addingCalculatedTable(name rawName: String, expression: String, columns list: [ColumnSignature]) throws -> ModelMetadata {
        let name = try validatedTableName(rawName, ignoring: nil)
        try validateNewColumns(list.map { NewTableColumn(name: $0.name, dataType: $0.dataType) }, table: name)
        let body = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !body.contains("\0") else { throw ModelEditError(lt("Biểu thức của bảng \(name) trống hoặc chứa NUL", "The expression of table \(name) is empty or contains NUL")) }
        let tableID = (tables.map(\.id).max() ?? 0) + 1
        let table = Table(id: tableID, name: name, isHidden: false, systemFlags: 2, description: nil, lineageTag: UUID().uuidString.lowercased(),
                          dataCategory: nil, isCalculatedUserTable: true)
        var nextID = (columns.map(\.id).max() ?? 0) + 1
        let added = list.map { column -> Column in
            defer { nextID += 1 }
            let columnName = column.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return Column(id: nextID, tableID: tableID, tableName: name, name: columnName, kind: .calculatedTableColumn,
                          dataType: column.dataType, isHidden: false, expression: nil, formatString: nil, sortByColumnID: nil,
                          summarizeBy: Int(TableMetadataWriter.summarizeBy(column.dataType, name: columnName, isRowNumber: false)),
                          dataCategory: nil, displayFolder: nil, isKey: false, sourceColumn: column.sourceColumn ?? "[\(columnName)]",
                          description: nil, lineageTag: nil)
        }
        var expressions = calculatedTableExpressions
        expressions[name] = body
        return ModelMetadata(copying: self, columns: columns + added, tables: tables + [table], calculatedTableExpressions: expressions)
    }

    // MARK: Sửa và xoá cột, bảng tính toán (T116, VM-F9)

    /// Sửa công thức cột tính toán: giữ ID, tên và thuộc tính (Desktop chỉ đổi `Expression` và dữ liệu). Kiểu đổi thì định dạng và cách
    /// tổng hợp về mặc định của kiểu mới, như cột mới của bộ ghi. Cột nằm trong quan hệ, là cấp của phân cấp hay là cột sắp xếp của cột
    /// khác vẫn sửa được (US4): bộ ghi dựng lại chỉ mục `R$`/`U$` theo dữ liệu mới như Desktop.
    func updatingCalculatedColumn(table: String, name: String, expression: String, dataType: DataType) throws -> ModelMetadata {
        guard let index = columns.firstIndex(where: { $0.tableName == table && $0.name == name }) else {
            throw ModelEditError(lt("Không có cột \(table)[\(name)]", "There is no column \(table)[\(name)]"))
        }
        let old = columns[index]
        guard old.kind == .calculated else { throw ModelEditError(lt("Cột \(table)[\(name)] không phải cột tính toán", "Column \(table)[\(name)] isn't a calculated column")) }
        let body = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw ModelEditError(lt("Biểu thức của cột \(name) không được để trống", "The expression of column \(name) can't be empty")) }
        guard !body.contains("\0") else { throw ModelEditError(lt("Biểu thức chứa ký tự NUL", "The expression contains a NUL character")) }
        guard [.int64, .double, .decimal, .string, .dateTime, .boolean].contains(dataType) else {
            throw ModelEditError(lt("Cột tính toán \(name) không có kiểu dữ liệu xác định", "The calculated column \(name) has no determined data type"))
        }
        let sameType = old.dataType == dataType
        var all = columns
        all[index] = Column(id: old.id, tableID: old.tableID, tableName: old.tableName, name: old.name, kind: .calculated, dataType: dataType,
                            isHidden: old.isHidden, expression: body,
                            formatString: sameType ? old.formatString : TableMetadataWriter.formatString(dataType),
                            sortByColumnID: old.sortByColumnID,
                            summarizeBy: sameType ? old.summarizeBy : Int(TableMetadataWriter.summarizeBy(dataType, name: old.name, isRowNumber: false)),
                            dataCategory: old.dataCategory, displayFolder: old.displayFolder, isKey: old.isKey, sourceColumn: old.sourceColumn,
                            description: old.description, lineageTag: old.lineageTag)
        return ModelMetadata(copying: self, columns: all, storage: storage.filter { !($0.tableName == table && $0.columnName == name) })
    }

    /// Xoá cột tính toán. Chặn khi measure, cột hoặc bảng tính toán còn dùng cột (FR-004); nơi dùng trong báo cáo do ứng dụng kiểm.
    /// Quan hệ dùng cột bị bỏ, cột bỏ khỏi các phân cấp (phân cấp hết cấp thì bỏ), cột sắp theo cột này về sắp mặc định
    /// (US4, `[SUY ĐOÁN]` như Desktop, VM-F13 chưa quan sát); danh sách ở `indexCascade(of:)`.
    func deletingCalculatedColumn(table: String, name: String) throws -> ModelMetadata {
        guard let column = columns.first(where: { $0.tableName == table && $0.name == name }) else {
            throw ModelEditError(lt("Không có cột \(table)[\(name)]", "There is no column \(table)[\(name)]"))
        }
        guard column.kind == .calculated else { throw ModelEditError(lt("Cột \(table)[\(name)] không phải cột tính toán, chưa xoá được", "Column \(table)[\(name)] isn't a calculated column and can't be deleted yet")) }
        var blockers: [String] = []
        let measureUses = measures.filter { Self.mentionsColumn($0.expression, table: table, column: name) }.map(\.name)
        if !measureUses.isEmpty { blockers.append(lt("measure \(measureUses.joined(separator: ", ")) dùng cột", "measures \(measureUses.joined(separator: ", ")) use the column")) }
        let calculated = columns.filter { $0.id != column.id && ($0.expression.map { Self.mentionsColumn($0, table: table, column: name) } ?? false) }.map(\.name)
        if !calculated.isEmpty { blockers.append(lt("cột tính toán \(calculated.joined(separator: ", ")) dùng cột", "calculated columns \(calculated.joined(separator: ", ")) use the column")) }
        let tablesUsing = calculatedTableExpressions.filter { Self.mentionsColumn($0.value, table: table, column: name) }.keys.sorted()
        if !tablesUsing.isEmpty { blockers.append(lt("bảng tính toán \(tablesUsing.joined(separator: ", ")) dùng cột", "calculated tables \(tablesUsing.joined(separator: ", ")) use the column")) }
        if !blockers.isEmpty { throw ModelEditError(lt("Không thể xoá cột \(table)[\(name)]: ", "Couldn't delete column \(table)[\(name)]: ") + blockers.joined(separator: "; ")) }
        let uses = { (r: Relationship) in (r.fromTable == table && r.fromColumn == name) || (r.toTable == table && r.toColumn == name) }
        let kept = hierarchies.compactMap { h -> Hierarchy? in
            guard h.tableName == table, h.levels.contains(where: { $0.columnName == name }) else { return h }
            let levels = h.levels.filter { $0.columnName != name }
            return levels.isEmpty ? nil : Hierarchy(tableName: h.tableName, name: h.name, isHidden: h.isHidden, displayFolder: h.displayFolder,
                                                     lineageTag: h.lineageTag, levels: levels)
        }
        let remaining = columns.filter { $0.id != column.id }.map { c in c.sortByColumnID == column.id ? Column.copy(c, sortByColumnID: .some(nil)) : c }
        return ModelMetadata(copying: self, columns: remaining, relationships: relationships.filter { !uses($0) }, hierarchies: kept,
                             storage: storage.filter { !($0.tableName == table && $0.columnName == name) })
    }

    /// Những gì bị bỏ kèm khi xoá cột `table[name]` (lời cho hộp xác nhận): quan hệ, cấp phân cấp, cột sắp xếp theo cột này.
    public func indexCascade(of table: String, name: String) -> [String] {
        guard let column = columns.first(where: { $0.tableName == table && $0.name == name }) else { return [] }
        var lines: [String] = []
        for r in relationships where (r.fromTable == table && r.fromColumn == name) || (r.toTable == table && r.toColumn == name) {
            lines.append(lt("quan hệ \(r.fromTable)[\(r.fromColumn)] → \(r.toTable)[\(r.toColumn)]", "relationship \(r.fromTable)[\(r.fromColumn)] → \(r.toTable)[\(r.toColumn)]"))
        }
        for h in hierarchies where h.tableName == table && h.levels.contains(where: { $0.columnName == name }) {
            lines.append(h.levels.count == 1 ? lt("phân cấp \(h.name)", "hierarchy \(h.name)") : lt("cấp \(name) của phân cấp \(h.name)", "level \(name) of hierarchy \(h.name)"))
        }
        for c in columns where c.sortByColumnID == column.id && c.id != column.id {
            lines.append(lt("cách sắp xếp của cột \(c.name) (về sắp theo chính nó)", "the sort-by setting of column \(c.name) (reverts to sorting by itself)"))
        }
        return lines
    }

    /// Sửa công thức bảng tính toán: cột kết quả theo biểu thức mới; cột cùng tên giữ ID và thuộc tính (định dạng, tổng hợp nếu cùng
    /// kiểu), cột mới cấp ID mới, cột mất thì chặn nếu còn được dùng. Cột tính toán thêm trên bảng giữ nguyên (ứng dụng tính lại).
    /// [SUY ĐOÁN] chưa quan sát Desktop sửa công thức bảng tính toán; làm như thay dữ liệu bảng (VM-F9, mục 5).
    func updatingCalculatedTable(name: String, expression: String, columns list: [ColumnSignature]) throws -> ModelMetadata {
        guard let table = tables.first(where: { $0.name == name && $0.isUserTable }) else { throw ModelEditError(lt("Không có bảng \(name)", "There is no table \(name)")) }
        guard table.isCalculatedUserTable else { throw ModelEditError(lt("Bảng \(name) không phải bảng tính toán", "Table \(name) isn't a calculated table")) }
        try validateNewColumns(list.map { NewTableColumn(name: $0.name, dataType: $0.dataType) }, table: name)
        let body = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !body.contains("\0") else { throw ModelEditError(lt("Biểu thức của bảng \(name) trống hoặc chứa NUL", "The expression of table \(name) is empty or contains NUL")) }
        let own = columns.filter { $0.tableID == table.id }
        let results = own.filter { $0.kind == .calculatedTableColumn }
        let byName = Dictionary(results.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let kept = Set(list.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let removed = results.filter { !kept.contains($0.name.lowercased()) }
        let survivors = Set(columns.map(\.id)).subtracting(removed.map(\.id))
        let blockers = usesOfRemovedColumns(removed, in: name, survivingIDs: survivors)
        if !blockers.isEmpty { throw ModelEditError(lt("Không thể sửa bảng \(name): ", "Couldn't edit table \(name): ") + blockers.joined(separator: "; ")) }
        if let clash = list.first(where: { column in
            let key = column.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return own.contains { $0.kind == .calculated && $0.name.lowercased() == key } || measures.contains { $0.name.lowercased() == key }
        }) {
            throw ModelEditError(lt("Cột kết quả \(clash.name) trùng tên một cột tính toán hoặc measure của bảng \(name)", "The result column \(clash.name) has the same name as a calculated column or measure of table \(name)"))
        }
        var nextID = (columns.map(\.id).max() ?? 0) + 1
        let rebuilt = list.map { signature -> Column in
            let columnName = signature.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let previous = byName[columnName.lowercased()]
            let id = previous?.id ?? nextID
            if previous == nil { nextID += 1 }
            let sameType = previous?.dataType == signature.dataType
            return Column(id: id, tableID: table.id, tableName: name, name: columnName, kind: .calculatedTableColumn, dataType: signature.dataType,
                          isHidden: previous?.isHidden ?? false, expression: nil, formatString: sameType ? previous?.formatString : nil,
                          sortByColumnID: previous?.sortByColumnID.flatMap { survivors.contains($0) ? $0 : nil },
                          summarizeBy: sameType ? (previous?.summarizeBy ?? 2)
                              : Int(TableMetadataWriter.summarizeBy(signature.dataType, name: columnName, isRowNumber: false)),
                          dataCategory: previous?.dataCategory, displayFolder: previous?.displayFolder, isKey: previous?.isKey ?? false,
                          sourceColumn: signature.sourceColumn ?? "[\(columnName)]", description: previous?.description, lineageTag: previous?.lineageTag)
        }
        let others = own.filter { $0.kind != .calculatedTableColumn }
        var all = columns.filter { $0.tableID != table.id }
        let position = columns.firstIndex { $0.tableID == table.id }.map { min($0, all.count) } ?? all.count
        all.insert(contentsOf: others.filter { $0.kind == .rowNumber } + rebuilt + others.filter { $0.kind != .rowNumber }, at: position)
        var expressions = calculatedTableExpressions
        expressions[name] = body
        return ModelMetadata(copying: self, columns: all, storage: storage.filter { $0.tableName != name }, calculatedTableExpressions: expressions)
    }

    /// Chỉ mục phải dựng lại khi dữ liệu cột đổi: quan hệ (`R$`), phân cấp (`U$`), cột khác sắp xếp theo cột này.
    public func indexUses(of column: Column) -> [String] {
        var uses: [String] = []
        let rels = relationships.filter {
            ($0.fromTable == column.tableName && $0.fromColumn == column.name) || ($0.toTable == column.tableName && $0.toColumn == column.name)
        }.map(\.name)
        if !rels.isEmpty { uses.append(lt("cột nằm trong quan hệ \(rels.joined(separator: ", "))", "column is in relationships \(rels.joined(separator: ", "))")) }
        let hier = hierarchies.filter { $0.tableName == column.tableName && $0.levels.contains { $0.columnName == column.name } }.map(\.name)
        if !hier.isEmpty { uses.append(lt("cột là cấp của phân cấp \(hier.joined(separator: ", "))", "column is a level of hierarchies \(hier.joined(separator: ", "))")) }
        let sorted = columns.filter { $0.sortByColumnID == column.id && $0.id != column.id }.map(\.name)
        if !sorted.isEmpty { uses.append(lt("cột \(sorted.joined(separator: ", ")) sắp xếp theo cột này", "columns \(sorted.joined(separator: ", ")) sort by this column")) }
        return uses
    }

    // MARK: replaceTable

    func replacingTable(_ oldName: String, with new: NewTable) throws -> ModelMetadata {
        guard let tableIndex = tables.firstIndex(where: { $0.name == oldName && $0.isUserTable }) else {
            throw ModelEditError(lt("Không có bảng \(oldName)", "There is no table \(oldName)"))
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
            throw ModelEditError(lt("Không thể thay bảng \(oldName): ", "Couldn't replace table \(oldName): ") + blockers.joined(separator: "; "))
        }
        if let clash = new.columns.first(where: { column in
            measures.contains { $0.tableName == oldName && $0.name.lowercased() == column.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        }) {
            throw ModelEditError(lt("Cột \(clash.name) trùng tên một measure của bảng \(oldName)", "Column \(clash.name) has the same name as a measure of table \(oldName)"))
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
                                      description: old.description, lineageTag: old.lineageTag, dataCategory: old.dataCategory,
                                isCalculatedUserTable: old.isCalculatedUserTable)
        let renamed = name != oldName
        let newRelationships = !renamed ? relationships : relationships.map {
            Relationship(name: $0.name, fromTable: $0.fromTable == oldName ? name : $0.fromTable, fromColumn: $0.fromColumn,
                         toTable: $0.toTable == oldName ? name : $0.toTable, toColumn: $0.toColumn, isActive: $0.isActive,
                         cardinality: $0.cardinality, crossFilteringBehavior: $0.crossFilteringBehavior,
                         joinOnDateBehavior: $0.joinOnDateBehavior)
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
        // Bảng ngày tự động (SystemFlags 2, không phải bảng người dùng) cũng xoá được, sau khi đã bỏ variation và quan hệ của nó (T031).
        guard let table = tables.first(where: { $0.name == name && ($0.isUserTable || $0.systemFlags == 2) }) else {
            throw ModelEditError(lt("Không có bảng \(name)", "There is no table \(name)"))
        }
        var blockers: [String] = []
        let related = (relationships + dateTableRelationships).filter { $0.fromTable == name || $0.toTable == name }.map(\.name)
        if !related.isEmpty { blockers.append(lt("còn quan hệ \(related.joined(separator: ", "))", "relationships remain: \(related.joined(separator: ", "))")) }
        let hosted = measures.filter { $0.tableName == name }.map(\.name)
        if !hosted.isEmpty { blockers.append(lt("còn chứa measure \(hosted.joined(separator: ", "))", "still contains measures \(hosted.joined(separator: ", "))")) }
        let users = measures.filter { $0.tableName != name && Self.mentionsTable($0.expression, name) }.map(\.name)
        if !users.isEmpty { blockers.append(lt("measure \(users.joined(separator: ", ")) đang dùng bảng", "measures \(users.joined(separator: ", ")) use the table")) }
        // Cột tính toán và bảng tính toán ở bảng khác nhắc tới bảng này (T098, FR-004).
        let calculated = columns.filter { $0.tableName != name && $0.kind == .calculated && Self.mentionsTable($0.expression ?? "", name) }
            .map { "\($0.tableName)[\($0.name)]" }
        if !calculated.isEmpty { blockers.append(lt("cột tính toán \(calculated.joined(separator: ", ")) đang dùng bảng", "calculated columns \(calculated.joined(separator: ", ")) use the table")) }
        let calculatedTables = calculatedTableExpressions.filter { $0.key != name && Self.mentionsTable($0.value, name) }.keys.sorted()
        if !calculatedTables.isEmpty { blockers.append(lt("bảng tính toán \(calculatedTables.joined(separator: ", ")) đang dùng bảng", "calculated tables \(calculatedTables.joined(separator: ", ")) use the table")) }
        if !blockers.isEmpty { throw ModelEditError(lt("Không thể xoá bảng \(name): ", "Couldn't delete table \(name): ") + blockers.joined(separator: "; ")) }
        var queries = partitionQueries, expressions = calculatedTableExpressions
        queries[name] = nil
        expressions[name] = nil
        return ModelMetadata(copying: self, columns: columns.filter { $0.tableID != table.id },
                             tables: tables.filter { $0.id != table.id },
                             hierarchies: hierarchies.filter { $0.tableName != name },
                             storage: storage.filter { $0.tableName != name }, partitionQueries: queries,
                             calculatedTableExpressions: expressions)
    }

    // MARK: Kiểm tra

    /// Tên bảng đã cắt khoảng trắng: không rỗng, không NUL, không trùng bảng hay measure nào (không phân biệt hoa thường).
    private func validatedTableName(_ raw: String, ignoring old: String?) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ModelEditError(lt("Tên bảng không được để trống", "The table name can't be empty")) }
        guard !name.contains("\0") else { throw ModelEditError(lt("Tên bảng chứa ký tự NUL", "The table name contains a NUL character")) }
        let key = name.lowercased()
        if tables.contains(where: { $0.name.lowercased() == key && $0.name != old }) {
            throw ModelEditError(lt("Tên bảng \(name) trùng một bảng đã có (không phân biệt hoa thường)", "The table name \(name) matches an existing table (case-insensitive)"))
        }
        if measures.contains(where: { $0.name.lowercased() == key }) {
            throw ModelEditError(lt("Tên bảng \(name) trùng tên một measure", "The table name \(name) matches a measure name"))
        }
        return name
    }

    private func validateNewColumns(_ list: [NewTableColumn], table: String) throws {
        guard !list.isEmpty else { throw ModelEditError(lt("Bảng \(table) cần có ít nhất một cột", "Table \(table) needs at least one column")) }
        var seen: [String: String] = [:]
        for column in list {
            let name = column.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw ModelEditError(lt("Tên cột không được để trống (bảng \(table))", "A column name can't be empty (table \(table))")) }
            guard !name.contains("\0") else { throw ModelEditError(lt("Tên cột \(name) chứa ký tự NUL (bảng \(table))", "The column name \(name) contains a NUL character (table \(table))")) }
            if let first = seen[name.lowercased()] {
                throw ModelEditError(lt("Bảng \(table) có hai cột tên \(first) (không phân biệt hoa thường)", "Table \(table) has two columns named \(first) (case-insensitive)"))
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
            if !rels.isEmpty { uses.append(lt("quan hệ \(rels.joined(separator: ", "))", "relationships \(rels.joined(separator: ", "))")) }
            let hier = hierarchies.filter { $0.tableName == table && $0.levels.contains { $0.columnName == column.name } }.map(\.name)
            if !hier.isEmpty { uses.append(lt("phân cấp \(hier.joined(separator: ", "))", "hierarchies \(hier.joined(separator: ", "))")) }
            let sorted = columns.filter { $0.sortByColumnID == column.id && survivingIDs.contains($0.id) }.map(\.name)
            if !sorted.isEmpty { uses.append(lt("cột sắp xếp theo: \(sorted.joined(separator: ", "))", "columns sorted by: \(sorted.joined(separator: ", "))")) }
            let measureUses = measures.filter { Self.mentionsColumn($0.expression, table: table, column: column.name) }.map(\.name)
            if !measureUses.isEmpty { uses.append(lt("measure \(measureUses.joined(separator: ", "))", "measures \(measureUses.joined(separator: ", "))")) }
            let calculated = columns.filter { $0.expression.map { Self.mentionsColumn($0, table: table, column: column.name) } ?? false }.map(\.name)
            if !calculated.isEmpty { uses.append(lt("cột tính toán \(calculated.joined(separator: ", "))", "calculated columns \(calculated.joined(separator: ", "))")) }
            if !uses.isEmpty { lines.append(lt("cột \(column.name) đang được dùng bởi ", "column \(column.name) is used by ") + uses.joined(separator: lt(" và ", " and "))) }
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
