// Phase F (T082): chuyển kết quả cột/bảng tính toán thành dữ liệu cột và suy kiểu dữ liệu từ giá trị.
// [SUY ĐOÁN] Desktop suy kiểu từ biểu thức (tĩnh); ở đây suy từ giá trị đã tính: số nguyên lẫn số thực là số thực, tiền tệ lẫn số
// nguyên là tiền tệ, mọi giá trị trống là chuỗi. Lẫn kiểu khác (chuỗi với số…) thì từ chối như Desktop từ chối biểu thức kiểu variant.
import PBIXKit
import ColumnStore

public enum CalculatedData {
    /// Kiểu chung của các giá trị (bỏ BLANK). Ném lỗi khi lẫn kiểu không gộp được.
    public static func inferType(_ values: [Value]) throws(DAXError) -> DAXType {
        var seen: Set<DAXType> = []
        for value in values {
            switch value {
            case .blank: continue
            case .integer: seen.insert(.integer)
            case .double: seen.insert(.double)
            case .currency: seen.insert(.currency)
            case .string: seen.insert(.string)
            case .boolean: seen.insert(.boolean)
            case .dateTime: seen.insert(.dateTime)
            }
            if seen.count > 2 { break }
        }
        if seen.isEmpty { return .string }
        if seen.count == 1 { return seen.first! }
        if seen == [.integer, .double] { return .double }
        if seen == [.integer, .currency] { return .currency }
        if seen == [.double, .currency] { return .double }
        throw DAXError(.typeMismatch, lt("biểu thức trả nhiều kiểu dữ liệu (\(seen.map { "\($0)" }.sorted().joined(separator: ", "))), không dùng làm cột tính toán được", "the expression returns multiple data types (\(seen.map { "\($0)" }.sorted().joined(separator: ", "))) and can't be used as a calculated column"))
    }

    /// Dữ liệu cột kiểu `type` từ các giá trị. Giá trị không chuyển được sang kiểu đó thì lỗi.
    public static func columnData(_ values: [Value], type: DAXType) throws(DAXError) -> ColumnData {
        func fail(_ v: Value) -> DAXError { DAXError(.typeMismatch, lt("giá trị \(v) không chuyển được sang kiểu \(type)", "value \(v) can't be converted to type \(type)")) }
        switch type {
        case .integer:
            var out: [Int64?] = []; out.reserveCapacity(values.count)
            for v in values {
                switch v {
                case .blank: out.append(nil)
                case .integer(let i): out.append(i)
                case .boolean(let b): out.append(b ? 1 : 0)
                default: throw fail(v)
                }
            }
            return ColumnBuilder.integers(out)
        case .double:
            var out: [Double?] = []; out.reserveCapacity(values.count)
            for v in values {
                switch v {
                case .blank: out.append(nil)
                case .integer(let i): out.append(Double(i))
                case .double(let d): out.append(d)
                case .currency(let c): out.append(Double(c) / 10_000)
                default: throw fail(v)
                }
            }
            return ColumnBuilder.doubles(out)
        case .currency:
            var out: [Int64?] = []; out.reserveCapacity(values.count)
            for v in values {
                switch v {
                case .blank: out.append(nil)
                case .integer(let i): out.append(i * 10_000)
                case .currency(let c): out.append(c)
                default: throw fail(v)
                }
            }
            return ColumnBuilder.currency(out)
        case .string:
            var out: [String?] = []; out.reserveCapacity(values.count)
            for v in values {
                if case .blank = v { out.append(nil) } else { out.append(v.asText()) }
            }
            // Như kho Desktop: bỏ khoảng trắng cuối, gộp hoa thường (VM-F12, T022).
            return ColumnBuilder.strings(ModelText.normalize(out))
        case .boolean:
            var out: [Bool?] = []; out.reserveCapacity(values.count)
            for v in values {
                switch v {
                case .blank: out.append(nil)
                case .boolean(let b): out.append(b)
                default: throw fail(v)
                }
            }
            return ColumnBuilder.booleans(out)
        case .dateTime:
            var out: [Double?] = []; out.reserveCapacity(values.count)
            for v in values {
                switch v {
                case .blank: out.append(nil)
                case .dateTime(let d): out.append(d)
                default: throw fail(v)
                }
            }
            return ColumnBuilder.dateTimes(out)
        }
    }
}
