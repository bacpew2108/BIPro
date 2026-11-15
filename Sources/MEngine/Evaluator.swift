// Phase F (T049): bộ chạy M. Duyệt cây cú pháp, đánh giá lười theo bước `let`, lỗi là giá trị.
//
// - `let`/bản ghi: mỗi bước là một thunk, chỉ tính khi được dùng (bước lỗi không dùng không làm hỏng kết quả); vòng tham chiếu báo lỗi.
// - Lỗi M là `MError` được ném; `try … otherwise` bắt; trong danh sách/bản ghi lỗi nằm ở phần tử (`.error`), ném khi truy cập.
// - Đối số hàm được tính trước khi gọi (M gốc tính lười): đối số lỗi không dùng sẽ ném. [SUY ĐOÁN] chấp nhận được ở phạm vi Phase F.
// - Một luồng: scope và thunk không chia sẻ giữa các Task.

import ColumnStore

public struct MEvaluator: Sendable {
    public let environment: MEnvironment

    public init(environment: MEnvironment) {
        self.environment = environment
    }

    public func evaluate(source: String, upTo step: String? = nil, rowLimit: Int? = nil) async throws -> MValue {
        try await evaluate(try MParser.parse(source), upTo: step, rowLimit: rowLimit)
    }

    /// `step`: đánh giá đến hết bước này của `let` ngoài cùng (xem trước ở bước giữa).
    /// `rowLimit`: nếu kết quả là bảng thì chỉ giữ chừng đó dòng đầu (xem trước); nguồn nhận gợi ý riêng qua `MEnvironment`.
    public func evaluate(_ expression: MExpression, upTo step: String? = nil, rowLimit: Int? = nil) async throws -> MValue {
        try Task.checkCancellation()
        let interpreter = Interpreter(environment: environment)
        var result: MValue
        if let step {
            guard case .letIn(let bindings, _) = expression, bindings.contains(where: { $0.name == step }) else {
                throw MError.expression("Bước '\(step)' không có trong truy vấn")
            }
            let scope = interpreter.letScope(bindings, parent: interpreter.root)
            result = try interpreter.lookup(step, in: scope, line: 1)
        } else {
            result = try interpreter.evaluate(expression, in: interpreter.root)
        }
        if case .error(let e) = result { throw e }
        if let rowLimit, case .table(let table) = result { result = .table(table.prefix(rowLimit)) }
        return result
    }
}

final class MThunk: @unchecked Sendable {
    private enum State {
        case pending(MExpression, MScope)
        case evaluating
        case done(MValue)
    }

    private var state: State
    let name: String

    init(name: String, expression: MExpression, scope: MScope) {
        self.name = name
        state = .pending(expression, scope)
    }

    init(name: String, value: MValue) {
        self.name = name
        state = .done(value)
    }

    func force(_ interpreter: Interpreter) throws -> MValue {
        switch state {
        case .done(let value):
            if case .error(let e) = value { throw e }
            return value
        case .evaluating:
            throw MError.expression("Phát hiện vòng tham chiếu khi tính '\(name)'")
        case .pending(let expression, let scope):
            state = .evaluating
            do {
                let value = try interpreter.evaluate(expression, in: scope)
                state = .done(value)
                return value
            } catch let e as MError {
                state = .done(.error(e))
                throw e
            } catch {
                state = .pending(expression, scope)   // huỷ (Task cancel) không làm hỏng thunk
                throw error
            }
        }
    }
}

final class MScope: @unchecked Sendable {
    var thunks: [String: MThunk] = [:]
    let parent: MScope?

    init(parent: MScope?) {
        self.parent = parent
    }
}

final class Interpreter: @unchecked Sendable {
    let environment: MEnvironment
    let root: MScope

    init(environment: MEnvironment) {
        self.environment = environment
        root = MScope(parent: nil)
    }

    func letScope(_ bindings: [MBinding], parent: MScope) -> MScope {
        let scope = MScope(parent: parent)
        for binding in bindings { scope.thunks[binding.name] = MThunk(name: binding.name, expression: binding.value, scope: scope) }
        return scope
    }

    // MARK: Tra tên

    func lookup(_ name: String, in scope: MScope, line: Int) throws -> MValue {
        var current: MScope? = scope
        while let s = current {
            if let thunk = s.thunks[name] { return try thunk.force(self) }
            current = s.parent
        }
        if let value = environment.bindings[name] {
            if case .error(let e) = value { throw e }
            return value
        }
        if let value = MBuiltins.value(named: name, interpreter: self) { return value }
        if let function = MLibrary.functions[name] { return .function(function) }
        if name.contains(".") || name.hasPrefix("#") { throw MError.unsupported(name, line: line) }
        throw MError.expression("Tên '\(name)' chưa được khai báo")
    }

