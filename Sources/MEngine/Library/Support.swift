// Phase F (T049): hàm trợ giúp cho thư viện M (nhóm F-MFUN và lead): lấy đối số có kiểu, gọi hàm M, báo lỗi thống nhất.

import ColumnStore

extension Array where Element == MValue {
    /// Đối số bảng thứ `index` của hàm `function`.
    public func table(_ index: Int, _ function: String) throws -> TableData {
        guard case .table(let t) = self[index] else { throw MError.expression("\(function): đối số \(index + 1) phải là bảng, nhận \(self[index].kindName)") }
        return t
    }

    public func text(_ index: Int, _ function: String) throws -> String {
        guard case .text(let s) = self[index] else { throw MError.expression("\(function): đối số \(index + 1) phải là text, nhận \(self[index].kindName)") }
        return s
    }

    public func number(_ index: Int, _ function: String) throws -> Double {
        guard let n = MOperators.number(self[index]) else { throw MError.expression("\(function): đối số \(index + 1) phải là số, nhận \(self[index].kindName)") }
        return n
    }

    public func list(_ index: Int, _ function: String) throws -> [MValue] {
        guard case .list(let l) = self[index] else { throw MError.expression("\(function): đối số \(index + 1) phải là danh sách, nhận \(self[index].kindName)") }
        return l
    }

    public func function(_ index: Int, _ function: String) throws -> MFunction {
        guard case .function(let f) = self[index] else { throw MError.expression("\(function): đối số \(index + 1) phải là hàm, nhận \(self[index].kindName)") }
        return f
    }

    /// Đối số tuỳ chọn: `nil` khi là `null`.
    public func optional(_ index: Int) -> MValue? {
        if case .null = self[index] { return nil }
        return self[index]
    }
}

extension MFunction {
    /// Gọi hàm M từ thư viện (ví dụ vị từ của `Table.SelectRows`), đủ tham số tuỳ chọn là `null`.
    public func call(_ arguments: [MValue]) throws -> MValue {
        guard arguments.count <= parameters.count else { throw MError.expression("\(name): quá nhiều đối số") }
        let padded = arguments + Array(repeating: MValue.null, count: parameters.count - arguments.count)
        return try implementation(padded)
    }
}
