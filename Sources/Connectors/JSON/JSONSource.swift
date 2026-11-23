import PBIXKit
import Foundation
import ColumnStore

public struct JSONSource: DataSource {
    public let kind: SourceKind = .json
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func items() async throws -> [any SourceItem] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SourceError.unreadable(lt("File không tồn tại: \(url.lastPathComponent)", "The file doesn't exist: \(url.lastPathComponent)"))
        }
        let name = url.deletingPathExtension().lastPathComponent
        return [JSONItem(name: name, url: url)]
    }
}

private struct JSONItem: SourceItem, Sendable {
    let name: String
    let kind: SourceItemKind = .record
    let columns: [SourceColumn]? = nil
    let rowCountHint: Int? = nil
    let url: URL

    func preview(limit: Int) async throws -> TableData {
        let table = try await parse(progress: nil)
        return table.prefix(limit)
    }

    func load(progress: SourceProgress?) async throws -> TableData {
        try await parse(progress: progress)
    }

    private func parse(progress: SourceProgress?) async throws -> TableData {
        if Task.isCancelled { throw SourceError.cancelled }
        progress?(0.0)

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SourceError.unreadable(lt("Không thể đọc file: \(url.lastPathComponent)", "Couldn't read the file: \(url.lastPathComponent)"))
        }

        if data.isEmpty {
            throw SourceError.empty
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw SourceError.unreadable(lt("JSON không hợp lệ: \(error.localizedDescription)", "Invalid JSON: \(error.localizedDescription)"))
        }

        if Task.isCancelled { throw SourceError.cancelled }

        // [SUY ĐOÁN] Suy luận cấu trúc bảng từ JSON gốc:
        // 1. Mảng các đối tượng (bản ghi)
        // 2. Một đối tượng đơn (bảng 1 hàng)
        // 3. Mảng các giá trị đơn (bảng 1 cột Value)
        let table: TableData
        if let records = jsonObject as? [[String: Any]] {
            table = try buildTableFromRecords(records: records, rawData: data)
        } else if let singleObj = jsonObject as? [String: Any] {
            table = try buildTableFromRecords(records: [singleObj], rawData: data)
        } else if let primitives = jsonObject as? [Any] {
            table = try buildTableFromPrimitives(primitives: primitives)
        } else {
            throw SourceError.unreadable(lt("Cấu trúc JSON gốc không được hỗ trợ", "The root JSON structure isn't supported"))
        }