    // MARK: Đánh giá

    func evaluate(_ expression: MExpression, in scope: MScope) throws -> MValue {
        switch expression {
        case .null: return .null
        case .logical(let b): return .logical(b)
        case .number(let n): return .number(n)
        case .text(let s): return .text(s)
        case .identifier(let name, let line): return try lookup(name, in: scope, line: line)
        case .list(let items): return try evaluateList(items, in: scope)
        case .range(let a, let b): return try evaluateList([.range(a, b)], in: scope)
        case .record(let bindings): return try evaluateRecord(bindings, in: scope)
        case .letIn(let bindings, let body): return try evaluate(body, in: letScope(bindings, parent: scope))
        case .ifThenElse(let condition, let whenTrue, let whenFalse):
            guard case .logical(let b) = try evaluate(condition, in: scope) else {
                throw MError.expression("Điều kiện của if phải là giá trị logic")
            }
            return try evaluate(b ? whenTrue : whenFalse, in: scope)
        case .function(let parameters, let returnType, let body):
            return .function(try closure(parameters, returnType: returnType, body: body, scope: scope))
        case .invoke(let callee, let arguments, let line): return try invoke(callee, arguments, line: line, in: scope)
        case .fieldAccess(let target, let name, let optional): return try fieldAccess(try evaluate(target, in: scope), name, optional: optional)
        case .itemAccess(let target, let index, let optional):
            return try itemAccess(try evaluate(target, in: scope), try evaluate(index, in: scope), optional: optional)
        case .unary(let op, let operand):
            let v = try evaluate(operand, in: scope)
            switch op {
            case .negate: return try MOperators.negate(v)
            case .plus:
                guard MOperators.number(v) != nil || { if case .null = v { true } else { false } }() else { throw MOperators.invalid("+", v) }
                return v
            case .not:
                guard case .logical(let b) = v else { throw MOperators.invalid("not", v) }
                return .logical(!b)
            }
        case .binary(let op, let left, let right): return try binary(op, left, right, in: scope)
        case .isType(let value, let type): return .logical(try MType.resolve(type).accepts(try evaluate(value, in: scope)))
        case .asType(let value, let type):
            let v = try evaluate(value, in: scope)
            let resolved = try MType.resolve(type)
            guard resolved.accepts(v) else { throw MError.expression("Không thể chuyển đổi giá trị \(v.kindName) sang kiểu \(resolved.kind.rawValue)") }
            return v
        case .tryOtherwise(let protected, let otherwise): return try evaluateTry(protected, otherwise: otherwise, in: scope)
        case .error(let value): throw try makeError(try evaluate(value, in: scope))
        case .type(let type): return .type(try MType.resolve(type))
        }
    }

    private func binary(_ op: MBinaryOp, _ left: MExpression, _ right: MExpression, in scope: MScope) throws -> MValue {
        switch op {
        case .and, .or:
            let l = try evaluate(left, in: scope)
            guard case .logical(let a) = l else { throw MOperators.invalid(op == .and ? "and" : "or", l) }
            if op == .and, !a { return .logical(false) }
            if op == .or, a { return .logical(true) }
            let r = try evaluate(right, in: scope)
            guard case .logical(let b) = r else { throw MOperators.invalid(op == .and ? "and" : "or", r) }
            return .logical(b)
        default:
            return try MOperators.apply(op, try evaluate(left, in: scope), try evaluate(right, in: scope))
        }
    }

    // MARK: Danh sách, bản ghi

    private func evaluateList(_ items: [MExpression], in scope: MScope) throws -> MValue {
        var values: [MValue] = []
        for item in items {
            try Task.checkCancellation()
            if case .range(let from, let to) = item {
                guard case .number(let a) = try evaluate(from, in: scope), case .number(let b) = try evaluate(to, in: scope),
                      a == a.rounded(), b == b.rounded() else { throw MError.expression("Khoảng a..b phải là số nguyên") }
                if b >= a { values.append(contentsOf: stride(from: a, through: b, by: 1).map { .number($0) }) }
            } else {
                do { values.append(try evaluate(item, in: scope)) } catch let e as MError { values.append(.error(e)) }
            }
        }
        return .list(values)
    }

    private func evaluateRecord(_ bindings: [MBinding], in scope: MScope) throws -> MValue {
        let inner = letScope(bindings, parent: scope)
        var fields: [MField] = []
        for binding in bindings {
            try Task.checkCancellation()
            do { fields.append(MField(name: binding.name, value: try inner.thunks[binding.name]!.force(self))) }
            catch let e as MError { fields.append(MField(name: binding.name, value: .error(e))) }
        }
        return .record(fields)
    }

