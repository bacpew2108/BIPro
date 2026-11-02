// Hỗ trợ test cho WP F-AGG (đợt 3): môi trường MiniBank và kho nhỏ "Kho" có BLANK, số thực, chuỗi và hoà nhau.
// Đáp án lấy từ Tests/DAXEngineTests/F-AGG/fagg_expected.py (Python 3 stdlib, đọc MiniBankData.swift),
// không tính bằng Swift. Kho nhỏ được dựng từ đúng các giá trị trong script Python.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

/// Môi trường đánh giá: kho, catalog, evaluator riêng cho từng test.
struct FAggEnv {
    let store: ColumnStore
    let catalog: Catalog
    let evaluator: Evaluator

    /// MiniBank kèm toàn bộ measure của MiniBank.
    static func minibank() -> FAggEnv {
        let inputs = MiniBank.measures.map {
            ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression)
        }
        return FAggEnv(store: MiniBank.makeStore(), schema: MiniBank.schema, measures: inputs)
    }

    /// Kho nhỏ "Kho" (xem `FAggKho`), không có measure.
    static func kho() -> FAggEnv {
        FAggEnv(store: FAggKho.store(), schema: FAggKho.schema, measures: [])
    }

    private init(store: ColumnStore, schema: ModelSchema, measures: [ModelMeasureInput]) {
        self.store = store
        self.catalog = Catalog(schema: schema, measures: measures)
        self.evaluator = Evaluator(store: store, catalog: catalog)
    }

    /// Ngữ cảnh gốc: không lọc, có lược đồ để tính expanded table.
    var base: FilterContext {
        FilterContext.empty.bound(to: store.schema)
    }

    /// Bộ lọc một cột theo tên bảng và tên cột.
    func filter(_ table: String, _ column: String, _ values: [Value]) throws -> FilterContext {
        guard let meta = store.schema.column(table: table, name: column) else {
            throw DAXError(.unknownName, "không có cột \(table)[\(column)]")
        }
        return FilterContext(items: [FilterItem(column: meta.id, values: values)]).bound(to: store.schema)
    }

    /// Đánh giá một biểu thức vô hướng (không row context). Không truyền `filter` thì không lọc.
    func value(_ text: String, filter: FilterContext? = nil) throws -> Value {
        let expr = try Binder.bind(try parseExpression(text), catalog: catalog)
        return try evaluator.scalar(expr, in: EvalContext(filter: filter ?? base, row: nil))
    }
}

/// Loại lỗi DAX của một lời gọi; nil nếu thành công hoặc lỗi không phải DAXError.
func fAggKindOf(_ body: () throws -> Value) -> DAXError.Kind? {
    do {
        _ = try body()
        return nil
    } catch let error as DAXError {
        return error.kind
    } catch {
        return nil
    }
}

/// Kho nhỏ "Kho" (bảng 201): 6 dòng, có BLANK ở mỗi cột, có giá trị hoà nhau và có số âm.
///   so    (số nguyên): 5, BLANK, 3, 5, 1, 7
///   tien  (currency):  1,0; 2,5; BLANK; 2,5; -0,5; 10,0
///   nhom  (chuỗi):     a, b, a, BLANK, c, b
///   thuc  (số thực):   1,5; 2,0; 2,5; 0,5; 4,0; -3,0
enum FAggKho {
    static let bang = TableID(raw: 201)
    static let so = ColumnID(table: bang, index: 1)
    static let tien = ColumnID(table: bang, index: 2)
    static let nhom = ColumnID(table: bang, index: 3)
    static let thuc = ColumnID(table: bang, index: 4)

    static let schema = ModelSchema(
        culture: "en-US",
        tables: [
            ModelSchema.Table(id: bang, name: "Kho", isHidden: false, isUserTable: true, isDateTable: false, columns: [
                ModelSchema.Column(id: so, name: "so", type: .integer, isCalculated: false, isHidden: false,
                                   isKey: false, sortByColumn: nil, formatString: nil),
                ModelSchema.Column(id: tien, name: "tien", type: .currency, isCalculated: false, isHidden: false,
                                   isKey: false, sortByColumn: nil, formatString: nil),
                ModelSchema.Column(id: nhom, name: "nhom", type: .string, isCalculated: false, isHidden: false,
                                   isKey: false, sortByColumn: nil, formatString: nil),
                ModelSchema.Column(id: thuc, name: "thuc", type: .double, isCalculated: false, isHidden: false,
                                   isKey: false, sortByColumn: nil, formatString: nil),
            ]),
        ],
        relationships: [])

    static func store() -> ColumnStore {
        let source = InMemoryColumnSource(
            schema: schema,
            rowCounts: [bang: 6],
            columns: [
                so: ColumnBuilder.integers([5, nil, 3, 5, 1, 7]),
                tien: ColumnBuilder.currency([10_000, 25_000, nil, 25_000, -5_000, 100_000]),
                nhom: ColumnBuilder.strings(["a", "b", "a", nil, "c", "b"]),
                thuc: ColumnBuilder.doubles([1.5, 2.0, 2.5, 0.5, 4.0, -3.0]),
            ])
        return ColumnStore(source: source)
    }
}