        progress?(1.0)
        return table
    }

    /// [SUY ĐOÁN] Trích xuất thứ tự khoá theo lần xuất hiện đầu tiên trong văn bản JSON
    private func extractKeyOrder(from rawData: Data, records: [[String: Any]]) -> [String] {
        var orderedKeys: [String] = []
        var seen = Set<String>()

        if let text = String(data: rawData, encoding: .utf8) {
            // Regex tìm các key "key":
            let pattern = "\"([^\"]+)\"\\s*:"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsText = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
                for match in matches {
                    let key = nsText.substring(with: match.range(at: 1))
                    // Chỉ lấy nếu key thực sự là một trường trong các bản ghi cấp 1
                    if records.contains(where: { $0[key] != nil }) {
                        if seen.insert(key).inserted {
                            orderedKeys.append(key)
                        }
                    }
                }
            }
        }

        // Bổ sung các key có thể chưa thấy qua regex
        for record in records {
            for key in record.keys {
                if seen.insert(key).inserted {
                    orderedKeys.append(key)
                }
            }
        }

        return orderedKeys
    }

    private func buildTableFromRecords(records: [[String: Any]], rawData: Data) throws -> TableData {
        if records.isEmpty {
            return try TableData(columns: [])
        }

        let keys = extractKeyOrder(from: rawData, records: records)

        var columns: [TableColumn] = []
        for key in keys {
            var cellValues: [Any?] = []
            cellValues.reserveCapacity(records.count)
            for record in records {
                let rawVal = record[key]
                if rawVal is NSNull || rawVal == nil {
                    cellValues.append(nil)
                } else {
                    cellValues.append(rawVal)
                }
            }

            let colData = convertToColumnData(values: cellValues)
            columns.append(TableColumn(name: key, data: colData))
        }

        return try TableData(columns: columns)
    }

    private func buildTableFromPrimitives(primitives: [Any]) throws -> TableData {
        let values: [Any?] = primitives.map { ($0 is NSNull) ? nil : $0 }
        let colData = convertToColumnData(values: values)
        return try TableData(columns: [TableColumn(name: "Value", data: colData)])
    }

    /// [SUY ĐOÁN] Chuyển đổi mảng giá trị JSON thành ColumnData theo quy tắc:
    /// number nguyên → integer, có phần lẻ → double, bool → boolean, string → string, lẫn kiểu → string.
    /// Giá trị lồng (object/array) → chuỗi JSON gọn.
    private func convertToColumnData(values: [Any?]) -> ColumnData {
        var hasInt = false
        var hasDouble = false
        var hasBool = false
        var hasString = false

        for val in values {
            guard let val = val else { continue }
            if isBoolean(val) {
                hasBool = true
            } else if let num = val as? NSNumber {
                if isInteger(num) {
                    hasInt = true
                } else {
                    hasDouble = true
                }
            } else {
                hasString = true
            }
        }

        let nonNullCount = (hasInt ? 1 : 0) + (hasDouble ? 1 : 0) + (hasBool ? 1 : 0) + (hasString ? 1 : 0)
        if nonNullCount == 0 {
            // Toàn ô rỗng
            return ColumnBuilder.strings(Array(repeating: nil, count: values.count))
        }

        // Nếu chỉ có int (hoặc int + double -> double)
        if !hasBool && !hasString {
            if hasDouble {
                let doubles: [Double?] = values.map { val in
                    guard let val = val, let num = val as? NSNumber else { return nil }
                    return num.doubleValue
                }
                return ColumnBuilder.doubles(doubles)
            } else if hasInt {
                let ints: [Int64?] = values.map { val in
                    guard let val = val, let num = val as? NSNumber else { return nil }
                    return num.int64Value
                }
                return ColumnBuilder.integers(ints)
            }
        }

        // Nếu chỉ có boolean
        if hasBool && !hasInt && !hasDouble && !hasString {
            let bools: [Bool?] = values.map { val in
                guard let val = val else { return nil }
                return (val as? NSNumber)?.boolValue
            }
            return ColumnBuilder.booleans(bools)
        }

        // Còn lại (string thuần hoặc lẫn kiểu) -> chuyển toàn bộ sang chuỗi
        let strings: [String?] = values.map { val in
            guard let val = val else { return nil }
            return stringify(val)
        }
        return ColumnBuilder.strings(strings)
    }

    private func isBoolean(_ val: Any) -> Bool {
        guard let num = val as? NSNumber else { return false }
        return CFGetTypeID(num) == CFBooleanGetTypeID()
    }

    private func isInteger(_ num: NSNumber) -> Bool {
        let d = num.doubleValue
        return floor(d) == d && d >= Double(Int64.min) && d <= Double(Int64.max)
    }

    /// [SUY ĐOÁN] Giá trị lồng (đối tượng hoặc mảng) → chuỗi JSON gọn trong cột string
    private func stringify(_ val: Any) -> String {
        if let str = val as? String {
            return str
        }
        if isBoolean(val), let num = val as? NSNumber {
            return num.boolValue ? "true" : "false"
        }
        if let num = val as? NSNumber {
            if isInteger(num) {
                return "\(num.int64Value)"
            } else {
                return "\(num.doubleValue)"
            }
        }
        if let obj = val as? [String: Any] {
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: []) {
                return String(data: data, encoding: .utf8) ?? "{}"
            }
            return "{}"
        }
        if let arr = val as? [Any] {
            if let data = try? JSONSerialization.data(withJSONObject: arr, options: []) {
                return String(data: data, encoding: .utf8) ?? "[]"
            }
            return "[]"
        }
        return "\(val)"
    }
}
