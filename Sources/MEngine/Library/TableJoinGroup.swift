// Phase F: thư viện hàm M, nhóm Join, Group, Pivot (lead). Mỗi hàm: tên đầy đủ, tham số (tuỳ chọn đánh dấu isOptional), `observed`
// (true khi ngữ nghĩa đã đối chiếu golden Desktop, false = [SUY ĐOÁN]). Dùng trợ giúp ở Support.swift.
//
// Đối chiếu Desktop 2.159 (VM-F4, `docs/phase-f-evidence/vm-f4/QUAN-SAT.md`, probe M trên bảng nhỏ): khoá `null` khớp `null`, so khoá phân biệt
// hoa thường và khác kiểu thì không khớp, kiểu mặc định của `NestedJoin` là LeftOuter, `Table.Group` Global theo thứ tự xuất hiện đầu tiên,
// `Table.Pivot` sắp nhóm theo cột khoá tăng dần (null trước), trùng ô không có hàm tổng hợp là lỗi Ở Ô (không ném cả hàm),
// Unpivot bỏ ô null, `Table.Combine` hợp cột theo thứ tự thấy đầu tiên. Thứ tự dòng khớp của join do Desktop tự quyết (băm), BI Pro giữ thứ tự
// dòng trái; dòng không khớp xếp cuối (phải trước trái) như Desktop. Cột lẫn kiểu của `Table.Combine` chuyển thành text (Desktop nạp `any` thành `string`).

import ColumnStore
import Foundation

public enum JoinGroupLibrary {
    public static let functions: [MFunction] = [
        combine, join, nestedJoin, expandTableColumn, group, pivot, unpivot, unpivotOtherColumns, toRows,
    ]

    // MARK: - Trợ giúp

    /// Khoá so khớp của join/group: số so theo giá trị (nguyên = thực cùng giá trị), chuỗi phân biệt hoa thường, `null` khớp `null`.
    private enum Key: Hashable {
        case blank
        case number(Double)
        case text(String)
        case logical(Bool)
        case date(Double)

        init(_ value: StoredValue) {
            switch value {
            case .blank: self = .blank
            case .integer(let v): self = .number(Double(v))
            case .double(let v): self = .number(v)
            case .currency(let v): self = .number(Double(v) / 10_000)
            case .string(let v): self = .text(v)
            case .boolean(let v): self = .logical(v)
            case .dateTime(let v): self = .date(v)
            }
        }
    }

    private static func columnIndices(_ table: TableData, _ value: MValue, function: String) throws -> [Int] {
        try TableRowsHelper.extractColumnNames(value, functionName: function).map { name in
            guard let index = table.index(ofColumn: name) else { throw MError.expression("\(function): không tìm thấy cột '\(name)'") }
            return index
        }
    }

    /// Khoá của từng dòng; ô lỗi ở cột khoá ném lỗi (M không so khớp giá trị lỗi).
    private static func keys(_ table: TableData, columns: [Int], function: String) throws -> [[Key]] {
        for column in columns {
            if let (row, message) = table.errorMask[column]?.min(by: { $0.key < $1.key }) {
                throw MError.expression("\(function): ô lỗi ở cột khoá '\(table.columns[column].name)' dòng \(row + 1): \(message)")
            }
        }
        return (0..<table.rowCount).map { row in columns.map { Key(table.value(row: row, column: $0)) } }
    }

    private static func mType(of column: TableColumn) -> MType { MType(column.data.type.mTypeKind, isNullable: true) }

