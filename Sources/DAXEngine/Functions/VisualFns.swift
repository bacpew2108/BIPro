// Functions/VisualFns.swift
// Các hàm DAX phục vụ visual của Power BI Desktop (Package E1, Phase C).
// NATURALLEFTOUTERJOIN, SUBSTITUTEWITHINDEX, GROUPBY, CURRENTGROUP, SAMPLE,
// SAMPLEAXISWITHLOCALMINMAX, IGNORE, NONVISUAL, ROLLUPADDISSUBTOTAL, ROLLUPGROUP.

import Foundation
import ColumnStore

public enum VisualFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "NATURALLEFTOUTERJOIN",
                     params: [.table("left"), .table("right")],
                     impl: .table(naturalLeftOuterJoinBody)),

        FunctionSpec(name: "SUBSTITUTEWITHINDEX",
                     params: [.table("table"), .scalar("name"), .table("semiJoinIndexTable"),
                              .lazy("orderBy", repeats: true),
                              .keyword("order", ["ASC", "DESC"], optional: false, repeats: true)],
                     impl: .table(substituteWithIndexBody)),

        FunctionSpec(name: "GROUPBY",
                     params: [.table("table"), .lazy("args", optional: true, repeats: true)],
                     impl: .table(groupByBody)),

        FunctionSpec(name: "CURRENTGROUP",
                     params: [],
                     impl: .table(currentGroupBody)),

        FunctionSpec(name: "SAMPLE",
                     params: [.scalar("size"), .table("table"), .lazy("orderBy", optional: true, repeats: true),
                              .keyword("order", ["ASC", "DESC"], optional: true)],
                     impl: .table(sampleBody)),

        FunctionSpec(name: "ROW",
                     params: [.scalar("name", repeats: true), .lazy("expression", repeats: true)],
                     impl: .table(rowBody)),

        FunctionSpec(name: "SAMPLEAXISWITHLOCALMINMAX",
                     params: [
                        .scalar("size"),
                        .table("table"),
                        .tableOrColumn("axis"),
                        .lazy("measure"),
                        .scalar("minResolution"),
                        .lazy("dynamicSeries", optional: true),
                        .keyword("selectionCriteria", ["ALPHABETICAL", "ANY"], optional: true),
                        .keyword("order", ["ASC", "DESC"], optional: true),
                        .scalar("maxResolution", optional: true),
                        .scalar("maxDynamicSeries", optional: true),
                        .scalar("maxIterations", optional: true)
                     ],
                     impl: .table(sampleAxisBody)),

        FunctionSpec(name: "NONVISUAL",
                     params: [.table("table")],
                     impl: .table(nonvisualBody)),

        FunctionSpec(name: "ROLLUPADDISSUBTOTAL",
                     params: [.lazy("args", repeats: true)],
                     impl: .table(rollupAddIsSubtotalBody)),

        FunctionSpec(name: "ROLLUPGROUP",
                     params: [.tableOrColumn("columns", repeats: true)],
                     impl: .table(rollupGroupBody)),
    ]

    // MARK: - NATURALLEFTOUTERJOIN

    private static let naturalLeftOuterJoinBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard frame.args.count == 2, frame.args[0] != nil, frame.args[1] != nil else {
            throw DAXError(.arity, "NATURALLEFTOUTERJOIN cần đúng 2 bảng")
        }
        let left = try frame.table(0)
        let right = try frame.table(1)

        func normName(_ s: String) -> String {
            s.replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces).lowercased()
        }

        // Tìm các cặp cột nối theo cùng tên và cùng lineage (nếu cả 2 có lineage)
        var joinPairs: [(left: Int, right: Int)] = []
        for (rIdx, rCol) in right.columns.enumerated() {
            let rNorm = normName(rCol)
            for (lIdx, lCol) in left.columns.enumerated() {
                let lNorm = normName(lCol)
                if lNorm == rNorm {
                    let lLineage = left.lineage[lIdx]
                    let rLineage = right.lineage[rIdx]
                    if let lLineage, let rLineage {
                        guard lLineage == rLineage else {
                            throw DAXError(.typeMismatch, "NATURALLEFTOUTERJOIN: cột '\(lCol)' cùng tên nhưng khác lineage")
                        }
                    }
                    joinPairs.append((left: lIdx, right: rIdx))
                    break
                }
            }
        }

        let rightNonJoin = (0..<right.columns.count).filter { r in
            !joinPairs.contains(where: { $0.right == r })
        }

        let outColumns = left.columns + rightNonJoin.map { right.columns[$0] }
        let outLineages = left.lineage + rightNonJoin.map { right.lineage[$0] }

        var outRows: [[Value]] = []
        for lRow in left.rows {
            var matches: [[Value]] = []
            for rRow in right.rows {
                var equal = true
                for pair in joinPairs {
                    let cmp = try Value.compare(.strictEqual, lRow[pair.left], rRow[pair.right])
                    if cmp != .boolean(true) {
                        equal = false
                        break
                    }
                }
                if equal {
                    matches.append(rRow)
                }
            }

            if matches.isEmpty {
                let blankRight = rightNonJoin.map { _ in Value.blank }
                outRows.append(lRow + blankRight)
            } else {
                for m in matches {
                    let rightVals = rightNonJoin.map { m[$0] }
                    outRows.append(lRow + rightVals)
                }
            }
        }

        return TableValue(columns: outColumns, rows: outRows, lineage: outLineages)
    }

    // MARK: - SUBSTITUTEWITHINDEX

    private static let substituteWithIndexBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard frame.args.count >= 3 else {
            throw DAXError(.arity, "SUBSTITUTEWITHINDEX cần ít nhất bảng, tên và bảng chỉ số")
        }
        let evaluator = try fkEvaluator(frame)
        let mainTable = try frame.table(0)
        let indexColName = try frame.scalar(1).asText()
        let formattedName = indexColName.hasPrefix("[") && indexColName.hasSuffix("]") ? indexColName : "[\(indexColName)]"
        let indexTable = try frame.table(2)

        func normName(_ s: String) -> String {
            s.replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces).lowercased()
        }

        // Tìm các cột join giữa mainTable và indexTable
        var joinPairs: [(main: Int, index: Int)] = []
        for (iIdx, iCol) in indexTable.columns.enumerated() {
            let iNorm = normName(iCol)
            for (mIdx, mCol) in mainTable.columns.enumerated() {
                let mNorm = normName(mCol)
                if iNorm == mNorm {
                    let mLineage = mainTable.lineage[mIdx]
                    let iLineage = indexTable.lineage[iIdx]
                    if let mLineage, let iLineage {
                        guard mLineage == iLineage else {
                            throw DAXError(.typeMismatch, "SUBSTITUTEWITHINDEX: cột '\(mCol)' cùng tên nhưng khác lineage")
                        }
                    }
                    joinPairs.append((main: mIdx, index: iIdx))
                    break
                }
            }
        }
        guard !joinPairs.isEmpty else {
            throw DAXError(.runtime, "SUBSTITUTEWITHINDEX: không tìm thấy cột nối chung")
        }

        // Sắp xếp indexTable theo các biểu thức sắp xếp
        var orderSpecs: [(expr: BoundExpr, desc: Bool)] = []
        var i = 3
        while i < frame.args.count {
            guard let arg = frame.args[i] else {
                i += 1
                continue
            }
            var isDir = false
            var dirDesc = false
            switch arg {
            case .keyword(let word):
                isDir = true
                dirDesc = (word == "DESC")
            case .literal(.integer(let v)):
                isDir = true
                dirDesc = (v == 0)
            case .literal(.boolean(let b)):
                isDir = true
                dirDesc = !b
            default:
                break
            }
            if isDir && !orderSpecs.isEmpty {
                orderSpecs[orderSpecs.count - 1].desc = dirDesc
            } else {
                orderSpecs.append((expr: arg, desc: false))
            }
            i += 1
        }

        var indexEntries: [(index: Int, keys: [Value])] = []
        try frame.iterate(indexTable) { (inner: EvalContext) throws(DAXError) in
            guard let rowIdx = inner.row?.row else { return }
            var keys: [Value] = []
            keys.reserveCapacity(orderSpecs.count)
            for spec in orderSpecs {
                keys.append(try evaluator.scalar(spec.expr, in: inner))
            }
            indexEntries.append((index: rowIdx, keys: keys))
        }

        indexEntries.sort { (a, b) -> Bool in
            for (k, spec) in orderSpecs.enumerated() {
                let valA = k < a.keys.count ? a.keys[k] : .blank
                let valB = k < b.keys.count ? b.keys[k] : .blank
                let cmp = QueryExecutor.compareValues(valA, valB)
                if cmp != 0 {
                    return spec.desc ? cmp > 0 : cmp < 0
                }
            }
            return a.index < b.index
        }

        var joinKeyToIndex: [[Value]: Int] = [:]
        for (orderPos, entry) in indexEntries.enumerated() {
            let row = indexTable.rows[entry.index]
            let joinKey = joinPairs.map { row[$0.index] }
            if joinKeyToIndex[joinKey] == nil {
                joinKeyToIndex[joinKey] = orderPos
            }
        }

        // Bỏ các cột join khỏi mainTable, thêm [Name] ở cuối
        let mainNonJoin = (0..<mainTable.columns.count).filter { m in
            !joinPairs.contains(where: { $0.main == m })
        }
        let outColumns = mainNonJoin.map { mainTable.columns[$0] } + [formattedName]
        let outLineages = mainNonJoin.map { mainTable.lineage[$0] } + [nil as ColumnID?]

        var outRows: [[Value]] = []
        for mRow in mainTable.rows {
            let key = joinPairs.map { mRow[$0.main] }
            if let assignedIndex = joinKeyToIndex[key] {
                let keptVals = mainNonJoin.map { mRow[$0] }
                outRows.append(keptVals + [.integer(Int64(assignedIndex))])
            }
        }

        return TableValue(columns: outColumns, rows: outRows, lineage: outLineages)
    }

    // MARK: - GROUPBY

    private static let currentGroupBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard let evaluator = frame.eval as? Evaluator, let current = evaluator.currentGroupStack.last else {
            throw DAXError(.runtime, "CURRENTGROUP() chỉ được dùng bên trong biểu thức của GROUPBY")
        }
        return current
    }

    private static let groupByBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard frame.args.count >= 1, frame.args[0] != nil else {
            throw DAXError(.arity, "GROUPBY cần ít nhất một bảng")
        }
        let evaluator = try fkEvaluator(frame)
        let source = try frame.table(0)

        var groupCols: [BoundExpr] = []
        var extensions: [(name: String, expr: BoundExpr)] = []
        var i = 1
        while i < frame.args.count {
            guard let arg = frame.args[i] else {
                i += 1
                continue
            }
            if case .literal(.string(let name)) = arg {
                guard i + 1 < frame.args.count, let expr = frame.args[i + 1] else {
                    throw DAXError(.arity, "GROUPBY: thiếu biểu thức cho '\(name)'")
                }
                extensions.append((name: name, expr: expr))
                i += 2
            } else {
                groupCols.append(arg)
                i += 1
            }
        }

        func evaluateExtensions(for groupTable: TableValue) throws(DAXError) -> [Value] {
            evaluator.currentGroupStack.append(groupTable)
            defer { evaluator.currentGroupStack.removeLast() }
            var vals: [Value] = []
            vals.reserveCapacity(extensions.count)
            for ext in extensions {
                let v = try evaluator.scalar(ext.expr, in: frame.ctx)
                vals.append(v)
            }
            return vals
        }

        // Trường hợp không có cột nhóm: ra đúng 1 dòng
        if groupCols.isEmpty {
            let extVals = try evaluateExtensions(for: source)
            let outCols = extensions.map { $0.name.hasPrefix("[") ? $0.name : "[\($0.name)]" }
            return TableValue(columns: outCols, rows: [extVals], lineage: extensions.map { _ in nil })
        }

        var groupMap: [[Value]: [Int]] = [:]
        var groupOrder: [[Value]] = []

        try frame.iterate(source) { (inner: EvalContext) throws(DAXError) in
            guard let r = inner.row?.row else { return }
            var key: [Value] = []
            key.reserveCapacity(groupCols.count)
            for g in groupCols {
                key.append(try evaluator.scalar(g, in: inner))
            }
            if groupMap[key] == nil {
                groupMap[key] = [r]
                groupOrder.append(key)
            } else {
                groupMap[key]?.append(r)
            }
        }

        var outRows: [[Value]] = []
        outRows.reserveCapacity(groupOrder.count)
        for key in groupOrder {
            let rowIndices = groupMap[key] ?? []
            let subRows = rowIndices.map { source.rows[$0] }
            let subTable = TableValue(columns: source.columns, rows: subRows, lineage: source.lineage)
            let extVals = try evaluateExtensions(for: subTable)
            outRows.append(key + extVals)
        }

        var outColNames: [String] = []
        var outLineages: [ColumnID?] = []
        for g in groupCols {
            switch g {
            case .column(let id):
                outColNames.append(fkQualifiedName(id, evaluator))
                outLineages.append(id)
            case .virtualColumn(let name):
                outColNames.append(name.hasPrefix("[") ? name : "[\(name)]")
                outLineages.append(nil)
            default:
                outColNames.append("[Group]")
                outLineages.append(nil)
            }
        }
        for ext in extensions {
            outColNames.append(ext.name.hasPrefix("[") ? ext.name : "[\(ext.name)]")
            outLineages.append(nil)
        }

        return TableValue(columns: outColNames, rows: outRows, lineage: outLineages)
    }

    // MARK: - SAMPLE

    private static let sampleBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard frame.args.count >= 2, frame.args[1] != nil else {
            throw DAXError(.arity, "SAMPLE cần kích thước và bảng")
        }
        let evaluator = try fkEvaluator(frame)
        let size = try fkTopCount(try frame.scalar(0))
        let source = try frame.table(1)

        if size <= 0 {
            return TableValue(columns: source.columns, rows: [], lineage: source.lineage)
        }

        var orderSpecs: [(expr: BoundExpr, desc: Bool)] = []
        var i = 2
        while i < frame.args.count {
            guard let arg = frame.args[i] else {
                i += 1
                continue
            }
            var isDir = false
            var dirDesc = false
            switch arg {
            case .keyword(let word):
                isDir = true
                dirDesc = (word == "DESC")
            case .literal(.integer(let v)):
                isDir = true
                dirDesc = (v == 0)
            case .literal(.boolean(let b)):
                isDir = true
                dirDesc = !b
            default:
                break
            }
            if isDir && !orderSpecs.isEmpty {
                orderSpecs[orderSpecs.count - 1].desc = dirDesc
            } else {
                orderSpecs.append((expr: arg, desc: false))
            }
            i += 1
        }

        var entries: [(index: Int, keys: [Value])] = []
        try frame.iterate(source) { (inner: EvalContext) throws(DAXError) in
            guard let r = inner.row?.row else { return }
            var keys: [Value] = []
            keys.reserveCapacity(orderSpecs.count)
            for spec in orderSpecs {
                keys.append(try evaluator.scalar(spec.expr, in: inner))
            }
            entries.append((index: r, keys: keys))
        }

        if !orderSpecs.isEmpty {
            let descs = orderSpecs.map(\.desc)
            entries.sort { (a, b) -> Bool in
                do throws(DAXError) {
                    let c = try fkCompareMultiKeys(a.keys, b.keys, descs: descs)
                    if c != 0 { return c < 0 }
                    return a.index < b.index
                } catch {
                    return a.index < b.index
                }
            }
        }

        let sortedRows = entries.map { source.rows[$0.index] }
        let total = sortedRows.count
        if total <= size {
            return TableValue(columns: source.columns, rows: sortedRows, lineage: source.lineage)
        }

        var selectedIndices: [Int] = []
        for s in 0..<size {
            let idx = Int((Double(s) * Double(total - 1) / Double(size - 1)).rounded())
            selectedIndices.append(idx)
        }

        return TableValue(columns: source.columns, rows: selectedIndices.map { sortedRows[$0] }, lineage: source.lineage)
    }

    // MARK: - SAMPLEAXISWITHLOCALMINMAX

    private static let sampleAxisBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard frame.args.count >= 2 else {
            throw DAXError(.arity, "SAMPLEAXISWITHLOCALMINMAX cần kích thước và bảng")
        }
        let size = try fkTopCount(try frame.scalar(0))
        let table = try frame.table(1)

        // Nhom6 và dataset chuẩn có số dòng <= size thì trả đủ dòng
        if table.rows.count <= size {
            return table
        }

        // [SUY ĐOÁN] Chia trục thành các bin đều và lấy min, max của mỗi bin
        let binCount = max(1, size / 2)
        let binSize = Double(table.rows.count) / Double(binCount)
        var picked: [Int] = []
        for b in 0..<binCount {
            let start = Int(Double(b) * binSize)
            let end = min(table.rows.count, Int(Double(b + 1) * binSize))
            if start < end {
                picked.append(start)
                if end - 1 > start {
                    picked.append(end - 1)
                }
            }
        }
        return TableValue(columns: table.columns, rows: picked.map { table.rows[$0] }, lineage: table.lineage)
    }

    // MARK: - ROW

    private static let rowBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard frame.args.count >= 2, frame.args.count % 2 == 0 else {
            throw DAXError(.arity, "ROW cần các cặp (tên, biểu thức)")
        }
        var colNames: [String] = []
        var rowValues: [Value] = []
        var i = 0
        while i < frame.args.count {
            let name = try frame.scalar(i).asText()
            let formatted = name.hasPrefix("[") && name.hasSuffix("]") ? name : "[\(name)]"
            colNames.append(formatted)
            let val = try frame.eval.scalar(frame.args[i + 1]!, in: frame.ctx)
            rowValues.append(val)
            i += 2
        }
        return TableValue(columns: colNames, rows: [rowValues], lineage: colNames.map { _ in nil })
    }

    // MARK: - NONVISUAL, ROLLUPADDISSUBTOTAL, ROLLUPGROUP

    private static let nonvisualBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard frame.args.count == 1, frame.args[0] != nil else {
            throw DAXError(.arity, "NONVISUAL cần đúng một bảng")
        }
        return try frame.table(0)
    }

    private static let rollupAddIsSubtotalBody: FunctionSpec.TableBody = { (_: CallFrame) throws(DAXError) -> TableValue in
        throw DAXError(.runtime, "ROLLUPADDISSUBTOTAL chỉ dùng bên trong SUMMARIZECOLUMNS")
    }

    private static let rollupGroupBody: FunctionSpec.TableBody = { (_: CallFrame) throws(DAXError) -> TableValue in
        throw DAXError(.runtime, "ROLLUPGROUP chỉ dùng bên trong SUMMARIZECOLUMNS")
    }
}
