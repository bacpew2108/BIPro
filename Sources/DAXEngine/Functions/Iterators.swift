// Iterator (F-AGG, đợt 3). Thân biểu thức chạy trong row context của từng dòng; measure bên trong
// kích hoạt context transition (qua Evaluator.measureValue). Bảng vật lý lặp qua `iterateArgument`, không materialize.
// Chữ ký do lead khai báo ở đợt 0.
//
// - SUMX, AVERAGEX: BLANK bị bỏ qua (AVERAGEX không tính BLANK vào mẫu). Kiểu kết quả theo FKAccumulator.
// - MINX, MAXX: nhỏ nhất/lớn nhất trong các giá trị không BLANK; không có thì BLANK.
// - CONCATENATEX(bảng, biểu thức, delimiter, [khoá, [ASC|DESC]]…): BLANK của biểu thức bị bỏ qua (không sinh
//   delimiter thừa). Không có khoá thì giữ thứ tự lặp của bảng [SUY ĐOÁN]. Khoá BLANK đứng trước [SUY ĐOÁN].
//   Khoá khác loại (số/chuỗi/logic) báo .typeMismatch. Sắp xếp ổn định (hoà thì giữ thứ tự lặp).
// - PERCENTILEX.INC(bảng, biểu thức, k, [ASC|DESC]): bỏ BLANK; k ngoài [0, 1] báo .runtime; công thức nội suy
//   tuyến tính của Excel PERCENTILE.INC (rank = k·(n−1)). DESC sắp giảm dần rồi áp cùng công thức [SUY ĐOÁN].
//   Mọi giá trị là currency thì kết quả là currency (làm tròn 10^-4), còn lại là số thực [SUY ĐOÁN].
// - RANKX(bảng, biểu thức, [value], [ASC|DESC], [DENSE|SKIP]): value bỏ trống thì lấy biểu thức ở ngữ cảnh gọi
//   (row context ngoài). value BLANK cho BLANK. Dòng BLANK của bảng không được xếp hạng. Mặc định DESC và SKIP
//   [SUY ĐOÁN, theo tài liệu DAX đã biết]: SKIP cho 1,1,3; DENSE cho 1,1,2.

import ColumnStore

