// Phase F: Thư viện hàm M nhóm cột (Table.PromoteHeaders, Table.TransformColumnTypes, ...).
import Foundation
import ColumnStore

public enum TableColumnsLibrary {
    public static let functions: [MFunction] = [
        MFunction(
            name: "Table.PromoteHeaders",
            parameters: [MParameter(name: "table"), MParameter(name: "options", isOptional: true)],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.PromoteHeaders")
            guard table.rowCount > 0 else { return .table(table) }

            // Lấy dòng đầu tiên làm tên cột
            var seenNames = Set<String>()
            var newHeaders: [String] = []

            for c in 0..<table.columns.count {
                var headerName = "Column\(c + 1)"
                if table.error(row: 0, column: c) == nil {
                    let cell = MTables.cell(table, row: 0, column: c)
                    switch cell {
                    case .text(let s):
                        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { headerName = trimmed }
                    case .number(let d):
                        if d == d.rounded() && abs(d) < 9.2e18 {
                            headerName = String(Int64(d))
                        } else {
                            headerName = String(format: "%g", d)
                        }
                    case .currency(let cur):
                        let d = Double(cur) / 10_000
                        headerName = d == d.rounded() ? String(Int64(d)) : String(format: "%g", d)
                    case .logical(let b):
                        headerName = b ? "true" : "false"
                    default:
                        break
                    }
                }
                var finalName = headerName
                var suffix = 1
                while seenNames.contains(finalName) {
                    finalName = "\(headerName)_\(suffix)"
                    suffix += 1
                }
                seenNames.insert(finalName)
                newHeaders.append(finalName)
            }

            // Cắt từ dòng 1 trở đi
            let remainingRows = Array(1..<table.rowCount)
            var newColumns: [TableColumn] = []
            newColumns.reserveCapacity(table.columns.count)

            for (c, col) in table.columns.enumerated() {
                let data = col.data
                let slicedData: ColumnData
                switch data.type {
                case .integer:
                    slicedData = ColumnBuilder.integers(remainingRows.map { if case .integer(let v) = data.value(at: $0) { v } else { nil } })
                case .currency:
                    slicedData = ColumnBuilder.currency(remainingRows.map { if case .currency(let v) = data.value(at: $0) { v } else { nil } })
                case .double:
                    slicedData = ColumnBuilder.doubles(remainingRows.map { if case .double(let v) = data.value(at: $0) { v } else { nil } })
                case .dateTime:
                    slicedData = ColumnBuilder.dateTimes(remainingRows.map { if case .dateTime(let v) = data.value(at: $0) { v } else { nil } })
                case .boolean:
                    slicedData = ColumnBuilder.booleans(remainingRows.map { if case .boolean(let v) = data.value(at: $0) { v } else { nil } })
                case .string:
                    slicedData = ColumnBuilder.strings(remainingRows.map { if case .string(let v) = data.value(at: $0) { v } else { nil } })
                }
                newColumns.append(TableColumn(name: newHeaders[c], data: slicedData))
            }

            // Dịch errorMask giảm 1 dòng (dòng 0 bị bỏ)
            var newMask: [Int: [Int: String]] = [:]
            for (colIdx, cellErrors) in table.errorMask {
                var colErrors: [Int: String] = [:]
                for (oldRow, msg) in cellErrors where oldRow >= 1 {
                    colErrors[oldRow - 1] = msg
                }
                if !colErrors.isEmpty {
                    newMask[colIdx] = colErrors
                }
            }

            return .table(try TableData(columns: newColumns, errorMask: newMask))
        },

        MFunction(
            name: "Table.TransformColumnTypes",
            parameters: [MParameter(name: "table"), MParameter(name: "typeTransformations"), MParameter(name: "culture", isOptional: true)],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.TransformColumnTypes")
            let transList = try args.list(1, "Table.TransformColumnTypes")

            var transforms: [String: MType] = [:]
            for item in transList {
                guard case .list(let pair) = item, pair.count >= 2, case .text(let name) = pair[0] else {
                    throw MError.expression("Table.TransformColumnTypes: mỗi biến đổi phải có dạng {\"Tên cột\", Kiểu}")
                }
                let type: MType
                switch pair[1] {
                case .type(let t):
                    type = t
                default:
                    throw MError.expression("Table.TransformColumnTypes: kiểu không hợp lệ cho cột '\(name)'")
                }
                transforms[name] = type
            }

            var newColumns: [TableColumn] = []
            var newMask = table.errorMask

            var sources: [Int?] = []
            for (colIdx, col) in table.columns.enumerated() {
                guard let targetType = transforms[col.name] else {
                    newColumns.append(col)
                    sources.append(colIdx)
                    continue
                }
                if table.structured[colIdx] != nil || table.nested[colIdx] != nil {
                    throw MError.expression("Table.TransformColumnTypes: cột '\(col.name)' chứa bản ghi, danh sách hoặc bảng; hãy mở rộng trước khi đổi kiểu")
                }
                sources.append(nil)
                let newCol = try TableColumnsTypesHelper.transformColumn(
                    col: col,
                    colIdx: colIdx,
                    targetType: targetType,
                    table: table,
                    newErrorMask: &newMask
                )
                newColumns.append(newCol)
            }

            return .table(try table.keeping(columns: newColumns, sources: sources, errorMask: newMask))
        },

        MFunction(
            name: "Table.RenameColumns",
            parameters: [MParameter(name: "table"), MParameter(name: "renames"), MParameter(name: "missingField", isOptional: true)],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.RenameColumns")
            let renameList = try args.list(1, "Table.RenameColumns")

            var renameMap: [String: String] = [:]
            for item in renameList {
                guard case .list(let pair) = item, pair.count >= 2, case .text(let old) = pair[0], case .text(let new) = pair[1] else {
                    throw MError.expression("Table.RenameColumns: mỗi cặp phải có dạng {\"Tên cũ\", \"Tên mới\"}")
                }
                renameMap[old] = new
            }

            var newColumns: [TableColumn] = []
            for col in table.columns {
                if let newName = renameMap[col.name] {
                    newColumns.append(TableColumn(name: newName, data: col.data))
                    renameMap.removeValue(forKey: col.name)
                } else {
                    newColumns.append(col)
                }
            }

            if !renameMap.isEmpty {
                let missing = renameMap.keys.sorted().joined(separator: ", ")
                throw MError.expression("Table.RenameColumns: không tìm thấy cột '\(missing)'")
            }

            return .table(try table.keeping(columns: newColumns, sources: Array(table.columns.indices), errorMask: table.errorMask))
        },

        MFunction(
            name: "Table.RemoveColumns",
            parameters: [MParameter(name: "table"), MParameter(name: "columns"), MParameter(name: "missingField", isOptional: true)],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.RemoveColumns")
            let toRemove = Set(try TableRowsHelper.extractColumnNames(args[1], functionName: "Table.RemoveColumns"))

            // Kiểm tra cột có tồn tại không
            for colName in toRemove {
                if table.index(ofColumn: colName) == nil {
                    throw MError.expression("Table.RemoveColumns: không tìm thấy cột '\(colName)'")
                }
            }

            var newColumns: [TableColumn] = []
            var newMask: [Int: [Int: String]] = [:]
            var sources: [Int?] = []

            for (oldIdx, col) in table.columns.enumerated() {
                if toRemove.contains(col.name) { continue }
                let newIdx = newColumns.count
                newColumns.append(col)
                sources.append(oldIdx)
                if let errors = table.errorMask[oldIdx] {
                    newMask[newIdx] = errors
                }
            }

            return .table(try table.keeping(columns: newColumns, sources: sources, errorMask: newMask))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.SelectColumns",
            parameters: [MParameter(name: "table"), MParameter(name: "columns"), MParameter(name: "missingField", isOptional: true)],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.SelectColumns")
            let selectedNames = try TableRowsHelper.extractColumnNames(args[1], functionName: "Table.SelectColumns")

            var newColumns: [TableColumn] = []
            var newMask: [Int: [Int: String]] = [:]
            var sources: [Int?] = []

            for name in selectedNames {
                guard let oldIdx = table.index(ofColumn: name) else {
                    throw MError.expression("Table.SelectColumns: không tìm thấy cột '\(name)'")
                }
                let newIdx = newColumns.count
                newColumns.append(table.columns[oldIdx])
                sources.append(oldIdx)
                if let errors = table.errorMask[oldIdx] {
                    newMask[newIdx] = errors
                }
            }

            return .table(try table.keeping(columns: newColumns, sources: sources, errorMask: newMask))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.ReorderColumns",
            parameters: [MParameter(name: "table"), MParameter(name: "columnOrder"), MParameter(name: "missingField", isOptional: true)],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.ReorderColumns")
            let orderedNames = try TableRowsHelper.extractColumnNames(args[1], functionName: "Table.ReorderColumns")

            var newColumns: [TableColumn] = []
            var newMask: [Int: [Int: String]] = [:]
            var seen = Set<String>()
            var sources: [Int?] = []

            for name in orderedNames {
                guard let oldIdx = table.index(ofColumn: name) else {
                    throw MError.expression("Table.ReorderColumns: không tìm thấy cột '\(name)'")
                }
                let newIdx = newColumns.count
                newColumns.append(table.columns[oldIdx])
                sources.append(oldIdx)
                seen.insert(name)
                if let errors = table.errorMask[oldIdx] {
                    newMask[newIdx] = errors
                }
            }

            for (oldIdx, col) in table.columns.enumerated() {
                if !seen.contains(col.name) {
                    let newIdx = newColumns.count
                    newColumns.append(col)
                    sources.append(oldIdx)
                    if let errors = table.errorMask[oldIdx] {
                        newMask[newIdx] = errors
                    }
                }
            }

            return .table(try table.keeping(columns: newColumns, sources: sources, errorMask: newMask))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.DuplicateColumn",
            parameters: [MParameter(name: "table"), MParameter(name: "column"), MParameter(name: "newColumnName"), MParameter(name: "newColumnType", isOptional: true)],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.DuplicateColumn")
            let colName = try args.text(1, "Table.DuplicateColumn")
            let newName = try args.text(2, "Table.DuplicateColumn")
            guard let oldIdx = table.index(ofColumn: colName) else {
                throw MError.expression("Table.DuplicateColumn: không tìm thấy cột '\(colName)'")
            }

            var newColumns = table.columns
            let dupCol = TableColumn(name: newName, data: table.columns[oldIdx].data)
            newColumns.append(dupCol)

            var newMask = table.errorMask
            if let errors = table.errorMask[oldIdx] {
                newMask[newColumns.count - 1] = errors
            }

            return .table(try TableData(columns: newColumns, errorMask: newMask))
        },

        MFunction(
            name: "Table.AddColumn",
            parameters: [MParameter(name: "table"), MParameter(name: "newColumnName"), MParameter(name: "columnGenerator"), MParameter(name: "columnType", isOptional: true)],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.AddColumn")
            let newColName = try args.text(1, "Table.AddColumn")
            let generator = try args.function(2, "Table.AddColumn")
            let declaredType: MType? = args.optional(3).flatMap {
                if case .type(let t) = $0 { return t } else { return nil }
            }

            var newVals: [MValue] = []
            newVals.reserveCapacity(table.rowCount)
            for r in 0..<table.rowCount {
                let rowRecord = MTables.row(table, r)
                newVals.append(try generator.call([rowRecord]))
            }

            let newColData = try MTables.column(newVals, type: declaredType, name: newColName)
            var newColumns = table.columns
            newColumns.append(TableColumn(name: newColName, data: newColData))

            return .table(try TableData(columns: newColumns, errorMask: table.errorMask))
        },

        MFunction(
            name: "Table.AddIndexColumn",
            parameters: [MParameter(name: "table"), MParameter(name: "newColumnName"), MParameter(name: "initialValue", isOptional: true), MParameter(name: "increment", isOptional: true), MParameter(name: "columnType", isOptional: true)],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.AddIndexColumn")
            let newColName = try args.text(1, "Table.AddIndexColumn")
            let initial = args.optional(2).flatMap { MOperators.number($0).map(Int64.init) } ?? 0
            let step = args.optional(3).flatMap { MOperators.number($0).map(Int64.init) } ?? 1

            var indices: [Int64?] = []
            indices.reserveCapacity(table.rowCount)
            for r in 0..<table.rowCount {
                indices.append(initial + Int64(r) * step)
            }

            let newColData = ColumnBuilder.integers(indices)
            var newColumns = table.columns
            newColumns.append(TableColumn(name: newColName, data: newColData))

            return .table(try TableData(columns: newColumns, errorMask: table.errorMask))
        },

        MFunction(
            name: "Table.SplitColumn",
            parameters: [MParameter(name: "table"), MParameter(name: "sourceColumn"), MParameter(name: "splitter"), MParameter(name: "columnNamesOrNumber", isOptional: true)],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.SplitColumn")
            let srcName = try args.text(1, "Table.SplitColumn")
            let splitter = try args.function(2, "Table.SplitColumn")
            guard let srcIdx = table.index(ofColumn: srcName) else {
                throw MError.expression("Table.SplitColumn: không tìm thấy cột '\(srcName)'")
            }

            let targetNames: [String]
            if let targetArg = args.optional(3) {
                targetNames = try TableRowsHelper.extractColumnNames(targetArg, functionName: "Table.SplitColumn")
            } else {
                targetNames = ["\(srcName).1", "\(srcName).2"]
            }

            // Phân tách từng dòng
            var splitValuesByColumn: [[String?]] = Array(repeating: [], count: targetNames.count)
            for colIdx in 0..<targetNames.count {
                splitValuesByColumn[colIdx].reserveCapacity(table.rowCount)
            }

            for r in 0..<table.rowCount {
                let cell = MTables.cell(table, row: r, column: srcIdx)
                let splitRes = try splitter.call([cell])
                var parts: [String] = []
                if case .list(let items) = splitRes {
                    for it in items {
                        if case .text(let s) = it { parts.append(s) }
                    }
                }
                for c in 0..<targetNames.count {
                    if c < parts.count {
                        splitValuesByColumn[c].append(parts[c])
                    } else {
                        splitValuesByColumn[c].append(nil) // Thiếu phần -> null
                    }
                }
            }

            var newColumns: [TableColumn] = []
            var newMask: [Int: [Int: String]] = [:]

            // Cột trước srcIdx
            for i in 0..<srcIdx {
                let newIdx = newColumns.count
                newColumns.append(table.columns[i])
                if let errs = table.errorMask[i] { newMask[newIdx] = errs }
            }

            // Các cột mới thay thế tại srcIdx
            for c in 0..<targetNames.count {
                let newIdx = newColumns.count
                let colData = ColumnBuilder.strings(splitValuesByColumn[c])
                newColumns.append(TableColumn(name: targetNames[c], data: colData))
            }

            // Cột sau srcIdx
            for i in (srcIdx + 1)..<table.columns.count {
                let newIdx = newColumns.count
                newColumns.append(table.columns[i])
                if let errs = table.errorMask[i] { newMask[newIdx] = errs }
            }

            return .table(try TableData(columns: newColumns, errorMask: newMask))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.CombineColumns",
            parameters: [MParameter(name: "table"), MParameter(name: "sourceColumns"), MParameter(name: "combiner"), MParameter(name: "column")],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.CombineColumns")
            let srcNames = try TableRowsHelper.extractColumnNames(args[1], functionName: "Table.CombineColumns")
            let combiner = try args.function(2, "Table.CombineColumns")
            let newColName = try args.text(3, "Table.CombineColumns")

            let srcIndices = try srcNames.map { name -> Int in
                guard let idx = table.index(ofColumn: name) else {
                    throw MError.expression("Table.CombineColumns: không tìm thấy cột '\(name)'")
                }
                return idx
            }
            let srcSet = Set(srcNames)
            guard let insertIdx = table.columns.firstIndex(where: { srcSet.contains($0.name) }) else {
                throw MError.expression("Table.CombineColumns: danh sách cột nguồn rỗng")
            }

            var combinedVals: [String?] = []
            combinedVals.reserveCapacity(table.rowCount)

            for r in 0..<table.rowCount {
                let rowItems: [MValue] = srcIndices.map { MTables.cell(table, row: r, column: $0) }
                let res = try combiner.call([.list(rowItems)])
                if case .text(let s) = res {
                    combinedVals.append(s)
                } else if case .null = res {
                    combinedVals.append(nil)
                } else {
                    throw MError.expression("Table.CombineColumns: combiner phải trả text hoặc null")
                }
            }

            var newColumns: [TableColumn] = []
            var newMask: [Int: [Int: String]] = [:]

            for (oldIdx, col) in table.columns.enumerated() {
                if oldIdx == insertIdx {
                    let newIdx = newColumns.count
                    newColumns.append(TableColumn(name: newColName, data: ColumnBuilder.strings(combinedVals)))
                }
                if srcSet.contains(col.name) { continue }
                let newIdx = newColumns.count
                newColumns.append(col)
                if let errs = table.errorMask[oldIdx] { newMask[newIdx] = errs }
            }

            return .table(try TableData(columns: newColumns, errorMask: newMask))
        },

        MFunction(
            name: "Table.TransformColumns",
            parameters: [MParameter(name: "table"), MParameter(name: "transformOperations"), MParameter(name: "defaultTransformation", isOptional: true), MParameter(name: "missingField", isOptional: true)],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.TransformColumns")
            let opList = try args.list(1, "Table.TransformColumns")

            struct Op {
                let fn: MFunction
                let targetType: MType?
            }
            var opMap: [String: Op] = [:]

            for item in opList {
                guard case .list(let items) = item, items.count >= 2, case .text(let col) = items[0], case .function(let fn) = items[1] else {
                    throw MError.expression("Table.TransformColumns: thao tác phải có dạng {\"Tên cột\", Hàm, Kiểu?}")
                }
                let type: MType?
                if items.count > 2, case .type(let t) = items[2] {
                    type = t
                } else {
                    type = nil
                }
                opMap[col] = Op(fn: fn, targetType: type)
            }

            var newColumns: [TableColumn] = []
            for (colIdx, col) in table.columns.enumerated() {
                guard let op = opMap[col.name] else {
                    newColumns.append(col)
                    continue
                }
                var newVals: [MValue] = []
                newVals.reserveCapacity(table.rowCount)
                for r in 0..<table.rowCount {
                    let cur = MTables.cell(table, row: r, column: colIdx)
                    let res = try op.fn.call([cur])
                    newVals.append(res)
                }
                let newColData = try MTables.column(newVals, type: op.targetType, name: col.name)
                newColumns.append(TableColumn(name: col.name, data: newColData))
            }

            return .table(try TableData(columns: newColumns, errorMask: table.errorMask))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.ColumnNames",
            parameters: [MParameter(name: "table")],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.ColumnNames")
            return .list(table.columns.map { .text($0.name) })
        },

        MFunction(
            name: "Table.RowCount",
            parameters: [MParameter(name: "table")],
            observed: true
        ) { args in
            let table = try args.table(0, "Table.RowCount")
            return .number(Double(table.rowCount))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Table.ColumnCount",
            parameters: [MParameter(name: "table")],
            observed: false
        ) { args in
            let table = try args.table(0, "Table.ColumnCount")
            return .number(Double(table.columns.count))
        }
    ]
}
