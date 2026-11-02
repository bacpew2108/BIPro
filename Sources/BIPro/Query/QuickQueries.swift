import Foundation
import PBIXKit

public struct MeasureInfo: Sendable, Hashable {
    public var tableName: String
    public var name: String
    public var expression: String
    public var description: String?

    public init(tableName: String, name: String, expression: String, description: String? = nil) {
        self.tableName = tableName
        self.name = name
        self.expression = expression
        self.description = description
    }

    public init(_ m: ModelMetadata.Measure) {
        self.init(tableName: m.tableName, name: m.name, expression: m.expression, description: m.description)
    }
}

public struct ColumnInfo: Sendable, Hashable {
    public var tableName: String
    public var name: String
    public var isKey: Bool
    public var isDateTime: Bool
    public var isRowNumber: Bool

    public init(tableName: String, name: String, isKey: Bool = false, isDateTime: Bool = false, isRowNumber: Bool = false) {
        self.tableName = tableName
        self.name = name
        self.isKey = isKey
        self.isDateTime = isDateTime
        self.isRowNumber = isRowNumber
    }

    public init(_ c: ModelMetadata.Column) {
        self.init(tableName: c.tableName, name: c.name, isKey: c.isKey, isDateTime: c.dataType == .dateTime, isRowNumber: c.kind == .rowNumber)
    }
}

public enum QuickQueries {
    // MARK: - Mẫu 1: Measure, "Đánh giá" (O8-query-1)
    public static func evaluate(measureName: String) -> String {
        let lines = [
            "EVALUATE",
            "    SUMMARIZECOLUMNS(",
            "        \"\(measureName)\", [\(measureName)]",
            "    )"
        ]
        return lines.joined(separator: "\n")
    }

    public static func evaluate(measure: MeasureInfo) -> String {
        evaluate(measureName: measure.name)
    }

    public static func evaluate(measure: ModelMetadata.Measure) -> String {
        evaluate(measureName: measure.name)
    }

    // MARK: - Mẫu 2: Measure, "Định nghĩa và đánh giá" (O8-query-2)
    public static func defineAndEvaluate(measure: MeasureInfo) -> String {
        var lines: [String] = ["DEFINE"]
        lines.append(contentsOf: formatMeasureDefinition(
            tableName: measure.tableName,
            name: measure.name,
            expression: measure.expression,
            description: measure.description
        ))
        lines.append("")
        lines.append("EVALUATE")
        lines.append("    SUMMARIZECOLUMNS(")
        lines.append("        \"\(measure.name)\", [\(measure.name)]")
        lines.append("    )")
        return lines.joined(separator: "\n")
    }

    public static func defineAndEvaluate(measure: ModelMetadata.Measure) -> String {
        defineAndEvaluate(measure: MeasureInfo(measure))
    }

    // MARK: - Mẫu 3: Measure, "Định nghĩa kèm tham chiếu và đánh giá" (O8-query-3)
    public static func defineWithReferencesAndEvaluate(
        measure: MeasureInfo,
        allMeasures: [MeasureInfo]
    ) -> String {
        let orderedMeasures = resolveDependencyOrder(for: measure, allMeasures: allMeasures)
        var lines: [String] = ["DEFINE"]
        for m in orderedMeasures {
            lines.append(contentsOf: formatMeasureDefinition(
                tableName: m.tableName,
                name: m.name,
                expression: m.expression,
                description: m.description
            ))
        }
        lines.append("")
        lines.append("EVALUATE")
        lines.append("    SUMMARIZECOLUMNS(")
        for (idx, m) in orderedMeasures.enumerated() {
            let isLast = idx == orderedMeasures.count - 1
            lines.append("        \"\(m.name)\", [\(m.name)]" + (isLast ? "" : ","))
        }
        lines.append("    )")
        return lines.joined(separator: "\n")
    }

