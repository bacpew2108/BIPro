// Tiện ích dùng chung cho test F-KIT (đợt 2). Bộ đánh giá thử nghiệm thay CORE, chỉ hiểu BoundExpr.literal.
import Testing
import ColumnStore
@testable import DAXEngine

/// Nhật ký các giá trị bộ đánh giá thử nghiệm đã trả về, theo thứ tự. Dùng để kiểm đánh giá lười.
final class FKNhatKy: @unchecked Sendable {
    var giaTri: [Value] = []
}

/// Bộ đánh giá thử nghiệm: chỉ hiểu `.literal`, mọi thứ khác báo lỗi .runtime.
struct FKDanhGia: Evaluating {
    let nhatKy: FKNhatKy

    func scalar(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> Value {
        guard case .literal(let v) = expr else {
            throw DAXError(.runtime, "FKDanhGia chỉ hiểu literal")
        }
        nhatKy.giaTri.append(v)
        return v
    }

    func table(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> TableValue {
        throw DAXError(.runtime, "FKDanhGia không hỗ trợ biểu thức bảng")
    }

    func column(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> ColumnID {
        throw DAXError(.runtime, "FKDanhGia không hỗ trợ cột")
    }

    func iterate(_ table: TableValue, in ctx: EvalContext,
                 _ body: (EvalContext) throws(DAXError) -> Void) throws(DAXError) {
        throw DAXError(.runtime, "FKDanhGia không hỗ trợ lặp")
    }
}

/// Đối số literal.
func fkLit(_ v: Value) -> BoundExpr? {
    BoundExpr.literal(v)
}

/// Gọi thân scalar của hàm `ten` với các đối số đã cho. Trả về giá trị hoặc lỗi DAX.
func fkChay(_ ten: String, _ doi: [BoundExpr?], nhatKy: FKNhatKy = FKNhatKy()) -> Result<Value, DAXError> {
    guard let spec = FunctionRegistry.byName[ten], case .scalar(let body) = spec.impl else {
        return .failure(DAXError(.unsupportedFunction, "không có hàm scalar \(ten)"))
    }
    let khung = CallFrame(args: doi, ctx: EvalContext(), eval: FKDanhGia(nhatKy: nhatKy))
    do {
        return .success(try body(khung))
    } catch {
        return .failure(error)
    }
}

/// Kết quả là số gần `mong` (sai số tương đối 1e-9). Không phải số thì trả false.
func fkKhopSo(_ r: Result<Value, DAXError>, _ mong: Double) -> Bool {
    guard case .success(let v) = r else { return false }
    let d: Double
    switch v {
    case .double(let x): d = x
    case .integer(let x): d = Double(x)
    case .currency(let x): d = Double(x) / 10_000
    default: return false
    }
    return abs(d - mong) <= 1e-9 * max(1, abs(mong))
}

/// Loại lỗi của kết quả nếu là lỗi, nil nếu thành công.
func fkLoi(_ r: Result<Value, DAXError>) -> DAXError.Kind? {
    if case .failure(let e) = r { return e.kind }
    return nil
}
