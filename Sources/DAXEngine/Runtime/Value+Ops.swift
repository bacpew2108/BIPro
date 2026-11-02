// Ép kiểu, số học, so sánh, logic, nối chuỗi và BLANK của `Value` (VAL, đợt 1b).
// Quy tắc chính: docs/phase-b-research/architecture.md §5.5; so khớp oracle: docs/PHASE_B_PLAN.md §5.3.
// Chỗ tài liệu chưa chốt được ghi [SUY ĐOÁN] và chờ oracle (O1 lưới, O2 Copy, O15 làm tròn).
import Foundation

// MARK: - Toán hạng số đã ép

/// Toán hạng số sau khi ép kiểu. BLANK không nằm ở đây: BLANK được xử lý riêng theo từng phép toán.
enum NumOperand: Sendable {
    case integer(Int64)
    case double(Double)
    case currency(Int64)      // đã nhân 10⁴
    case dateTime(Double)     // số ngày kiểu OLE, ngày 0 là 1899-12-30

    var asDouble: Double {
        switch self {
        case .integer(let v): return Double(v)
        case .double(let v): return v
        case .currency(let v): return Double(v) / 10_000
        case .dateTime(let v): return v
        }
    }

    var asValue: Value {
        switch self {
        case .integer(let v): return .integer(v)
        case .double(let v): return .double(v)
        case .currency(let v): return .currency(v)
        case .dateTime(let v): return .dateTime(v)
        }
    }
}

/// Đọc chuỗi như số thập phân en-US: `[+-]? chữ số (. chữ số)? ([eE] [+-]? chữ số)?`, bỏ khoảng trắng hai đầu.
/// Không nhận `NaN`, `Infinity`, dấu phẩy ngăn nghìn hay ký hiệu tiền tệ. Trả nil nếu không đọc được.
func parseDAXNumber(_ text: String) -> NumOperand? {
    let bytes = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    func isDigit(_ b: UInt8) -> Bool { b >= 48 && b <= 57 }
    var i = 0
    if i < bytes.count && (bytes[i] == 43 || bytes[i] == 45) { i += 1 }     // + -
    var digits = 0
    while i < bytes.count && isDigit(bytes[i]) { i += 1; digits += 1 }
    var integral = true
    if i < bytes.count && bytes[i] == 46 {                                  // .
        integral = false
        i += 1
        while i < bytes.count && isDigit(bytes[i]) { i += 1; digits += 1 }
    }
    guard digits > 0 else { return nil }
    if i < bytes.count && (bytes[i] == 101 || bytes[i] == 69) {            // e E
        integral = false
        i += 1
        if i < bytes.count && (bytes[i] == 43 || bytes[i] == 45) { i += 1 }
        var expDigits = 0
        while i < bytes.count && isDigit(bytes[i]) { i += 1; expDigits += 1 }
        guard expDigits > 0 else { return nil }
    }
    guard i == bytes.count else { return nil }
    let s = String(decoding: bytes, as: UTF8.self)
    if integral, let v = Int64(s) { return .integer(v) }
    guard let d = Double(s) else { return nil }
    return .double(d)
}

/// Toán hạng số của một giá trị không phải BLANK. Chuỗi không đọc được thì báo `.typeMismatch`.
/// TRUE/FALSE thành 1/0 [SUY ĐOÁN: DAX coi boolean là số trong phép số học].
func numericOperand(of value: Value) throws(DAXError) -> NumOperand? {
    switch value {
    case .blank: return nil
    case .integer(let v): return .integer(v)
    case .double(let v): return .double(v)
    case .currency(let v): return .currency(v)
    case .dateTime(let v): return .dateTime(v)
    case .boolean(let b): return .integer(b ? 1 : 0)
    case .string(let s):
        guard let n = parseDAXNumber(s) else {
            throw DAXError(.typeMismatch, "Cannot convert value '\(s)' of type Text to type Number.")
        }
        return n
    }
}

