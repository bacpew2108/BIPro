// Hàm toán (F-KIT, đợt 2). Chữ ký do lead khai báo ở đợt 0.
// INT làm tròn xuống; MOD có dấu theo số chia (docs/phase-b-research/architecture.md §5.5).
// [SUY ĐOÁN] ABS, INT, MOD, ROUND, FLOOR cho BLANK khi đối số là BLANK: kết quả BLANK, như phép số học (§5.5). Chờ oracle.
// [SUY ĐOÁN] Làm tròn đưa số về 15 chữ số có nghĩa trước khi làm tròn, để 2,675 làm tròn ra 2,68 (kiểu Excel). Chờ O15.

import Foundation

public enum MathFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "ABS", params: [.scalar("number")], impl: .scalar(MathFunctions.absBody)),
        FunctionSpec(name: "INT", params: [.scalar("number")], impl: .scalar(MathFunctions.intBody)),
        FunctionSpec(name: "MOD", params: [.scalar("number"), .scalar("divisor")],
                     impl: .scalar(MathFunctions.modBody)),
        FunctionSpec(name: "DIVIDE", params: [.scalar("numerator"), .scalar("denominator"),
                                              .scalar("alternateResult", optional: true)],
                     impl: .scalar(MathFunctions.divideBody)),
        FunctionSpec(name: "ROUND", params: [.scalar("number"), .scalar("num_digits")],
                     impl: .scalar(MathFunctions.roundBody)),
        FunctionSpec(name: "FLOOR", params: [.scalar("number"), .scalar("significance", optional: true)],
                     impl: .scalar(MathFunctions.floorBody)),
    ]

    // MARK: - Thân hàm

    /// ABS: giữ kiểu số (integer, currency); ngày thành số thực.
    static func absBody(_ frame: CallFrame) throws(DAXError) -> Value {
        guard let n = try numericOperand(of: try frame.scalar(0)) else { return .blank }
        switch n {
        case .integer(let x):
            if x == Int64.min { return .double(-Double(x)) }
            return .integer(abs(x))
        case .currency(let c):
            if c == Int64.min { return .double(-Double(c) / 10_000) }
            return .currency(abs(c))
        case .double(let d):
            return .double(abs(d))
        case .dateTime(let d):
            return .double(abs(d))                   // [SUY ĐOÁN] ngày thành số serial
        }
    }

    /// INT: làm tròn xuống (về phía âm vô cùng). INT(-4,5) = -5.
    static func intBody(_ frame: CallFrame) throws(DAXError) -> Value {
        guard let n = try numericOperand(of: try frame.scalar(0)) else { return .blank }
        switch n {
        case .integer:
            return n.asValue
        case .currency(let c):
            return .integer(chiLamVeAm(c, 10_000))   // đơn vị 10⁻⁴, chia lấy sàn để không mất chính xác
        case .double(let d), .dateTime(let d):
            return soNguyenHoacThuc(d.rounded(.down))
        }
    }

    /// MOD(n, d) = n − d × INT(n / d). Kết quả cùng dấu với số chia. Số chia 0 báo lỗi.
    static func modBody(_ frame: CallFrame) throws(DAXError) -> Value {
        guard let so = try numericOperand(of: try frame.scalar(0)),
              let chia = try numericOperand(of: try frame.scalar(1)) else { return .blank }
        if case .integer(let x) = so, case .integer(let y) = chia {
            guard y != 0 else { throw DAXError(.runtime, "MOD: số chia bằng 0") }
            if y == -1 { return .integer(0) }        // tránh Int64.min % -1 gây trap
            var du = x % y
            if du != 0 && (du < 0) != (y < 0) { du += y }
            return .integer(du)
        }
        let x = so.asDouble
        let y = chia.asDouble
        guard y != 0 else { throw DAXError(.runtime, "MOD: số chia bằng 0") }
        return .double(clean15Digits(x - y * (x / y).rounded(.down)))
    }

    /// DIVIDE: dùng Value.divide của VAL. Mẫu BLANK hoặc bằng 0 thì trả alternateResult (mặc định BLANK).
    static func divideBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let tu = try frame.scalar(0)
        let mau = try frame.scalar(1)
        var thayThe: Value = .blank
        if !frame.isBlankArgument(2) {
            thayThe = try frame.scalar(2)
        }
        return try Value.divide(tu, mau, alternate: thayThe)
    }

    /// ROUND: làm tròn nửa xa số 0 tới num_digits chữ số thập phân (âm là làm tròn tới hàng chục, trăm…).
    static func roundBody(_ frame: CallFrame) throws(DAXError) -> Value {
        guard let n = try numericOperand(of: try frame.scalar(0)) else { return .blank }
        let chuSo = try soNguyenCua(try frame.scalar(1), gioiHan: 300)
        let ketQua = lamTronNuaXa(n.asDouble, chuSo: chuSo)
        if case .integer = n {
            return soNguyenHoacThuc(ketQua)
        }
        return .double(ketQua)
    }

    /// FLOOR(n, significance): làm tròn về phía 0 tới bội số của significance (mặc định 1). FLOOR(-2,5; 2) = -2.
    static func floorBody(_ frame: CallFrame) throws(DAXError) -> Value {
        guard let n = try numericOperand(of: try frame.scalar(0)) else { return .blank }
        var boi: NumOperand = .integer(1)
        if !frame.isBlankArgument(1) {
            guard let s = try numericOperand(of: try frame.scalar(1)) else { return .blank }
            boi = s
        }
        if case .integer(let x) = n, case .integer(let s) = boi {
            if s == 0 { return .integer(0) }          // [SUY ĐOÁN] significance 0 cho 0
            if s < 0 { throw DAXError(.runtime, "FLOOR: significance không được âm") }   // [SUY ĐOÁN]
            return .integer((x / s) * s)              // chia cắt về 0 đúng nghĩa "về phía 0"
        }
        let x = n.asDouble
        let s = boi.asDouble
        if s == 0 { return .integer(0) }              // [SUY ĐOÁN]
        if s < 0 { throw DAXError(.runtime, "FLOOR: significance không được âm") }   // [SUY ĐOÁN]
        let thuong = clean15Digits(x / s)
        return .double(clean15Digits(thuong.rounded(.towardZero) * s))
    }
}

