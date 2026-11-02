// Hàm tổng hợp. Đợt 2 (F-KIT) cài SUM và COUNTROWS. Đợt 3 (F-AGG) cài AVERAGE, COUNT, DISTINCTCOUNT, MIN, MAX
// và FKAccumulator dùng chung cho AVERAGE, SUMX, AVERAGEX. Chữ ký do lead khai báo ở đợt 0.
//
// - SUM(cột): cộng các dòng thấy được của bảng chứa cột (R(T) của ngữ cảnh). BLANK bị bỏ qua. Không có giá trị
//   không BLANK nào thì BLANK. Số nguyên giữ Int64, currency giữ Int64 (đã nhân 10^4), số thực cộng Neumaier.
// - AVERAGE(cột): như SUM nhưng chia cho số giá trị không BLANK. Số nguyên ra số thực; currency ra currency
//   làm tròn về 10^-4 (nửa xa 0); số thực ra số thực.
// - COUNT(cột): đếm giá trị không BLANK của các dòng thấy được. Không có dòng nào thì 0.
// - DISTINCTCOUNT(cột): đếm giá trị khác nhau, BLANK thấy được tính là một giá trị. Không có dòng thì 0.
// - MIN, MAX(cột): giá trị nhỏ nhất/lớn nhất không BLANK. Cột mã hoá so theo thứ hạng sắp xếp của chỉ mục.
//   MIN, MAX(giá trị1, giá trị2): hai vô hướng; vế BLANK bị bỏ qua.
// - COUNTROWS(bảng): đếm R(T), không materialize. FILTER trên nguồn vật lý được đếm trực tiếp qua vị ngữ.
//   Không đối số: đếm dòng thấy được của bảng vật lý trong row context gần nhất.
//
// [SUY ĐOÁN] SUM trên cột văn bản, logic hoặc ngày báo .typeMismatch (theo kiểu cột, kể cả khi không có dòng).
// [SUY ĐOÁN] Tràn Int64 khi cộng số nguyên báo .runtime, không chuyển sang số thực.
// [SUY ĐOÁN] COUNTROWS() không đối số dùng bảng vật lý của row context gần nhất; bảng ảo báo lỗi.
// [SUY ĐOÁN] DISTINCTCOUNT tính BLANK thấy được là một giá trị; dòng BLANK ảo của bảng chiều được tính.
// [SUY ĐOÁN] AVERAGE/SUMX trên cột ngày hoặc văn bản báo .typeMismatch. Kiểu kết quả của FKAccumulator xem ở dưới.
import ColumnStore

/// Cộng Neumaier: bù sai số làm tròn khi cộng số thực (đúng cho các số cùng dấu lớn và nhỏ xen kẽ).
private struct FKNeumaier {
    private(set) var sum = 0.0
    private var compensation = 0.0

    mutating func add(_ x: Double) {
        let total = sum + x
        if abs(sum) >= abs(x) {
            compensation += (sum - total) + x
        } else {
            compensation += (x - total) + sum
        }
        sum = total
    }

    var value: Double { sum + compensation }
}