    /// Dựng bảng từ giá trị theo cột. Giá trị `.error` thành ô trống kèm thông điệp trong `errorMask`.
    private static func assemble(names: [String], types: [MType?], columns: [[MValue]], nested: [Int: [TableData]] = [:]) throws -> TableData {
        var built: [TableColumn] = []
        var mask: [Int: [Int: String]] = [:]
        for (index, name) in names.enumerated() {
            var values = columns[index]
            for (row, value) in values.enumerated() {
                if case .error(let error) = value {
                    mask[index, default: [:]][row] = error.message
                    values[row] = .null
                }
            }
            built.append(TableColumn(name: name, data: try MTables.column(values, type: types[index], name: name)))
        }
        do {
            return try TableData(columns: built, errorMask: mask, nested: nested)
        } catch TableDataError.duplicateColumn(let name) {
            throw MError.expression("Tên cột trùng: \(name)")
        } catch TableDataError.emptyColumnName {
            throw MError.expression("Tên cột không được rỗng")
        }
    }

    private static func joinKind(_ value: MValue?, function: String, default fallback: Int) throws -> Int {
        guard let value else { return fallback }
        guard let n = MOperators.number(value), (0...5).contains(n), n == n.rounded() else {
            throw MError.expression("\(function): kiểu join không hợp lệ")
        }
        return Int(n)
    }

    /// `Table.ToRows(table)`: danh sách các hàng, mỗi hàng là danh sách giá trị (dùng trong probe Desktop).
    private static let toRows = MFunction(name: "Table.ToRows", parameters: [MParameter(name: "table")], observed: true) { args in
        let table = try args.table(0, "Table.ToRows")
        return .list((0..<table.rowCount).map { row in .list(table.columns.indices.map { MTables.cell(table, row: row, column: $0) }) })
    }

    // MARK: - Table.Combine

    /// `Table.Combine(tables, columns?)`: nối các bảng, cột hợp theo thứ tự xuất hiện đầu tiên, ô thiếu là `null`.
    private static let combine = MFunction(
        name: "Table.Combine", parameters: [MParameter(name: "tables"), MParameter(name: "columns", isOptional: true)], observed: true
    ) { args in
        let items = try args.list(0, "Table.Combine")
        var tables: [TableData] = []
        for item in items {
            switch item {
            case .table(let t): tables.append(t)
            case .error(let e): throw e
            case .null: continue
            default: throw MError.expression("Table.Combine: phần tử phải là bảng, nhận \(item.kindName)")
            }
        }
        var names: [String] = []
        var types: [String: MType] = [:]
        var conflicting = Set<String>()
        if let requested = args.optional(1) {
            names = try TableRowsHelper.extractColumnNames(requested, functionName: "Table.Combine")
        }
        let fixed = !names.isEmpty
        for table in tables {
            for column in table.columns {
                if !fixed, !names.contains(column.name) { names.append(column.name) }
                let t = mType(of: column)
                if let known = types[column.name] { if known.kind != t.kind { conflicting.insert(column.name) } } else { types[column.name] = t }
            }
        }
        var columns: [[MValue]] = names.map { _ in [] }
        for table in tables {
            for (slot, name) in names.enumerated() {
                if let index = table.index(ofColumn: name) {
                    columns[slot].append(contentsOf: (0..<table.rowCount).map { MTables.cell(table, row: $0, column: index) })
                } else {
                    columns[slot].append(contentsOf: Array(repeating: MValue.null, count: table.rowCount))
                }
            }
        }
        // Cột cùng tên khác kiểu: M cho kiểu `any` (xem trước Desktop giữ nguyên số/chữ lẫn nhau) nhưng Close & Apply nạp thành `string`
        // (VM-F8: giá trị 1 và "x" thành "1", "x"). TableData chưa có cột lẫn kiểu, nên BI Pro chuyển cột thành text ngay ở bước này
        // bằng `Text.From`; khác Desktop ở các bước sau Combine còn thao tác trên số thật (sắp xếp, so sánh).
        var finalTypes = names.map { types[$0] }
        for (slot, name) in names.enumerated() where conflicting.contains(name) {
            columns[slot] = try columns[slot].map { value in
                if case .error = value { return value }
                return try ValueText.textFrom(value)
            }
            finalTypes[slot] = MType(.text, isNullable: true)
        }
        return .table(try assemble(names: names, types: finalTypes, columns: columns))
    }