    private func fieldAccess(_ target: MValue, _ name: String, optional: Bool) throws -> MValue {
        switch target {
        case .record(let fields):
            if let field = fields.first(where: { $0.name == name }) {
                if case .error(let e) = field.value { throw e }
                return field.value
            }
        case .table(let table):
            if let index = table.index(ofColumn: name) { return MTables.column(table, index) }
        case .null where optional:
            return .null
        case .error(let e):
            throw e
        default:
            throw MError.expression("Không thể truy cập trường '\(name)' của giá trị \(target.kindName)")
        }
        if optional { return .null }
        throw MError.expression("Không tìm thấy trường '\(name)'")
    }

    private func itemAccess(_ target: MValue, _ index: MValue, optional: Bool) throws -> MValue {
        guard case .number(let d) = index, d == d.rounded(), d >= 0 else { throw MError.expression("Chỉ mục phải là số nguyên không âm") }
        let i = Int(d)
        switch target {
        case .list(let items):
            guard i < items.count else {
                if optional { return .null }
                throw MError.expression("Chỉ mục \(i) vượt quá số phần tử (\(items.count))")
            }
            if case .error(let e) = items[i] { throw e }
            return items[i]
        case .table(let table):
            guard i < table.rowCount else {
                if optional { return .null }
                throw MError.expression("Chỉ mục \(i) vượt quá số dòng (\(table.rowCount))")
            }
            return MTables.row(table, i)
        case .null where optional:
            return .null
        default:
            throw MError.expression("Không thể truy cập phần tử của giá trị \(target.kindName)")
        }
    }

    // MARK: Hàm

    private func closure(_ parameters: [MParameter], returnType: MTypeExpr?, body: MExpression, scope: MScope) throws -> MFunction {
        let resolved = try parameters.map { p in try p.type.map(MType.resolve) }
        let resultType = try returnType.map(MType.resolve)
        return MFunction(name: "(hàm)", parameters: parameters, observed: true) { [self] arguments in
            let inner = MScope(parent: scope)
            for (index, parameter) in parameters.enumerated() {
                let value = arguments[index]
                if let type = resolved[index], !type.accepts(value) {
                    throw MError.expression("Đối số '\(parameter.name)' không thuộc kiểu \(type.kind.rawValue)")
                }
                inner.thunks[parameter.name] = MThunk(name: parameter.name, value: value)
            }
            let result = try evaluate(body, in: inner)
            if let resultType, !resultType.accepts(result) {
                throw MError.expression("Kết quả không thuộc kiểu \(resultType.kind.rawValue)")
            }
            return result
        }
    }

    private func invoke(_ callee: MExpression, _ arguments: [MExpression], line: Int, in scope: MScope) throws -> MValue {
        try Task.checkCancellation()
        guard case .function(let function) = try evaluate(callee, in: scope) else {
            throw MError.expression("Chỉ có thể gọi giá trị kiểu hàm")
        }
        let required = function.parameters.filter { !$0.isOptional }.count
        guard arguments.count >= required, arguments.count <= function.parameters.count else {
            throw MError.expression("Số đối số không hợp lệ: \(function.name) cần \(required) đến \(function.parameters.count), nhận \(arguments.count)")
        }
        var values = try arguments.map { try evaluate($0, in: scope) }
        values.append(contentsOf: Array(repeating: MValue.null, count: function.parameters.count - values.count))
        return try function.implementation(values)
    }

    // MARK: try, error

    private func evaluateTry(_ protected: MExpression, otherwise: MExpression?, in scope: MScope) throws -> MValue {
        do {
            let value = try evaluate(protected, in: scope)
            if otherwise != nil { return value }
            return .record([MField(name: "HasError", value: .logical(false)), MField(name: "Value", value: value)])
        } catch let e as MError {
            if let otherwise { return try evaluate(otherwise, in: scope) }
            return .record([MField(name: "HasError", value: .logical(true)), MField(name: "Error", value: .record([
                MField(name: "Reason", value: .text(e.reason)), MField(name: "Message", value: .text(e.message)),
                MField(name: "Detail", value: e.detail.map { .text($0) } ?? .null),
            ]))])
        }
    }

    private func makeError(_ value: MValue) throws -> MError {
        switch value {
        case .text(let message): return MError.expression(message)
        case .record(let fields):
            func text(_ name: String) -> String? { if case .text(let s)? = fields.first(where: { $0.name == name })?.value { s } else { nil } }
            var detail = text("Detail")
            if detail == nil, let field = fields.first(where: { $0.name == "Detail" }), case .null = field.value {} else if detail == nil,
               let field = fields.first(where: { $0.name == "Detail" }), let n = MOperators.number(field.value) { detail = String(n) }
            return MError(reason: text("Reason") ?? "Expression.Error", message: text("Message") ?? "", detail: detail)
        default:
            throw MError.expression("error cần giá trị text hoặc record")
        }
    }
}