public enum AggregationFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "SUM", params: [.column("column")], impl: .scalar(sumBody)),
        FunctionSpec(name: "AVERAGE", params: [.column("column")], impl: .scalar(averageBody)),
        FunctionSpec(name: "COUNTROWS", params: [.table("table", optional: true)], impl: .scalar(countRowsBody)),
        FunctionSpec(name: "COUNT", params: [.column("column")], impl: .scalar(countBody)),
        FunctionSpec(name: "DISTINCTCOUNT", params: [.column("column")], impl: .scalar(distinctCountBody)),
        FunctionSpec(name: "MIN", params: [.columnOrScalar("column"), .scalar("value2", optional: true)],
                     impl: .scalar(extremeBody(wantMax: false))),
        FunctionSpec(name: "MAX", params: [.columnOrScalar("column"), .scalar("value2", optional: true)],
                     impl: .scalar(extremeBody(wantMax: true))),
    ]

    // MARK: SUM

    private static let sumBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let column = try frame.column(0)
        let evaluator = try fkEvaluator(frame)
        let store = evaluator.store
        let data = try evaluator.runtimeCall { try store.column(column) }
        let kind = data.type
        guard kind == .integer || kind == .currency || kind == .double else {
            let name = store.schema.column(column)?.name ?? "\(column)"
            throw DAXError(.typeMismatch, "SUM không hỗ trợ cột \(name) có kiểu \(kind)")
        }
        let rows = try evaluator.visibleRows(of: column.table, in: frame.ctx)

        var count = 0
        var integerTotal: Int64 = 0
        var realTotal = FKNeumaier()
        var overflow = false
        var mismatch = false
        rows.forEach { r in
            if overflow || mismatch { return }
            switch data.value(at: r) {
            case .blank:
                return
            case .integer(let v), .currency(let v):
                if kind == .double {
                    realTotal.add(Double(v))
                    count += 1
                    return
                }
                let step = integerTotal.addingReportingOverflow(v)
                if step.overflow {
                    overflow = true
                } else {
                    integerTotal = step.partialValue
                    count += 1
                }
            case .double(let d):
                guard kind == .double else {
                    mismatch = true
                    return
                }
                realTotal.add(d)
                count += 1
            default:
                mismatch = true
            }
        }
        if mismatch {
            throw DAXError(.typeMismatch, "SUM gặp giá trị không khớp kiểu của cột")
        }
        if overflow {
            throw DAXError(.runtime, "SUM tràn Int64")
        }
        if count == 0 { return .blank }
        switch kind {
        case .currency: return .currency(integerTotal)
        case .integer: return .integer(integerTotal)
        default: return .double(realTotal.value)
        }
    }

    // MARK: AVERAGE, COUNT, DISTINCTCOUNT, MIN, MAX (F-AGG đợt 3)

    /// Cột và tập dòng thấy được của bảng chứa cột (R(T) của ngữ cảnh gọi). Giá trị được đọc ở chỗ gọi.
    private static func visibleColumn(_ frame: CallFrame, _ column: ColumnID) throws(DAXError) -> (ColumnData, RowSet) {
        let evaluator = try fkEvaluator(frame)
        let data = try evaluator.columnData(column)
        let rows = try evaluator.visibleRows(of: column.table, in: frame.ctx)
        return (data, rows)
    }

    private static let averageBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let column = try frame.column(0)
        let (data, rows) = try visibleColumn(frame, column)
        guard data.type == .integer || data.type == .currency || data.type == .double else {
            let store = try fkEvaluator(frame).store
            let name = store.schema.column(column)?.name ?? "\(column)"
            throw DAXError(.typeMismatch, "AVERAGE không hỗ trợ cột \(name) có kiểu \(data.type)")
        }
        var acc = FKAccumulator()
        try fkForEachRow(rows) { (r: Int) throws(DAXError) in
            try acc.add(Value(stored: data.value(at: r)))
        }
        return try acc.average()
    }

    private static let countBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let column = try frame.column(0)
        let (data, rows) = try visibleColumn(frame, column)
        var n: Int64 = 0
        try fkForEachRow(rows) { (r: Int) throws(DAXError) in
            if !fkIsBlankRow(data, r) { n += 1 }
        }
        // Không có giá trị nào thì BLANK, không phải 0 (tài liệu DAX; khớp golden G1 ở năm không có dữ liệu).
        return n == 0 ? .blank : .integer(n)
    }

    private static let distinctCountBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let column = try frame.column(0)
        let (data, rows) = try visibleColumn(frame, column)
        if data.isEncoded {
            // Mã 0 là BLANK. Một dòng BLANK thấy được được tính là một giá trị khác biệt [SUY ĐOÁN].
            var codes = Set<Int>()
            try fkForEachRow(rows) { (r: Int) throws(DAXError) in
                codes.insert(data.code(atRow: r) ?? 0)
            }
            // Không có dòng thấy được thì BLANK (golden G1: Active Accounts ở năm không có giao dịch).
            return codes.isEmpty ? .blank : .integer(Int64(codes.count))
        }
        var values = Set<StoredValue>()
        try fkForEachRow(rows) { (r: Int) throws(DAXError) in
            values.insert(data.value(at: r))
        }
        return values.isEmpty ? .blank : .integer(Int64(values.count))
    }

    /// MIN hoặc MAX: cột (các dòng thấy được, BLANK bỏ qua) hoặc hai giá trị vô hướng.
    private static func extremeBody(wantMax: Bool) -> FunctionSpec.ScalarBody {
        return { (frame: CallFrame) throws(DAXError) -> Value in
            if case .column(let column)? = fkArg(frame, 0) {
                guard frame.isBlankArgument(1) else {
                    throw DAXError(.arity, "\(wantMax ? "MAX" : "MIN") với một cột chỉ nhận một đối số")
                }
                return try extremeOfColumn(frame, column, wantMax: wantMax)
            }
            guard !frame.isBlankArgument(0), !frame.isBlankArgument(1) else {
                throw DAXError(.arity, "\(wantMax ? "MAX" : "MIN") cần một cột hoặc hai giá trị")
            }
            let first = try frame.scalar(0)
            let second = try frame.scalar(1)
            // [SUY ĐOÁN] Vế BLANK bị bỏ qua: MIN(BLANK(), 5) = 5.
            return try fkPickExtreme(first.isBlank ? nil : first, second, wantMax: wantMax) ?? .blank
        }
    }

    /// Giá trị lớn nhất hoặc nhỏ nhất của cột trên các dòng thấy được. Không có thì BLANK.
    /// Cột mã hoá so theo thứ hạng sắp xếp của chỉ mục (không đọc từng giá trị); cột dense so theo `Value.compare`.
    private static func extremeOfColumn(_ frame: CallFrame, _ column: ColumnID, wantMax: Bool) throws(DAXError) -> Value {
        let evaluator = try fkEvaluator(frame)
        let (data, rows) = try visibleColumn(frame, column)
        if data.isEncoded {
            let index = try evaluator.columnIndex(column)
            var best: (code: Int, rank: Int)?
            try fkForEachRow(rows) { (r: Int) throws(DAXError) in
                let code = data.code(atRow: r) ?? 0
                guard code != 0, let rank = index.sortRank(ofCode: code) else { return }
                guard let current = best else {
                    best = (code, rank)
                    return
                }
                let better = wantMax ? rank > current.rank : rank < current.rank
                if better { best = (code, rank) }
            }
            guard let best, let stored = data.dictionaryValue(code: best.code) else { return .blank }
            return Value(stored: stored)
        }
        var best: Value?
        try fkForEachRow(rows) { (r: Int) throws(DAXError) in
            best = try fkPickExtreme(best, Value(stored: data.value(at: r)), wantMax: wantMax)
        }
        return best ?? .blank
    }

    // MARK: COUNTROWS

    private static let countRowsBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let evaluator = try fkEvaluator(frame)
        if frame.isBlankArgument(0) {
            guard let row = frame.ctx.row, row.table != Evaluator.virtualTable else {
                throw DAXError(.arity, "COUNTROWS() cần đối số bảng hoặc row context của một bảng vật lý")
            }
            return countValue(try evaluator.visibleRows(of: row.table, in: frame.ctx).count)
        }
        guard let expr = fkArg(frame, 0) else {
            throw DAXError(.arity, "COUNTROWS cần đối số bảng")
        }
        return countValue(try fkCountTable(expr, evaluator, frame.ctx))
    }

    /// COUNTROWS của bảng rỗng là BLANK, không phải 0 (tài liệu DAX).
    private static func countValue(_ n: Int) -> Value {
        n == 0 ? .blank : .integer(Int64(n))
    }

    /// Số dòng của biểu thức bảng. Nguồn vật lý và FILTER trên nguồn vật lý được đếm không materialize.
    private static func fkCountTable(_ expr: BoundExpr, _ evaluator: Evaluator,
                                     _ ctx: EvalContext) throws(DAXError) -> Int {
        if let physical = try fkPhysicalSource(expr, evaluator, ctx) {
            return physical.rows.count
        }
        if case .call(let fid, let args) = expr {
            let spec = try evaluator.specification(fid)
            if spec.name == "FILTER", let matches = try fkFilterMatches(args: args, evaluator: evaluator, ctx: ctx) {
                return matches.rows.count
            }
        }
        var n = 0
        try evaluator.iterateExpr(expr, in: ctx) { (_: EvalContext) throws(DAXError) in n += 1 }
        return n
    }
}

