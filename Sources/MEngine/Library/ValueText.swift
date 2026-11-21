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
        },

        // Wave 3C (T021): Trích xuất chuỗi theo dấu phân cách / phạm vi
        MFunction(
            name: "Text.BeforeDelimiter",
            parameters: [MParameter(name: "text"), MParameter(name: "delimiter"), MParameter(name: "index", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.BeforeDelimiter")
            let delim = try args.text(1, "Text.BeforeDelimiter")
            guard !delim.isEmpty else { return .text(s) }
            let skip = try args.optional(2).map { try MInt.from(MOperators.number($0) ?? 0, "Text.BeforeDelimiter") } ?? 0
            let parts = s.components(separatedBy: delim)
            guard skip >= 0, skip < parts.count - 1 else { return .text(s) }
            return .text(parts.prefix(skip + 1).joined(separator: delim))
        },

        MFunction(
            name: "Text.AfterDelimiter",
            parameters: [MParameter(name: "text"), MParameter(name: "delimiter"), MParameter(name: "index", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.AfterDelimiter")
            let delim = try args.text(1, "Text.AfterDelimiter")
            guard !delim.isEmpty else { return .text("") }
            let skip = try args.optional(2).map { try MInt.from(MOperators.number($0) ?? 0, "Text.AfterDelimiter") } ?? 0
            let parts = s.components(separatedBy: delim)
            guard skip >= 0, skip + 1 < parts.count else { return .text("") }
            return .text(parts.dropFirst(skip + 1).joined(separator: delim))
        },

        MFunction(
            name: "Text.BetweenDelimiters",
            parameters: [
                MParameter(name: "text"),
                MParameter(name: "startDelimiter"),
                MParameter(name: "endDelimiter"),
                MParameter(name: "startIndex", isOptional: true),
                MParameter(name: "endIndex", isOptional: true)
            ],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.BetweenDelimiters")
            let startDelim = try args.text(1, "Text.BetweenDelimiters")
            let endDelim = try args.text(2, "Text.BetweenDelimiters")
            guard !startDelim.isEmpty, !endDelim.isEmpty else { return .text("") }
            let startSkip = try args.optional(3).map { try MInt.from(MOperators.number($0) ?? 0, "Text.BetweenDelimiters") } ?? 0
            let endSkip = try args.optional(4).map { try MInt.from(MOperators.number($0) ?? 0, "Text.BetweenDelimiters") } ?? 0
            let startParts = s.components(separatedBy: startDelim)
            guard startSkip >= 0, startSkip + 1 < startParts.count else { return .text("") }
            let remainder = startParts.dropFirst(startSkip + 1).joined(separator: startDelim)
            let endParts = remainder.components(separatedBy: endDelim)
            guard endSkip >= 0, endSkip < endParts.count - 1 else { return .text("") }
            return .text(endParts.prefix(endSkip + 1).joined(separator: endDelim))
        },

        MFunction(
            name: "Text.Range",
            parameters: [MParameter(name: "text"), MParameter(name: "offset"), MParameter(name: "count", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Text.Range")
            let offset = try MInt.from(args.number(1, "Text.Range"), "Text.Range")
            guard offset >= 0, offset <= s.count else {
                throw MError.expression("Text.Range: offset \(offset) nằm ngoài độ dài chuỗi \(s.count)")
            }
            let startIdx = s.index(s.startIndex, offsetBy: offset)
            if let countVal = args.optional(2) {
                guard let n = MOperators.number(countVal) else { throw MError.expression("Text.Range: count phải là số") }
                let count = try MInt.from(n, "Text.Range")
                guard count >= 0, offset + count <= s.count else {
                    throw MError.expression("Text.Range: count \(count) vượt quá cuối chuỗi")
                }
                let endIdx = s.index(startIdx, offsetBy: count)
                return .text(String(s[startIdx..<endIdx]))
            }
            return .text(String(s[startIdx...]))
        }
    ]
}
