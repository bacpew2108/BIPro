// Hỗ trợ test F-TABLE (đợt 3). Môi trường đánh giá trên MiniBank với `FunctionRegistry.all` thật (không thay thân hàm).
// Đáp án lấy từ script Python stdlib độc lập (scratchpad/oracle/ftable_oracle.py), đọc dữ liệu thô MiniBank.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

/// Môi trường đánh giá trên MiniBank, có evaluator riêng cho từng test (để đếm `materializedRowCount` đúng).
struct FTEnv {
    let store: ColumnStore
    let catalog: Catalog
    let evaluator: Evaluator

    init(store: ColumnStore = MiniBank.makeStore()) {
        self.store = store
        let inputs = MiniBank.measures.map {
            ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression)
        }
        self.catalog = Catalog(schema: MiniBank.schema, measures: inputs)
        self.evaluator = Evaluator(store: store, catalog: catalog)
    }

    /// Ngữ cảnh gốc: không lọc, có lược đồ để tính expanded table.
    var base: FilterContext {
        FilterContext.empty.bound(to: store.schema)
    }

    /// Đánh giá một biểu thức vô hướng (không row context).
    func value(_ text: String) throws -> Value {
        let expr = try Binder.bind(try parseExpression(text), catalog: catalog)
        return try evaluator.scalar(expr, in: EvalContext(filter: base, row: nil))
    }

    /// Đánh giá một biểu thức bảng (không row context).
    func table(_ text: String) throws -> TableValue {
        let expr = try Binder.bind(try parseExpression(text), catalog: catalog)
        return try evaluator.table(expr, in: EvalContext(filter: base, row: nil))
    }

    /// Số dòng của biểu thức bảng, qua COUNTROWS.
    func count(_ text: String) throws -> Int64 {
        guard case .integer(let n) = try value("COUNTROWS ( \(text) )") else {
            throw DAXError(.typeMismatch, "\(text) không đếm được")
        }
        return n
    }
}

/// Giá trị số nguyên của integer hoặc currency (đơn vị nguyên, currency đã nhân 10^4).
func ftSoNguyen(_ value: Value) -> Int64? {
    switch value {
    case .integer(let x): return x
    case .currency(let c): return c
    default: return nil
    }
}

/// Loại lỗi DAX của một lời gọi; nil nếu thành công.
func ftLoai(_ body: () throws -> Value) -> DAXError.Kind? {
    do {
        _ = try body()
        return nil
    } catch let error as DAXError {
        return error.kind
    } catch {
        return nil
    }
}

/// Tập chuỗi thấy được trong một cột bảng ảo (bỏ BLANK và giá trị không phải chuỗi).
func ftChuoi(_ values: [Value]) -> Set<String> {
    Set(values.compactMap { value in
        if case .string(let s) = value { return s }
        return nil
    })
}