// MARK: - Tiện ích dùng chung cho AVERAGE, COUNT, MIN/MAX và các iterator (F-AGG đợt 3)

/// Gọi `body` với từng dòng của tập dòng. Lỗi của `body` dừng vòng lặp và được ném lại.
fileprivate func fkForEachRow(_ rows: RowSet, _ body: (Int) throws(DAXError) -> Void) throws(DAXError) {
    var failure: DAXError?
    rows.forEach { r in
        guard failure == nil else { return }
        do throws(DAXError) {
            try body(r)
        } catch {
            failure = error
        }
    }
    if let failure { throw failure }
}

/// BLANK của một dòng: mã 0 với cột mã hoá, `.blank` với cột dense (kể cả dòng BLANK ảo vượt số dòng).
fileprivate func fkIsBlankRow(_ data: ColumnData, _ row: Int) -> Bool {
    if data.isEncoded { return (data.code(atRow: row) ?? 0) == 0 }
    return data.value(at: row) == .blank
}

/// Lớn hơn (hoặc nhỏ hơn, khi `wantMax` là false) giữa `current` và `candidate`. BLANK bị bỏ qua.
/// Trả nil khi cả hai đều không có giá trị.
func fkPickExtreme(_ current: Value?, _ candidate: Value, wantMax: Bool) throws(DAXError) -> Value? {
    if candidate.isBlank { return current }
    guard let current else { return candidate }
    if case .boolean(true) = try Value.compare(wantMax ? .greater : .less, candidate, current) {
        return candidate
    }
    return current
}

