// Phase F: Thư viện hàm M nhóm Number.
import PBIXKit
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

        // Desktop 2.159 (2026-11-17): mặc định RoundingMode.ToEven, làm tròn theo giá trị thập phân (`MRounding`).
        MFunction(
            name: "Number.Round",
            parameters: [MParameter(name: "number"), MParameter(name: "digits", isOptional: true), MParameter(name: "roundingMode", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let n = try args.number(0, "Number.Round")
            let digits = try args.optional(1).map { v -> Int in
                guard let d = MOperators.number(v) else { throw MError.expression(lt("Number.Round: digits phải là số", "Number.Round: digits must be a number")) }
                return try MInt.from(d, "Number.Round")
            } ?? 0
            let mode = try args.optional(2).map { v -> Int in
                guard let m = MOperators.number(v), (0...4).contains(m) else { throw MError.expression(lt("Number.Round: roundingMode không hợp lệ", "Number.Round: invalid roundingMode")) }
                return Int(m)
            } ?? 4
            return .number(MRounding.round(n, digits: digits, mode: mode))
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
                guard let d = MOperators.number(v) else { throw MError.expression(lt("Number.RoundDown: digits phải là số", "Number.RoundDown: digits must be a number")) }
                return try MInt.from(d, "Number.RoundDown")
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
                guard let d = MOperators.number(v) else { throw MError.expression(lt("Number.RoundUp: digits phải là số", "Number.RoundUp: digits must be a number")) }
                return try MInt.from(d, "Number.RoundUp")
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

/// Làm tròn như `Number.Round` của Power Query (quan sát Desktop 2.159, 2026-11-17): trên giá trị thập phân của số (chuỗi ngắn nhất của
/// Double: 2.675 là 2,675 chứ không phải 2,67499…), chế độ chỉ quyết điểm giữa: Up 0 (về +∞), Down 1 (về −∞), AwayFromZero 2,
/// TowardZero 3, ToEven 4 (mặc định).
enum MRounding {
    static func round(_ n: Double, digits: Int, mode: Int) -> Double {
        guard n.isFinite, digits <= 20 else { return n }
        if digits < -20 { return 0 }
        guard var value = Decimal(string: "\(n)") else { return n }
        let scale = pow(Decimal(10), abs(digits))
        value = digits >= 0 ? value * scale : value / scale
        var floorValue = Decimal()
        NSDecimalRound(&floorValue, &value, 0, .down)
        let fraction = value - floorValue
        let half = Decimal(string: "0.5")!
        let up: Bool
        if fraction > half { up = true } else if fraction < half { up = false } else {
            switch mode {
            case 0: up = true
            case 1: up = false
            case 2: up = value > 0
            case 3: up = value < 0
            default:
                var two = floorValue / 2, whole = Decimal()
                NSDecimalRound(&whole, &two, 0, .down)
                up = whole * 2 != floorValue   // phần nguyên lẻ thì lên số chẵn
            }
        }
        var result = up ? floorValue + 1 : floorValue
        result = digits >= 0 ? result / scale : result * scale
        return NSDecimalNumber(decimal: result).doubleValue
    }
}
