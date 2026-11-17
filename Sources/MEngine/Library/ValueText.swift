// Phase F: Thư viện hàm M nhóm Text.
import Foundation
import ColumnStore

enum ValueText {
    /// Giá trị M thành text như `Text.From` (dùng cả khi `Table.Combine` gặp cột lẫn kiểu: Desktop nạp cột `any` thành chuỗi).
    static func textFrom(_ value: MValue) throws -> MValue {
        switch value {
        case .null:
            return .null
        case .text(let s):
            return .text(s)
        case .number(let n):
            if n.isNaN { return .text("NaN") }
            if n.isInfinite { return .text(n > 0 ? "Infinity" : "-Infinity") }
            if n == n.rounded() && abs(n) < 9e18 {
                return .text(String(Int64(n)))
            } else {
                let formatted = String(format: "%g", n)
                return .text(formatted)
            }
        case .currency(let c):
            let d = Double(c) / 10_000
            if d == d.rounded() && abs(d) < 9e18 {
                return .text(String(Int64(d)))
            } else {
                return .text(String(format: "%g", d))
            }
        case .logical(let b):
            return .text(b ? "true" : "false")
        case .date(let d):
            let civil = ValueDateHelper.civilFromSerial(d)
            return .text(String(format: "%04d-%02d-%02d", civil.year, civil.month, civil.day))
        case .dateTime(let d):
            let datePart = floor(d)
            let timePart = (d - datePart) * 86_400
            let civil = ValueDateHelper.civilFromSerial(datePart)
            let secs = timePart.isFinite ? Int(timePart.rounded()) : 0
            let h = (secs / 3600) % 24
            let m = (secs / 60) % 60
            let s = secs % 60
            return .text(String(format: "%04d-%02d-%02d %02d:%02d:%02d", civil.year, civil.month, civil.day, h, m, s))
        case .time(let t):
            let secs = t.isFinite ? Int((t * 86_400).rounded()) : 0
            let h = (secs / 3600) % 24
            let m = (secs / 60) % 60
            let s = secs % 60
            return .text(String(format: "%02d:%02d:%02d", h, m, s))
        default:
            throw MError.expression("Text.From: chưa hỗ trợ chuyển đổi từ kiểu \(value.kindName)")
        }
    }

    static let functions: [MFunction] = [
        MFunction(
            name: "Text.Upper",
            parameters: [MParameter(name: "text"), MParameter(name: "culture", isOptional: true)],
            observed: true
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.Upper")
            return .text(s.uppercased())
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.Lower",
            parameters: [MParameter(name: "text"), MParameter(name: "culture", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.Lower")
            return .text(s.lowercased())
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.Proper",
            parameters: [MParameter(name: "text"), MParameter(name: "culture", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.Proper")
            return .text(s.capitalized)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.Trim",
            parameters: [MParameter(name: "text"), MParameter(name: "trim", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.Trim")
            let trimChars: CharacterSet
            if let t = args.optional(1) {
                if case .text(let chars) = t {
                    trimChars = CharacterSet(charactersIn: chars)
                } else if case .null = t {
                    trimChars = .whitespacesAndNewlines
                } else {
                    throw MError.expression("Text.Trim: đối số 2 phải là text hoặc null, nhận \(t.kindName)")
                }
            } else {
                trimChars = .whitespacesAndNewlines
            }
            return .text(s.trimmingCharacters(in: trimChars))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.Clean",
            parameters: [MParameter(name: "text")],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.Clean")
            let cleaned = s.unicodeScalars.filter { scalar in
                !(scalar.value < 32 || scalar.value == 127)
            }
            return .text(String(String.UnicodeScalarView(cleaned)))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.Length",
            parameters: [MParameter(name: "text")],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.Length")
            return .number(Double(s.count))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.Contains",
            parameters: [MParameter(name: "string"), MParameter(name: "substring"), MParameter(name: "comparer", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.Contains")
            let sub = try args.text(1, "Text.Contains")
            return .logical(s.contains(sub))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.StartsWith",
            parameters: [MParameter(name: "string"), MParameter(name: "substring"), MParameter(name: "comparer", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.StartsWith")
            let sub = try args.text(1, "Text.StartsWith")
            return .logical(s.hasPrefix(sub))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.EndsWith",
            parameters: [MParameter(name: "string"), MParameter(name: "substring"), MParameter(name: "comparer", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.EndsWith")
            let sub = try args.text(1, "Text.EndsWith")
            return .logical(s.hasSuffix(sub))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.Replace",
            parameters: [MParameter(name: "text"), MParameter(name: "old"), MParameter(name: "new")],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.Replace")
            let old = try args.text(1, "Text.Replace")
            let new = try args.text(2, "Text.Replace")
            return .text(s.replacingOccurrences(of: old, with: new))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.Combine",
            parameters: [MParameter(name: "texts"), MParameter(name: "separator", isOptional: true)],
            observed: false
        ) { args in
            let list = try args.list(0, "Text.Combine")
            let separator = try args.optional(1).map { v in
                guard case .text(let s) = v else { throw MError.expression("Text.Combine: separator phải là text") }
                return s
            } ?? ""
            var parts: [String] = []
            for item in list {
                switch item {
                case .null:
                    continue
                case .text(let s):
                    parts.append(s)
                default:
                    throw MError.expression("Text.Combine: phần tử danh sách phải là text hoặc null, nhận \(item.kindName)")
                }
            }
            return .text(parts.joined(separator: separator))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.From",
            parameters: [MParameter(name: "value"), MParameter(name: "culture", isOptional: true)],
            observed: false
        ) { args in
            return try textFrom(args[0])
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.Start",
            parameters: [MParameter(name: "text"), MParameter(name: "count")],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.Start")
            let count = try MInt.from(args.number(1, "Text.Start"), "Text.Start")
            guard count >= 0 else { throw MError.expression("Text.Start: count không được âm") }
            return .text(String(s.prefix(count)))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.End",
            parameters: [MParameter(name: "text"), MParameter(name: "count")],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.End")
            let count = try MInt.from(args.number(1, "Text.End"), "Text.End")
            guard count >= 0 else { throw MError.expression("Text.End: count không được âm") }
            return .text(String(s.suffix(count)))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Text.PadStart",
            parameters: [MParameter(name: "text"), MParameter(name: "count"), MParameter(name: "character", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.PadStart")
            let targetCount = try MInt.from(args.number(1, "Text.PadStart"), "Text.PadStart")
            guard targetCount >= 0 else { throw MError.expression("Text.PadStart: count không được âm") }
            if s.count >= targetCount { return .text(s) }
            let padChar: Character
            if let c = args.optional(2) {
                let charText = try args.text(2, "Text.PadStart")
                padChar = charText.first ?? " "
            } else {
                padChar = " "
            }
            let padNeeded = targetCount - s.count
            let padding = String(repeating: padChar, count: padNeeded)
            return .text(padding + s)
        }
    ]
}