    public static func defineWithReferencesAndEvaluate(
        measure: ModelMetadata.Measure,
        allMeasures: [ModelMetadata.Measure],
        allColumns: [ModelMetadata.Column] = []
    ) -> String {
        defineWithReferencesAndEvaluate(
            measure: MeasureInfo(measure),
            allMeasures: allMeasures.map(MeasureInfo.init)
        )
    }

    // MARK: - Mẫu 4: Bảng, "Hiện 100 dòng đầu" (O8-query-4)
    public static func top100Rows(table: String, columns: [ColumnInfo]) -> String {
        let validColumns = columns.filter { !$0.isRowNumber }
        // c_sắp: nếu bảng có cột kiểu dateTime đánh dấu là khoá ngày của date table thì lấy cột đó.
        // Dim_Date dùng full_date. Nếu không thì lấy cột đầu tiên (ghi [SUY ĐOÁN]).
        let sortCol = validColumns.first { $0.isDateTime && $0.isKey }?.name
            // [SUY ĐOÁN] Nếu bảng không có cột dateTime đánh dấu khoá ngày thì lấy cột đầu tiên
            ?? validColumns.first?.name
            ?? ""

        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        var lines: [String] = []
        lines.append("EVALUATE")
        lines.append("\tSELECTCOLUMNS(")
        lines.append("\t\tTOPN(")
        lines.append("\t\t\t100,")
        lines.append("\t\t\t'\(escapedTable)',")
        lines.append("\t\t\t'\(escapedTable)'[\(sortCol)],")
        lines.append("\t\t\tASC")
        lines.append("\t\t),")
        for (idx, col) in validColumns.enumerated() {
            let isLast = idx == validColumns.count - 1
            lines.append("\t\t'\(escapedTable)'[\(col.name)]" + (isLast ? "" : ","))
        }
        lines.append("\t)")
        lines.append("\tORDER BY '\(escapedTable)'[\(sortCol)] ASC")
        return lines.joined(separator: "\n")
    }

    public static func top100Rows(table: String, columns: [ModelMetadata.Column]) -> String {
        top100Rows(table: table, columns: columns.map(ColumnInfo.init))
    }

    // MARK: - Mẫu 5: Cột, "Xem trước dữ liệu" (O8-query-5)
    public static func previewData(tableName: String, columnName: String) -> String {
        let escapedTable = tableName.replacingOccurrences(of: "'", with: "''")
        return "EVALUATE\n\tDISTINCT('\(escapedTable)'[\(columnName)])"
    }

    public static func previewData(column: ModelMetadata.Column) -> String {
        previewData(tableName: column.tableName, columnName: column.name)
    }

    // MARK: - Mẫu 6: Bảng/Measure/Cột, "Định nghĩa measure mới"
    // [SUY ĐOÁN] Chưa có mẫu của Power BI: biểu thức measure còn trống sau dấu "=", không chạy truy vấn tự động
    public static func defineNewMeasure(tableName: String) -> String {
        let escapedTable = tableName.replacingOccurrences(of: "'", with: "''")
        let lines = [
            "DEFINE",
            "    MEASURE '\(escapedTable)'[Measure mới] = ",
            "",
            "EVALUATE",
            "    SUMMARIZECOLUMNS(",
            "        \"Measure mới\", [Measure mới]",
            "    )"
        ]
        return lines.joined(separator: "\n")
    }

    public static func defineNewMeasure(measure: MeasureInfo) -> String {
        defineNewMeasure(tableName: measure.tableName)
    }

    public static func defineNewMeasure(measure: ModelMetadata.Measure) -> String {
        defineNewMeasure(tableName: measure.tableName)
    }

    public static func defineNewMeasure(column: ColumnInfo) -> String {
        defineNewMeasure(tableName: column.tableName)
    }

    public static func defineNewMeasure(column: ModelMetadata.Column) -> String {
        defineNewMeasure(tableName: column.tableName)
    }

