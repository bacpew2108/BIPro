// Hàm logic (F-KIT, đợt 2). Chữ ký do lead khai báo ở đợt 0; thân hàm do F-KIT thay.
// Ngữ nghĩa BLANK: docs/phase-b-research/architecture.md §5.5.
//
// Đối số lười: IF và SWITCH chỉ gọi frame.scalar(i) cho nhánh được chọn; COALESCE dừng ở giá trị không BLANK đầu tiên.
// Quy ước SWITCH: binder (LANG) giữ đối số theo thứ tự nguồn, dạng phẳng [expr, v1, r1, v2, r2, …, else?].
// Số đối số sau expr là chẵn thì không có else; lẻ thì đối số cuối là else.
// [SUY ĐOÁN] Các value được so theo thứ tự và dừng ở value khớp đầu tiên; đây là cách đọc của đặc tả, chưa có oracle.

public enum LogicalFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "IF",
                     params: [.scalar("logical_test"), .lazy("value_if_true"), .lazy("value_if_false", optional: true)],
                     impl: .scalar(LogicalFunctions.ifBody)),
        // SWITCH: [expression, (value, result)*, else?]. Binder ghép cặp value/result theo thứ tự.
        FunctionSpec(name: "SWITCH",
                     params: [.scalar("expression"), .lazy("value", repeats: true), .lazy("result", repeats: true),
                              .lazy("else", optional: true)],
                     impl: .scalar(LogicalFunctions.switchBody)),
        FunctionSpec(name: "AND", params: [.scalar("logical1"), .scalar("logical2")],
                     impl: .scalar(LogicalFunctions.andBody)),
        FunctionSpec(name: "OR", params: [.scalar("logical1"), .scalar("logical2")],
                     impl: .scalar(LogicalFunctions.orBody)),
        FunctionSpec(name: "NOT", params: [.scalar("logical")],
                     impl: .scalar(LogicalFunctions.notBody)),
        FunctionSpec(name: "TRUE", params: [], impl: .scalar(LogicalFunctions.trueBody)),
        FunctionSpec(name: "FALSE", params: [], impl: .scalar(LogicalFunctions.falseBody)),
        FunctionSpec(name: "BLANK", params: [], impl: .scalar(LogicalFunctions.blankBody)),
        FunctionSpec(name: "COALESCE", params: [.lazy("value", repeats: true)],
                     impl: .scalar(LogicalFunctions.coalesceBody)),
    ]

    // MARK: - Thân hàm

    /// IF: điều kiện BLANK là FALSE. Thiếu nhánh sai thì ra BLANK.
    static func ifBody(_ frame: CallFrame) throws(DAXError) -> Value {
        if try frame.scalar(0).asLogical() {
            return try frame.scalar(1)
        }
        if frame.isBlankArgument(2) { return .blank }
        return try frame.scalar(2)
    }

    /// SWITCH: so `expression` với từng value bằng `=`; trả result của cặp khớp đầu tiên, không khớp thì else hoặc BLANK.
    static func switchBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let bieuThuc = try frame.scalar(0)
        let soSauExpr = frame.args.count - 1
        let coElse = soSauExpr % 2 == 1
        let soCap = soSauExpr / 2
        for k in 0..<soCap {
            let giaTriSo = try frame.scalar(1 + 2 * k)
            let ketQua = try Value.compare(.equal, bieuThuc, giaTriSo)
            if case .boolean(true) = ketQua {
                return try frame.scalar(2 + 2 * k)
            }
        }
        if coElse {
            return try frame.scalar(frame.args.count - 1)
        }
        return .blank
    }

    /// AND: BLANK là FALSE (architecture.md §5.5).
    static func andBody(_ frame: CallFrame) throws(DAXError) -> Value {
        try Value.logical(.and, try frame.scalar(0), try frame.scalar(1))
    }

    /// OR: BLANK là FALSE, nên BLANK || TRUE là TRUE.
    static func orBody(_ frame: CallFrame) throws(DAXError) -> Value {
        try Value.logical(.or, try frame.scalar(0), try frame.scalar(1))
    }

    /// NOT: đảo giá trị logic của đối số (BLANK là FALSE, nên NOT(BLANK) là TRUE).
    static func notBody(_ frame: CallFrame) throws(DAXError) -> Value {
        try Value.unary(.not, try frame.scalar(0))
    }

    static func trueBody(_ frame: CallFrame) throws(DAXError) -> Value {
        .boolean(true)
    }

    static func falseBody(_ frame: CallFrame) throws(DAXError) -> Value {
        .boolean(false)
    }

    static func blankBody(_ frame: CallFrame) throws(DAXError) -> Value {
        .blank
    }

    /// COALESCE: giá trị không BLANK đầu tiên, các đối số sau đó không được đánh giá. Tất cả BLANK thì ra BLANK.
    static func coalesceBody(_ frame: CallFrame) throws(DAXError) -> Value {
        for i in 0..<frame.args.count {
            let giaTri = try frame.scalar(i)
            if !giaTri.isBlank { return giaTri }
        }
        return .blank
    }
}