    // MARK: - Table.Join, Table.NestedJoin

    /// Kết quả khớp: cặp (dòng trái, dòng phải) theo thứ tự dòng trái rồi dòng phải; dòng không khớp có `nil` ở phía kia.
    /// `leftInPlace`: dòng trái không khớp đứng đúng vị trí của nó (NestedJoin, mỗi dòng trái một dòng kết quả); sai thì xếp cuối (Table.Join).
    private static func matches(left: TableData, leftKey: [Int], right: TableData, rightKey: [Int], kind: Int, function: String,
                                leftInPlace: Bool = false) throws -> [(Int?, Int?)] {
        guard leftKey.count == rightKey.count, !leftKey.isEmpty else {
            throw MError.expression("\(function): hai bên phải có cùng số cột khoá")
        }
        let leftKeys = try keys(left, columns: leftKey, function: function)
        let rightKeys = try keys(right, columns: rightKey, function: function)
        var index: [[Key]: [Int]] = [:]
        for (row, key) in rightKeys.enumerated() { index[key, default: []].append(row) }
        var pairs: [(Int?, Int?)] = []
        var unmatchedLeft: [Int] = []
        var matchedRight = Set<Int>()
        for (row, key) in leftKeys.enumerated() {
            if let found = index[key] {
                if kind == 4 { continue }
                for r in found { matchedRight.insert(r) }
                if kind != 5 { for r in found { pairs.append((row, r)) } }
            } else if kind == 1 || kind == 3 || kind == 4 {
                if leftInPlace { pairs.append((row, nil)) } else { unmatchedLeft.append(row) }
            }
        }
        if kind == 2 || kind == 3 || kind == 5 {
            for r in 0..<right.rowCount where !matchedRight.contains(r) { pairs.append((nil, r)) }
        }
        pairs.append(contentsOf: unmatchedLeft.map { ($0, nil) })
        return pairs
    }

    private static func cells(_ table: TableData, column: Int, rows: [Int?]) -> [MValue] {
        rows.map { row in row.map { MTables.cell(table, row: $0, column: column) } ?? .null }
    }

    /// `Table.Join(table1, key1, table2, key2, joinKind?)`: mặc định Inner; cột hai bảng ghép cạnh nhau, trùng tên là lỗi.
    private static let join = MFunction(
        name: "Table.Join",
        parameters: [MParameter(name: "table1"), MParameter(name: "key1"), MParameter(name: "table2"), MParameter(name: "key2"),
                     MParameter(name: "joinKind", isOptional: true), MParameter(name: "joinAlgorithm", isOptional: true),
                     MParameter(name: "keyEqualityComparers", isOptional: true)],
        observed: true
    ) { args in
        let left = try args.table(0, "Table.Join"), right = try args.table(2, "Table.Join")
        let leftKey = try columnIndices(left, args[1], function: "Table.Join")
        let rightKey = try columnIndices(right, args[3], function: "Table.Join")
        let kind = try joinKind(args.optional(4), function: "Table.Join", default: 0)
        let pairs = try matches(left: left, leftKey: leftKey, right: right, rightKey: rightKey, kind: kind, function: "Table.Join")
        let leftRows = pairs.map(\.0), rightRows = pairs.map(\.1)
        var names: [String] = [], types: [MType?] = [], columns: [[MValue]] = []
        for (index, column) in left.columns.enumerated() {
            names.append(column.name); types.append(mType(of: column)); columns.append(cells(left, column: index, rows: leftRows))
        }
        for (index, column) in right.columns.enumerated() {
            if names.contains(column.name) { throw MError.expression("Table.Join: cột '\(column.name)' có ở cả hai bảng, hãy đổi tên trước") }
            names.append(column.name); types.append(mType(of: column)); columns.append(cells(right, column: index, rows: rightRows))
        }
        return .table(try assemble(names: names, types: types, columns: columns))
    }

