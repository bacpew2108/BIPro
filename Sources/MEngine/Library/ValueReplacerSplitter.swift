// Phase F: Thư viện hàm M nhóm Replacer, Splitter, Combiner.
import PBIXKit
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
                guard let n = MOperators.number(v) else { throw MError.expression(lt("Splitter.SplitTextByDelimiter: quoteStyle phải là số", "Splitter.SplitTextByDelimiter: quoteStyle must be a number")) }
                return try MInt.from(n, "Splitter.SplitTextByDelimiter")
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

        // Wave 3C (T021): Splitter theo số ký tự lặp lại và theo danh sách vị trí
        MFunction(
            name: "Splitter.SplitTextByRepeatedLengths",
            parameters: [MParameter(name: "length")],
            observed: false
        ) { args in
            let length = try MInt.from(args.number(0, "Splitter.SplitTextByRepeatedLengths"), "Splitter.SplitTextByRepeatedLengths")
            guard length > 0 else { throw MError.expression(lt("Splitter.SplitTextByRepeatedLengths: length phải > 0", "Splitter.SplitTextByRepeatedLengths: length must be > 0")) }
            let inner = MFunction(
                name: "Splitter.SplitTextByRepeatedLengths_inner",
                parameters: [MParameter(name: "text")],
                observed: false
            ) { innerArgs in
                if case .null = innerArgs[0] { return .null }
                let text = try innerArgs.text(0, "Splitter.SplitTextByRepeatedLengths")
                if text.isEmpty { return .list([.text("")]) }
                let chars = Array(text)
                var parts: [MValue] = []
                var i = 0
                while i < chars.count {
                    let end = min(i + length, chars.count)
                    parts.append(.text(String(chars[i..<end])))
                    i = end
                }
                return .list(parts)
            }
            return .function(inner)
        },

        MFunction(
            name: "Splitter.SplitTextByPositions",
            parameters: [MParameter(name: "positions"), MParameter(name: "startAtEnd", isOptional: true)],
            observed: false
        ) { args in
            let posList = try args.list(0, "Splitter.SplitTextByPositions")
            let positions = try posList.map { v -> Int in
                guard let n = MOperators.number(v) else { throw MError.expression(lt("Splitter.SplitTextByPositions: vị trí phải là số", "Splitter.SplitTextByPositions: positions must be numbers")) }
                return try MInt.from(n, "Splitter.SplitTextByPositions")
            }.sorted()
            let inner = MFunction(
                name: "Splitter.SplitTextByPositions_inner",
                parameters: [MParameter(name: "text")],
                observed: false
            ) { innerArgs in
                if case .null = innerArgs[0] { return .null }
                let text = try innerArgs.text(0, "Splitter.SplitTextByPositions")
                let chars = Array(text)
                guard !positions.isEmpty else { return .list([.text(text)]) }
                var parts: [MValue] = []
                for idx in positions.indices {
                    let s = min(max(positions[idx], 0), chars.count)
                    let e = idx + 1 < positions.count ? min(max(positions[idx + 1], s), chars.count) : chars.count
                    parts.append(.text(String(chars[s..<e])))
                }
                return .list(parts)
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
                        throw MError.expression(lt("Combiner: phần tử danh sách phải là text hoặc null, nhận \(item.kindName)", "Combiner: a list item must be text or null, got \(item.kindName)"))
                    }
                }
                return .text(parts.joined(separator: delimiter))
            }
            return .function(inner)
        }
    ]
}
