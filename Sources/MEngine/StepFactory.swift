// Phase F, T055: lệnh Ribbon của Power Query Editor → bước M. Tên bước và biểu thức khớp nguyên văn Desktop 2.159
// (`docs/phase-f-evidence/vm-f3/QUAN-SAT.md` mục 1, golden `chuoi-1.m`, `chuoi-2.m`). Lệnh chưa quan sát ghi [SUY ĐOÁN] bên dưới.

import Foundation

public enum MLiteral: Sendable, Equatable {
    case null
    case logical(Bool)
    case number(Double)
    case text(String)

    var m: String {
        switch self {
        case .null: "null"
        case .logical(let b): b ? "true" : "false"
        case .number(let d): d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(d)
        case .text(let s): StepFactory.quote(s)
        }
    }
}

public struct SortKey: Sendable, Equatable {
    public var column: String
    public var descending: Bool
    public init(column: String, descending: Bool) { self.column = column; self.descending = descending }
}

public struct ColumnRename: Sendable, Equatable {
    public var old: String
    public var new: String
    public init(old: String, new: String) { self.old = old; self.new = new }
}

public struct ErrorReplacement: Sendable, Equatable {
    public var column: String
    public var value: MLiteral
    public init(column: String, value: MLiteral) { self.column = column; self.value = value }
}

/// Kiểu cột của lệnh Data Type. Quan sát: `wholeNumber`, `decimal`, `date`, `text`; còn lại [SUY ĐOÁN] theo tài liệu M.
public enum MColumnType: Sendable, Equatable {
    case text, wholeNumber, decimal, fixedDecimal, percentage, date, dateTime, dateTimeZone, time, duration, logical, binary

    var m: String {
        switch self {
        case .text: "type text"
        case .wholeNumber: "Int64.Type"
        case .decimal: "type number"
        case .fixedDecimal: "Currency.Type"
        case .percentage: "Percentage.Type"
        case .date: "type date"
        case .dateTime: "type datetime"
        case .dateTimeZone: "type datetimezone"
        case .time: "type time"
        case .duration: "type duration"
        case .logical: "type logical"
        case .binary: "type binary"
        }
    }
}

public struct ColumnTypeChange: Sendable, Equatable {
    public var column: String
    public var type: MColumnType
    public init(column: String, type: MColumnType) { self.column = column; self.type = type }
}

/// Lệnh Format (tab Transform). Tên bước `Uppercased Text` quan sát; các tên còn lại [SUY ĐOÁN] theo quy luật của Desktop.
public enum TextFormat: Sendable, Equatable {
    case lowercase, uppercase, capitalizeEachWord, trim, clean

    var stepName: String {
        switch self {
        case .lowercase: "Lowercased Text"
        case .uppercase: "Uppercased Text"
        case .capitalizeEachWord: "Capitalized Each Word"
        case .trim: "Trimmed Text"
        case .clean: "Cleaned Text"
        }
    }

    var function: String {
        switch self {
        case .lowercase: "Text.Lower"
        case .uppercase: "Text.Upper"
        case .capitalizeEachWord: "Text.Proper"
        case .trim: "Text.Trim"
        case .clean: "Text.Clean"
        }
    }
}

/// Kiểu join của hộp Merge Queries. Tên hằng M theo tài liệu (`JoinKind.*`).
public enum JoinChoice: String, Sendable, Equatable, CaseIterable {
    case leftOuter = "JoinKind.LeftOuter", rightOuter = "JoinKind.RightOuter", fullOuter = "JoinKind.FullOuter"
    case inner = "JoinKind.Inner", leftAnti = "JoinKind.LeftAnti", rightAnti = "JoinKind.RightAnti"
}

/// Phép tổng hợp của Group By.
public enum GroupOperation: Sendable, Equatable {
    case sum, average, median, min, max, countRows, countDistinctRows
}

public struct GroupAggregate: Sendable, Equatable {
    public var name: String
    public var operation: GroupOperation
    /// Cột tính; `nil` cho phép đếm dòng.
    public var column: String?
    public init(name: String, operation: GroupOperation, column: String? = nil) {
        self.name = name; self.operation = operation; self.column = column
    }

    var m: String {
        let source = column.map { "[\($0)]" } ?? "_"
        switch operation {
        case .sum: return "{\(StepFactory.quote(name)), each List.Sum(\(source)), type nullable number}"
        case .average: return "{\(StepFactory.quote(name)), each List.Average(\(source)), type nullable number}"
        case .median: return "{\(StepFactory.quote(name)), each List.Median(\(source)), type nullable number}"
        case .min: return "{\(StepFactory.quote(name)), each List.Min(\(source))}"
        case .max: return "{\(StepFactory.quote(name)), each List.Max(\(source))}"
        case .countRows: return "{\(StepFactory.quote(name)), each Table.RowCount(_), Int64.Type}"
        case .countDistinctRows: return "{\(StepFactory.quote(name)), each Table.RowCount(Table.Distinct(_)), Int64.Type}"
        }
    }
}