/// Toán hạng số không ném lỗi, dùng khi kiểu đã được xác định là số hoặc boolean. Trả nil với BLANK và chuỗi.
func plainNumber(of value: Value) -> NumOperand? {
    switch value {
    case .integer(let v): return .integer(v)
    case .double(let v): return .double(v)
    case .currency(let v): return .currency(v)
    case .dateTime(let v): return .dateTime(v)
    case .boolean(let b): return .integer(b ? 1 : 0)
    case .blank, .string: return nil
    }
}

/// Chuỗi hiển thị cho NaN và ±∞. [SUY ĐOÁN, chờ O1: chưa quan sát Power BI hiển thị thế nào.]
func nonFiniteText(_ d: Double) -> String {
    if d.isNaN { return "NaN" }
    return d > 0 ? "∞" : "-∞"
}

/// Số đơn vị currency (×10⁴) của toán hạng nguyên hoặc currency. Nil nếu tràn Int64 hoặc là số thực.
private func currencyUnits(_ n: NumOperand) -> Int64? {
    switch n {
    case .currency(let c): return c
    case .integer(let i):
        let r = i.multipliedReportingOverflow(by: 10_000)
        return r.overflow ? nil : r.partialValue
    case .double, .dateTime: return nil
    }
}

/// Kết quả so sánh; `.unordered` khi có NaN.
private enum CmpResult: Sendable {
    case less, equal, greater, unordered
}

private func compareValues<T: Comparable>(_ x: T, _ y: T) -> CmpResult {
    if x < y { return .less }
    if x > y { return .greater }
    return .equal
}

/// So hai số. Nguyên với nguyên và currency với currency/nguyên được so chính xác; còn lại so theo Double.
private func numericOrder(_ a: NumOperand, _ b: NumOperand) -> CmpResult {
    switch (a, b) {
    case (.integer(let x), .integer(let y)): return compareValues(x, y)
    case (.currency(let x), .currency(let y)): return compareValues(x, y)
    case (.currency(let x), .integer):
        if let s = currencyUnits(b) { return compareValues(x, s) }
    case (.integer, .currency(let y)):
        if let s = currencyUnits(a) { return compareValues(s, y) }
    default:
        break
    }
    let x = a.asDouble, y = b.asDouble
    if x.isNaN || y.isNaN { return .unordered }
    return compareValues(x, y)
}

/// So chuỗi theo không phân biệt hoa thường. [SUY ĐOÁN: chưa đối chiếu collation của model.]
private func textOrder(_ a: String, _ b: String) -> CmpResult {
    let x = a.lowercased(), y = b.lowercased()
    if x == y { return .equal }
    return x.unicodeScalars.lexicographicallyPrecedes(y.unicodeScalars) ? .less : .greater
}

/// Giá trị thay cho BLANK khi so với vế kia: "" với chuỗi, FALSE với boolean, 0 với số và ngày.
private func blankStandIn(for other: Value) -> Value {
    switch other {
    case .string: return .string("")
    case .boolean: return .boolean(false)
    default: return .integer(0)
    }
}

/// Ngày OLE thành "M/d/yyyy h:mm:ss AM" theo en-US, giờ UTC. [SUY ĐOÁN, chờ O2: định dạng khi Copy.]
private func dateTimeText(_ serial: Double) -> String {
    guard serial.isFinite else { return nonFiniteText(serial) }
    // 25569 là số ngày từ 1899-12-30 đến 1970-01-01.
    let ms = ((serial - 25_569) * 86_400_000).rounded()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    let date = Date(timeIntervalSince1970: ms / 1000)
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let hour = c.hour ?? 0
    let hour12 = hour % 12 == 0 ? 12 : hour % 12
    func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    return "\(c.month ?? 0)/\(c.day ?? 0)/\(c.year ?? 0) \(hour12):\(two(c.minute ?? 0)):\(two(c.second ?? 0)) \(hour < 12 ? "AM" : "PM")"
}

// MARK: - API công khai

extension Value {

    /// `true` chỉ khi giá trị là BLANK. ISBLANK(0) là FALSE.
    public var isBlank: Bool {
        if case .blank = self { return true }
        return false
    }

