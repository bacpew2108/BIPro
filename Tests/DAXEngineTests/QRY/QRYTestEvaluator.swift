// Evaluator thử nghiệm cho test QRY (đợt 2). Không thay thế CORE: chỉ đủ để kiểm tra truy vấn trên MiniBank.
// - Measure của model "Trans Amount" và "Trans Count" được tính trực tiếp từ dữ liệu; measure DEFINE thì bind thân và đánh giá.
// - Hàm vô hướng gọi thân đã cài trong registry (BLANK, DIVIDE…). FILTER được cài tại đây vì hàm bảng của F-KIT chưa gộp.
// - `cancelOn`: khi tính measure có tên này, huỷ Task hiện tại (kiểm đường huỷ giữa chừng).
import ColumnStore
import DAXEngine
import DAXTestSupport

struct QRYTestEvaluator: Evaluating {
    let catalog: Catalog
    let store: ColumnStore
    var cancelOn: String? = nil

    // MARK: - Evaluating

    func scalar(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> Value {
        switch expr {
        case .literal(let value):
            return value
        case .column(let column):
            guard let row = ctx.row else {
                throw DAXError(.runtime, "cột \(column) cần row context")
            }
            return try cell(column, row: row.row)
        case .measure(let id):
            return try measure(id, ctx)
        case .unary(let op, let operand):
            return try Value.unary(op, try scalar(operand, in: ctx))
        case .binary(let op, let left, let right):
            let l = try scalar(left, in: ctx)
            let r = try scalar(right, in: ctx)
            switch op {
            case .add, .subtract, .multiply, .divide, .power:
                return try Value.arithmetic(op, l, r)
            case .equal, .strictEqual, .notEqual, .less, .greater, .lessEqual, .greaterEqual:
                return try Value.compare(op, l, r)
            case .and, .or:
                return try Value.logical(op, l, r)
            case .concat:
                return Value.concatenate(l, r)
            case .inSet:
                throw DAXError(.unsupportedFunction, "IN chưa có trong evaluator thử nghiệm")
            }
        case .call(let function, let args):
            let spec = FunctionRegistry.all[Int(function.raw)]
            guard case .scalar(let body) = spec.impl else {
                throw DAXError(.runtime, "\(spec.name) không phải hàm vô hướng")
            }
            return try body(CallFrame(args: args, ctx: ctx, eval: self))
        default:
            throw DAXError(.unsupportedFunction, "evaluator thử nghiệm chưa hỗ trợ biểu thức này")
        }
    }

    func table(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> TableValue {
        switch expr {
        case .table(let id):
            return try fullTable(id, ctx.filter)
        case .call(let function, let args):
            let spec = FunctionRegistry.all[Int(function.raw)]
            let frame = CallFrame(args: args, ctx: ctx, eval: self)
            if spec.name == "FILTER" {
                return try filterTable(frame)
            }
            guard case .table(let body) = spec.impl else {
                throw DAXError(.runtime, "\(spec.name) không phải hàm bảng")
            }
            return try body(frame)
        default:
            throw DAXError(.unsupportedFunction, "evaluator thử nghiệm chưa hỗ trợ bảng này")
        }
    }

    func column(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> ColumnID {
        guard case .column(let column) = expr else {
            throw DAXError(.expectedColumnRef, "cần tham chiếu cột")
        }
        return column
    }

    func iterate(_ table: TableValue, in ctx: EvalContext,
                 _ body: (EvalContext) throws(DAXError) -> Void) throws(DAXError) {
        throw DAXError(.unsupportedFunction, "evaluator thử nghiệm chưa hỗ trợ iterate")
    }

    // MARK: - Measure

    private func measure(_ id: MeasureID, _ ctx: EvalContext) throws(DAXError) -> Value {
        guard let measure = catalog.measure(id) else {
            throw DAXError(.unknownName, "không có measure \(id.raw)")
        }
        switch measure.origin {
        case .model:
            if cancelOn == measure.name {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            let rows = try ctx.filter.visibleRows(in: store, table: MiniBank.Tables.factTrans, overrides: [])
            switch measure.name {
            case "Trans Amount":
                var total: Int64 = 0
                for raw in rows.rows {
                    switch try cell(MiniBank.Columns.FactTrans.amount, row: Int(raw)) {
                    case .currency(let v), .integer(let v): total += v
                    default: break
                    }
                }
                return .currency(total)
            case "Trans Count":
                return .integer(Int64(rows.count))
            default:
                throw DAXError(.unsupportedFunction, "evaluator thử nghiệm không có measure \(measure.name)")
            }
        case .define:
            let body = try Binder.bindMeasure(id, catalog: catalog)
            return try scalar(body, in: ctx)
        case .defineColumn:
            throw DAXError(.unsupportedFunction, "COLUMN cần row context của evaluator CORE")
        }
    }

    // MARK: - Bảng

    private func fullTable(_ id: TableID, _ filter: FilterContext) throws(DAXError) -> TableValue {
        let rows = try filter.visibleRows(in: store, table: id, overrides: [])
        var kept: [Int] = []
        for raw in rows.rows {
            kept.append(Int(raw))
        }
        return try buildTable(id, rows: kept)
    }

    /// FILTER(T, điều kiện) với T là một bảng gốc; điều kiện được tính theo từng dòng.
    private func filterTable(_ frame: CallFrame) throws(DAXError) -> TableValue {
        guard let first = frame.args.first ?? nil, case .table(let id) = first else {
            throw DAXError(.unsupportedFunction, "FILTER thử nghiệm chỉ nhận một bảng gốc")
        }
        let rows = try frame.ctx.filter.visibleRows(in: store, table: id, overrides: [])
        let rowCount = try safe { try store.rowCount(id) }
        var kept: [Int] = []
        for raw in rows.rows {
            let r = Int(raw)
            if r >= rowCount { continue }
            let rowCtx = EvalContext(filter: frame.ctx.filter, row: RowContext(table: id, row: r))
            if case .boolean(true) = try frame.scalar(1, in: rowCtx) {
                kept.append(r)
            }
        }
        return try buildTable(id, rows: kept)
    }

    private func buildTable(_ id: TableID, rows: [Int]) throws(DAXError) -> TableValue {
        guard let table = catalog.schema.table(id) else {
            throw DAXError(.unknownName, "không có bảng \(id)")
        }
        var out: [[Value]] = []
        out.reserveCapacity(rows.count)
        for r in rows {
            var row: [Value] = []
            for column in table.columns {
                row.append(try cell(column.id, row: r))
            }
            out.append(row)
        }
        let lineage: [ColumnID?] = table.columns.map { $0.id }
        return TableValue(columns: table.columns.map { $0.name }, rows: out, lineage: lineage)
    }

    // MARK: - Ô

    /// Giá trị của cột tại dòng; dòng từ rowCount trở đi là blank row ảo (mọi cột BLANK).
    private func cell(_ column: ColumnID, row: Int) throws(DAXError) -> Value {
        let rowCount = try safe { try store.rowCount(column.table) }
        if row >= rowCount {
            return .blank
        }
        let data = try safe { try store.column(column) }
        return Value(stored: data.value(at: row))
    }

    private func safe<T>(_ body: () throws -> T) throws(DAXError) -> T {
        do {
            return try body()
        } catch let error as DAXError {
            throw error
        } catch {
            throw DAXError(.runtime, "\(error)")
        }
    }
}

// MARK: - Bộ dựng dùng chung

/// Catalog MiniBank với hai measure của model và kho cột dùng chung cho mọi test QRY.
let qryCatalog = Catalog(schema: MiniBank.schema, measures: [
    ModelMeasureInput(table: "Fact_Trans", name: "Trans Amount", expression: "SUM(Fact_Trans[amount])"),
    ModelMeasureInput(table: "Fact_Trans", name: "Trans Count", expression: "COUNTROWS(Fact_Trans)"),
])

let qryStore = MiniBank.makeStore()

/// Chạy một truy vấn bằng evaluator thử nghiệm.
func qryRun(_ text: String, options: QueryExecutor.Options = QueryExecutor.Options(),
            cancelOn: String? = nil) async throws(DAXError) -> QueryResult {
    let query = try parseQuery(text)
    return try await QueryExecutor.execute(
        query, model: qryCatalog, store: qryStore,
        makeEvaluator: { QRYTestEvaluator(catalog: $0, store: qryStore, cancelOn: cancelOn) },
        options: options)
}

/// Số thực của một giá trị số (tiền tệ đổi về đơn vị gốc), nil nếu không phải số.
func qrySo(_ value: Value) -> Double? {
    switch value {
    case .integer(let v): return Double(v)
    case .double(let v): return v
    case .currency(let v): return Double(v) / 10_000
    default: return nil
    }
}

/// Giá trị thành nhãn để so với bảng đáp án: BLANK, chuỗi, hoặc số nguyên.
func qryNhan(_ value: Value) -> String {
    switch value {
    case .blank: return "BLANK"
    case .string(let s): return s
    case .integer(let v): return "\(v)"
    default: return "\(value)"
    }
}

/// Lỗi DAX khi chạy truy vấn, nil nếu thành công.
func qryLoi(_ text: String) async -> DAXError? {
    do {
        _ = try await qryRun(text)
        return nil
    } catch {
        return error
    }
}
