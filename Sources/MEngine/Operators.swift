// Phase F (T049): toán tử của M. Ngữ nghĩa theo tài liệu ngôn ngữ; điểm chưa đối chiếu Desktop (VM-F3) ghi [SUY ĐOÁN].

import ColumnStore

enum MOperators {
    static func invalid(_ op: String, _ a: MValue, _ b: MValue? = nil) -> MError {
        if let b { return MError.expression("Không thể áp dụng toán tử \(op) cho kiểu \(a.kindName) và \(b.kindName)") }
        return MError.expression("Không thể áp dụng toán tử \(op) cho kiểu \(a.kindName)")
    }

    static func number(_ v: MValue) -> Double? {
        switch v {
        case .number(let d): d
        case .currency(let c): Double(c) / 10_000
        default: nil
        }
    }

    static func apply(_ op: MBinaryOp, _ a: MValue, _ b: MValue) throws -> MValue {
        switch op {
        case .equal: return .logical(equals(a, b))
        case .notEqual: return .logical(!equals(a, b))
        case .less, .greater, .lessOrEqual, .greaterOrEqual:
            // [SUY ĐOÁN] so sánh có `null` cho `null` (tài liệu M); kiểm ở VM-F3.
            if case .null = a { return .null }
            if case .null = b { return .null }
            guard let order = compare(a, b) else { throw invalid(op.rawValue, a, b) }
            let result: Bool
            switch op {
            case .less: result = order < 0
            case .greater: result = order > 0
            case .lessOrEqual: result = order <= 0
            default: result = order >= 0
            }
            return .logical(result)
        case .add, .subtract, .multiply, .divide:
            if case .null = a { return .null }
            if case .null = b { return .null }
            return try arithmetic(op, a, b)
        case .concat:
            if case .null = a { return .null }
            if case .null = b { return .null }
            switch (a, b) {
            case (.text(let x), .text(let y)): return .text(x + y)
            case (.list(let x), .list(let y)): return .list(x + y)
            case (.record(let x), .record(let y)):
                var merged = x
                for field in y {
                    if let i = merged.firstIndex(where: { $0.name == field.name }) { merged[i] = field } else { merged.append(field) }
                }
                return .record(merged)
            default: throw invalid("&", a, b)
            }
        case .and, .or:
            throw MError.expression("Toán tử logic được xử lý ở bộ đánh giá")
        }
    }

    private static func arithmetic(_ op: MBinaryOp, _ a: MValue, _ b: MValue) throws -> MValue {
        if let x = number(a), let y = number(b) {
            switch op {
            case .add: return .number(x + y)
            case .subtract: return .number(x - y)
            case .multiply: return .number(x * y)
            default: return .number(x / y)   // 1/0 = #infinity như M
            }
        }
        switch (op, a, b) {
        case (.add, .date(let d), .duration(let u)), (.add, .duration(let u), .date(let d)): return .date(d + u)
        case (.add, .dateTime(let d), .duration(let u)), (.add, .duration(let u), .dateTime(let d)): return .dateTime(d + u)
        case (.add, .time(let d), .duration(let u)), (.add, .duration(let u), .time(let d)): return .time(d + u)
        case (.add, .duration(let x), .duration(let y)): return .duration(x + y)
        case (.subtract, .date(let d), .duration(let u)): return .date(d - u)
        case (.subtract, .dateTime(let d), .duration(let u)): return .dateTime(d - u)
        case (.subtract, .time(let d), .duration(let u)): return .time(d - u)
        case (.subtract, .date(let x), .date(let y)), (.subtract, .dateTime(let x), .dateTime(let y)),
             (.subtract, .time(let x), .time(let y)), (.subtract, .duration(let x), .duration(let y)):
            return .duration(x - y)
        case (.multiply, .duration(let u), _) where number(b) != nil: return .duration(u * number(b)!)
        case (.multiply, _, .duration(let u)) where number(a) != nil: return .duration(u * number(a)!)
        case (.divide, .duration(let u), _) where number(b) != nil: return .duration(u / number(b)!)
        case (.divide, .duration(let x), .duration(let y)): return .number(x / y)
        default: throw invalid(op.rawValue, a, b)
        }
    }

    static func negate(_ v: MValue) throws -> MValue {
        switch v {
        case .null: return .null
        case .number(let d): return .number(-d)
        case .currency(let c): return .currency(-c)
        case .duration(let d): return .duration(-d)
        default: throw invalid("-", v)
        }
    }

    // MARK: So sánh

    /// Toán tử `=` của M. Khác kiểu thì `false` (không lỗi); bản ghi so theo tên trường, không theo thứ tự.
    static func equals(_ a: MValue, _ b: MValue) -> Bool {
        if let x = number(a), let y = number(b) { return x == y }
        switch (a, b) {
        case (.null, .null): return true
        case (.logical(let x), .logical(let y)): return x == y
        case (.text(let x), .text(let y)): return x == y
        // Desktop 2.159 (VM-F3, 2026-11-15): `#date(2026,1,1) = #datetime(2026,1,1,0,0,0)` là false (khác kiểu), không đổi qua lại.
        case (.date(let x), .date(let y)), (.dateTime(let x), .dateTime(let y)),
             (.time(let x), .time(let y)), (.duration(let x), .duration(let y)): return x == y
        case (.list(let x), .list(let y)): return x.count == y.count && zip(x, y).allSatisfy { equals($0, $1) }
        case (.record(let x), .record(let y)):
            guard x.count == y.count else { return false }
            return x.allSatisfy { f in y.first { $0.name == f.name }.map { equals(f.value, $0.value) } ?? false }
        case (.table(let x), .table(let y)): return MTables.identical(x, y)
        case (.type(let x), .type(let y)): return x == y
        default: return false
        }
    }

    /// Thứ tự: số, chuỗi (theo giá trị ký tự, phân biệt hoa thường), logic (false < true), ngày/giờ/khoảng. `nil` nếu không so được.
    static func compare(_ a: MValue, _ b: MValue) -> Int? {
        func order<T: Comparable>(_ x: T, _ y: T) -> Int { x < y ? -1 : (x > y ? 1 : 0) }
        if let x = number(a), let y = number(b) { return x.isNaN || y.isNaN ? nil : order(x, y) }
        switch (a, b) {
        case (.text(let x), .text(let y)):
            if x.unicodeScalars.elementsEqual(y.unicodeScalars) { return 0 }
            return x.unicodeScalars.lexicographicallyPrecedes(y.unicodeScalars, by: { $0.value < $1.value }) ? -1 : 1
        case (.logical(let x), .logical(let y)): return order(x ? 1 : 0, y ? 1 : 0)
        // `date < datetime` báo lỗi "We cannot apply operator < to types Date and DateTime" trong Desktop (VM-F3): không so khác kiểu.
        case (.date(let x), .date(let y)), (.dateTime(let x), .dateTime(let y)),
             (.time(let x), .time(let y)), (.duration(let x), .duration(let y)): return order(x, y)
        default: return nil
        }
    }
}
