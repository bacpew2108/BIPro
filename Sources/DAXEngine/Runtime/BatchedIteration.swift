// Tính gộp theo nhóm cho vòng lặp X (E3-cấu-trúc, specs/001-e3-cau-truc).
//
// Mục tiêu: SUMX/AVERAGEX/MINX/MAXX trên giá trị riêng của một cột, với thân CALCULATE(agg(cột), …) không phụ
// thuộc dòng, quét fact một lần cho mọi nhóm thay vì dựng ngữ cảnh và quét cho từng nhóm.
// Hợp đồng: kết quả phải bằng đường từng dòng từng byte (contracts/engine-equivalence.md). Không nhận ra mẫu
// thì trả nil và vòng lặp chạy như cũ.
//
// Phạm vi hiện tại: MAX/MIN của một cột, với REMOVEFILTERS cố định và tùy chọn một bước `cột = t` (t là MAX/MIN
// của chính cột đó trong bước trước). SUM/COUNT chưa làm (chưa có nhu cầu).

import ColumnStore
import Foundation

enum BatchedIteration {
    /// Trạng thái ghi đè công tắc, dùng cho test chạy hai chế độ trong cùng một tiến trình.
    private final class Override: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Bool?

        func get() -> Bool? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ newValue: Bool?) {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    private static let override = Override()

    /// Giá trị theo biến môi trường `BIPRO_BATCH`: `0` tắt, còn lại (kể cả không đặt) bật.
    static let environmentEnabled: Bool = ProcessInfo.processInfo.environment["BIPRO_BATCH"] != "0"

    /// `nil` = theo biến môi trường. Test đặt `true`/`false` rồi trả về `nil` khi xong.
    static var overrideEnabled: Bool? {
        get { override.get() }
        set { override.set(newValue) }
    }

    static var isEnabled: Bool { overrideEnabled ?? environmentEnabled }
}

/// Hình dạng thân vòng lặp mà đường gộp xử lý (data-model.md, BatchedShape).
struct BatchedShape {
    enum Aggregate { case max, min }

    struct Step {
        let aggregate: Aggregate
        let column: ColumnID
    }

    /// Bước đầu: `CALCULATE(agg(cột), REMOVEFILTERS(…))`, cho giá trị `t`.
    let first: Step
    /// Bước hai tùy chọn: `CALCULATE(agg(cột2), REMOVEFILTERS(…), first.column = t)`.
    let second: Step?
    /// Đối số REMOVEFILTERS, giống nhau ở hai bước.
    let modifiers: [BoundExpr?]
}

extension BatchedIteration {
    /// Số lần đường gộp đã chạy thật, đếm theo từng `ColumnStore` (không tính lần nhận mẫu hụt). Dùng cho test để chắc
    /// không qua nhờ đường cũ; đếm theo store để test khác chạy song song không làm sai số đếm.
    private static let counter = TakenCounter()

