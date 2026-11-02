// Hỗ trợ test cho bộ hàm lõi của F-KIT (đợt 2): SUM, COUNTROWS, VALUES, FILTER, RELATED, REMOVEFILTERS, KEEPFILTERS.
// Môi trường dùng `FunctionRegistry.all` thật (không thay thân hàm), nên test kiểm đúng bản đã cài.
// Đáp án MiniBank lấy từ MiniBankExpected (Python stdlib) và từ script đối chiếu độc lập.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

/// Môi trường đánh giá trên MiniBank: kho, catalog (có measure của MiniBank), evaluator riêng cho từng test.
struct FKCoreEnv {
    let store: ColumnStore
    let catalog: Catalog
    let evaluator: Evaluator

    /// Mặc định là MiniBank kèm measure của MiniBank. Với `schema` khác thì không có measure.
    init(store: ColumnStore = MiniBank.makeStore(), schema: ModelSchema? = nil) {
        self.store = store
        if let schema {
            self.catalog = Catalog(schema: schema, measures: [])
        } else {
            let inputs = MiniBank.measures.map {
                ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression)
            }
            self.catalog = Catalog(schema: MiniBank.schema, measures: inputs)
        }
        self.evaluator = Evaluator(store: store, catalog: catalog)
    }

    /// Môi trường cho kho nhỏ `FKCoreThu` (không có measure).
    static func thu(_ store: ColumnStore) -> FKCoreEnv {
        FKCoreEnv(store: store, schema: FKCoreThu.schema)
    }

    /// Ngữ cảnh gốc: không lọc, có lược đồ để tính expanded table.
    var base: FilterContext {
        FilterContext.empty.bound(to: store.schema)
    }

    /// Bộ lọc một cột (theo tên bảng và tên cột trong MiniBank).
    func filter(_ table: String, _ column: String, _ values: [Value]) throws -> FilterContext {
        guard let meta = store.schema.column(table: table, name: column) else {
            throw DAXError(.unknownName, "không có cột \(table)[\(column)]")
        }
        return FilterContext(items: [FilterItem(column: meta.id, values: values)]).bound(to: store.schema)
    }

    /// Đánh giá một biểu thức vô hướng (không row context).
    func value(_ text: String, filter: FilterContext? = nil) throws -> Value {
        let expr = try Binder.bind(try parseExpression(text), catalog: catalog)
        return try evaluator.scalar(expr, in: EvalContext(filter: filter ?? base, row: nil))
    }

    /// Đánh giá một biểu thức bảng (không row context).
    func table(_ text: String, filter: FilterContext? = nil) throws -> TableValue {
        let expr = try Binder.bind(try parseExpression(text), catalog: catalog)
        return try evaluator.table(expr, in: EvalContext(filter: filter ?? base, row: nil))
    }

    /// Số dòng của biểu thức bảng hoặc giá trị COUNTROWS, dùng để so với đáp án.
    func count(_ text: String, filter: FilterContext? = nil) throws -> Int64 {
        guard case .integer(let n) = try value(text, filter: filter) else {
            throw DAXError(.typeMismatch, "\(text) không trả về số nguyên")
        }
        return n
    }
}

/// Loại lỗi DAX của một lời gọi; nil nếu thành công.
func fkKindOf(_ body: () throws -> Value) -> DAXError.Kind? {
    do {
        _ = try body()
        return nil
    } catch let error as DAXError {
        return error.kind
    } catch {
        return nil
    }
}

/// Tập giá trị của cột (không thứ tự), để so với đáp án không phụ thuộc thứ tự sắp.
func fkTapGiaTri(_ table: TableValue) -> Set<Value> {
    Set(table.rows.map { $0[0] })
}

/// Chuỗi thấy được trong một cột bảng ảo (bỏ qua không phải chuỗi).
func fkChuoi(_ values: Set<Value>) -> Set<String> {
    Set(values.compactMap { value in
        if case .string(let s) = value { return s }
        return nil
    })
}

// MARK: - Kho thử nghiệm nhỏ: bảng "Thu" với BLANK, số thực, tràn Int64 và cột văn bản

enum FKCoreThu {
    static let bang = TableID(raw: 101)
    static let x = ColumnID(table: bang, index: 1)        // số nguyên, có BLANK ở dòng 2
    static let d = ColumnID(table: bang, index: 2)        // số thực: 1e16, 1, -1e16
    static let big = ColumnID(table: bang, index: 3)      // số nguyên: Int64.max, 1, 0 (tràn)
    static let tien = ColumnID(table: bang, index: 4)     // currency: 1,0; BLANK; 2,5
    static let chu = ColumnID(table: bang, index: 5)      // văn bản

    static let schema = ModelSchema(
        culture: "en-US",
        tables: [
            ModelSchema.Table(id: bang, name: "Thu", isHidden: false, isUserTable: true, isDateTable: false, columns: [
                ModelSchema.Column(id: x, name: "x", type: .integer, isCalculated: false, isHidden: false,
                                   isKey: false, sortByColumn: nil, formatString: nil),
                ModelSchema.Column(id: d, name: "d", type: .double, isCalculated: false, isHidden: false,
                                   isKey: false, sortByColumn: nil, formatString: nil),
                ModelSchema.Column(id: big, name: "big", type: .integer, isCalculated: false, isHidden: false,
                                   isKey: false, sortByColumn: nil, formatString: nil),
                ModelSchema.Column(id: tien, name: "tien", type: .currency, isCalculated: false, isHidden: false,
                                   isKey: false, sortByColumn: nil, formatString: nil),
                ModelSchema.Column(id: chu, name: "chu", type: .string, isCalculated: false, isHidden: false,
                                   isKey: false, sortByColumn: nil, formatString: nil),
            ]),
        ],
        relationships: [])

    static func store() -> ColumnStore {
        let source = InMemoryColumnSource(
            schema: schema,
            rowCounts: [bang: 3],
            columns: [
                x: ColumnBuilder.integers([1, nil, 3]),
                d: ColumnBuilder.doubles([1e16, 1.0, -1e16]),
                big: ColumnBuilder.integers([Int64.max, 1, 0]),
                tien: ColumnBuilder.currency([10_000, nil, 25_000]),
                chu: ColumnBuilder.strings(["a", "b", nil]),
            ])
        return ColumnStore(source: source)
    }
}