// MARK: - Tiện ích dùng chung trong F-KIT (internal, không công khai)

/// Đưa số về 15 chữ số có nghĩa, như cách hiển thị thông thường; khử sai số nhị phân nhỏ (0,3/0,1 ra 3, không ra 2,999…).
func clean15Digits(_ x: Double) -> Double {
    guard x.isFinite, x != 0 else { return x }
    return Double(String(format: "%.15g", x)) ?? x
}

/// Làm tròn nửa xa số 0 tới `chuSo` chữ số thập phân. Trả x nếu kết quả trung gian không hữu hạn.
func lamTronNuaXa(_ x: Double, chuSo: Int) -> Double {
    guard x.isFinite else { return x }
    let he = pow(10.0, Double(chuSo))
    guard he.isFinite, he > 0 else { return x }
    let nhanLen = clean15Digits(clean15Digits(x) * he)
    guard nhanLen.isFinite else { return x }
    return clean15Digits(nhanLen.rounded(.toNearestOrAwayFromZero) / he)
}

/// Số nguyên Int64 nếu đổi được không mất phần, không thì giữ dạng thực.
func soNguyenHoacThuc(_ d: Double) -> Value {
    guard d.isFinite, abs(d) < 9.0e18 else { return .double(d) }
    return .integer(Int64(d))
}

/// Chia lấy sàn cho số dương (làm tròn về âm vô cùng).
func chiLamVeAm(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}

/// Số nguyên từ một giá trị (cắt phần thập phân về 0), kẹp vào ±gioiHan. BLANK là 0.
func soNguyenCua(_ v: Value, gioiHan: Double = 1.0e9) throws(DAXError) -> Int {
    let d = try v.asDouble()
    guard !d.isNaN else { throw DAXError(.runtime, "giá trị số không hợp lệ (NaN)") }
    let kep = max(-gioiHan, min(gioiHan, d.rounded(.towardZero)))
    return Int(kep)
}