    /// `Table.NestedJoin(table1, key1, table2, key2, newColumnName, joinKind?)`: mặc định LeftOuter; cột mới chứa bảng khớp của bảng 2.
    private static let nestedJoin = MFunction(
        name: "Table.NestedJoin",
        parameters: [MParameter(name: "table1"), MParameter(name: "key1"), MParameter(name: "table2"), MParameter(name: "key2"),
                     MParameter(name: "newColumnName"), MParameter(name: "joinKind", isOptional: true),
                     MParameter(name: "keyEqualityComparers", isOptional: true)],
        observed: true
    ) { args in
        let left = try args.table(0, "Table.NestedJoin"), right = try args.table(2, "Table.NestedJoin")
        let leftKey = try columnIndices(left, args[1], function: "Table.NestedJoin")
        let rightKey = try columnIndices(right, args[3], function: "Table.NestedJoin")
        let newName = try args.text(4, "Table.NestedJoin")
        if left.index(ofColumn: newName) != nil { throw MError.expression("Table.NestedJoin: cột '\(newName)' đã có") }
        let kind = try joinKind(args.optional(5), function: "Table.NestedJoin", default: 1)
        let pairs = try matches(left: left, leftKey: leftKey, right: right, rightKey: rightKey, kind: kind, function: "Table.NestedJoin", leftInPlace: true)

        // Một dòng kết quả cho mỗi dòng trái (kèm các dòng phải khớp); dòng phải không khớp (Right/Full/RightAnti) thành dòng riêng với phía trái trống.
        var leftRows: [Int?] = [], groups: [[Int]] = []
        for (l, r) in pairs {
            if let l, let r {
                if leftRows.last.flatMap({ $0 }) == l { groups[groups.count - 1].append(r) } else { leftRows.append(l); groups.append([r]) }
            } else if let l {
                leftRows.append(l); groups.append([])
            } else if let r {
                leftRows.append(nil); groups.append([r])
            }
        }
        var names: [String] = [], types: [MType?] = [], columns: [[MValue]] = []
        for (index, column) in left.columns.enumerated() {
            names.append(column.name); types.append(mType(of: column)); columns.append(cells(left, column: index, rows: leftRows))
        }
        names.append(newName); types.append(MType(.text, isNullable: true)); columns.append(Array(repeating: .null, count: leftRows.count))
        let nestedTables = try groups.map { try TableRowsHelper.sliceRows(table: right, rowIndices: $0) }
        return .table(try assemble(names: names, types: types, columns: columns, nested: [left.columns.count: nestedTables]))
    }

