// Phase F: Thư viện hàm M nhóm dòng (Table.SelectRows, Table.Sort, ...).
import PBIXKit
import Foundation
import ColumnStore

public enum TableRowsLibrary {
    public static let functions: [MFunction] = [
        MFunction(
            name: "Table.SelectRows",
            parameters: [MParameter(name: "table"), MParameter(name: "condition")],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.SelectRows")
            let condition = try args.function(1, "Table.SelectRows")
            var kept: [Int] = []
            kept.reserveCapacity(table.rowCount)
            for r in 0..<table.rowCount {
                let rowRecord = MTables.row(table, r)
                let res = try condition.call([rowRecord])
                guard case .logical(let b) = res else {
                    throw MError.expression(lt("Table.SelectRows: vị từ phải trả về true hoặc false, nhận \(res.kindName)", "Table.SelectRows: the predicate must return true or false, got \(res.kindName)"))
                }
                if b { kept.append(r) }
            }
            return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: kept))
        },

        MFunction(
            name: "Table.Sort",
            parameters: [MParameter(name: "table"), MParameter(name: "comparisonCriteria")],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.Sort")
            let critVal = args[1]
            var criteria: [(colIdx: Int, descending: Bool)] = []

            func parseItem(_ item: MValue) throws -> (colIdx: Int, descending: Bool) {
                switch item {
                case .text(let col):
                    guard let idx = table.index(ofColumn: col) else {
                        throw MError.expression(lt("Table.Sort: không tìm thấy cột '\(col)'", "Table.Sort: column '\(col)' not found"))
                    }
                    return (idx, false)
                case .list(let pair):
                    guard !pair.isEmpty, case .text(let col) = pair[0] else {
                        throw MError.expression(lt("Table.Sort: phần tử tiêu chí sắp xếp phải bắt đầu bằng tên cột", "Table.Sort: a sort criterion must start with a column name"))
                    }
                    guard let idx = table.index(ofColumn: col) else {
                        throw MError.expression(lt("Table.Sort: không tìm thấy cột '\(col)'", "Table.Sort: column '\(col)' not found"))
                    }
                    var desc = false
                    if pair.count > 1 {
                        if case .number(let order) = pair[1], order == 1 {
                            desc = true
                        }
                    }
                    return (idx, desc)
                default:
                    throw MError.expression(lt("Table.Sort: tiêu chí sắp xếp không hợp lệ: \(item.kindName)", "Table.Sort: invalid sort criterion: \(item.kindName)"))
                }
            }

            switch critVal {
            case .text:
                criteria.append(try parseItem(critVal))
            case .list(let items):
                if items.count == 2, case .text = items[0], (items[1].isNumber || items[1] == .null) {
                    criteria.append(try parseItem(critVal))
                } else {
                    for it in items {
                        criteria.append(try parseItem(it))
                    }
                }
            default:
                throw MError.expression(lt("Table.Sort: tiêu chí sắp xếp phải là text hoặc list", "Table.Sort: the sort criterion must be text or a list"))
            }

            // Tiền trích xuất giá trị cột sắp xếp để so sánh O(1) không tốn chi phí gọi hàm/tạo đối tượng
            enum PreExtractedKey {
                case integers([Int64?], descending: Bool)
                case doubles([Double?], descending: Bool)
                case strings([String?], descending: Bool)
                case general([MValue], descending: Bool)
            }

            let preKeys: [PreExtractedKey] = criteria.map { crit in
                let col = table.columns[crit.colIdx]
                let hasErr = table.errorMask[crit.colIdx] != nil
                if !hasErr {
                    switch col.data.type {
                    case .integer:
                        var arr = [Int64?]()
                        arr.reserveCapacity(table.rowCount)
                        for r in 0..<table.rowCount {
                            if case .integer(let v) = col.data.value(at: r) { arr.append(v) } else { arr.append(nil) }
                        }
                        return .integers(arr, descending: crit.descending)
                    case .double:
                        var arr = [Double?]()
                        arr.reserveCapacity(table.rowCount)
                        for r in 0..<table.rowCount {
                            if case .double(let v) = col.data.value(at: r) { arr.append(v) } else { arr.append(nil) }
                        }
                        return .doubles(arr, descending: crit.descending)
                    case .string:
                        var arr = [String?]()
                        arr.reserveCapacity(table.rowCount)
                        for r in 0..<table.rowCount {
                            if case .string(let v) = col.data.value(at: r) { arr.append(v) } else { arr.append(nil) }
                        }
                        return .strings(arr, descending: crit.descending)
                    default:
                        break
                    }
                }
                var arr = [MValue]()
                arr.reserveCapacity(table.rowCount)
                for r in 0..<table.rowCount {
                    arr.append(MTables.cell(table, row: r, column: crit.colIdx))
                }
                return .general(arr, descending: crit.descending)
            }

            let sortedIndices = (0..<table.rowCount).sorted { (r1, r2) -> Bool in
                for key in preKeys {
                    switch key {
                    case .integers(let arr, let desc):
                        let v1 = arr[r1]
                        let v2 = arr[r2]
                        if v1 == v2 { continue }
                        guard let v1 else { return !desc }
                        guard let v2 else { return desc }
                        return desc ? (v1 > v2) : (v1 < v2)
                    case .doubles(let arr, let desc):
                        let v1 = arr[r1]
                        let v2 = arr[r2]
                        if v1 == v2 { continue }
                        guard let v1 else { return !desc }
                        guard let v2 else { return desc }
                        return desc ? (v1 > v2) : (v1 < v2)
                    case .strings(let arr, let desc):
                        let v1 = arr[r1]
                        let v2 = arr[r2]
                        if v1 == v2 { continue }
                        guard let v1 else { return !desc }
                        guard let v2 else { return desc }
                        let cmp = v1.unicodeScalars.lexicographicallyPrecedes(v2.unicodeScalars, by: { $0.value < $1.value })
                        return desc ? !cmp : cmp
                    case .general(let arr, let desc):
                        let v1 = arr[r1]
                        let v2 = arr[r2]
                        switch (v1, v2) {
                        case (.null, .null): continue
                        case (.null, _): return !desc
                        case (_, .null): return desc
                        default:
                            if let cmp = MOperators.compare(v1, v2), cmp != 0 {
                                return desc ? (cmp > 0) : (cmp < 0)
                            }
                        }
                    }
                }
                return r1 < r2
            }

            return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: sortedIndices))
        },

        MFunction(
            name: "Table.FirstN",
            parameters: [MParameter(name: "table"), MParameter(name: "countOrCondition")],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.FirstN")
            let arg1 = args[1]
            if let n = MOperators.number(arg1) {
                let count = try MInt.from(n, "Table.FirstN")
                guard count >= 0 else { throw MError.expression(lt("Table.FirstN: count không được âm", "Table.FirstN: count can't be negative")) }
                let take = min(count, table.rowCount)
                return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: Array(0..<take)))
            } else if case .function(let cond) = arg1 {
                var kept: [Int] = []
                for r in 0..<table.rowCount {
                    let res = try cond.call([MTables.row(table, r)])
                    guard case .logical(let b) = res else {
                        throw MError.expression(lt("Table.FirstN: điều kiện phải trả về logic, nhận \(res.kindName)", "Table.FirstN: the condition must return a logical value, got \(res.kindName)"))
                    }
                    if !b { break }
                    kept.append(r)
                }
                return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: kept))
            } else {
                throw MError.expression(lt("Table.FirstN: đối số 2 phải là số hoặc hàm điều kiện", "Table.FirstN: argument 2 must be a number or a condition function"))
            }
        },

        MFunction(
            name: "Table.Skip",
            parameters: [MParameter(name: "table"), MParameter(name: "countOrCondition", isOptional: true)],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.Skip")
            let countVal = args.optional(1)
            let count: Int
            if let c = countVal {
                guard let n = MOperators.number(c) else {
                    throw MError.expression(lt("Table.Skip: count phải là số", "Table.Skip: count must be a number"))
                }
                count = try MInt.from(n, "Table.Skip")
            } else {
                count = 1
            }
            guard count >= 0 else { throw MError.expression(lt("Table.Skip: count không được âm", "Table.Skip: count can't be negative")) }
            let start = min(count, table.rowCount)
            return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: Array(start..<table.rowCount)))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.LastN",
            parameters: [MParameter(name: "table"), MParameter(name: "countOrCondition")],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.LastN")
            let count = try MInt.from(args.number(1, "Table.LastN"), "Table.LastN")
            guard count >= 0 else { throw MError.expression(lt("Table.LastN: count không được âm", "Table.LastN: count can't be negative")) }
            let take = min(count, table.rowCount)
            let start = table.rowCount - take
            return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: Array(start..<table.rowCount)))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.RemoveFirstN",
            parameters: [MParameter(name: "table"), MParameter(name: "countOrCondition", isOptional: true)],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.RemoveFirstN")
            let count = try args.optional(1).flatMap(MOperators.number).map { try MInt.from($0, "Table.RemoveFirstN") } ?? 1
            guard count >= 0 else { throw MError.expression(lt("Table.RemoveFirstN: count không được âm", "Table.RemoveFirstN: count can't be negative")) }
            let start = min(count, table.rowCount)
            return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: Array(start..<table.rowCount)))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.RemoveLastN",
            parameters: [MParameter(name: "table"), MParameter(name: "countOrCondition", isOptional: true)],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.RemoveLastN")
            let count = try args.optional(1).flatMap(MOperators.number).map { try MInt.from($0, "Table.RemoveLastN") } ?? 1
            guard count >= 0 else { throw MError.expression(lt("Table.RemoveLastN: count không được âm", "Table.RemoveLastN: count can't be negative")) }
            let keptCount = max(0, table.rowCount - count)
            return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: Array(0..<keptCount)))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.Range",
            parameters: [MParameter(name: "table"), MParameter(name: "offset"), MParameter(name: "count", isOptional: true)],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.Range")
            let offset = try MInt.from(args.number(1, "Table.Range"), "Table.Range")
            guard offset >= 0 else { throw MError.expression(lt("Table.Range: offset không được âm", "Table.Range: offset can't be negative")) }
            let start = min(offset, table.rowCount)
            let count = try args.optional(2).flatMap(MOperators.number).map { try MInt.from($0, "Table.Range") } ?? (table.rowCount - start)
            guard count >= 0 else { throw MError.expression(lt("Table.Range: count không được âm", "Table.Range: count can't be negative")) }
            let end = min(start + count, table.rowCount)
            return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: Array(start..<end)))
        },

        MFunction(
            name: "Table.Distinct",
            parameters: [MParameter(name: "table"), MParameter(name: "equationCriteria", isOptional: true)],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.Distinct")
            let keyColumns: [Int]
            if let crit = args.optional(1) {
                let colNames = try TableRowsHelper.extractColumnNames(crit, functionName: "Table.Distinct")
                keyColumns = try colNames.map { name in
                    guard let idx = table.index(ofColumn: name) else {
                        throw MError.expression(lt("Table.Distinct: không tìm thấy cột '\(name)'", "Table.Distinct: column '\(name)' not found"))
                    }
                    return idx
                }
            } else {
                keyColumns = Array(0..<table.columns.count)
            }

            var kept: [Int] = []
            // Để phân biệt và giữ thứ tự xuất hiện đầu tiên:
            // Nếu không có ô lỗi trên cột khoá, ta có thể dùng trực tiếp mã dictionary (rất nhanh).
            // Nếu có lỗi, so bằng MTables.cell.
            struct DistinctKey: Hashable {
                let values: [StoredValue]
            }
            var seen = Set<DistinctKey>()
            for r in 0..<table.rowCount {
                // Kiểm tra xem dòng r có lỗi ở cột khoá nào không
                var hasError = false
                for c in keyColumns {
                    if table.error(row: r, column: c) != nil {
                        hasError = true
                        break
                    }
                }
                if hasError {
                    // Dòng có lỗi: so theo MValue đầy đủ
                    var isDup = false
                    for prev in kept {
                        var matchAll = true
                        for c in keyColumns {
                            if !MOperators.equals(MTables.cell(table, row: r, column: c), MTables.cell(table, row: prev, column: c)) {
                                matchAll = false
                                break
                            }
                        }
                        if matchAll { isDup = true; break }
                    }
                    if !isDup { kept.append(r) }
                } else {
                    let k = DistinctKey(values: keyColumns.map { table.value(row: r, column: $0) })
                    if seen.insert(k).inserted {
                        kept.append(r)
                    }
                }
            }

            return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: kept))
        },

        MFunction(
            name: "Table.ReplaceValue",
            parameters: [MParameter(name: "table"), MParameter(name: "oldValue"), MParameter(name: "newValue"), MParameter(name: "replacer"), MParameter(name: "columnsToSearch")],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.ReplaceValue")
            let oldValue = args[1]
            let newValue = args[2]
            let replacer = try args.function(3, "Table.ReplaceValue")
            let colNames = try TableRowsHelper.extractColumnNames(args[4], functionName: "Table.ReplaceValue")
            let targetCols = Set(colNames)

            var newColumns: [TableColumn] = []
            for (colIdx, col) in table.columns.enumerated() {
                if !targetCols.contains(col.name) {
                    newColumns.append(col)
                    continue
                }
                // Cột cần thay thế giá trị
                var newValues: [MValue] = []
                newValues.reserveCapacity(table.rowCount)
                for r in 0..<table.rowCount {
                    if table.error(row: r, column: colIdx) != nil {
                        newValues.append(.null)
                    } else {
                        let cur = MTables.cell(table, row: r, column: colIdx)
                        let replaced = try replacer.call([cur, oldValue, newValue])
                        newValues.append(replaced)
                    }
                }
                let newColData = try MTables.column(newValues, type: MType(col.data.type.mTypeKind), name: col.name)
                newColumns.append(TableColumn(name: col.name, data: newColData))
            }

            return .table(try TableData(columns: newColumns, errorMask: table.errorMask))
        },

        MFunction(
            name: "Table.FillDown",
            parameters: [MParameter(name: "table"), MParameter(name: "columns")],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.FillDown")
            let colNames = try TableRowsHelper.extractColumnNames(args[1], functionName: "Table.FillDown")
            let targetCols = Set(colNames)

            var newColumns: [TableColumn] = []
            for (colIdx, col) in table.columns.enumerated() {
                if !targetCols.contains(col.name) {
                    newColumns.append(col)
                    continue
                }
                var lastVal: MValue = .null
                var newValues: [MValue] = []
                newValues.reserveCapacity(table.rowCount)
                for r in 0..<table.rowCount {
                    if table.error(row: r, column: colIdx) != nil {
                        newValues.append(.null)
                    } else {
                        let cur = MTables.cell(table, row: r, column: colIdx)
                        if cur != .null {
                            lastVal = cur
                            newValues.append(cur)
                        } else {
                            newValues.append(lastVal)
                        }
                    }
                }
                let newColData = try MTables.column(newValues, type: MType(col.data.type.mTypeKind), name: col.name)
                newColumns.append(TableColumn(name: col.name, data: newColData))
            }

            return .table(try TableData(columns: newColumns, errorMask: table.errorMask))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.FillUp",
            parameters: [MParameter(name: "table"), MParameter(name: "columns")],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.FillUp")
            let colNames = try TableRowsHelper.extractColumnNames(args[1], functionName: "Table.FillUp")
            let targetCols = Set(colNames)

            var newColumns: [TableColumn] = []
            for (colIdx, col) in table.columns.enumerated() {
                if !targetCols.contains(col.name) {
                    newColumns.append(col)
                    continue
                }
                var lastVal: MValue = .null
                var newValues = Array(repeating: MValue.null, count: table.rowCount)
                for r in (0..<table.rowCount).reversed() {
                    if table.error(row: r, column: colIdx) != nil {
                        newValues[r] = .null
                    } else {
                        let cur = MTables.cell(table, row: r, column: colIdx)
                        if cur != .null {
                            lastVal = cur
                            newValues[r] = cur
                        } else {
                            newValues[r] = lastVal
                        }
                    }
                }
                let newColData = try MTables.column(newValues, type: MType(col.data.type.mTypeKind), name: col.name)
                newColumns.append(TableColumn(name: col.name, data: newColData))
            }

            return .table(try TableData(columns: newColumns, errorMask: table.errorMask))
        },

        MFunction(
            name: "Table.ReverseRows",
            parameters: [MParameter(name: "table")],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.ReverseRows")
            let reversedIndices = Array((0..<table.rowCount).reversed())
            return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: reversedIndices))
        },

        MFunction(
            name: "Table.ReplaceErrorValues",
            parameters: [MParameter(name: "table"), MParameter(name: "errorReplacement")],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.ReplaceErrorValues")
            let repArg = args[1]
            var replacements: [String: MValue] = [:]

            switch repArg {
            case .list(let pairs):
                for item in pairs {
                    guard case .list(let pair) = item, pair.count >= 2, case .text(let col) = pair[0] else {
                        throw MError.expression(lt("Table.ReplaceErrorValues: mỗi mục phải là {tên cột, giá trị thay thế}", "Table.ReplaceErrorValues: each item must be {column name, replacement value}"))
                    }
                    replacements[col] = pair[1]
                }
            case .record(let fields):
                for f in fields { replacements[f.name] = f.value }
            default:
                throw MError.expression(lt("Table.ReplaceErrorValues: đối số 2 phải là list hoặc record", "Table.ReplaceErrorValues: argument 2 must be a list or record"))
            }

            var newColumns: [TableColumn] = []
            var newMask = table.errorMask

            for (colIdx, col) in table.columns.enumerated() {
                guard let repVal = replacements[col.name], let colErrors = newMask[colIdx], !colErrors.isEmpty else {
                    newColumns.append(col)
                    continue
                }
                // Thay thế các ô lỗi
                newMask.removeValue(forKey: colIdx)
                var newVals: [MValue] = []
                newVals.reserveCapacity(table.rowCount)
                for r in 0..<table.rowCount {
                    if colErrors[r] != nil {
                        newVals.append(repVal)
                    } else {
                        newVals.append(MTables.cell(table, row: r, column: colIdx))
                    }
                }
                let newColData = try MTables.column(newVals, type: MType(col.data.type.mTypeKind), name: col.name)
                newColumns.append(TableColumn(name: col.name, data: newColData))
            }

            return .table(try TableData(columns: newColumns, errorMask: newMask))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.RemoveRowsWithErrors",
            parameters: [MParameter(name: "table"), MParameter(name: "columns", isOptional: true)],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.RemoveRowsWithErrors")
            let checkCols: Set<Int>
            if let c = args.optional(1) {
                let names = try TableRowsHelper.extractColumnNames(c, functionName: "Table.RemoveRowsWithErrors")
                checkCols = Set(try names.map { n in
                    guard let idx = table.index(ofColumn: n) else { throw MError.expression(lt("Table.RemoveRowsWithErrors: không tìm thấy cột '\(n)'", "Table.RemoveRowsWithErrors: column '\(n)' not found")) }
                    return idx
                })
            } else {
                checkCols = Set(0..<table.columns.count)
            }

            var kept: [Int] = []
            for r in 0..<table.rowCount {
                var hasErr = false
                for c in checkCols {
                    if table.error(row: r, column: c) != nil {
                        hasErr = true
                        break
                    }
                }
                if !hasErr { kept.append(r) }
            }
            return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: kept))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.SelectRowsWithErrors",
            parameters: [MParameter(name: "table"), MParameter(name: "columns", isOptional: true)],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.SelectRowsWithErrors")
            let checkCols: Set<Int>
            if let c = args.optional(1) {
                let names = try TableRowsHelper.extractColumnNames(c, functionName: "Table.SelectRowsWithErrors")
                checkCols = Set(try names.map { n in
                    guard let idx = table.index(ofColumn: n) else { throw MError.expression(lt("Table.SelectRowsWithErrors: không tìm thấy cột '\(n)'", "Table.SelectRowsWithErrors: column '\(n)' not found")) }
                    return idx
                })
            } else {
                checkCols = Set(0..<table.columns.count)
            }

            var kept: [Int] = []
            for r in 0..<table.rowCount {
                var hasErr = false
                for c in checkCols {
                    if table.error(row: r, column: c) != nil {
                        hasErr = true
                        break
                    }
                }
                if hasErr { kept.append(r) }
            }
            return .table(try TableRowsHelper.sliceRows(table: table, rowIndices: kept))
        },

        // Đợt tồn đọng sau Phase F, T026: bước Source của Enter Data (VM-F11a): `Table.FromRows(Json.Document(…), type table [A = _t, …])`.
        // `columns`: danh sách tên, số cột, kiểu bảng (lấy tên và kiểu trường) hoặc bỏ trống (`Column1…` theo hàng dài nhất). Hàng ngắn
        // hơn số cột thì bù null, dài hơn thì báo lỗi (tài liệu M; `[SUY ĐOÁN]` thông điệp).
        MFunction(
            name: "Table.FromRows",
            parameters: [MParameter(name: "rows"), MParameter(name: "columns", isOptional: true)],
            observed: true
        ) { args in
            let rows = try args.list(0, "Table.FromRows").map { row -> [MValue] in
                guard case .list(let values) = row else { throw MError.expression(lt("Table.FromRows: mỗi hàng phải là danh sách, nhận \(row.kindName)", "Table.FromRows: each row must be a list, got \(row.kindName)")) }
                return values
            }
            var names: [String]
            var types: [MType?]
            switch args.optional(1) {
            case .none:
                names = (0..<(rows.map(\.count).max() ?? 0)).map { "Column\($0 + 1)" }
                types = names.map { _ in nil }
            case .number(let n)?:
                names = (0..<max(try MInt.from(n, "Table.FromRows"), 0)).map { "Column\($0 + 1)" }
                types = names.map { _ in nil }
            case .list(let list)?:
                names = try list.map { value in
                    guard case .text(let name) = value else { throw MError.expression(lt("Table.FromRows: tên cột phải là text", "Table.FromRows: column names must be text")) }
                    return name
                }
                types = names.map { _ in nil }
            case .type(let type)? where type.kind == .table:
                names = type.fields.map(\.name)
                types = type.fields.map { $0.type.kind == .any ? nil : $0.type }
            default:
                throw MError.expression(lt("Table.FromRows: tham số columns không hợp lệ", "Table.FromRows: invalid columns parameter"))
            }
            let filled = try rows.map { row -> [MValue] in
                guard row.count <= names.count else {
                    throw MError.expression(lt("Table.FromRows: hàng có \(row.count) giá trị trong khi bảng có \(names.count) cột", "Table.FromRows: a row has \(row.count) values but the table has \(names.count) columns"))
                }
                return row + Array(repeating: MValue.null, count: names.count - row.count)
            }
            return .table(try MTables.build(names: names, types: types, rows: filled))
        }
    ]
}

extension DAXType {
    var mTypeKind: MType.Kind {
        switch self {
        case .integer: .int64
        case .double: .double
        case .currency: .currency
        case .string: .text
        case .boolean: .logical
        case .dateTime: .datetime
        }
    }
}

extension MValue {
    var isNumber: Bool {
        switch self {
        case .number, .currency: true
        default: false
        }
    }
}
