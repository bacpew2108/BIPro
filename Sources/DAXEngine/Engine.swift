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