    /// `Table.ExpandTableColumn(table, column, columnNames, newColumnNames?)`: mỗi dòng nhân theo số dòng của bảng lồng (bảng rỗng cho một dòng trống).
    private static let expandTableColumn = MFunction(
        name: "Table.ExpandTableColumn",
        parameters: [MParameter(name: "table"), MParameter(name: "column"), MParameter(name: "columnNames"),
                     MParameter(name: "newColumnNames", isOptional: true)],
        observed: true
    ) { args in
        let table = try args.table(0, "Table.ExpandTableColumn")
        let name = try args.text(1, "Table.ExpandTableColumn")
        guard let column = table.index(ofColumn: name) else { throw MError.expression("Table.ExpandTableColumn: không tìm thấy cột '\(name)'") }
        guard let nested = table.nested[column] else {
            throw MError.expression("Table.ExpandTableColumn: cột '\(name)' không phải cột bảng lồng (chỉ giữ nguyên ngay sau Table.NestedJoin)")
        }
        let wanted = try TableRowsHelper.extractColumnNames(args[2], functionName: "Table.ExpandTableColumn")
        let renamed = try args.optional(3).map { try TableRowsHelper.extractColumnNames($0, functionName: "Table.ExpandTableColumn") } ?? wanted
        guard renamed.count == wanted.count else { throw MError.expression("Table.ExpandTableColumn: số tên mới khác số cột cần mở") }

        // Kiểu cột mở: lấy từ một bảng lồng bất kỳ (mọi bảng lồng cùng lược đồ).
        let schema = nested.first
        var sourceIndex: [Int] = []
        for wantedName in wanted {
            guard let schema, let i = schema.index(ofColumn: wantedName) else {
                throw MError.expression("Table.ExpandTableColumn: bảng lồng không có cột '\(wantedName)'")
            }
            sourceIndex.append(i)
        }
        var rowSource: [(row: Int, inner: Int?)] = []
        for (row, inner) in nested.enumerated() {
            if inner.rowCount == 0 { rowSource.append((row, nil)) } else { for i in 0..<inner.rowCount { rowSource.append((row, i)) } }
        }
        var names: [String] = [], types: [MType?] = [], columns: [[MValue]] = []
        for (index, col) in table.columns.enumerated() where index != column {
            names.append(col.name); types.append(mType(of: col))
            columns.append(rowSource.map { MTables.cell(table, row: $0.row, column: index) })
        }
        for (k, newName) in renamed.enumerated() {
            if names.contains(newName) { throw MError.expression("Table.ExpandTableColumn: cột '\(newName)' đã có, hãy đặt tên khác") }
            names.append(newName)
            types.append(schema.map { mType(of: $0.columns[sourceIndex[k]]) })
            columns.append(rowSource.map { entry in
                guard let inner = entry.inner else { return .null }
                return MTables.cell(nested[entry.row], row: inner, column: sourceIndex[k])
            })
        }
        return .table(try assemble(names: names, types: types, columns: columns))
    }

    // MARK: - Table.Group

    /// `Table.Group(table, key, aggregatedColumns, groupKind?, comparer?)`: mặc định Global; nhóm theo thứ tự xuất hiện đầu tiên.
    private static let group = MFunction(
        name: "Table.Group",
        parameters: [MParameter(name: "table"), MParameter(name: "key"), MParameter(name: "aggregatedColumns"),
                     MParameter(name: "groupKind", isOptional: true), MParameter(name: "comparer", isOptional: true)],
        observed: true
    ) { args in
        let table = try args.table(0, "Table.Group")
        let keyColumns = try columnIndices(table, args[1], function: "Table.Group")
        var aggregates: [(name: String, function: MFunction, type: MType?)] = []
        for item in try args.list(2, "Table.Group") {
            guard case .list(let parts) = item, parts.count >= 2, parts.count <= 3, case .text(let name) = parts[0], case .function(let f) = parts[1] else {
                throw MError.expression("Table.Group: mỗi phép tổng hợp phải là {tên, hàm, kiểu?}")
            }
            var type: MType?
            if parts.count == 3, case .type(let t) = parts[2] { type = t }
            aggregates.append((name, f, type))
        }
        let kind = try joinKind(args.optional(3), function: "Table.Group", default: 1)
        guard kind == 0 || kind == 1 else { throw MError.expression("Table.Group: kiểu nhóm không hợp lệ") }
        let rowKeys = try keys(table, columns: keyColumns, function: "Table.Group")

        var groups: [[Int]] = []
        if kind == 1 {
            var positions: [[Key]: Int] = [:]
            for (row, key) in rowKeys.enumerated() {
                if let p = positions[key] { groups[p].append(row) } else { positions[key] = groups.count; groups.append([row]) }
            }
        } else {
            for (row, key) in rowKeys.enumerated() {
                if row > 0, rowKeys[row - 1] == key { groups[groups.count - 1].append(row) } else { groups.append([row]) }
            }
        }
        var names: [String] = [], types: [MType?] = [], columns: [[MValue]] = []
        for c in keyColumns {
            names.append(table.columns[c].name); types.append(mType(of: table.columns[c]))
            columns.append(groups.map { MTables.cell(table, row: $0[0], column: c) })
        }
        let subTables = try groups.map { MValue.table(try TableRowsHelper.sliceRows(table: table, rowIndices: $0)) }
        for aggregate in aggregates {
            names.append(aggregate.name); types.append(aggregate.type)
            columns.append(try subTables.map { sub in
                do { return try aggregate.function.call([sub]) } catch let error as MError { return .error(error) }
            })
        }
        return .table(try assemble(names: names, types: types, columns: columns))
    }

