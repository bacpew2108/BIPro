// Hàm cửa sổ (Window Functions — Wave 3 / v1.1b): OFFSET, INDEX, WINDOW cùng ORDERBY và PARTITIONBY.
// Đối chiếu 100% VM-V11B dax-golden.json (window_offset_index_window trên Dim_Client[client_region]).
//
// Thiết kế:
// - ORDERBY(...) và PARTITIONBY(...) được đăng ký trong FunctionRegistry để Binder bind bình thường trong row scope
//   của bảng `relation`; OFFSET/INDEX/WINDOW đọc trực tiếp các đối số bên trong `.call` đó.
// - Khi gọi trong ngữ cảnh có row context hoặc filter context (vd ADDCOLUMNS(Base, "Prev", CALCULATE(MAXX(OFFSET(...))))):
//   vị trí hiện tại (current row) được xác định bằng cách so khớp mọi cột có lineage/tên khớp từ rowStack/filter hiện tại
//   với từng dòng trong phân vùng (partition) đã sắp xếp theo ORDERBY.

import ColumnStore

public enum WindowFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "ORDERBY",
                     params: [.lazy("orderBy_item", repeats: true)],
                     impl: .table(clauseStub("ORDERBY"))),
        FunctionSpec(name: "PARTITIONBY",
                     params: [.lazy("partition_item", repeats: true)],
                     impl: .table(clauseStub("PARTITIONBY"))),
        FunctionSpec(name: "OFFSET",
                     params: [.scalar("delta"), .table("relation", optional: true),
                              .lazy("orderBy", optional: true), .lazy("blanks", optional: true),
                              .lazy("partitionBy", optional: true)],
                     impl: .table(offsetBody)),
        FunctionSpec(name: "INDEX",
                     params: [.scalar("position"), .table("relation", optional: true),
                              .lazy("orderBy", optional: true), .lazy("blanks", optional: true),
                              .lazy("partitionBy", optional: true)],
                     impl: .table(indexBody)),
        FunctionSpec(name: "WINDOW",
                     params: [.scalar("from"), .keyword("from_type", ["ABS", "REL"]),
                              .scalar("to"), .keyword("to_type", ["ABS", "REL"]),
                              .table("relation", optional: true),
                              .lazy("orderBy", optional: true), .lazy("blanks", optional: true),
                              .lazy("partitionBy", optional: true)],
                     impl: .table(windowBody)),
    ]

    private static func clauseStub(_ name: String) -> FunctionSpec.TableBody {
        return { _ throws(DAXError) -> TableValue in
            throw DAXError(.runtime, "\(name) chỉ được dùng làm đối số bên trong OFFSET, INDEX hoặc WINDOW")
        }
    }

    // MARK: - OFFSET

    private static let offsetBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        let delta = Int((try frame.scalar(0).asDouble()).rounded(.towardZero))
        let resolved = try resolveWindow(frame, relationIndex: 1, clauseStart: 2)
        guard let cur = resolved.currentIndex else { return resolved.empty }
        let target = cur + delta
        guard target >= 0 && target < resolved.partitionIndices.count else { return resolved.empty }
        let rowIdx = resolved.partitionIndices[target]
        return TableValue(columns: resolved.source.columns, rows: [resolved.source.rows[rowIdx]], lineage: resolved.source.lineage)
    }

    // MARK: - INDEX

    private static let indexBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        let pos = Int((try frame.scalar(0).asDouble()).rounded(.towardZero))
        let resolved = try resolveWindow(frame, relationIndex: 1, clauseStart: 2)
        let count = resolved.partitionIndices.count
        guard count > 0, pos != 0 else { return resolved.empty }
        let idx = pos > 0 ? (pos - 1) : (count + pos)
        guard idx >= 0 && idx < count else { return resolved.empty }
        let rowIdx = resolved.partitionIndices[idx]
        return TableValue(columns: resolved.source.columns, rows: [resolved.source.rows[rowIdx]], lineage: resolved.source.lineage)
    }

    // MARK: - WINDOW

    private static let windowBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        let fromVal = Int((try frame.scalar(0).asDouble()).rounded(.towardZero))
        let fromType = frame.keyword(1)?.uppercased() ?? "REL"
        let toVal = Int((try frame.scalar(2).asDouble()).rounded(.towardZero))
        let toType = frame.keyword(3)?.uppercased() ?? "REL"
        let resolved = try resolveWindow(frame, relationIndex: 4, clauseStart: 5)
        let count = resolved.partitionIndices.count
        guard count > 0 else { return resolved.empty }

        func boundIndex(_ v: Int, _ kind: String, isStart: Bool) -> Int? {
            if kind == "ABS" {
                if v == 0 { return isStart ? 0 : -1 }
                return v > 0 ? (v - 1) : (count + v)
            } else {
                guard let cur = resolved.currentIndex else { return nil }
                return cur + v
            }
        }
        guard let rawLo = boundIndex(fromVal, fromType, isStart: true),
              let rawHi = boundIndex(toVal, toType, isStart: false) else { return resolved.empty }
        let lo = max(0, rawLo)
        let hi = min(count - 1, rawHi)
        guard lo <= hi else { return resolved.empty }
        var outRows: [[Value]] = []
        outRows.reserveCapacity(hi - lo + 1)
        for i in lo...hi {
            outRows.append(resolved.source.rows[resolved.partitionIndices[i]])
        }
        return TableValue(columns: resolved.source.columns, rows: outRows, lineage: resolved.source.lineage)
    }

    // MARK: - Lõi phân vùng, sắp xếp và xác định dòng hiện tại

    private struct ResolvedWindow {
        let source: TableValue
        let partitionIndices: [Int]
        let currentIndex: Int?
        var empty: TableValue { TableValue(columns: source.columns, rows: [], lineage: source.lineage) }
    }

    private static func resolveWindow(_ frame: CallFrame, relationIndex: Int, clauseStart: Int) throws(DAXError) -> ResolvedWindow {
        let evaluator = try fkEvaluator(frame)
        guard let relExpr = fkArg(frame, relationIndex) else {
            throw DAXError(.arity, "hàm cửa sổ cần đối số bảng relation")
        }
        let source = try evaluator.table(relExpr, in: frame.ctx)

        // Tách ORDERBY và PARTITIONBY trong các đối số sau relation
        var orderSpecs: [(expr: BoundExpr, desc: Bool)] = []
        var partitionExprs: [BoundExpr] = []
        for idx in clauseStart..<frame.args.count {
            guard let arg = frame.args[idx] else { continue }
            if case .call(let fid, let subArgs) = arg {
                let spec = try evaluator.specification(fid)
                if spec.name == "ORDERBY" {
                    var k = 0
                    while k < subArgs.count {
                        guard let item = subArgs[k] else { k += 1; continue }
                        if case .keyword(let w) = item, (w == "ASC" || w == "DESC"), !orderSpecs.isEmpty {
                            orderSpecs[orderSpecs.count - 1].desc = (w == "DESC")
                        } else {
                            orderSpecs.append((expr: item, desc: false))
                        }
                        k += 1
                    }
                } else if spec.name == "PARTITIONBY" {
                    for sub in subArgs { if let sub { partitionExprs.append(sub) } }
                }
            }
        }

        // Xác định giá trị hiện tại cho từng cột của `source` từ rowStack (ưu tiên) hoặc filterContext
        var currentColValues: [Int: Value] = [:]
        for colIdx in 0..<source.columns.count {
            if let v = try lookupCurrentValue(colIndex: colIdx, in: source, evaluator: evaluator, ctx: frame.ctx) {
                currentColValues[colIdx] = v
            }
        }

        // Tính khoá phân vùng & sắp xếp cho mỗi dòng của `source`
        var partKeys: [[Value]] = Array(repeating: [], count: source.rows.count)
        var orderKeys: [[Value]] = Array(repeating: [], count: source.rows.count)
        try evaluator.iterate(source, in: frame.ctx) { (inner: EvalContext) throws(DAXError) in
            guard let r = inner.row?.row else { return }
            if !partitionExprs.isEmpty {
                var pk: [Value] = []
                for pe in partitionExprs { pk.append(try evaluator.scalar(pe, in: inner)) }
                partKeys[r] = pk
            }
            if !orderSpecs.isEmpty {
                var ok: [Value] = []
                for os in orderSpecs { ok.append(try evaluator.scalar(os.expr, in: inner)) }
                orderKeys[r] = ok
            }
        }

        // Tìm dòng khớp ngữ cảnh hiện tại trong `source`
        let matchedRow: Int? = {
            guard !currentColValues.isEmpty else { return nil }
            for r in 0..<source.rows.count {
                var allMatch = true
                for (c, expected) in currentColValues {
                    if source.rows[r][c] != expected { allMatch = false; break }
                }
                if allMatch { return r }
            }
            return nil
        }()

        // Lọc các dòng thuộc cùng partition với dòng hiện tại (nếu có PARTITIONBY)
        var candidates = Array(0..<source.rows.count)
        if !partitionExprs.isEmpty {
            let targetPartKey: [Value]?
            if let mr = matchedRow {
                targetPartKey = partKeys[mr]
            } else {
                // Đánh giá partitionExprs trong ngữ cảnh hiện tại nếu không có row match trực tiếp
                var pk: [Value] = []
                for pe in partitionExprs { pk.append((try? evaluator.scalar(pe, in: frame.ctx)) ?? .blank) }
                targetPartKey = pk
            }
            if let tpk = targetPartKey {
                candidates = candidates.filter { partKeys[$0] == tpk }
            }
        }

        // Sắp xếp ổn định theo ORDERBY (hoặc theo mọi cột của source nếu không có ORDERBY)
        let descs = orderSpecs.map(\.desc)
        var sortFailure: DAXError?
        candidates.sort { a, b in
            do throws(DAXError) {
                let cmp: Int
                if !orderSpecs.isEmpty {
                    cmp = try fkCompareMultiKeys(orderKeys[a], orderKeys[b], descs: descs)
                } else {
                    cmp = try fkCompareMultiKeys(source.rows[a], source.rows[b], descs: Array(repeating: false, count: source.columns.count))
                }
                return cmp != 0 ? cmp < 0 : a < b
            } catch {
                sortFailure = sortFailure ?? error
                return a < b
            }
        }
        if let sortFailure { throw sortFailure }

        let currentPos = matchedRow.flatMap { mr in candidates.firstIndex(of: mr) }
        return ResolvedWindow(source: source, partitionIndices: candidates, currentIndex: currentPos)
    }

    private static func lookupCurrentValue(colIndex: Int, in source: TableValue, evaluator: Evaluator, ctx: EvalContext) throws(DAXError) -> Value? {
        let lineage = colIndex < source.lineage.count ? source.lineage[colIndex] : nil
        let rawName = source.columns[colIndex]
        let bareName = rawName.hasPrefix("[") && rawName.hasSuffix("]") ? String(rawName.dropFirst().dropLast()).lowercased() : rawName.lowercased()

        // 1. Tra trong rowStack hiện tại (từ trong ra ngoài)
        if ctx.row != nil {
            for frame in evaluator.rowStack.reversed() {
                switch frame {
                case .base(let tid, let r):
                    if let lid = lineage, lid.table == tid {
                        let data = try evaluator.columnData(lid)
                        return Value(stored: data.value(at: r))
                    }
                case .virtual(let tv, let r):
                    if let lid = lineage, let idx = tv.lineageIndex(of: lid) {
                        return tv.rows[r][idx]
                    }
                    if let idx = tv.columns.firstIndex(where: { c in
                        let lc = c.hasPrefix("[") && c.hasSuffix("]") ? String(c.dropFirst().dropLast()).lowercased() : c.lowercased()
                        return lc == bareName || c.lowercased() == rawName.lowercased()
                    }) {
                        return tv.rows[r][idx]
                    }
                }
            }
        }
        // 2. Tra trong filter context (khi chỉ còn đúng 1 giá trị thấy được của cột lineage)
        if let lid = lineage {
            let vals = try evaluator.visibleValues(of: lid, in: ctx)
            if vals.count == 1 { return vals[0] }
        }
        return nil
    }
}