    private final class TakenCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [ObjectIdentifier: Int] = [:]
        func increment(_ store: ColumnStore) {
            lock.lock()
            values[ObjectIdentifier(store), default: 0] += 1
            lock.unlock()
        }
        func get(_ store: ColumnStore) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return values[ObjectIdentifier(store)] ?? 0
        }
    }

    static func takenCount(_ store: ColumnStore) -> Int { counter.get(store) }
    private static func noteTaken(_ store: ColumnStore) { counter.increment(store) }

    // MARK: Nhận mẫu (T009)

    /// Nhận mẫu thân vòng lặp. Trả nil nếu không đúng mẫu (khi đó dùng đường cũ).
    /// Hợp lệ (research.md R2): `CALCULATE(MAX|MIN(cột), REMOVEFILTERS(bảng)…)`, hoặc
    /// `VAR t = CALCULATE(MAX|MIN(a), REMOVEFILTERS(…)) RETURN CALCULATE(MAX|MIN(b), REMOVEFILTERS(…), a = t)`
    /// với hai danh sách REMOVEFILTERS giống nhau.
    static func recognize(_ body: BoundExpr, evaluator: Evaluator) throws(DAXError) -> BatchedShape? {
        if case .varBlock(let slots, let values, let inner) = body {
            guard slots.count == 1, values.count == 1,
                  let first = try step(values[0], evaluator, parameter: nil),
                  let second = try step(inner, evaluator, parameter: (slots[0], first.step.column)),
                  String(describing: first.modifiers) == String(describing: second.modifiers) else { return nil }
            return BatchedShape(first: first.step, second: second.step, modifiers: first.modifiers)
        }
        guard let only = try step(body, evaluator, parameter: nil) else { return nil }
        return BatchedShape(first: only.step, second: nil, modifiers: only.modifiers)
    }

    /// Một lời gọi CALCULATE theo mẫu. `parameter` là (biến t, cột lọc) khi bước này phải có đúng một bộ lọc `cột = t`.
    private static func step(_ expr: BoundExpr, _ evaluator: Evaluator,
                             parameter: (slot: Int, column: ColumnID)?)
        throws(DAXError) -> (step: BatchedShape.Step, modifiers: [BoundExpr?])? {
        guard case .call(let fid, let args) = expr, args.count >= 1,
              try evaluator.specification(fid).name == "CALCULATE",
              case .call(let aggFid, let aggArgs)? = args[0], aggArgs.count == 1,
              case .column(let column)? = aggArgs[0] else { return nil }
        let aggregate: BatchedShape.Aggregate
        switch try evaluator.specification(aggFid).name {
        case "MAX": aggregate = .max
        case "MIN": aggregate = .min
        default: return nil
        }
        var modifiers: [BoundExpr?] = []
        var sawParameterFilter = false
        for arg in args.dropFirst() {
            guard let arg else { return nil }
            switch arg {
            case .call(let removeFid, let removeArgs):
                guard try evaluator.specification(removeFid).name == "REMOVEFILTERS", removeArgs.count == 1,
                      case .table? = removeArgs[0] else { return nil }
                modifiers.append(arg)
            case .binary(.equal, .column(let filtered), .variable(let slot)):
                guard let parameter, !sawParameterFilter, slot == parameter.slot, filtered == parameter.column else {
                    return nil
                }
                sawParameterFilter = true
            default:
                return nil
            }
        }
        if parameter != nil && !sawParameterFilter { return nil }
        return (BatchedShape.Step(aggregate: aggregate, column: column), modifiers)
    }

    // MARK: Chạy (T010–T014)

    /// Giá trị của thân vòng lặp ở từng dòng của bảng lặp (đúng thứ tự dòng), hoặc nil nếu phải dùng đường cũ.
    /// Người gọi (SUMX, AVERAGEX, MINX, MAXX) đưa các giá trị này vào cùng bộ tích luỹ như đường cũ.
    static func values(for frame: CallFrame) throws(DAXError) -> [Value]? {
        guard isEnabled, frame.args.count == 2, let tableExpr = frame.args[0], let body = frame.args[1],
              let evaluator = frame.eval as? Evaluator,
              let shape = try recognize(body, evaluator: evaluator),
              let result = try run(shape, tableExpr: tableExpr, ctx: frame.ctx, evaluator: evaluator) else { return nil }
        noteTaken(evaluator.store)
        return result
    }

    /// Chỉ các biểu thức bảng cho ra bảng ảo nhỏ mới đáng thử; tránh materialize cả bảng vật lý.
    private static func isGroupSource(_ expr: BoundExpr, _ evaluator: Evaluator) throws(DAXError) -> Bool {
        switch expr {
        case .variable(let slot):
            if case .table = try evaluator.lookupVariable(slot) { return true }
            return false
        case .call(let fid, _):
            return ["VALUES", "DISTINCT", "CALCULATETABLE"].contains(try evaluator.specification(fid).name)
        default:
            return false
        }
    }

    private static func run(_ shape: BatchedShape, tableExpr: BoundExpr, ctx: EvalContext,
                            evaluator: Evaluator) throws(DAXError) -> [Value]? {
        guard try isGroupSource(tableExpr, evaluator) else { return nil }
        let source = try evaluator.table(tableExpr, in: ctx)
        guard source.columns.count == 1, let group = source.lineage[0] else { return nil }
        if source.rows.isEmpty { return [] }

        // Mọi cột phải cùng bảng với cột nhóm, cột nhóm là số nguyên mã hoá, không bảng bị bỏ lọc là bảng chứa nhóm.
        let table = group.table
        guard shape.first.column.table == table, (shape.second?.column.table ?? table) == table,
              evaluator.store.schema.column(group)?.type == .integer else { return nil }
        for case .call(_, let removeArgs)? in shape.modifiers {
            guard case .table(let removed)? = removeArgs[0], removed != table else { return nil }
        }
        let groupData = try evaluator.columnData(group)
        guard groupData.isEncoded else { return nil }

        // Ngữ cảnh chung của mọi nhóm = ngữ cảnh đường cũ trừ bộ lọc `cột nhóm = v`:
        // shadow, chuyển ngữ cảnh của các hàng ngoài, bỏ lọc cột nhóm, rồi REMOVEFILTERS.
        var filter = ctx.filter.pushingShadow()
        if !evaluator.rowStack.isEmpty { filter = try evaluator.transitioned(filter) }
        filter = filter.removingColumns([group])
        filter = try evaluator.calculatedContext(shape.modifiers, EvalContext(filter: filter, row: nil)).filter
        // Bước hai ghi đè bộ lọc ngoài trên cột của bước một: nếu cột đó đang bị lọc thì để đường cũ xử lý.
        if shape.second != nil && filter.isFiltered(shape.first.column) { return nil }

        guard let firstKeys = try orderKeys(of: shape.first.column, evaluator) else { return nil }
        var secondKeys: [Int64] = []
        if let second = shape.second {
            guard let keys = try orderKeys(of: second.column, evaluator) else { return nil }
            secondKeys = keys
        }
        let firstData = try evaluator.columnData(shape.first.column)
        var secondData: ColumnData?
        if let second = shape.second { secondData = try evaluator.columnData(second.column) }
        let groupCodes = try groupCodeArray(of: group, evaluator)
        let codeCount = groupData.dictionaryCount + 1

        // R(T) chung: dòng của bảng còn thấy được khi chưa lọc theo nhóm. Mỗi nhóm lấy phần của nó.
        let rows = try evaluator.visibleRows(of: table, in: EvalContext(filter: filter, row: nil))

        // Mã nhóm của từng dòng bảng lặp. Giá trị lạ (không phải số nguyên hay BLANK) thì để đường cũ xử lý.
        let index = try evaluator.columnIndex(group)
        var wanted: [Int?] = []
        wanted.reserveCapacity(source.rows.count)
        for row in source.rows {
            switch row[0] {
            case .blank: wanted.append(0)
            case .integer(let i): wanted.append(index.code(of: .integer(i)))
            default: return nil
            }
        }

        // Các vòng nóng dưới đây dùng con trỏ: nhiều luồng cùng đọc mảng khoá dùng chung, đếm tham chiếu của mảng
        // sẽ thành điểm tranh chấp nếu mỗi phép đọc retain/release.
        var failure: DAXError?
        var cancelled = false
        let result: [Value]? = groupCodes.withUnsafeBufferPointer { gc in
        firstKeys.withUnsafeBufferPointer { fk in
        secondKeys.withUnsafeBufferPointer { sk in
            // Chia dòng theo mã nhóm (đếm rồi điền; thứ tự dòng tăng dần như đường cũ).
            var start = [Int](repeating: 0, count: codeCount + 1)
            var scanned = 0
            rows.forEach { r in
                scanned &+= 1
                if scanned & 0xFFF == 0, failure == nil {
                    do throws(DAXError) { try evaluator.checkCancelled() } catch { failure = error }
                }
                start[(r < gc.count ? Int(gc[r]) : 0) + 1] += 1
            }
            if failure != nil { return nil }
            for c in 0..<codeCount { start[c + 1] += start[c] }
            var fill = start
            var order = [UInt32](repeating: 0, count: start[codeCount])
            var filled = 0
            rows.forEach { r in
                filled &+= 1
                if filled & 0xFFF == 0, evaluator.isCancelledNow { cancelled = true }
                let code = r < gc.count ? Int(gc[r]) : 0
                order[fill[code]] = UInt32(r)
                fill[code] += 1
            }
            if cancelled { return nil }

            func better(_ key: Int64, than best: Int64, _ aggregate: BatchedShape.Aggregate) -> Bool {
                aggregate == .max ? key > best : key < best
            }

            /// Giá trị thân vòng lặp cho một nhóm; nil nghĩa là phải bỏ cuộc (t BLANK ở nhóm có dòng).
            func evaluateGroup(_ code: Int) -> Value?? {
                let lo = start[code], hi = start[code + 1]
                if lo == hi { return .some(.blank) }
                var bestKey = Int64.min
                var bestRow = -1
                for k in lo..<hi {
                    let r = Int(order[k])
                    let key = r < fk.count ? fk[r] : Int64.min
                    if key == Int64.min { continue }
                    if bestRow < 0 || better(key, than: bestKey, shape.first.aggregate) { bestKey = key; bestRow = r }
                }
                guard let second = shape.second, let secondData else {
                    return .some(bestRow < 0 ? .blank : Value(stored: firstData.value(at: bestRow)))
                }
                if bestRow < 0 { return nil }
                var best2Key = Int64.min
                var best2Row = -1
                for k in lo..<hi {
                    let r = Int(order[k])
                    guard r < fk.count, fk[r] == bestKey else { continue }
                    let key = r < sk.count ? sk[r] : Int64.min
                    if key == Int64.min { continue }
                    if best2Row < 0 || better(key, than: best2Key, second.aggregate) { best2Key = key; best2Row = r }
                }
                return .some(best2Row < 0 ? .blank : Value(stored: secondData.value(at: best2Row)))
            }

            var memo: [Int: Value] = [:]
            var out: [Value] = []
            out.reserveCapacity(wanted.count)
            for entry in wanted {
                if out.count & 0x3F == 0, evaluator.isCancelledNow { cancelled = true; return nil }
                guard let code = entry else { out.append(.blank); continue }
                if let hit = memo[code] { out.append(hit); continue }
                guard case .some(.some(let value)) = evaluateGroup(code) else { return nil }
                memo[code] = value
                out.append(value)
            }
            return out
        }}}
        if let failure { throw failure }
        if cancelled {
            try evaluator.checkCancelled()
            return nil
        }
        return result
    }

    /// Mã nhóm theo dòng (0 = BLANK) của cột mã hoá, nhớ theo (store, cột).
    private static func groupCodeArray(of column: ColumnID, _ evaluator: Evaluator) throws(DAXError) -> [Int32] {
        let data = try evaluator.columnData(column)
        return KeyMemo.shared.groupCodes(store: evaluator.store, column: column) {
            (0..<data.rowCount).map { Int32(data.code(atRow: $0) ?? 0) }
        }
    }

    // MARK: Khoá sắp xếp theo cột

    /// Khoá Int64 của từng dòng, giữ đúng thứ tự và quan hệ bằng nhau của `Value.compare`; BLANK là `Int64.min`.
    /// nil nếu kiểu cột chưa hỗ trợ (chuỗi, boolean) hoặc có giá trị trùng giá trị đánh dấu BLANK.
    private static func orderKeys(of column: ColumnID, _ evaluator: Evaluator) throws(DAXError) -> [Int64]? {
        var failure: DAXError?
        let keys = KeyMemo.shared.orderKeys(store: evaluator.store, column: column) {
            do throws(DAXError) { return try computeKeys(of: column, evaluator) } catch { failure = error; return nil }
        }
        if let failure { throw failure }
        return keys
    }

    private static func computeKeys(of column: ColumnID, _ evaluator: Evaluator) throws(DAXError) -> [Int64]? {
        let data = try evaluator.columnData(column)
        switch data.type {
        case .integer, .double, .currency, .dateTime: break
        default: return nil
        }
        switch data.payload {
        case .allBlank:
            return [Int64](repeating: .min, count: data.rowCount)
        case .dense(let dense):
            switch dense {
            case .doubles(let values), .dates(let values):
                return values.map { $0.isNaN ? Int64.min : doubleKey($0) }
            case .integers(let values, let blanks):
                if values.contains(Int64.min) { return nil }
                var out = values
                blanks?.forEach { if $0 < out.count { out[$0] = .min } }
                return out
            }
        case .encoded(let codes, let dictionary):
            let index = try evaluator.columnIndex(column)
            var table = [Int64](repeating: .min, count: dictionary.count + 1)
            for code in stride(from: 1, through: dictionary.count, by: 1) {
                guard let rank = index.sortRank(ofCode: code) else { return nil }
                table[code] = Int64(rank)
            }
            return (0..<data.rowCount).map { table[codes.code(at: $0)] }
        }
    }

    /// Khoá Int64 có cùng thứ tự với Double (không NaN); -0 và +0 cùng khoá.
    private static func doubleKey(_ x: Double) -> Int64 {
        let signed = Int64(bitPattern: (x == 0 ? 0.0 : x).bitPattern)
        return signed < 0 ? signed ^ Int64.max : signed
    }

    /// Nhớ khoá theo (store, cột), tính một lần dưới khoá để các luồng không cùng tính. Store được giữ yếu.
    private final class KeyMemo: @unchecked Sendable {
        static let shared = KeyMemo()

        private struct Entry {
            weak var store: ColumnStore?
            var keys: [ColumnID: [Int64]?] = [:]
            var codes: [ColumnID: [Int32]] = [:]
        }

        private let lock = NSLock()
        private var entries: [ObjectIdentifier: Entry] = [:]

        private func entry(for store: ColumnStore) -> Entry {
            let id = ObjectIdentifier(store)
            if let existing = entries[id], existing.store === store { return existing }
            entries = entries.filter { $0.value.store != nil }
            return Entry(store: store)
        }

        func orderKeys(store: ColumnStore, column: ColumnID, _ compute: () -> [Int64]?) -> [Int64]? {
            lock.lock()
            defer { lock.unlock() }
            var e = entry(for: store)
            if let found = e.keys[column] { return found }
            let value = compute()
            e.keys[column] = .some(value)
            entries[ObjectIdentifier(store)] = e
            return value
        }

        func groupCodes(store: ColumnStore, column: ColumnID, _ compute: () -> [Int32]) -> [Int32] {
            lock.lock()
            defer { lock.unlock() }
            var e = entry(for: store)
            if let found = e.codes[column] { return found }
            let value = compute()
            e.codes[column] = value
            entries[ObjectIdentifier(store)] = e
            return value
        }
    }
}
