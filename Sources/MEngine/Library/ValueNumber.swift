// Phase F: Thư viện hàm M nhóm Number.
import Foundation
import ColumnStore

enum ValueNumber {
    static let functions: [MFunction] = [
        MFunction(
            name: "Number.From",
            parameters: [MParameter(name: "value"), MParameter(name: "culture", isOptional: true)],
            observed: true
        ) { args in
            switch args[0] {
            case .null:
                return .null
            case .number(let n):
                return .number(n)
            case .currency(let c):
                return .number(Double(c) / 10_000)
            case .logical(let b):
                return .number(b ? 1 : 0)
            case .text(let s):
                // Văn hoá en-US: dấu phẩy ',' là phân cách nghìn (như quan sát Desktop: "1,5" -> 15).
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return .null }
                let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
                guard let val = Double(cleaned) else {
                    throw MError.expression("DataFormat.Error: We couldn't convert to Number. Details: \(s)")
                }
                return .number(val)
            default:
                throw MError.expression("DataFormat.Error: We couldn't convert to Number. Details: \(args[0].kindName)")
            }
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Number.Round",
            parameters: [MParameter(name: "number"), MParameter(name: "digits", isOptional: true), MParameter(name: "roundingMode", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let n = try args.number(0, "Number.Round")
            let digits = try args.optional(1).map { v -> Int in
                guard let d = MOperators.number(v) else { throw MError.expression("Number.Round: digits phải là số") }
                return Int(d)
            } ?? 0
            let factor = pow(10.0, Double(digits))
            let rounded = (n * factor).rounded() / factor
            return .number(rounded)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Number.Abs",
            parameters: [MParameter(name: "number")],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let n = try args.number(0, "Number.Abs")
            return .number(abs(n))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Number.RoundDown",
            parameters: [MParameter(name: "number"), MParameter(name: "digits", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let n = try args.number(0, "Number.RoundDown")
            let digits = try args.optional(1).map { v -> Int in
                guard let d = MOperators.number(v) else { throw MError.expression("Number.RoundDown: digits phải là số") }
                return Int(d)
            } ?? 0
            let factor = pow(10.0, Double(digits))
            let down = floor(n * factor) / factor
            return .number(down)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Number.RoundUp",
            parameters: [MParameter(name: "number"), MParameter(name: "digits", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let n = try args.number(0, "Number.RoundUp")
            let digits = try args.optional(1).map { v -> Int in
                guard let d = MOperators.number(v) else { throw MError.expression("Number.RoundUp: digits phải là số") }
                return Int(d)
            } ?? 0
            let factor = pow(10.0, Double(digits))
            let up = ceil(n * factor) / factor
            return .number(up)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Number.Mod",
            parameters: [MParameter(name: "number"), MParameter(name: "divisor")],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            if case .null = args[1] { return .null }
            let n = try args.number(0, "Number.Mod")
            let d = try args.number(1, "Number.Mod")
            guard d != 0 else { throw MError.expression("Number.Mod: chia cho 0") }
            return .number(n.truncatingRemainder(dividingBy: d))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Number.IntegerDivide",
            parameters: [MParameter(name: "number"), MParameter(name: "divisor")],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            if case .null = args[1] { return .null }
            let n = try args.number(0, "Number.IntegerDivide")
            let d = try args.number(1, "Number.IntegerDivide")
            guard d != 0 else { throw MError.expression("Number.IntegerDivide: chia cho 0") }
            return .number(trunc(n / d))
        }
    ]
}
