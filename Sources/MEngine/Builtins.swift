// Phase F (T049): giá trị dựng sẵn của ngôn ngữ (không thuộc thư viện hàm của gói F-MFUN): `#table`, `#date`, `#datetime`,
// `#time`, `#duration` và hằng kiểu (`Int64.Type`, ...).

import ColumnStore

enum MBuiltins {
    static func value(named name: String, interpreter: Interpreter) -> MValue? {
        if let type = MType.libraryConstants[name] { return .type(type) }
        switch name {
        case "#table": return .function(table)
        case "#date": return .function(date)
        case "#datetime": return .function(dateTime)
        case "#time": return .function(time)
        case "#duration": return .function(duration)
        // Hằng số của thư viện chuẩn (tài liệu M): Order.Ascending 0 / Descending 1; QuoteStyle.None 0 / Csv 1.
        case "Order.Ascending", "QuoteStyle.None": return .number(0)
        case "Order.Descending", "QuoteStyle.Csv": return .number(1)
        default: return nil
        }
    }

    private static func ints(_ args: [MValue], _ names: [String]) throws -> [Double] {
        try zip(args, names).map { value, name in
            guard let n = MOperators.number(value), n == n.rounded() || name == "giây" else {
                throw MError.expression("Giá trị \(name) phải là số")
            }
            return n
        }
    }

    private static let table = MFunction(
        name: "#table", parameters: [MParameter(name: "columns"), MParameter(name: "rows")], observed: true
    ) { args in
        var names: [String] = []
        var types: [MType?] = []
        switch args[0] {
        case .list(let items):
            for item in items {
                guard case .text(let name) = item else { throw MError.expression("Tên cột của #table phải là text") }
                names.append(name)
                types.append(nil)
            }
        case .type(let type) where type.kind == .table:
            for field in type.fields {
                names.append(field.name)
                types.append(field.type)
            }
        default:
            throw MError.unsupported("#table với tham số cột kiểu \(args[0].kindName)")
        }
        guard case .list(let rowValues) = args[1] else { throw MError.expression("Các hàng của #table phải là danh sách") }
        var rows: [[MValue]] = []
        for (index, row) in rowValues.enumerated() {
            if case .error(let e) = row { throw e }
            guard case .list(let cells) = row else { throw MError.expression("Hàng \(index + 1) của #table phải là danh sách") }
            guard cells.count == names.count else {
                throw MError.expression("Số cột của hàng \(index + 1) (\(cells.count)) khác số cột của bảng (\(names.count))")
            }
            rows.append(cells)
        }
        return .table(try MTables.build(names: names, types: types, rows: rows))
    }

    private static let date = MFunction(
        name: "#date", parameters: [MParameter(name: "year"), MParameter(name: "month"), MParameter(name: "day")], observed: true
    ) { args in
        let v = try ints(args, ["năm", "tháng", "ngày"])
        guard let serial = MDates.serial(year: Int(v[0]), month: Int(v[1]), day: Int(v[2])) else {
            if !(1...12).contains(Int(v[1])) { throw MError.expression("Giá trị tháng không hợp lệ: \(Int(v[1]))") }
            throw MError.expression("Ngày không tồn tại: \(Int(v[0]))-\(Int(v[1]))-\(Int(v[2]))")
        }
        return .date(serial)
    }

    private static let dateTime = MFunction(
        name: "#datetime", parameters: ["year", "month", "day", "hour", "minute", "second"].map { MParameter(name: $0) }, observed: true
    ) { args in
        let v = try ints(args, ["năm", "tháng", "ngày", "giờ", "phút", "giây"])
        guard let serial = MDates.serial(year: Int(v[0]), month: Int(v[1]), day: Int(v[2])) else {
            throw MError.expression("Giá trị tháng hoặc ngày không hợp lệ")
        }
        return .dateTime(serial + (v[3] * 3600 + v[4] * 60 + v[5]) / 86_400)
    }

    private static let time = MFunction(
        name: "#time", parameters: ["hour", "minute", "second"].map { MParameter(name: $0) }, observed: true
    ) { args in
        let v = try ints(args, ["giờ", "phút", "giây"])
        return .time((v[0] * 3600 + v[1] * 60 + v[2]) / 86_400)
    }

    private static let duration = MFunction(
        name: "#duration", parameters: ["days", "hours", "minutes", "seconds"].map { MParameter(name: $0) }, observed: true
    ) { args in
        let v = try ints(args, ["ngày", "giờ", "phút", "giây"])
        return .duration(v[0] + (v[1] * 3600 + v[2] * 60 + v[3]) / 86_400)
    }
}
