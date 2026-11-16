// Façade công khai của DAXEngine (lead). Từ đợt 2: execute và evaluate chạy thật; validate trả lỗi cú pháp.
import ColumnStore

public final class DAXEngine: Sendable {
    public let store: ColumnStore
    public let catalog: Catalog
    public let culture: String

    /// Engine cho model chỉ có cột (không có measure). Dùng cho test cột; measure của model cần `init(store:catalog:)`.
    public init(store: ColumnStore, culture: String = "en-US") {
        self.store = store
        self.catalog = Catalog(schema: store.schema)
        self.culture = culture
    }

    /// Engine đầy đủ: catalog gồm cả measure của model (ví dụ `Catalog(metadata:)`).
    public init(store: ColumnStore, catalog: Catalog, culture: String = "en-US") {
        self.store = store
        self.catalog = catalog
        self.culture = culture
    }

    /// Chạy một truy vấn DAX (DEFINE / EVALUATE / ORDER BY / START AT). Huỷ bằng Task.cancel().
    public func execute(_ query: String) async throws(DAXError) -> QueryResult {
        let parsed = try parseQuery(query)
        return try await QueryExecutor.execute(
            parsed,
            model: catalog,
            store: store,
            makeEvaluator: { Evaluator(store: self.store, catalog: $0) })
    }

    /// Đánh giá một measure dưới bộ lọc cho trước (dùng cho golden và CLI).
    /// `table` là bảng chủ của measure khi tên có thể trùng giữa các bảng.
    public func evaluate(measure: String, table: String?, filters: [FilterItem]) async throws(DAXError) -> Value {
        guard let found = catalog.measure(named: measure, table: table) else {
            throw DAXError(.unknownName, "không tìm thấy measure \"\(measure)\"")
        }
        let base = EvalContext(filter: FilterContext(items: filters).bound(to: catalog.schema), row: nil)
        let evaluator = Evaluator(store: store, catalog: catalog)
        return try evaluator.scalar(.measure(found.id), in: base)
    }

    /// Giá trị của cột tính toán `expression` trên bảng `table`, theo thứ tự dòng của bảng (Phase F, T081). Mỗi dòng đánh giá trong
    /// row context của chính dòng đó, bộ lọc rỗng (như Desktop tính cột khi làm mới), nên `RELATED`, `EARLIER`, `CALCULATE`
    /// (chuyển ngữ cảnh) dùng được.
    public func calculatedColumn(table: String, expression: String) throws(DAXError) -> [Value] {
        guard let schemaTable = store.schema.table(named: table) else {
            throw DAXError(.unknownName, "không tìm thấy bảng \"\(table)\"")
        }
        let bound = try Binder.bind(try parseExpression(expression), catalog: catalog)
        let evaluator = Evaluator(store: store, catalog: catalog)
        let rows: RowSet
        do { rows = try store.allRows(schemaTable.id) } catch { throw DAXError(.runtime, "không đọc được bảng \"\(table)\": \(error)") }
        var values: [Value] = []
        values.reserveCapacity(rows.count)
        try evaluator.iteratePhysical(schemaTable.id, rows, EvalContext()) { (ctx: EvalContext) throws(DAXError) in
            values.append(try evaluator.scalar(bound, in: ctx))
        }
        return values
    }

    /// Bảng tính toán: kết quả đầy đủ của biểu thức bảng `expression`, bộ lọc rỗng (Phase F, T081). Tên cột bỏ phần bảng
    /// (`'T'[Date]` → `Date`) như cột của bảng tính toán Desktop.
    public func calculatedTable(expression: String) throws(DAXError) -> ResultTable {
        let bound = try Binder.bind(try parseExpression(expression), catalog: catalog)
        let table = try Evaluator(store: store, catalog: catalog).table(bound, in: EvalContext())
        let names = table.columns.map { name -> String in
            guard name.hasSuffix("]"), let open = name.lastIndex(of: "[") else { return name }
            return String(name[name.index(after: open)..<name.index(before: name.endIndex)])
        }
        return ResultTable(columns: names, rows: table.rows)
    }

    /// Lỗi của một truy vấn cho editor (gạch chân): cú pháp, rồi lỗi tên và bind (cột, bảng, measure, hàm,
    /// số đối số). Không đánh giá gì nên nhanh và không chạm dữ liệu. Lỗi chỉ lộ ra khi chạy (kiểu, giá trị) không có ở đây.
    public func validate(_ expression: String) -> [DAXError] {
        do {
            let query = try parseQuery(expression)
            try QueryExecutor.check(query, model: catalog)
            return []
        } catch {
            return [error]
        }
    }
}