public enum StepCommand: Sendable, Equatable {
    case promoteHeaders
    case changeType([ColumnTypeChange])
    case sortRows([SortKey])
    case removeColumns([String])
    case renameColumns([ColumnRename])
    case replaceValue(old: MLiteral, new: MLiteral, columns: [String])
    /// Lọc theo danh sách giá trị (mũi tên cột): `[Cột] = v1 or [Cột] = v2`.
    case filterEquals(column: String, values: [MLiteral])
    case addIndexColumn(start: Int, step: Int)
    case addCustomColumn(name: String, formula: String)
    case reverseRows
    case fillDown([String])
    /// [SUY ĐOÁN] tên bước "Filled Up".
    case fillUp([String])
    case splitByDelimiter(column: String, delimiter: String, into: [String])
    case format(TextFormat, columns: [String])
    /// Group By cơ bản, Count Rows.
    case groupByCount(keys: [String], newColumn: String)
    case unpivotOtherColumns(keep: [String])
    case pivot(attributeColumn: String, valueColumn: String)
    case removeDuplicates([String])
    case keepTopRows(Int)
    case removeTopRows(Int)
    case replaceErrors([ErrorReplacement])
    /// Merge Queries [SUY ĐOÁN, chờ T067]: `Table.NestedJoin` với truy vấn khác, cột lồng tên `newColumn`.
    case merge(otherQuery: String, leftKeys: [String], rightKeys: [String], kind: JoinChoice, newColumn: String)
    /// Mở cột bảng lồng sau Merge [SUY ĐOÁN]; `prefixed` đặt tên mới `Cột.tên` như mặc định của Desktop.
    case expandColumn(column: String, names: [String], prefixed: Bool)
    /// Append Queries [SUY ĐOÁN]: nối bảng đang chọn với các truy vấn khác.
    case append(queries: [String])
    /// Group By nâng cao [SUY ĐOÁN]: nhiều khoá, nhiều phép tổng hợp.
    case groupBy(keys: [String], aggregates: [GroupAggregate])
}