    // MARK: - Mẫu 7: Measure, "Định nghĩa mọi measure trong mô hình"
    // [SUY ĐOÁN] DEFINE mọi measure của mô hình, sắp theo bảng rồi theo tên; mỗi measure theo đúng định dạng mẫu 2; rồi dòng trống và EVALUATE + SUMMARIZECOLUMNS(...) liệt kê measure được bấm
    public static func defineAllMeasures(
        clickedMeasure: MeasureInfo,
        allMeasures: [MeasureInfo]
    ) -> String {
        let sorted = allMeasures.sorted {
            let cmpTable = $0.tableName.localizedStandardCompare($1.tableName)
            if cmpTable != .orderedSame {
                return cmpTable == .orderedAscending
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        var lines: [String] = ["DEFINE"]
        for m in sorted {
            lines.append(contentsOf: formatMeasureDefinition(
                tableName: m.tableName,
                name: m.name,
                expression: m.expression,
                description: m.description
            ))
        }
        lines.append("")
        lines.append("EVALUATE")
        lines.append("    SUMMARIZECOLUMNS(")
        lines.append("        \"\(clickedMeasure.name)\", [\(clickedMeasure.name)]")
        lines.append("    )")
        return lines.joined(separator: "\n")
    }

    public static func defineAllMeasures(
        clickedMeasure: ModelMetadata.Measure,
        allMeasures: [ModelMetadata.Measure]
    ) -> String {
        defineAllMeasures(
            clickedMeasure: MeasureInfo(clickedMeasure),
            allMeasures: allMeasures.map(MeasureInfo.init)
        )
    }

    // MARK: - Trợ giúp định dạng và phân tích

    private static func formatMeasureDefinition(
        tableName: String,
        name: String,
        expression: String,
        description: String?
    ) -> [String] {
        var lines: [String] = []
        if let desc = description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            lines.append("    /// \(desc)")
        }
        let escapedTable = tableName.replacingOccurrences(of: "'", with: "''")
        let rawLines = expression.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .map { line in
                var s = line
                if s.hasSuffix("\r") { s.removeLast() }
                return s
            }

        if rawLines.count <= 1 {
            lines.append("    MEASURE '\(escapedTable)'[\(name)] = \(rawLines.first ?? "")")
        } else {
            // [SUY ĐOÁN] Biểu thức nhiều dòng: dòng đầu nằm sau dấu "=", các dòng sau thụt 8 dấu cách
            lines.append("    MEASURE '\(escapedTable)'[\(name)] = \(rawLines[0])")
            for line in rawLines.dropFirst() {
                lines.append("        \(line)")
            }
        }
        return lines
    }

    public struct DAXReference: Sendable, Hashable {
        public let tableName: String?
        public let itemName: String

        public init(tableName: String?, itemName: String) {
            self.tableName = tableName
            self.itemName = itemName
        }
    }

    /// Trích xuất các tham chiếu [tên] hoặc 'Bảng'[tên] / Bảng[tên] trong biểu thức DAX.
    /// Bỏ qua comment //, --, /* */ và chuỗi "...".
    public static func extractDAXReferences(from dax: String) -> [DAXReference] {
        var refs: [DAXReference] = []
        let chars = Array(dax)
        var i = 0
        let n = chars.count

        while i < n {
            let ch = chars[i]

            // 1. Single-line comment: // hoặc --
            if (ch == "/" && i + 1 < n && chars[i + 1] == "/") ||
               (ch == "-" && i + 1 < n && chars[i + 1] == "-") {
                i += 2
                while i < n && chars[i] != "\n" && chars[i] != "\r" { i += 1 }
                continue
            }

            // 2. Multi-line comment: /* ... */
            if ch == "/" && i + 1 < n && chars[i + 1] == "*" {
                i += 2
                while i + 1 < n && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(n, i + 2)
                continue
            }

            // 3. Chuỗi: " ... " (với "" là nháy kép thoát)
            if ch == "\"" {
                i += 1
                while i < n {
                    if chars[i] == "\"" {
                        if i + 1 < n && chars[i + 1] == "\"" {
                            i += 2
                        } else {
                            i += 1
                            break
                        }
                    } else {
                        i += 1
                    }
                }
                continue
            }

            // 4. Bảng có nháy đơn: 'Tên Bảng'[Mục]
            if ch == "'" {
                i += 1
                var tableName = ""
                while i < n {
                    if chars[i] == "'" {
                        if i + 1 < n && chars[i + 1] == "'" {
                            tableName.append("'")
                            i += 2
                        } else {
                            i += 1
                            break
                        }
                    } else {
                        tableName.append(chars[i])
                        i += 1
                    }
                }
                var j = i
                while j < n && (chars[j] == " " || chars[j] == "\t" || chars[j] == "\n" || chars[j] == "\r") {
                    j += 1
                }
                if j < n && chars[j] == "[" {
                    j += 1
                    var itemName = ""
                    while j < n && chars[j] != "]" {
                        itemName.append(chars[j])
                        j += 1
                    }
                    if j < n && chars[j] == "]" { j += 1 }
                    refs.append(DAXReference(tableName: tableName, itemName: itemName))
                    i = j
                    continue
                }
                continue
            }

            // 5. Mục không kèm bảng: [Mục]
            if ch == "[" {
                i += 1
                var itemName = ""
                while i < n && chars[i] != "]" {
                    itemName.append(chars[i])
                    i += 1
                }
                if i < n && chars[i] == "]" { i += 1 }
                refs.append(DAXReference(tableName: nil, itemName: itemName))
                continue
            }

            // 6. Bảng không nháy đơn: TenBang[Mục]
            if ch.isLetter || ch == "_" {
                var ident = String(ch)
                i += 1
                while i < n && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    ident.append(chars[i])
                    i += 1
                }
                var j = i
                while j < n && (chars[j] == " " || chars[j] == "\t") {
                    j += 1
                }
                if j < n && chars[j] == "[" {
                    j += 1
                    var itemName = ""
                    while j < n && chars[j] != "]" {
                        itemName.append(chars[j])
                        j += 1
                    }
                    if j < n && chars[j] == "]" { j += 1 }
                    refs.append(DAXReference(tableName: ident, itemName: itemName))
                    i = j
                    continue
                }
                continue
            }

            i += 1
        }

        return refs
    }

