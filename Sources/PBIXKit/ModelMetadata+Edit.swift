import Foundation

extension ModelMetadata {
    /// Bản sao với các danh sách đã sửa; mọi trường khác giữ nguyên.
    init(copying other: ModelMetadata, columns: [Column]? = nil, measures: [Measure]? = nil,
         relationships: [Relationship]? = nil, tables: [Table]? = nil, hierarchies: [Hierarchy]? = nil,
         storage: [ColumnStorage]? = nil, partitionQueries: [String: String]? = nil,
         expressions: [String]? = nil, expressionBodies: [String: String]? = nil,
         calculatedTableExpressions: [String: String]? = nil, modelAnnotations: [String: String]? = nil,
         dateTableRelationships: [Relationship]? = nil, variations: [Variation]? = nil,
         roleDefinitions: [RoleDefinition]? = nil) {
        self.tables = tables ?? other.tables
        self.columns = columns ?? other.columns
        self.measures = measures ?? other.measures
        self.hierarchies = hierarchies ?? other.hierarchies
        self.relationships = relationships ?? other.relationships
        self.storage = storage ?? other.storage
        self.partitionQueries = partitionQueries ?? other.partitionQueries
        self.calculatedTableExpressions = calculatedTableExpressions ?? other.calculatedTableExpressions
        let effectiveRoles = roleDefinitions ?? other.roleDefinitions
        self.roleDefinitions = effectiveRoles
        roles = effectiveRoles.map(\.name)
        perspectives = other.perspectives
        cultures = other.cultures
        self.expressions = expressions ?? other.expressions
        self.expressionBodies = expressionBodies ?? other.expressionBodies
        calculationGroups = other.calculationGroups
        functions = other.functions
        culture = other.culture
        self.modelAnnotations = modelAnnotations ?? other.modelAnnotations
        discourageImplicitMeasures = other.discourageImplicitMeasures
        self.dateTableRelationships = dateTableRelationships ?? other.dateTableRelationships
        self.variations = variations ?? other.variations
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
                throw ModelEditError(lt("Biểu thức của measure không được để trống", "The measure expression can't be empty"))
            }
            guard !new.expression.contains("\0") else { throw ModelEditError(lt("Biểu thức chứa ký tự NUL", "The expression contains a NUL character")) }
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
                throw ModelEditError(lt("Không có measure \(table)[\(name)]", "There is no measure \(table)[\(name)]"))
            }
            let old = measures[index]
            var newName = old.name
            if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), renamed != old.name {
                try validateMeasureName(renamed, in: table, ignoring: old.name)
                newName = renamed
            }
            if let expression = patch.expression {
                guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ModelEditError(lt("Biểu thức của measure không được để trống", "The measure expression can't be empty"))
                }
                guard !expression.contains("\0") else { throw ModelEditError(lt("Biểu thức chứa ký tự NUL", "The expression contains a NUL character")) }
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
                throw ModelEditError(lt("Không có measure \(table)[\(name)]", "There is no measure \(table)[\(name)]"))
            }
            return ModelMetadata(copying: self, measures: measures.filter { !($0.tableName == table && $0.name == name) })

        case .updateRelationship(let name, let patch):
            guard let index = relationships.firstIndex(where: { $0.name == name }) else {
                throw ModelEditError(lt("Không có quan hệ \(name)", "There is no relationship \(name)"))
            }
            if let behavior = patch.crossFilteringBehavior, behavior != 1 && behavior != 2 {
                throw ModelEditError(lt("Hướng lọc chéo phải là 1 (một chiều) hoặc 2 (hai chiều)", "The cross-filter direction must be 1 (single) or 2 (both)"))
            }
            let old = relationships[index]
            // Desktop không cho hai quan hệ hoạt động giữa cùng hai bảng (quan hệ mới thành không hoạt động).
            if patch.isActive == true, !old.isActive,
               relationships.contains(where: {
                   $0.isActive && $0.name != old.name
                       && Set([$0.fromTable, $0.toTable]) == Set([old.fromTable, old.toTable])
               }) {
                throw ModelEditError(lt("Đã có quan hệ hoạt động giữa \(old.fromTable) và \(old.toTable); tắt quan hệ đó trước khi bật quan hệ này", "There is already an active relationship between \(old.fromTable) and \(old.toTable); deactivate it before activating this one"))
            }
            var copy = relationships
            copy[index] = Relationship(name: old.name, fromTable: old.fromTable, fromColumn: old.fromColumn,
                                       toTable: old.toTable, toColumn: old.toColumn,
                                       isActive: patch.isActive ?? old.isActive, cardinality: old.cardinality,
                                       crossFilteringBehavior: patch.crossFilteringBehavior ?? old.crossFilteringBehavior,
                                       joinOnDateBehavior: old.joinOnDateBehavior)
            return ModelMetadata(copying: self, relationships: copy)

        case .updateTable(let name, let patch):
            guard let index = tables.firstIndex(where: { $0.name == name && $0.isUserTable }) else { throw ModelEditError(lt("Không có bảng \(name)", "There is no table \(name)")) }
            let old = tables[index]
            var newName = old.name
            if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), renamed != old.name {
                guard !renamed.isEmpty, !renamed.contains("\0") else { throw ModelEditError(lt("Tên bảng không hợp lệ", "Invalid table name")) }
                let key = renamed.lowercased()
                if tables.contains(where: { $0.id != old.id && $0.name.lowercased() == key }) {
                    throw ModelEditError(lt("Mô hình đã có bảng tên \(renamed)", "The model already has a table named \(renamed)"))
                }
                newName = renamed
            }
            var copy = tables
            // Như bộ đọc: bảng tính toán có cờ hay chú thích của Auto date/time không còn là bảng người dùng.
            let autoDate = patch.isPrivate == true || patch.showAsVariationsOnly == true
                || ["__PBI_LocalDateTable", "__PBI_TemplateDateTable"].contains { if case .set = patch.annotations[$0] { true } else { false } }
            copy[index] = Table(id: old.id, name: newName, isHidden: patch.isHidden ?? old.isHidden, systemFlags: old.systemFlags,
                                description: old.description, lineageTag: old.lineageTag,
                                dataCategory: patch.dataCategory.resolved(old.dataCategory),
                                isCalculatedUserTable: old.isCalculatedUserTable && !autoDate)
            if newName == old.name {
                return ModelMetadata(copying: self, tables: copy)
            }
            let updatedColumns = columns.map { c in
                c.tableName == old.name
                    ? Column(id: c.id, tableID: c.tableID, tableName: newName, name: c.name, kind: c.kind, dataType: c.dataType,
                             isHidden: c.isHidden, expression: c.expression, formatString: c.formatString,
                             sortByColumnID: c.sortByColumnID, summarizeBy: c.summarizeBy, dataCategory: c.dataCategory,
                             displayFolder: c.displayFolder, isKey: c.isKey, sourceColumn: c.sourceColumn,
                             description: c.description, lineageTag: c.lineageTag)
                    : c
            }
            let updatedMeasures = measures.map { m in
                m.tableName == old.name
                    ? Measure(tableName: newName, name: m.name, expression: m.expression, formatString: m.formatString,
                              displayFolder: m.displayFolder, isHidden: m.isHidden, description: m.description,
                              lineageTag: m.lineageTag, dataType: m.dataType, state: m.state,
                              formatStringDefinition: m.formatStringDefinition)
                    : m
            }
            let updatedRels = relationships.map { r in
                (r.fromTable == old.name || r.toTable == old.name)
                    ? Relationship(name: r.name, fromTable: r.fromTable == old.name ? newName : r.fromTable, fromColumn: r.fromColumn,
                                   toTable: r.toTable == old.name ? newName : r.toTable, toColumn: r.toColumn,
                                   isActive: r.isActive, cardinality: r.cardinality,
                                   crossFilteringBehavior: r.crossFilteringBehavior, joinOnDateBehavior: r.joinOnDateBehavior)
                    : r
            }
            let updatedDateRels = dateTableRelationships.map { r in
                (r.fromTable == old.name || r.toTable == old.name)
                    ? Relationship(name: r.name, fromTable: r.fromTable == old.name ? newName : r.fromTable, fromColumn: r.fromColumn,
                                   toTable: r.toTable == old.name ? newName : r.toTable, toColumn: r.toColumn,
                                   isActive: r.isActive, cardinality: r.cardinality,
                                   crossFilteringBehavior: r.crossFilteringBehavior, joinOnDateBehavior: r.joinOnDateBehavior)
                    : r
            }
            let updatedHierarchies = hierarchies.map { h in
                h.tableName == old.name
                    ? Hierarchy(tableName: newName, name: h.name, isHidden: h.isHidden, displayFolder: h.displayFolder,
                                lineageTag: h.lineageTag, levels: h.levels)
                    : h
            }
            let updatedVariations = variations.map { v in
                v.table == old.name
                    ? Variation(table: newName, column: v.column, name: v.name, relationship: v.relationship,
                                hierarchy: v.hierarchy, isDefault: v.isDefault)
                    : v
            }
            var updatedPartitions = partitionQueries
            if let pq = updatedPartitions.removeValue(forKey: old.name) { updatedPartitions[newName] = pq }
            var updatedCalcExprs = calculatedTableExpressions
            if let ce = updatedCalcExprs.removeValue(forKey: old.name) { updatedCalcExprs[newName] = ce }
            return ModelMetadata(copying: self, columns: updatedColumns, measures: updatedMeasures,
                                 relationships: updatedRels, tables: copy, hierarchies: updatedHierarchies,
                                 partitionQueries: updatedPartitions, calculatedTableExpressions: updatedCalcExprs,
                                 dateTableRelationships: updatedDateRels, variations: updatedVariations)

        case .addRelationship(let new):
            try validate(new)
            let cardinality = (new.fromMany ? "M" : "1") + ":" + (new.toMany ? "M" : "1")
            let added = Relationship(name: new.name, fromTable: new.fromTable, fromColumn: new.fromColumn, toTable: new.toTable,
                                     toColumn: new.toColumn, isActive: new.isActive, cardinality: cardinality,
                                     crossFilteringBehavior: new.crossFilteringBehavior, joinOnDateBehavior: new.joinOnDateBehavior)
            // Như bộ đọc: quan hệ tới bảng ngày tự động (không phải bảng người dùng, SystemFlags 2) nằm riêng.
            if isAutoDateTable(new.fromTable) || isAutoDateTable(new.toTable) {
                return ModelMetadata(copying: self, dateTableRelationships: dateTableRelationships + [added])
            }
            return ModelMetadata(copying: self, relationships: relationships + [added])

        case .addTable(let new): return try addingTable(new)
        case .replaceTable(let name, let new): return try replacingTable(name, with: new)
        case .dropTable(let name): return try droppingTable(name)
        case .setQuery(let name, let expression):
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelEditError(lt("Truy vấn không nạp cần tên và biểu thức M", "A non-loaded query needs a name and an M expression")) }
            if tables.contains(where: { $0.isUserTable && $0.name.caseInsensitiveCompare(key) == .orderedSame }) {
                throw ModelEditError(lt("Truy vấn không nạp «\(key)» trùng tên một bảng trong mô hình", "The non-loaded query «\(key)» has the same name as a table in the model"))
            }
            var bodies = expressionBodies
            bodies[key] = expression
            return ModelMetadata(copying: self, expressions: expressions.contains(key) ? expressions : expressions + [key], expressionBodies: bodies)
        case .dropQuery(let name):
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
            var bodies = expressionBodies
            bodies[key] = nil
            return ModelMetadata(copying: self, expressions: expressions.filter { $0 != key }, expressionBodies: bodies)

        case .addCalculatedColumn(let table, let name, let expression, let dataType):
            return try addingCalculatedColumn(table: table, name: name, expression: expression, dataType: dataType)
        case .addCalculatedTable(let name, let expression, let columns):
            return try addingCalculatedTable(name: name, expression: expression, columns: columns)
        case .updateCalculatedColumn(let table, let name, let expression, let dataType):
            return try updatingCalculatedColumn(table: table, name: name, expression: expression, dataType: dataType)
        case .deleteCalculatedColumn(let table, let name):
            return try deletingCalculatedColumn(table: table, name: name)
        case .updateCalculatedTable(let name, let expression, let columns):
            return try updatingCalculatedTable(name: name, expression: expression, columns: columns)
        case .addHierarchy(let new):
            guard let table = tables.first(where: { $0.name.caseInsensitiveCompare(new.table) == .orderedSame }) else {
                throw ModelEditError(lt("Không có bảng \(new.table)", "There is no table \(new.table)"))
            }
            guard !new.levels.isEmpty, !new.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ModelEditError(lt("Phân cấp cần tên và ít nhất một cấp", "A hierarchy needs a name and at least one level")) }
            for level in new.levels where !columns.contains(where: { $0.tableName == table.name && $0.name == level.column }) {
                throw ModelEditError(lt("Không có cột \(table.name)[\(level.column)]", "There is no column \(table.name)[\(level.column)]"))
            }
            if hierarchies.contains(where: { $0.tableName == table.name && $0.name.caseInsensitiveCompare(new.name) == .orderedSame }) {
                throw ModelEditError(lt("Bảng \(table.name) đã có phân cấp \(new.name)", "Table \(table.name) already has a hierarchy \(new.name)"))
            }
            // Như bộ đọc: chỉ phân cấp của bảng thường (SystemFlags 0) nằm trong `hierarchies`.
            guard table.systemFlags == 0 else { return self }
            let added = Hierarchy(tableName: table.name, name: new.name, isHidden: new.isHidden, displayFolder: nil, lineageTag: nil,
                                  levels: new.levels.map { Hierarchy.Level(name: $0.name, columnName: $0.column, lineageTag: nil) })
            return ModelMetadata(copying: self, hierarchies: hierarchies + [added])
        case .dropHierarchy(let table, let name):
            guard let owner = tables.first(where: { $0.name.caseInsensitiveCompare(table) == .orderedSame }) else { throw ModelEditError(lt("Không có bảng \(table)", "There is no table \(table)")) }
            guard owner.systemFlags == 0 else { return self }
            guard hierarchies.contains(where: { $0.tableName == owner.name && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw ModelEditError(lt("Bảng \(table) không có phân cấp \(name)", "Table \(table) has no hierarchy \(name)"))
            }
            return ModelMetadata(copying: self, hierarchies: hierarchies.filter { !($0.tableName == owner.name && $0.name.caseInsensitiveCompare(name) == .orderedSame) })
        case .addVariation(let table, let column, let relationship, let hierarchy):
            guard columns.contains(where: { $0.tableName == table && $0.name == column }) else { throw ModelEditError(lt("Không có cột \(table)[\(column)]", "There is no column \(table)[\(column)]")) }
            guard !variations.contains(where: { $0.table == table && $0.column == column }) else {
                throw ModelEditError(lt("Cột \(table)[\(column)] đã có variation", "Column \(table)[\(column)] already has a variation"))
            }
            guard let rel = (relationships + dateTableRelationships).first(where: { $0.name == relationship }) else {
                throw ModelEditError(lt("Không có quan hệ \(relationship)", "There is no relationship \(relationship)"))
            }
            guard rel.fromTable == table, rel.fromColumn == column, rel.toTable == hierarchy.table else {
                throw ModelEditError(lt("Quan hệ \(relationship) không nối \(table)[\(column)] với bảng \(hierarchy.table)", "Relationship \(relationship) doesn't join \(table)[\(column)] to table \(hierarchy.table)"))
            }
            let added = Variation(table: table, column: column, name: "Variation", relationship: relationship, hierarchy: hierarchy, isDefault: true)
            return ModelMetadata(copying: self, variations: variations + [added])
        case .dropVariation(let table, let column):
            guard variations.contains(where: { $0.table == table && $0.column == column }) else {
                throw ModelEditError(lt("Cột \(table)[\(column)] không có variation", "Column \(table)[\(column)] has no variation"))
            }
            return ModelMetadata(copying: self, variations: variations.filter { !($0.table == table && $0.column == column) })
        case .setModelAnnotation(let name, let value):
            var annotations = modelAnnotations
            annotations[name] = value
            return ModelMetadata(copying: self, modelAnnotations: annotations)

        case .upsertRole(let previousName, let role):
            let trimmed = role.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("\0") else { throw ModelEditError(lt("Tên vai trò không hợp lệ", "Invalid role name")) }
            for tp in role.tablePermissions {
                guard tables.contains(where: { $0.isUserTable && $0.name.caseInsensitiveCompare(tp.tableName) == .orderedSame }) else {
                    throw ModelEditError(lt("Không có bảng \(tp.tableName) cho quy tắc RLS", "There is no table \(tp.tableName) for the RLS rule"))
                }
            }
            let normalized = RoleDefinition(name: trimmed, description: role.description, modelPermission: role.modelPermission,
                                            tablePermissions: role.tablePermissions.filter { !$0.filterExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            var updated = roleDefinitions
            let matchName = previousName ?? trimmed
            if let clash = updated.firstIndex(where: {
                $0.name.caseInsensitiveCompare(trimmed) == .orderedSame && $0.name.caseInsensitiveCompare(matchName) != .orderedSame
            }) {
                throw ModelEditError(lt("Mô hình đã có vai trò tên \(updated[clash].name)", "The model already has a role named \(updated[clash].name)"))
            }
            if let existing = updated.firstIndex(where: { $0.name.caseInsensitiveCompare(matchName) == .orderedSame }) {
                updated[existing] = normalized
            } else {
                updated.append(normalized)
            }
            return ModelMetadata(copying: self, roleDefinitions: updated)

        case .deleteRole(let name):
            guard roleDefinitions.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw ModelEditError(lt("Không có vai trò \(name)", "There is no role \(name)"))
            }
            let updated = roleDefinitions.filter { $0.name.caseInsensitiveCompare(name) != .orderedSame }
            return ModelMetadata(copying: self, roleDefinitions: updated)

        case .deleteRelationship(let name):
            guard relationships.contains(where: { $0.name == name }) || dateTableRelationships.contains(where: { $0.name == name }) else {
                throw ModelEditError(lt("Không có quan hệ \(name)", "There is no relationship \(name)"))
            }
            if variations.contains(where: { $0.relationship == name }) { throw ModelEditError(lt("Quan hệ \(name) đang được một variation dùng", "Relationship \(name) is used by a variation")) }
            return ModelMetadata(copying: self, relationships: relationships.filter { $0.name != name },
                                 dateTableRelationships: dateTableRelationships.filter { $0.name != name })

        case .updateColumn(let table, let name, let patch):
            guard let index = columns.firstIndex(where: { $0.tableName == table && $0.name == name }) else {
                throw ModelEditError(lt("Không có cột \(table)[\(name)]", "There is no column \(table)[\(name)]"))
            }
            let old = columns[index]
            var newName = old.name
            if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), renamed != old.name {
                try validateColumnRename(old, to: renamed, allowUsed: patch.cascade)
                newName = renamed
            }
            var sortID = old.sortByColumnID
            switch patch.sortBy {
            case .none: break
            case .some(.clear): sortID = nil
            case .some(.set(let target)):
                guard let sort = columns.first(where: { $0.tableName == table && $0.name == target }) else {
                    throw ModelEditError(lt("Không có cột \(table)[\(target)] để sắp xếp theo", "There is no column \(table)[\(target)] to sort by"))
                }
                guard sort.id != old.id else { throw ModelEditError(lt("Cột không thể sắp xếp theo chính nó", "A column can't be sorted by itself")) }
                sortID = sort.id
            }
            if let summarize = patch.summarizeBy, !(1...8).contains(summarize) {
                throw ModelEditError(lt("Kiểu tổng hợp mặc định không hợp lệ (\(summarize))", "Invalid default summarization (\(summarize))"))
            }
            var copy = columns
            copy[index] = Column(
                id: old.id, tableID: old.tableID, tableName: old.tableName, name: newName, kind: old.kind,
                dataType: old.dataType, isHidden: patch.isHidden ?? old.isHidden, expression: old.expression,
                formatString: patch.formatString.resolved(old.formatString), sortByColumnID: sortID,
                summarizeBy: patch.summarizeBy ?? old.summarizeBy, dataCategory: patch.dataCategory.resolved(old.dataCategory),
                displayFolder: patch.displayFolder.resolved(old.displayFolder), isKey: patch.isKey ?? old.isKey,
                sourceColumn: old.sourceColumn, description: patch.description.resolved(old.description),
                lineageTag: old.lineageTag)
            if newName == old.name {
                return ModelMetadata(copying: self, columns: copy)
            }
            let updatedRels = relationships.map { r in
                (r.fromTable == table && r.fromColumn == old.name) || (r.toTable == table && r.toColumn == old.name)
                    ? Relationship(name: r.name, fromTable: r.fromTable,
                                   fromColumn: (r.fromTable == table && r.fromColumn == old.name) ? newName : r.fromColumn,
                                   toTable: r.toTable,
                                   toColumn: (r.toTable == table && r.toColumn == old.name) ? newName : r.toColumn,
                                   isActive: r.isActive, cardinality: r.cardinality,
                                   crossFilteringBehavior: r.crossFilteringBehavior, joinOnDateBehavior: r.joinOnDateBehavior)
                    : r
            }
            let updatedDateRels = dateTableRelationships.map { r in
                (r.fromTable == table && r.fromColumn == old.name) || (r.toTable == table && r.toColumn == old.name)
                    ? Relationship(name: r.name, fromTable: r.fromTable,
                                   fromColumn: (r.fromTable == table && r.fromColumn == old.name) ? newName : r.fromColumn,
                                   toTable: r.toTable,
                                   toColumn: (r.toTable == table && r.toColumn == old.name) ? newName : r.toColumn,
                                   isActive: r.isActive, cardinality: r.cardinality,
                                   crossFilteringBehavior: r.crossFilteringBehavior, joinOnDateBehavior: r.joinOnDateBehavior)
                    : r
            }
            let updatedHierarchies = hierarchies.map { h in
                h.tableName == table
                    ? Hierarchy(tableName: h.tableName, name: h.name, isHidden: h.isHidden, displayFolder: h.displayFolder,
                                lineageTag: h.lineageTag,
                                levels: h.levels.map { l in
                                    l.columnName == old.name ? Hierarchy.Level(name: l.name, columnName: newName, lineageTag: l.lineageTag) : l
                                })
                    : h
            }
            let updatedVariations = variations.map { v in
                (v.table == table && v.column == old.name)
                    ? Variation(table: v.table, column: newName, name: v.name, relationship: v.relationship,
                                hierarchy: v.hierarchy, isDefault: v.isDefault)
                    : v
            }
            return ModelMetadata(copying: self, columns: copy, relationships: updatedRels,
                                 hierarchies: updatedHierarchies, dateTableRelationships: updatedDateRels,
                                 variations: updatedVariations)
        }
    }

    /// Bảng ngày tự động của Auto date/time: bảng tính toán (SystemFlags 2) không còn là bảng người dùng.
    private func isAutoDateTable(_ name: String) -> Bool {
        tables.contains { $0.name == name && $0.systemFlags == 2 && !$0.isCalculatedUserTable }
    }

    /// Quan hệ mới: hai cột có thật, cùng kiểu, khác bảng, chưa có quan hệ nào nối đúng hai cột này, và không thêm quan hệ hoạt động
    /// thứ hai giữa hai bảng (Desktop để quan hệ mới thành không hoạt động).
    private func validate(_ new: NewRelationship) throws {
        guard !new.name.isEmpty else { throw ModelEditError(lt("Quan hệ cần có tên", "A relationship needs a name")) }
        guard !relationships.contains(where: { $0.name == new.name }) else { throw ModelEditError(lt("Đã có quan hệ tên \(new.name)", "A relationship named \(new.name) already exists")) }
        guard new.fromTable != new.toTable else { throw ModelEditError(lt("Hai đầu quan hệ phải ở hai bảng khác nhau", "The two ends of a relationship must be in different tables")) }
        guard new.crossFilteringBehavior == 1 || new.crossFilteringBehavior == 2 else { throw ModelEditError(lt("Hướng lọc chéo phải là 1 hoặc 2", "The cross-filter direction must be 1 or 2")) }
        guard let from = columns.first(where: { $0.tableName == new.fromTable && $0.name == new.fromColumn && $0.kind != .rowNumber }),
              let to = columns.first(where: { $0.tableName == new.toTable && $0.name == new.toColumn && $0.kind != .rowNumber }) else {
            throw ModelEditError(lt("Không có cột \(new.fromTable)[\(new.fromColumn)] hoặc \(new.toTable)[\(new.toColumn)]", "There is no column \(new.fromTable)[\(new.fromColumn)] or \(new.toTable)[\(new.toColumn)]"))
        }
        guard from.dataType == to.dataType else { throw ModelEditError(lt("Hai cột phải cùng kiểu dữ liệu", "The two columns must have the same data type")) }
        guard !(new.fromMany && new.toMany) else { throw ModelEditError(lt("Quan hệ nhiều-nhiều chưa được hỗ trợ", "Many-to-many relationships aren't supported yet")) }
        let same = relationships.contains {
            Set(["\($0.fromTable)[\($0.fromColumn)]", "\($0.toTable)[\($0.toColumn)]"]) ==
                Set(["\(new.fromTable)[\(new.fromColumn)]", "\(new.toTable)[\(new.toColumn)]"])
        }
        guard !same else { throw ModelEditError(lt("Đã có quan hệ nối hai cột này", "A relationship between these two columns already exists")) }
        if new.isActive, relationships.contains(where: {
            $0.isActive && Set([$0.fromTable, $0.toTable]) == Set([new.fromTable, new.toTable])
        }) {
            throw ModelEditError(lt("Đã có quan hệ hoạt động giữa \(new.fromTable) và \(new.toTable); quan hệ mới phải ở trạng thái không hoạt động", "There is already an active relationship between \(new.fromTable) and \(new.toTable); the new relationship must be inactive"))
        }
    }

    /// Đổi tên cột: tên không rỗng, không trùng cột hoặc measure cùng bảng; khi không cascade (`allowUsed == false`), từ chối cột trong quan hệ/phân cấp.
    private func validateColumnRename(_ column: Column, to name: String, allowUsed: Bool = false) throws {
        guard !name.isEmpty else { throw ModelEditError(lt("Tên cột không được để trống", "The column name can't be empty")) }
        guard !name.contains("\0") else { throw ModelEditError(lt("Tên cột chứa ký tự NUL", "The column name contains a NUL character")) }
        let key = name.lowercased()
        if columns.contains(where: { $0.tableName == column.tableName && $0.id != column.id && $0.name.lowercased() == key })
            || measures.contains(where: { $0.tableName == column.tableName && $0.name.lowercased() == key }) {
            throw ModelEditError(lt("Bảng \(column.tableName) đã có cột hoặc measure tên \(name)", "Table \(column.tableName) already has a column or measure named \(name)"))
        }
        guard !allowUsed else { return }
        if relationships.contains(where: {
            ($0.fromTable == column.tableName && $0.fromColumn == column.name) || ($0.toTable == column.tableName && $0.toColumn == column.name)
        }) {
            throw ModelEditError(lt("Cột \(column.tableName)[\(column.name)] là đầu của một quan hệ", "Column \(column.tableName)[\(column.name)] is an end of a relationship"))
        }
        if hierarchies.contains(where: { $0.tableName == column.tableName && $0.levels.contains { $0.columnName == column.name } }) {
            throw ModelEditError(lt("Cột \(column.tableName)[\(column.name)] nằm trong một phân cấp", "Column \(column.tableName)[\(column.name)] is in a hierarchy"))
        }
    }

    /// Tên measure phải không rỗng, không NUL, bảng có thật, và không trùng measure, cột cùng bảng hoặc tên bảng nào
    /// (không phân biệt hoa thường). `ignoring` là tên cũ khi đổi tên.
    private func validateMeasureName(_ name: String, in table: String, ignoring old: String?) throws {
        guard !name.isEmpty else { throw ModelEditError(lt("Tên measure không được để trống", "The measure name can't be empty")) }
        guard !name.contains("\0") else { throw ModelEditError(lt("Tên measure chứa ký tự NUL", "The measure name contains a NUL character")) }
        guard userTables.contains(where: { $0.name == table }) else { throw ModelEditError(lt("Không có bảng \(table)", "There is no table \(table)")) }
        let key = name.lowercased()
        if measures.contains(where: { $0.tableName == table && $0.name.lowercased() == key && $0.name != old }) {
            throw ModelEditError(lt("Bảng \(table) đã có measure tên \(name)", "Table \(table) already has a measure named \(name)"))
        }
        if columns.contains(where: { $0.tableName == table && $0.name.lowercased() == key }) {
            throw ModelEditError(lt("Bảng \(table) đã có cột tên \(name)", "Table \(table) already has a column named \(name)"))
        }
        if tables.contains(where: { $0.name.lowercased() == key }) {
            throw ModelEditError(lt("Tên \(name) trùng tên một bảng", "The name \(name) matches a table name"))
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