    // MARK: - Table.Pivot, Unpivot

    /// `Table.Pivot(table, pivotValues, attributeColumn, valueColumn, aggregationFunction?)`.
    private static let pivot = MFunction(
        name: "Table.Pivot",
        parameters: [MParameter(name: "table"), MParameter(name: "pivotValues"), MParameter(name: "attributeColumn"),
                     MParameter(name: "valueColumn"), MParameter(name: "aggregationFunction", isOptional: true)],
        observed: true
    ) { args in
        let table = try args.table(0, "Table.Pivot")
        var pivotValues: [String] = []
        for item in try args.list(1, "Table.Pivot") {
            guard case .text(let s) = item else { throw MError.expression("Table.Pivot: giá trị xoay phải là text, nhận \(item.kindName)") }
            if !pivotValues.contains(s) { pivotValues.append(s) }
        }
        let attributeName = try args.text(2, "Table.Pivot"), valueName = try args.text(3, "Table.Pivot")
        guard let attribute = table.index(ofColumn: attributeName) else { throw MError.expression("Table.Pivot: không tìm thấy cột '\(attributeName)'") }
        guard let value = table.index(ofColumn: valueName) else { throw MError.expression("Table.Pivot: không tìm thấy cột '\(valueName)'") }
        let aggregator = try args.optional(4).map { _ in try args.function(4, "Table.Pivot") }
        let keyColumns = table.columns.indices.filter { $0 != attribute && $0 != value }
        if let clash = pivotValues.first(where: { name in keyColumns.contains { table.columns[$0].name == name } }) {
            throw MError.expression("Table.Pivot: giá trị xoay '\(clash)' trùng tên một cột còn lại")
        }
        let rowKeys = try keys(table, columns: keyColumns, function: "Table.Pivot")
        var positions: [[Key]: Int] = [:]
        var rows: [[Int]] = []
        for (row, key) in rowKeys.enumerated() {
            if let p = positions[key] { rows[p].append(row) } else { positions[key] = rows.count; rows.append([row]) }
        }
        // Desktop 2.159: nhóm sắp theo cột khoá tăng dần, null trước (probe p4, p5).
        rows.sort { a, b in
            for c in keyColumns {
                let x = MTables.cell(table, row: a[0], column: c), y = MTables.cell(table, row: b[0], column: c)
                if case .null = x { if case .null = y { continue } else { return true } }
                if case .null = y { return false }
                if let order = MOperators.compare(x, y), order != 0 { return order < 0 }
            }
            return false
        }
        var names: [String] = [], types: [MType?] = [], columns: [[MValue]] = []
        for c in keyColumns {
            names.append(table.columns[c].name); types.append(mType(of: table.columns[c]))
            columns.append(rows.map { MTables.cell(table, row: $0[0], column: c) })
        }
        let valueType = mType(of: table.columns[value])
        for pivotValue in pivotValues {
            names.append(pivotValue)
            var cellsOut: [MValue] = []
            var resultKind: MType?
            for group in rows {
                let hits = group.filter { MTables.cell(table, row: $0, column: attribute) == .text(pivotValue) }
                if hits.isEmpty { cellsOut.append(.null); continue }
                let values = hits.map { MTables.cell(table, row: $0, column: value) }
                if let aggregator {
                    do { cellsOut.append(try aggregator.call([.list(values)])) } catch let error as MError { cellsOut.append(.error(error)) }
                } else if hits.count == 1 {
                    cellsOut.append(values[0])
                } else {
                    // Desktop: lỗi nằm ở ô, phần còn lại của bảng vẫn có.
                    cellsOut.append(.error(MError.expression("There were too many elements in the enumeration to complete the operation.")))
                }
            }
            // Có hàm tổng hợp thì kiểu cột theo kết quả (suy từ giá trị); không thì theo cột giá trị.
            resultKind = aggregator == nil ? valueType : nil
            types.append(resultKind)
            columns.append(cellsOut)
        }
        return .table(try assemble(names: names, types: types, columns: columns))
    }

