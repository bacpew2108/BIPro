// Hỗ trợ test CORE (đợt 2): môi trường đánh giá trên MiniBank và bộ hàm thử nghiệm.
//
// Các hàm SUM, COUNTROWS, VALUES, SUMX, AVERAGEX, FILTER, USERELATIONSHIP ở đây chỉ thay thân của hàm đã đăng ký
// (giữ nguyên tên, tham số và thứ tự), để test CORE không phụ thuộc F-KIT core đang làm song song.
// Khi F-KIT core được gộp, bỏ phần ghi đè này và chạy lại cùng các test. Tích hợp thật được làm sau khi gộp.
//
// SUM đếm số lần thân chạy (`CallCounter`), dùng cho test cache và test VAR lười.
import Foundation
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

/// Bộ đếm an toàn luồng, dùng để đếm số lần thân SUM chạy.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        stored += 1
    }
}

/// Môi trường đánh giá: store MiniBank, catalog (measure của MiniBank cộng thêm measure của test), evaluator.
struct CoreEnvironment {
    let store: ColumnStore
    let catalog: Catalog
    let cache: EngineCache
    let counter: CallCounter
    let evaluator: Evaluator

    init(extraMeasures: [ModelMeasureInput] = [], cache: EngineCache = EngineCache(),
         store: ColumnStore = MiniBank.makeStore()) {
        self.store = store
        self.cache = cache
        self.counter = CallCounter()
        let inputs = MiniBank.measures.map {
            ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression)
        } + extraMeasures
        self.catalog = Catalog(schema: MiniBank.schema, measures: inputs)
        self.evaluator = Evaluator(store: store, catalog: catalog, cache: cache,
                                   functions: coreTestFunctions(counter: counter))
    }

    /// Ngữ cảnh gốc: không lọc, có lược đồ để tính expanded table.
    var baseFilter: FilterContext {
        FilterContext.empty.bound(to: store.schema)
    }
}

/// Bộ hàm: giống `FunctionRegistry.all`, chỉ thay thân của các hàm thử nghiệm.
func coreTestFunctions(counter: CallCounter) -> [FunctionSpec] {
    let overrides: [String: FunctionSpec] = [
        "SUM": sumSpec(counter),
        "COUNTROWS": countRowsSpec,
        "VALUES": valuesSpec,
        "SUMX": sumxSpec,
        "AVERAGEX": averagexSpec,
        "FILTER": filterSpec,
        "USERELATIONSHIP": userRelationshipSpec,
    ]
    return FunctionRegistry.all.map { overrides[$0.name] ?? $0 }
}

/// Giá trị đọc được của cột trong môi trường (kiểm tra số liệu).
func evaluateText(_ text: String, in env: CoreEnvironment, filter: FilterContext? = nil,
                  row: RowContext? = nil) throws -> Value {
    let expr = try Binder.bind(try parseExpression(text), catalog: env.catalog)
    return try env.evaluator.scalar(expr, in: EvalContext(filter: filter ?? env.baseFilter, row: row))
}

/// Đánh giá một biểu thức bảng và trả bảng ảo.
func evaluateTableText(_ text: String, in env: CoreEnvironment) throws -> TableValue {
    let expr = try Binder.bind(try parseExpression(text), catalog: env.catalog)
    return try env.evaluator.table(expr, in: EvalContext(filter: env.baseFilter, row: nil))
}

/// Lấy số nguyên từ giá trị, nil nếu không phải số nguyên hoặc currency.
func integerValue(_ value: Value) -> Int64? {
    switch value {
    case .integer(let v): return v
    default: return nil
    }
}

// MARK: - Hàm thử nghiệm

