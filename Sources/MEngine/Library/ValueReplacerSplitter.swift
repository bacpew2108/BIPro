// Phase F: Thư viện hàm M nhóm Replacer, Splitter, Combiner.
import Foundation
import ColumnStore

enum ValueReplacerSplitter {
    static func splitCsv(input: String, delimiter: String) -> [String] {
        guard !delimiter.isEmpty else { return [input] }
        var result: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(input)
        let delimChars = Array(delimiter)
        var i = 0
        while i < chars.count {
            if chars[i] == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 2
                    continue
                }
                inQuotes.toggle()
                i += 1
            } else if !inQuotes && chars[i...].starts(with: delimChars) {
                result.append(current)
                current = ""
                i += delimChars.count
            } else {
                current.append(chars[i])
                i += 1
            }
        }
        result.append(current)
        return result
    }

    static let functions: [MFunction] = [
        MFunction(
            name: "Replacer.ReplaceText",
            parameters: [MParameter(name: "text"), MParameter(name: "old"), MParameter(name: "new")],
            observed: true
        ) { args in
            if case .null = args[0] { return .null }
            let s = try args.text(0, "Replacer.ReplaceText")
            let old = try args.text(1, "Replacer.ReplaceText")
            let new = try args.text(2, "Replacer.ReplaceText")
            return .text(s.replacingOccurrences(of: old, with: new))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Replacer.ReplaceValue",
            parameters: [MParameter(name: "value"), MParameter(name: "old"), MParameter(name: "new")],
            observed: false
        ) { args in
            let val = args[0]
            let old = args[1]
            let new = args[2]
            return MOperators.equals(val, old) ? new : val
        },

        MFunction(
            name: "Splitter.SplitTextByDelimiter",
            parameters: [MParameter(name: "delimiter"), MParameter(name: "quoteStyle", isOptional: true)],
            observed: true
        ) { args in
            let delimiter = try args.text(0, "Splitter.SplitTextByDelimiter")
            let quoteStyle = try args.optional(1).map { v -> Int in
                guard let n = MOperators.number(v) else { throw MError.expression("Splitter.SplitTextByDelimiter: quoteStyle phải là số") }
                return Int(n)
            } ?? 0

            let inner = MFunction(
                name: "Splitter.SplitTextByDelimiter_inner",
                parameters: [MParameter(name: "text")],
                observed: true
            ) { innerArgs in
                if case .null = innerArgs[0] { return .null }
                let text = try innerArgs.text(0, "Splitter")
                let parts: [String]
                if quoteStyle == 1 { // QuoteStyle.Csv
                    parts = splitCsv(input: text, delimiter: delimiter)
                } else {
                    parts = text.components(separatedBy: delimiter)
                }
                return .list(parts.map { .text($0) })
            }
            return .function(inner)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Combiner.CombineTextByDelimiter",
            parameters: [MParameter(name: "delimiter")],
            observed: false
        ) { args in
            let delimiter = try args.text(0, "Combiner.CombineTextByDelimiter")
            let inner = MFunction(
                name: "Combiner.CombineTextByDelimiter_inner",
                parameters: [MParameter(name: "list")],
                observed: false
            ) { innerArgs in
                let list = try innerArgs.list(0, "Combiner")
                var parts: [String] = []
                for item in list {
                    switch item {
                    case .null:
                        continue
                    case .text(let s):
                        parts.append(s)
                    default:
                        throw MError.expression("Combiner: phần tử danh sách phải là text hoặc null, nhận \(item.kindName)")
                    }
                }
                return .text(parts.joined(separator: delimiter))
            }
            return .function(inner)
        }
    ]
}
