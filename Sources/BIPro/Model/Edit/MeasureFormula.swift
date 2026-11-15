import Foundation

/// Phase E (R11): văn bản thanh công thức của một measure, `Tên = biểu thức` như Desktop.
enum MeasureFormula {
    struct Parts: Equatable {
        var name: String
        var expression: String
    }

    /// Tách `Tên = biểu thức`. Tên có thể trong `[...]` hoặc `'...'`; dấu `=` đầu tiên ngoài tên là chỗ tách. Nil khi thiếu
    /// tên hoặc thiếu dấu `=`. Biểu thức rỗng được trả `""` (người dùng chưa gõ).
    static func parse(_ text: String) -> Parts? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var index = trimmed.startIndex
        var name: String
        func scan(open: Character, close: Character) -> String? {
            var cursor = trimmed.index(after: index)
            var value = ""
            while cursor < trimmed.endIndex {
                let ch = trimmed[cursor]
                if ch == close {
                    let next = trimmed.index(after: cursor)
                    if next < trimmed.endIndex, trimmed[next] == close { value.append(close); cursor = trimmed.index(after: next); continue }
                    index = next
                    return value
                }
                value.append(ch)
                cursor = trimmed.index(after: cursor)
            }
            return nil
        }
        switch trimmed[index] {
        case "[":
            guard let quoted = scan(open: "[", close: "]") else { return nil }
            name = quoted
        case "'":
            guard let quoted = scan(open: "'", close: "'") else { return nil }
            name = quoted
        default:
            guard let equals = trimmed.firstIndex(of: "=") else { return nil }
            name = String(trimmed[index..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            index = equals
        }
        // Sau tên (kể cả tên trong dấu) phải là dấu `=`.
        let rest = trimmed[index...].drop(while: { $0 == " " || $0 == "\t" })
        guard rest.first == "=" else { return nil }
        guard !name.isEmpty else { return nil }
        let expression = rest.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        return Parts(name: name, expression: expression)
    }

    /// `Tên = biểu thức`; biểu thức nhiều dòng thì xuống dòng sau dấu `=`.
    static func format(name: String, expression: String) -> String {
        expression.contains("\n") ? "\(name) =\n\(expression)" : "\(name) = \(expression)"
    }
}