    /// Tên kiểu theo cách DAX hiển thị trong thông báo lỗi. [SUY ĐOÁN: chỉ "Text" và "Integer" lấy từ thông điệp mẫu của đặc tả.]
    var daxTypeName: String {
        switch self {
        case .blank: return "BLANK"
        case .integer: return "Integer"
        case .double: return "Decimal"
        case .currency: return "Fixed Decimal"
        case .string: return "Text"
        case .boolean: return "True/False"
        case .dateTime: return "DateTime"
        }
    }

    /// Ép sang logic cho && || NOT. BLANK là FALSE; số khác 0 là TRUE; chuỗi "TRUE"/"FALSE" (không phân biệt hoa thường) được chấp nhận.
    /// [SUY ĐOÁN: số thành logic và chuỗi thành logic chưa có oracle.]
    public func asLogical() throws(DAXError) -> Bool {
        switch self {
        case .blank: return false
        case .boolean(let b): return b
        case .integer(let v): return v != 0
        case .double(let d): return d != 0
        case .currency(let c): return c != 0
        case .dateTime(let d): return d != 0
        case .string(let s):
            switch s.uppercased() {
            case "TRUE": return true
            case "FALSE": return false
            default:
                throw DAXError(.typeMismatch, "Cannot convert value '\(s)' of type Text to type True/False.")
            }
        }
    }

    /// Ép sang số thực cho hàm toán (F-KIT). BLANK là 0; chuỗi phải đọc được như số.
    public func asDouble() throws(DAXError) -> Double {
        guard let n = try numericOperand(of: self) else { return 0 }
        return n.asDouble
    }

    /// Ép sang chuỗi cho toán tử & và hàm văn bản. BLANK là "". Số dùng dạng thập phân không ký hiệu mũ, tối đa 15 chữ số có nghĩa.
    /// [SUY ĐOÁN: chưa đối chiếu với Power BI, đặc biệt số rất lớn/nhỏ và ngày.]
    public func asText() -> String {
        switch self {
        case .blank: return ""
        case .string(let s): return s
        case .boolean(let b): return b ? "TRUE" : "FALSE"
        case .integer(let v): return String(v)
        case .currency(let c):
            let text = DecimalText(currencyRaw: c).plainString
            return c < 0 && text != "0" ? "-" + text : text
        case .double(let d):
            guard d.isFinite else { return nonFiniteText(d) }
            let text = DecimalText(magnitudeOf: abs(d)).plainString
            return d < 0 && text != "0" ? "-" + text : text
        case .dateTime(let d): return dateTimeText(d)
        }
    }

    /// Số học: `+ - * / ^`. `/` và `^` luôn ra số thực. Quy tắc BLANK và ép kiểu theo architecture.md §5.5.
    public static func arithmetic(_ op: BinaryOp, _ lhs: Value, _ rhs: Value) throws(DAXError) -> Value {
        let a = try numericOperand(of: lhs)
        let b = try numericOperand(of: rhs)
        switch op {
        case .add:
            return addSub(a, b, subtract: false)
        case .subtract:
            return addSub(a, b, subtract: true)
        case .multiply:
            guard let a, let b else { return .blank }           // BLANK × x = BLANK
            return multiply(a, b)
        case .divide:
            guard let a else { return .blank }                  // BLANK / x = BLANK
            return .double(a.asDouble / (b?.asDouble ?? 0))     // x / BLANK coi BLANK là 0: ±∞ hoặc NaN, không báo lỗi
        case .power:
            // [SUY ĐOÁN] Lũy thừa: BLANK ở một trong hai vế cho BLANK, giống phép nhân.
            guard let a, let b else { return .blank }
            return .double(pow(a.asDouble, b.asDouble))
        default:
            throw DAXError(.runtime, "toán tử \(op.rawValue) không phải toán tử số học")
        }
    }