public enum StepFactory {
    /// Bước (một hoặc hai) cho lệnh `command` áp lên bước `previous`. `existingNames` để tên không trùng ("Changed Type1").
    public static func steps(for command: StepCommand, after previous: String, existingNames: Set<String>) -> [MStep] {
        let p = MQuery.reference(to: previous)
        func make(_ base: String, _ expression: String, taken: Set<String> = []) -> MStep {
            MStep(name: uniqueName(base, existing: existingNames.union(taken)), expression: expression)
        }
        func list(_ names: [String]) -> String { "{" + names.map(quote).joined(separator: ", ") + "}" }

        switch command {
        case .promoteHeaders:
            return [make("Promoted Headers", "Table.PromoteHeaders(\(p), [PromoteAllScalars=true])")]
        case .changeType(let changes):
            return [make("Changed Type", "Table.TransformColumnTypes(\(p),\(typePairs(changes)))")]
        case .sortRows(let keys):
            let pairs = keys.map { "{\(quote($0.column)), \($0.descending ? "Order.Descending" : "Order.Ascending")}" }
            return [make("Sorted Rows", "Table.Sort(\(p),{\(pairs.joined(separator: ", "))})")]
        case .removeColumns(let columns):
            return [make("Removed Columns", "Table.RemoveColumns(\(p),\(list(columns)))")]
        case .renameColumns(let renames):
            let pairs = renames.map { "{\(quote($0.old)), \(quote($0.new))}" }
            return [make("Renamed Columns", "Table.RenameColumns(\(p),{\(pairs.joined(separator: ", "))})")]
        case .replaceValue(let old, let new, let columns):
            var replacer = "Replacer.ReplaceValue"
            if case .text = old, case .text = new { replacer = "Replacer.ReplaceText" }
            return [make("Replaced Value", "Table.ReplaceValue(\(p),\(old.m),\(new.m),\(replacer),\(list(columns)))")]
        case .filterEquals(let column, let values):
            let condition = values.map { "[\(column)] = \($0.m)" }.joined(separator: " or ")
            return [make("Filtered Rows", "Table.SelectRows(\(p), each (\(condition)))")]
        case .addIndexColumn(let start, let step):
            return [make("Added Index", "Table.AddIndexColumn(\(p), \"Index\", \(start), \(step), Int64.Type)")]
        case .addCustomColumn(let name, let formula):
            return [make("Added Custom", "Table.AddColumn(\(p), \(quote(name)), each \(formula))")]
        case .reverseRows:
            return [make("Reversed Rows", "Table.ReverseRows(\(p))")]
        case .fillDown(let columns):
            return [make("Filled Down", "Table.FillDown(\(p),\(list(columns)))")]
        case .fillUp(let columns):
            return [make("Filled Up", "Table.FillUp(\(p),\(list(columns)))")]
        case .splitByDelimiter(let column, let delimiter, let into):
            let split = make("Split Column by Delimiter",
                             "Table.SplitColumn(\(p), \(quote(column)), Splitter.SplitTextByDelimiter(\(quote(delimiter)), QuoteStyle.Csv), \(list(into)))")
            // Desktop gán lại kiểu `text` cho các cột mới ở bước kế tiếp (QUAN-SAT mục 1).
            let retype = make("Changed Type", "Table.TransformColumnTypes(\(MQuery.reference(to: split.name)),\(typePairs(into.map { ColumnTypeChange(column: $0, type: .text) })))",
                              taken: [split.name])
            return [split, retype]
        case .format(let format, let columns):
            let pairs = columns.map { "{\(quote($0)), \(format.function), type text}" }
            return [make(format.stepName, "Table.TransformColumns(\(p),{\(pairs.joined(separator: ", "))})")]
        case .groupByCount(let keys, let newColumn):
            return [make("Grouped Rows", "Table.Group(\(p), \(list(keys)), {{\(quote(newColumn)), each Table.RowCount(_), Int64.Type}})")]
        case .unpivotOtherColumns(let keep):
            return [make("Unpivoted Other Columns", "Table.UnpivotOtherColumns(\(p), \(list(keep)), \"Attribute\", \"Value\")")]
        case .pivot(let attribute, let value):
            return [make("Pivoted Column",
                         "Table.Pivot(\(p), List.Distinct(\(p)[\(attribute)]), \(quote(attribute)), \(quote(value)), List.Sum)")]
        case .removeDuplicates(let columns):
            return [make("Removed Duplicates", "Table.Distinct(\(p), \(list(columns)))")]
        case .keepTopRows(let n):
            return [make("Kept First Rows", "Table.FirstN(\(p),\(n))")]
        case .removeTopRows(let n):
            return [make("Removed Top Rows", "Table.Skip(\(p),\(n))")]
        case .replaceErrors(let replacements):
            let pairs = replacements.map { "{\(quote($0.column)), \($0.value.m)}" }
            return [make("Replaced Errors", "Table.ReplaceErrorValues(\(p), {\(pairs.joined(separator: ", "))})")]
        case .merge(let other, let leftKeys, let rightKeys, let kind, let newColumn):
            return [make("Merged Queries",
                         "Table.NestedJoin(\(p), \(list(leftKeys)), \(MQuery.reference(to: other)), \(list(rightKeys)), \(quote(newColumn)), \(kind.rawValue))")]
        case .expandColumn(let column, let names, let prefixed):
            let renamed = prefixed ? list(names.map { "\(column).\($0)" }) : list(names)
            return [make("Expanded \(column)", "Table.ExpandTableColumn(\(p), \(quote(column)), \(list(names)), \(renamed))")]
        case .append(let queries):
            let items = ([p] + queries.map(MQuery.reference(to:))).joined(separator: ", ")
            return [make("Appended Query", "Table.Combine({\(items)})")]
        case .groupBy(let keys, let aggregates):
            return [make("Grouped Rows", "Table.Group(\(p), \(list(keys)), {\(aggregates.map(\.m).joined(separator: ", "))})")]
        }
    }

    /// `base`, rồi `base1`, `base2`… cho đến khi không trùng (như "Changed Type1" của Desktop).
    public static func uniqueName(_ base: String, existing: Set<String>) -> String {
        guard existing.contains(base) else { return base }
        var n = 1
        while existing.contains("\(base)\(n)") { n += 1 }
        return "\(base)\(n)"
    }

    /// Chuỗi M: `"` nhân đôi, xuống dòng/tab dùng `#(lf)`, `#(cr)`, `#(tab)`.
    public static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\"\""
            case "\n": out += "#(lf)"
            case "\r": out += "#(cr)"
            case "\t": out += "#(tab)"
            default: out.unicodeScalars.append(c)
            }
        }
        return out + "\""
    }

    private static func typePairs(_ changes: [ColumnTypeChange]) -> String {
        "{" + changes.map { "{\(quote($0.column)), \($0.type.m)}" }.joined(separator: ", ") + "}"
    }
}