private func sumSpec(_ counter: CallCounter) -> FunctionSpec {
    FunctionSpec(name: "SUM", params: [.column("column")], impl: .scalar { (frame: CallFrame) throws(DAXError) -> Value in
        counter.increment()
        let column = try frame.column(0)
        guard let store = frame.store else { throw DAXError(.runtime, "thiếu store") }
        let rows = try frame.ctx.filter.visibleRows(in: store, table: column.table, overrides: [])
        let data: ColumnData
        do {
            data = try store.column(column)
        } catch {
            throw DAXError(.runtime, "không đọc được cột: \(error)")
        }
        if rows.count == 0 { return .blank }
        var total: Value = .integer(0)
        var failure: DAXError?
        rows.forEach { r in
            guard failure == nil else { return }
            do throws(DAXError) {
                total = try Value.arithmetic(.add, total, Value(stored: data.value(at: r)))
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        return total
    })
}

private let countRowsSpec = FunctionSpec(name: "COUNTROWS", params: [.table("table", optional: true)],
                                          impl: .scalar { (frame: CallFrame) throws(DAXError) -> Value in
    var n = 0
    try frame.iterateArgument(0) { (_: EvalContext) throws(DAXError) in n += 1 }
    return .integer(Int64(n))
})

private let valuesSpec = FunctionSpec(name: "VALUES", params: [.tableOrColumn("tableOrColumnName")],
                                       impl: .table { (frame: CallFrame) throws(DAXError) -> TableValue in
    let column = try frame.column(0)
    guard let store = frame.store else { throw DAXError(.runtime, "thiếu store") }
    let values = try frame.ctx.filter.visibleValues(of: column, in: store)
    let name = store.schema.column(column)?.name ?? ""
    return TableValue.values(of: column, name: name, values: values)
})

private let sumxSpec = FunctionSpec(name: "SUMX", params: [.table("table"), .lazy("expression")],
                                     impl: .scalar { (frame: CallFrame) throws(DAXError) -> Value in
    var total: Value = .integer(0)
    try frame.iterateArgument(0) { (ctx: EvalContext) throws(DAXError) in
        let v = try frame.scalar(1, in: ctx)
        total = try Value.arithmetic(.add, total, v)
    }
    return total
})

private let averagexSpec = FunctionSpec(name: "AVERAGEX", params: [.table("table"), .lazy("expression")],
                                         impl: .scalar { (frame: CallFrame) throws(DAXError) -> Value in
    var total: Value = .integer(0)
    var n = 0
    try frame.iterateArgument(0) { (ctx: EvalContext) throws(DAXError) in
        let v = try frame.scalar(1, in: ctx)
        total = try Value.arithmetic(.add, total, v)
        n += 1
    }
    if n == 0 { return .blank }
    return try Value.arithmetic(.divide, total, .integer(Int64(n)))
})

private let filterSpec = FunctionSpec(name: "FILTER", params: [.table("table"), .lazy("filter")],
                                       impl: .table { (frame: CallFrame) throws(DAXError) -> TableValue in
    let source = try frame.table(0)
    var kept: [[Value]] = []
    try frame.iterate(source) { (ctx: EvalContext) throws(DAXError) in
        if try frame.scalar(1, in: ctx).asLogical(), let r = ctx.row?.row {
            kept.append(source.rows[r])
        }
    }
    return TableValue(columns: source.columns, rows: kept, lineage: source.lineage)
})

private let userRelationshipSpec = FunctionSpec(
    name: "USERELATIONSHIP", params: [.column("columnName1"), .column("columnName2")],
    impl: .modifier { (frame: CallFrame) throws(DAXError) -> [ContextModifier] in
        let a = try frame.column(0)
        let b = try frame.column(1)
        guard let store = frame.store else { throw DAXError(.runtime, "thiếu store") }
        guard let relationship = store.schema.relationships.first(where: {
            ($0.manyColumn == a && $0.oneColumn == b) || ($0.manyColumn == b && $0.oneColumn == a)
        }) else {
            throw DAXError(.ambiguousPath, "không có quan hệ giữa \(a) và \(b)")
        }
        return [.useRelationship(relationship.id)]
    })