/// a / b làm tròn về số nguyên, nửa xa 0. Yêu cầu b > 0.
func fkRoundedDivide(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    let r = a % b
    if r == 0 { return q }
    let magnitude = r < 0 ? -r : r
    // |r| >= b/2 (viết dạng không tràn): làm tròn ra xa 0.
    if magnitude >= b - magnitude {
        return a < 0 ? q - 1 : q + 1
    }
    return q
}

/// Tích luỹ số cho AVERAGE, SUMX và AVERAGEX. BLANK bị bỏ qua; giá trị không phải số báo .typeMismatch.
/// Kiểu kết quả [SUY ĐOÁN]: có số thực thì ra số thực; không có số thực nhưng có currency thì ra currency;
/// còn lại tổng là số nguyên, trung bình là số thực. Trung bình currency làm tròn về 10^-4, nửa xa 0.
struct FKAccumulator {
    private(set) var count = 0
    private var integers: Int64 = 0
    private var currencies: Int64 = 0
    private var reals = FKNeumaier()
    private var sawCurrency = false
    private var sawDouble = false

    mutating func add(_ value: Value) throws(DAXError) {
        switch value {
        case .blank:
            return
        case .integer(let v):
            let step = integers.addingReportingOverflow(v)
            guard !step.overflow else { throw DAXError(.runtime, "tổng số nguyên tràn Int64") }
            integers = step.partialValue
        case .currency(let v):
            sawCurrency = true
            let step = currencies.addingReportingOverflow(v)
            guard !step.overflow else { throw DAXError(.runtime, "tổng currency tràn Int64") }
            currencies = step.partialValue
        case .double(let d):
            sawDouble = true
            reals.add(d)
        case .string, .boolean, .dateTime:
            throw DAXError(.typeMismatch, "không cộng hoặc lấy trung bình được giá trị không phải số")
        }
        count += 1
    }

    /// Tổng đơn vị currency (×10^4) của mọi giá trị nguyên và currency. Tràn Int64 báo .runtime.
    private func currencyUnits() throws(DAXError) -> Int64 {
        let scaled = integers.multipliedReportingOverflow(by: 10_000)
        let total = scaled.partialValue.addingReportingOverflow(currencies)
        guard !scaled.overflow, !total.overflow else { throw DAXError(.runtime, "tổng currency tràn Int64") }
        return total.partialValue
    }

    private func realTotal() -> Double {
        var sum = reals
        sum.add(Double(integers))
        sum.add(Double(currencies) / 10_000)
        return sum.value
    }

    /// Tổng; BLANK khi không có giá trị nào.
    func total() throws(DAXError) -> Value {
        guard count > 0 else { return .blank }
        if sawDouble { return .double(realTotal()) }
        if sawCurrency { return .currency(try currencyUnits()) }
        return .integer(integers)
    }

    /// Trung bình; BLANK khi không có giá trị nào.
    func average() throws(DAXError) -> Value {
        guard count > 0 else { return .blank }
        if sawDouble { return .double(realTotal() / Double(count)) }
        if sawCurrency { return .currency(fkRoundedDivide(try currencyUnits(), Int64(count))) }
        return .double(Double(integers) / Double(count))
    }
}