    /// Toán tử một ngôi: `-`, `+`, `NOT`.
    public static func unary(_ op: UnaryOp, _ value: Value) throws(DAXError) -> Value {
        switch op {
        case .not:
            let b = try value.asLogical()
            return .boolean(!b)
        case .plus:
            guard let n = try numericOperand(of: value) else { return .blank }
            return n.asValue
        case .negate:
            // [SUY ĐOÁN] -BLANK là BLANK, giống phép nhân với -1.
            guard let n = try numericOperand(of: value) else { return .blank }
            switch n {
            case .integer(let v):
                let r = (0 as Int64).subtractingReportingOverflow(v)
                return r.overflow ? .double(-Double(v)) : .integer(r.partialValue)
            case .double(let d): return .double(-d)
            case .currency(let c):
                let r = (0 as Int64).subtractingReportingOverflow(c)
                return r.overflow ? .double(-Double(c) / 10_000) : .currency(r.partialValue)
            case .dateTime(let d): return .double(-d)   // [SUY ĐOÁN]
            }
        }
    }

    /// So sánh: `= == <> < > <= >=`. Trả `.boolean`. Quy tắc BLANK và lỗi kiểu theo architecture.md §5.5.
    /// Chuỗi với số báo `.typeMismatch` với thông điệp của DAX (trừ `==`, xem bên dưới).
    public static func compare(_ op: BinaryOp, _ lhs: Value, _ rhs: Value) throws(DAXError) -> Value {
        if op == .strictEqual {
            return .boolean(strictlyEqual(lhs, rhs))
        }
        let ord = try ordering(lhs, rhs)
        switch op {
        case .equal: return .boolean(ord == .equal)
        case .notEqual: return .boolean(ord != .equal)            // NaN <> x là TRUE
        case .less: return .boolean(ord == .less)
        case .greater: return .boolean(ord == .greater)
        case .lessEqual: return .boolean(ord == .less || ord == .equal)
        case .greaterEqual: return .boolean(ord == .greater || ord == .equal)
        default:
            throw DAXError(.runtime, "toán tử \(op.rawValue) không phải toán tử so sánh")
        }
    }

    /// `&&` và `||`. BLANK là FALSE (BLANK && TRUE là FALSE; BLANK || TRUE là TRUE).
    public static func logical(_ op: BinaryOp, _ lhs: Value, _ rhs: Value) throws(DAXError) -> Value {
        let a = try lhs.asLogical()
        let b = try rhs.asLogical()
        switch op {
        case .and: return .boolean(a && b)
        case .or: return .boolean(a || b)
        default: throw DAXError(.runtime, "toán tử \(op.rawValue) không phải toán tử logic")
        }
    }

    /// Toán tử `&`: nối hai vế sau khi ép sang chuỗi. BLANK thành "".
    public static func concatenate(_ lhs: Value, _ rhs: Value) -> Value {
        .string(lhs.asText() + rhs.asText())
    }

    /// DIVIDE(a, b[, alt]). Trả `alternate` (mặc định BLANK) khi b là BLANK hoặc b = 0, không báo lỗi.
    /// Các trường hợp khác dùng `/`. Helper này để F-KIT gọi trong thân hàm DIVIDE.
    public static func divide(_ numerator: Value, _ denominator: Value, alternate: Value = .blank) throws(DAXError) -> Value {
        if denominator.isBlank { return alternate }
        let d = try denominator.asDouble()
        if d == 0 { return alternate }
        return try arithmetic(.divide, numerator, denominator)
    }

    // MARK: - Nội bộ

    fileprivate static func addSub(_ lhs: NumOperand?, _ rhs: NumOperand?, subtract: Bool) -> Value {
        if lhs == nil && rhs == nil { return .blank }
        // BLANK ± x: BLANK coi như 0 (BLANK + 5 = 5, BLANK - 5 = -5).
        let a = lhs ?? .integer(0)
        let b = rhs ?? .integer(0)
        switch (a, b) {
        case (.dateTime(let x), .dateTime(let y)):
            return .double(subtract ? x - y : x + y)                          // [SUY ĐOÁN]
        case (.dateTime(let x), _):
            return .dateTime(subtract ? x - b.asDouble : x + b.asDouble)      // ngày ± số ngày là ngày
        case (_, .dateTime(let y)):
            return subtract ? .double(a.asDouble - y) : .dateTime(a.asDouble + y)   // [SUY ĐOÁN]
        case (.double, _), (_, .double):
            return .double(subtract ? a.asDouble - b.asDouble : a.asDouble + b.asDouble)
        case (.currency, _), (_, .currency):
            if let x = currencyUnits(a), let y = currencyUnits(b) {
                let r = subtract ? x.subtractingReportingOverflow(y) : x.addingReportingOverflow(y)
                if !r.overflow { return .currency(r.partialValue) }
            }
            return .double(subtract ? a.asDouble - b.asDouble : a.asDouble + b.asDouble)  // [SUY ĐOÁN] tràn thì ra số thực
        case (.integer(let x), .integer(let y)):
            let r = subtract ? x.subtractingReportingOverflow(y) : x.addingReportingOverflow(y)
            if !r.overflow { return .integer(r.partialValue) }
            return .double(subtract ? Double(x) - Double(y) : Double(x) + Double(y))   // [SUY ĐOÁN] tràn thì ra số thực
        }
    }