    private static func unpivotRows(_ table: TableData, pivotColumns: [Int], attributeName: String, valueName: String, function: String) throws -> MValue {
        let keepColumns = table.columns.indices.filter { !pivotColumns.contains($0) }
        var names: [String] = keepColumns.map { table.columns[$0].name }
        guard !names.contains(attributeName), !names.contains(valueName), attributeName != valueName else {
            throw MError.expression("\(function): tên cột thuộc tính/giá trị trùng một cột còn lại")
        }
        var keep: [[MValue]] = keepColumns.map { _ in [] }
        var attributes: [MValue] = [], values: [MValue] = []
        for row in 0..<table.rowCount {
            for p in pivotColumns {
                let cell = MTables.cell(table, row: row, column: p)
                if case .null = cell { continue }
                for (slot, c) in keepColumns.enumerated() { keep[slot].append(MTables.cell(table, row: row, column: c)) }
                attributes.append(.text(table.columns[p].name))
                values.append(cell)
            }
        }
        var types: [MType?] = keepColumns.map { mType(of: table.columns[$0]) }
        names += [attributeName, valueName]
        types += [MType(.text, isNullable: true), nil]
        let kinds = Set(pivotColumns.map { table.columns[$0].data.type })
        if kinds.count == 1, let only = pivotColumns.first { types[types.count - 1] = mType(of: table.columns[only]) }
        return .table(try assemble(names: names, types: types, columns: keep + [attributes, values]))
    }

    /// `Table.Unpivot(table, pivotColumns, attributeColumn, valueColumn)`: bỏ ô `null`.
    private static let unpivot = MFunction(
        name: "Table.Unpivot",
        parameters: [MParameter(name: "table"), MParameter(name: "pivotColumns"), MParameter(name: "attributeColumn"), MParameter(name: "valueColumn")],
        observed: true
    ) { args in
        let table = try args.table(0, "Table.Unpivot")
        let pivots = try columnIndices(table, args[1], function: "Table.Unpivot")
        return try unpivotRows(table, pivotColumns: pivots, attributeName: try args.text(2, "Table.Unpivot"),
                               valueName: try args.text(3, "Table.Unpivot"), function: "Table.Unpivot")
    }

    /// `Table.UnpivotOtherColumns(table, pivotColumns, attributeColumn, valueColumn)`: `pivotColumns` là cột GIỮ, mọi cột khác bị xoay.
    private static let unpivotOtherColumns = MFunction(
        name: "Table.UnpivotOtherColumns",
        parameters: [MParameter(name: "table"), MParameter(name: "pivotColumns"), MParameter(name: "attributeColumn"), MParameter(name: "valueColumn")],
        observed: true
    ) { args in
        let table = try args.table(0, "Table.UnpivotOtherColumns")
        let keep = try columnIndices(table, args[1], function: "Table.UnpivotOtherColumns")
        let pivots = table.columns.indices.filter { !keep.contains($0) }
        return try unpivotRows(table, pivotColumns: pivots, attributeName: try args.text(2, "Table.UnpivotOtherColumns"),
                               valueName: try args.text(3, "Table.UnpivotOtherColumns"), function: "Table.UnpivotOtherColumns")
    }
}