public enum IteratorFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "SUMX", params: [.table("table"), .lazy("expression")], impl: .scalar(sumxBody)),
        FunctionSpec(name: "AVERAGEX", params: [.table("table"), .lazy("expression")], impl: .scalar(averagexBody)),
        FunctionSpec(name: "MINX", params: [.table("table"), .lazy("expression")],
                     impl: .scalar(extremexBody(wantMax: false))),
        FunctionSpec(name: "MAXX", params: [.table("table"), .lazy("expression")],
                     impl: .scalar(extremexBody(wantMax: true))),
        FunctionSpec(name: "CONCATENATEX", params: [.table("table"), .lazy("expression"), .scalar("delimiter"),
                                                    .lazy("orderBy_expression", optional: true, repeats: true),
                                                    .keyword("order", ["ASC", "DESC"], optional: true)],
                     impl: .scalar(concatenatexBody)),
        FunctionSpec(name: "PERCENTILEX.INC", params: [.table("table"), .lazy("expression"), .scalar("percentile"),
                                                       .keyword("order", ["ASC", "DESC"], optional: true)],
                     impl: .scalar(percentileBody)),
        FunctionSpec(name: "RANKX", params: [.table("table"), .lazy("expression"), .scalar("value", optional: true),
                                             .keyword("order", ["ASC", "DESC"], optional: true),
                                             .keyword("ties", ["DENSE", "SKIP"], optional: true)],
                     impl: .scalar(rankxBody)),
    ]

    // MARK: SUMX, AVERAGEX

    private static let sumxBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        var acc = FKAccumulator()
        try frame.iterateArgument(0) { (inner: EvalContext) throws(DAXError) in
            try acc.add(try frame.scalar(1, in: inner))
        }
        return try acc.total()
    }

    private static let averagexBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        var acc = FKAccumulator()
        try frame.iterateArgument(0) { (inner: EvalContext) throws(DAXError) in
            try acc.add(try frame.scalar(1, in: inner))
        }
        return try acc.average()
    }

    // MARK: MINX, MAXX

    private static func extremexBody(wantMax: Bool) -> FunctionSpec.ScalarBody {
        return { (frame: CallFrame) throws(DAXError) -> Value in
            var best: Value?
            try frame.iterateArgument(0) { (inner: EvalContext) throws(DAXError) in
                best = try fkPickExtreme(best, try frame.scalar(1, in: inner), wantMax: wantMax)
            }
            return best ?? .blank
        }
    }

    // MARK: CONCATENATEX

    private static let concatenatexBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        // Mỗi khoá là (biểu thức, hướng). Từ khoá ASC/DESC đứng ngay sau khoá của nó; mặc định ASC.
        var spec: [(expr: BoundExpr, desc: Bool?)] = []
        var position = 3
        while position < frame.args.count {
            guard let arg = frame.args[position] else {
                throw DAXError(.arity, "CONCATENATEX: đối số \(position + 1) bị bỏ trống")
            }
            if case .keyword(let word) = arg {
                guard let last = spec.indices.last, spec[last].desc == nil, word == "ASC" || word == "DESC" else {
                    throw DAXError(.arity, "CONCATENATEX: ASC hoặc DESC phải đứng ngay sau một biểu thức sắp xếp")
                }
                spec[last].desc = word == "DESC"
            } else {
                spec.append((expr: arg, desc: nil))
            }
            position += 1
        }

        var texts: [String] = []
        var keys: [[Value]] = []
        try frame.iterateArgument(0) { (inner: EvalContext) throws(DAXError) in
            let value = try frame.scalar(1, in: inner)
            if value.isBlank { return }
            texts.append(value.asText())
            var row: [Value] = []
            row.reserveCapacity(spec.count)
            for key in spec {
                row.append(try frame.eval.scalar(key.expr, in: inner))
            }
            keys.append(row)
        }

        var order = Array(0..<texts.count)
        if !spec.isEmpty {
            for k in 0..<spec.count {
                try fkRequireComparable(keys.map { $0[k] })
            }
            let descending = spec.map { $0.desc == true }
            order.sort { (a: Int, b: Int) -> Bool in
                for k in 0..<descending.count {
                    let c = fkCompare(keys[a][k], keys[b][k])
                    if c != 0 { return descending[k] ? c > 0 : c < 0 }
                }
                return a < b
            }
        }
        let delimiter = try frame.scalar(2).asText()
        return .string(order.map { texts[$0] }.joined(separator: delimiter))
    }

    // MARK: PERCENTILEX.INC

    private static let percentileBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let k = try frame.scalar(2).asDouble()
        guard k >= 0, k <= 1 else {
            throw DAXError(.runtime, "PERCENTILEX.INC: k phải nằm trong khoảng [0, 1]")
        }
        let descending = frame.keyword(3) == "DESC"
        // Với mỗi mẫu: giá trị đã đổi về số thực, và cờ cho biết mẫu có phải currency (giữ đơn vị ×10^4).
        var samples: [(value: Double, currency: Bool)] = []
        try frame.iterateArgument(0) { (inner: EvalContext) throws(DAXError) in
            switch try frame.scalar(1, in: inner) {
            case .blank:
                return
            case .integer(let n):
                samples.append((Double(n), false))
            case .double(let d):
                samples.append((d, false))
            case .currency(let c):
                samples.append((Double(c), true))
            case .string, .boolean, .dateTime:
                throw DAXError(.typeMismatch, "PERCENTILEX.INC cần biểu thức số")
            }
        }
        guard !samples.isEmpty else { return .blank }
        let allCurrency = samples.allSatisfy { $0.currency }
        let xs = samples.map { sample -> Double in
            if allCurrency { return sample.value }
            return sample.currency ? sample.value / 10_000 : sample.value
        }
        let sorted = xs.sorted { (a: Double, b: Double) -> Bool in descending ? a > b : a < b }
        let n = sorted.count
        let rank = k * Double(n - 1)
        let lo = Int(rank.rounded(.down))
        let frac = rank - Double(lo)
        let result = lo + 1 < n ? sorted[lo] + frac * (sorted[lo + 1] - sorted[lo]) : sorted[lo]
        if allCurrency {
            return .currency(Int64(result.rounded(.toNearestOrAwayFromZero)))
        }
        return .double(result)
    }

    // MARK: RANKX

    private static let rankxBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        var descending = true
        var dense = false
        var explicitValue: BoundExpr?
        for position in 2..<max(2, frame.args.count) {
            guard let arg = frame.args[position] else { continue }
            if case .keyword(let word) = arg {
                switch word {
                case "ASC": descending = false
                case "DESC": descending = true
                case "DENSE": dense = true
                case "SKIP": dense = false
                default: throw DAXError(.typeMismatch, "RANKX: từ khoá \(word) không hợp lệ")
                }
            } else if position == 2 {
                explicitValue = arg
            } else {
                throw DAXError(.arity, "RANKX: đối số \(position + 1) phải là từ khoá")
            }
        }
        // value mặc định: biểu thức tính ở ngữ cảnh gọi (trước khi lặp bảng).
        let value: Value
        if let explicitValue {
            value = try frame.eval.scalar(explicitValue, in: frame.ctx)
        } else {
            value = try frame.scalar(1)
        }
        if value.isBlank { return .blank }

        let op: BinaryOp = descending ? .greater : .less
        var betterCount: Int64 = 0
        var betterValues = Set<Value>()
        try frame.iterateArgument(0) { (inner: EvalContext) throws(DAXError) in
            let candidate = try frame.scalar(1, in: inner)
            if candidate.isBlank { return }
            guard case .boolean(true) = try Value.compare(op, candidate, value) else { return }
            betterCount += 1
            if dense { betterValues.insert(candidate) }
        }
        return .integer(1 + (dense ? Int64(betterValues.count) : betterCount))
    }
}

// MARK: - So sánh khoá sắp xếp (dùng chung cho CONCATENATEX)

/// Kiểm các khoá cùng một loại (số, chuỗi hoặc logic). BLANK không tính. Khác loại báo .typeMismatch.
func fkRequireComparable(_ values: [Value]) throws(DAXError) {
    var seen: Int?
    for value in values {
        let group: Int
        switch value {
        case .blank: continue
        case .integer, .double, .currency, .dateTime: group = 0
        case .string: group = 1
        case .boolean: group = 2
        }
        if let previous = seen, previous != group {
            throw DAXError(.typeMismatch, "các giá trị khoá sắp xếp khác kiểu, không so sánh được")
        }
        seen = group
    }
}

/// So hai khoá đã được kiểm kiểu: BLANK nhỏ nhất. Trả -1, 0 hoặc 1.
func fkCompare(_ a: Value, _ b: Value) -> Int {
    switch (a.isBlank, b.isBlank) {
    case (true, true): return 0
    case (true, false): return -1
    case (false, true): return 1
    case (false, false): break
    }
    if case .boolean(true)? = try? Value.compare(.less, a, b) { return -1 }
    if case .boolean(true)? = try? Value.compare(.greater, a, b) { return 1 }
    return 0
}