    fileprivate static func multiply(_ a: NumOperand, _ b: NumOperand) -> Value {
        switch (a, b) {
        case (.double, _), (_, .double), (.dateTime, _), (_, .dateTime):
            return .double(a.asDouble * b.asDouble)                           // [SUY ĐOÁN] ngày nhân số ra số thực
        case (.currency(let c), .integer(let n)), (.integer(let n), .currency(let c)):
            let r = c.multipliedReportingOverflow(by: n)
            return r.overflow ? .double(a.asDouble * b.asDouble) : .currency(r.partialValue)
        case (.currency(let c1), .currency(let c2)):
            // [SUY ĐOÁN] currency × currency: giữ thang 10⁴ bằng cách chia 10⁴, làm tròn tới đơn vị 10⁻⁴.
            let raw = (Double(c1) * Double(c2) / 10_000).rounded()
            if abs(raw) < 9.0e18 { return .currency(Int64(raw)) }
            return .double(a.asDouble * b.asDouble)
        case (.integer(let x), .integer(let y)):
            let r = x.multipliedReportingOverflow(by: y)
            return r.overflow ? .double(Double(x) * Double(y)) : .integer(r.partialValue)   // [SUY ĐOÁN] tràn thì ra số thực
        }
    }

    /// `=` (và `==` không dùng hàm này). Trả thứ tự, hoặc `.unordered` khi có NaN.
    fileprivate static func ordering(_ lhs: Value, _ rhs: Value) throws(DAXError) -> CmpResult {
        if lhs.isBlank && rhs.isBlank { return .equal }
        let l = lhs.isBlank ? blankStandIn(for: rhs) : lhs
        let r = rhs.isBlank ? blankStandIn(for: lhs) : rhs
        switch (l, r) {
        case (.string(let a), .string(let b)):
            return textOrder(a, b)
        case (.boolean(let a), .boolean(let b)):
            return a == b ? .equal : (a ? .greater : .less)
        default:
            break
        }
        if case .string = l { throw mismatch(l, r) }
        if case .string = r { throw mismatch(l, r) }
        guard let a = plainNumber(of: l), let b = plainNumber(of: r) else { return .unordered }
        return numericOrder(a, b)
    }

    /// `==`: không ép BLANK (BLANK == 0 là FALSE), và khác nhóm kiểu thì không bằng, không báo lỗi.
    /// [SUY ĐOÁN: hành vi của `==` chưa có oracle.]
    fileprivate static func strictlyEqual(_ lhs: Value, _ rhs: Value) -> Bool {
        switch (lhs, rhs) {
        case (.blank, .blank): return true
        case (.blank, _), (_, .blank): return false
        case (.string(let a), .string(let b)): return textOrder(a, b) == .equal
        case (.boolean(let a), .boolean(let b)): return a == b
        case (.string, _), (_, .string), (.boolean, _), (_, .boolean): return false
        default:
            guard let a = plainNumber(of: lhs), let b = plainNumber(of: rhs) else { return false }
            return numericOrder(a, b) == .equal
        }
    }

    private static func mismatch(_ l: Value, _ r: Value) -> DAXError {
        DAXError(.typeMismatch,
                 "DAX comparison operations do not support comparing values of type \(l.daxTypeName) with values of type \(r.daxTypeName)")
    }
}