    /// Duyệt thứ tự hậu tố DFS: phụ thuộc đứng trước, duyệt các tham chiếu theo thứ tự xuất hiện trong biểu thức,
    /// mỗi measure một lần.
    public static func resolveDependencyOrder(
        for rootMeasure: MeasureInfo,
        allMeasures: [MeasureInfo]
    ) -> [MeasureInfo] {
        var result: [MeasureInfo] = []
        var visited = Set<String>()
        var inStack = Set<String>()

        let measureByName = Dictionary(grouping: allMeasures, by: { $0.name })

        func dfs(_ current: MeasureInfo) {
            inStack.insert(current.name)
            let refs = extractDAXReferences(from: current.expression)
            for ref in refs {
                guard let candidates = measureByName[ref.itemName], !candidates.isEmpty else {
                    continue
                }
                let target: MeasureInfo
                if let tName = ref.tableName {
                    if let matched = candidates.first(where: { $0.tableName.localizedCaseInsensitiveCompare(tName) == .orderedSame }) {
                        target = matched
                    } else {
                        // Tham chiếu tới cột của bảng đó, không phải measure
                        continue
                    }
                } else {
                    target = candidates[0]
                }

                if !visited.contains(target.name) && !inStack.contains(target.name) {
                    dfs(target)
                }
            }

            inStack.remove(current.name)
            if !visited.contains(current.name) {
                visited.insert(current.name)
                result.append(current)
            }
        }

        dfs(rootMeasure)
        return result
    }
}
