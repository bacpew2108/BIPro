import Foundation
import ColumnStore
import MEngine

public enum QueryRibbonTab: String, CaseIterable, Sendable {
    case home
    case transform
    case addColumn
    case view

    public var title: String {
        localizedTitle(language: .vi)
    }

    public func localizedTitle(language: ResolvedLanguage) -> String {
        let en = language == .en
        switch self {
        case .home: return en ? "Home" : "Trang chủ"
        case .transform: return en ? "Transform" : "Chuyển đổi"
        case .addColumn: return en ? "Add Column" : "Thêm cột"
        case .view: return en ? "View" : "Xem"
        }
    }
}

public struct QueryRibbonContext: Sendable {
    public var selectedColumns: [String]
    public var columnTypes: [String: DAXType]
    public var allColumns: [String]
    public var rowCount: Int?
    public var replaceOld: String?
    public var replaceNew: String?
    public var filterValues: [MLiteral]?
    public var delimiter: String?
    public var endDelimiter: String?
    public var charCount: Int?
    public var splitColumnCount: Int?
    public var replaceErrorText: String?
    public var customColumnName: String?
    public var customColumnFormula: String?

    public init(
        selectedColumns: [String] = [],
        columnTypes: [String: DAXType] = [:],
        allColumns: [String] = [],
        rowCount: Int? = nil,
        replaceOld: String? = nil,
        replaceNew: String? = nil,
        filterValues: [MLiteral]? = nil,
        delimiter: String? = nil,
        endDelimiter: String? = nil,
        charCount: Int? = nil,
        splitColumnCount: Int? = nil,
        replaceErrorText: String? = nil,
        customColumnName: String? = nil,
        customColumnFormula: String? = nil
    ) {
        self.selectedColumns = selectedColumns
        self.columnTypes = columnTypes
        self.allColumns = allColumns
        self.rowCount = rowCount
        self.replaceOld = replaceOld
        self.replaceNew = replaceNew
        self.filterValues = filterValues
        self.delimiter = delimiter
        self.endDelimiter = endDelimiter
        self.charCount = charCount
        self.splitColumnCount = splitColumnCount
        self.replaceErrorText = replaceErrorText
        self.customColumnName = customColumnName
        self.customColumnFormula = customColumnFormula
    }
}

public enum QueryRibbonCommand: String, CaseIterable, Sendable {
    // Trang chủ (Home)
    case removeColumns
    case sortAscending
    case sortDescending
    case keepTopRows
    case removeTopRows
    case removeDuplicates
    case promoteHeaders
    case changeTypeWholeNumber
    case changeTypeDecimal
    case changeTypeText
    case changeTypeDate
    case changeTypeDateTime
    case changeTypeLogical
    case replaceValue
    case filterEquals

    // Chuyển đổi (Transform)
    case reverseRows
    case fillDown
    case fillUp
    case replaceErrors
    case formatLowercase
    case formatUppercase
    case formatCapitalizeEachWord
    case formatTrim
    case formatClean
    case splitByDelimiter
    case splitByNumberOfChars
    case extractLength
    case extractFirstChars
    case extractLastChars
    case extractBeforeDelimiter
    case extractAfterDelimiter
    case extractBetweenDelimiters
    case dateYear
    case dateQuarter
    case dateMonth
    case dateMonthName
    case dateDay
    case dateDayName
    case dateStartOfMonth
    case dateEndOfMonth
    case groupByCount
    case unpivotOtherColumns
    case pivot

    // Thêm cột (Add Column)
    case addIndexColumnFrom0
    case addIndexColumnFrom1
    case addCustomColumn
    case addExtractLength
    case addExtractFirstChars
    case addExtractLastChars
    case addExtractBeforeDelimiter
    case addExtractAfterDelimiter
    case addExtractBetweenDelimiters
    case addDateYear
    case addDateQuarter
    case addDateMonth
    case addDateMonthName
    case addDateDay
    case addDateDayName
    case addDateStartOfMonth
    case addDateEndOfMonth

    public var title: String {
        localizedTitle(language: .vi)
    }

    public func localizedTitle(language: ResolvedLanguage) -> String {
        let en = language == .en
        switch self {
        case .removeColumns: return en ? "Remove Columns" : "Xoá cột"
        case .sortAscending: return en ? "Sort Ascending" : "Sắp xếp tăng dần"
        case .sortDescending: return en ? "Sort Descending" : "Sắp xếp giảm dần"
        case .keepTopRows: return en ? "Keep Top Rows" : "Giữ N dòng đầu"
        case .removeTopRows: return en ? "Remove Top Rows" : "Xoá N dòng đầu"
        case .removeDuplicates: return en ? "Remove Duplicates" : "Xoá dòng trùng"
        case .promoteHeaders: return en ? "Use First Row\nas Headers" : "Dùng dòng đầu\nlàm tiêu đề"
        case .changeTypeWholeNumber: return en ? "Whole Number" : "Số nguyên"
        case .changeTypeDecimal: return en ? "Decimal Number" : "Số thập phân"
        case .changeTypeText: return en ? "Text" : "Văn bản"
        case .changeTypeDate: return en ? "Date" : "Ngày"
        case .changeTypeDateTime: return en ? "Date/Time" : "Ngày giờ"
        case .changeTypeLogical: return en ? "True/False" : "Đúng-Sai"
        case .replaceValue: return en ? "Replace Values" : "Thay giá trị"
        case .filterEquals: return en ? "Filter Rows" : "Lọc theo giá trị"
        case .reverseRows: return en ? "Reverse Rows" : "Đảo thứ tự dòng"
        case .fillDown: return en ? "Fill Down" : "Điền xuống"
        case .fillUp: return en ? "Fill Up" : "Điền lên"
        case .replaceErrors: return en ? "Replace Errors" : "Thay lỗi"
        case .formatLowercase: return en ? "lowercase" : "chữ thường"
        case .formatUppercase: return en ? "UPPERCASE" : "CHỮ HOA"
        case .formatCapitalizeEachWord: return en ? "Capitalize Each Word" : "Viết Hoa Mỗi Từ"
        case .formatTrim: return en ? "Trim" : "Cắt khoảng trắng"
        case .formatClean: return en ? "Clean" : "Làm sạch"
        case .splitByDelimiter: return en ? "By Delimiter" : "Theo dấu phân cách"
        case .splitByNumberOfChars: return en ? "By Number of Characters" : "Theo số ký tự"
        case .extractLength, .addExtractLength: return en ? "Length" : "Độ dài"
        case .extractFirstChars, .addExtractFirstChars: return en ? "First Characters" : "Ký tự đầu"
        case .extractLastChars, .addExtractLastChars: return en ? "Last Characters" : "Ký tự cuối"
        case .extractBeforeDelimiter, .addExtractBeforeDelimiter: return en ? "Text Before Delimiter" : "Trước dấu phân cách"
        case .extractAfterDelimiter, .addExtractAfterDelimiter: return en ? "Text After Delimiter" : "Sau dấu phân cách"
        case .extractBetweenDelimiters, .addExtractBetweenDelimiters: return en ? "Text Between Delimiters" : "Giữa 2 dấu phân cách"
        case .dateYear, .addDateYear: return en ? "Year" : "Năm"
        case .dateQuarter, .addDateQuarter: return en ? "Quarter" : "Quý"
        case .dateMonth, .addDateMonth: return en ? "Month" : "Tháng"
        case .dateMonthName, .addDateMonthName: return en ? "Name of Month" : "Tên tháng"
        case .dateDay, .addDateDay: return en ? "Day" : "Ngày"
        case .dateDayName, .addDateDayName: return en ? "Name of Day" : "Tên thứ"
        case .dateStartOfMonth, .addDateStartOfMonth: return en ? "Start of Month" : "Đầu tháng"
        case .dateEndOfMonth, .addDateEndOfMonth: return en ? "End of Month" : "Cuối tháng"
        case .groupByCount: return en ? "Group By" : "Nhóm theo"
        case .unpivotOtherColumns: return en ? "Unpivot Other Columns" : "Bỏ xoay các cột khác"
        case .pivot: return en ? "Pivot Column" : "Xoay cột"
        case .addIndexColumnFrom0: return en ? "From 0" : "Từ 0"
        case .addIndexColumnFrom1: return en ? "From 1" : "Từ 1"
        case .addCustomColumn: return en ? "Custom Column" : "Cột tuỳ chỉnh"
        }
    }

    public var tab: QueryRibbonTab {
        switch self {
        case .removeColumns, .sortAscending, .sortDescending, .keepTopRows, .removeTopRows,
             .removeDuplicates, .promoteHeaders, .changeTypeWholeNumber, .changeTypeDecimal,
             .changeTypeText, .changeTypeDate, .changeTypeDateTime, .changeTypeLogical,
             .replaceValue, .filterEquals:
            return .home
        case .reverseRows, .fillDown, .fillUp, .replaceErrors, .formatLowercase, .formatUppercase,
             .formatCapitalizeEachWord, .formatTrim, .formatClean, .splitByDelimiter, .splitByNumberOfChars,
             .extractLength, .extractFirstChars, .extractLastChars, .extractBeforeDelimiter, .extractAfterDelimiter, .extractBetweenDelimiters,
             .dateYear, .dateQuarter, .dateMonth, .dateMonthName, .dateDay, .dateDayName, .dateStartOfMonth, .dateEndOfMonth,
             .groupByCount, .unpivotOtherColumns, .pivot:
            return .transform
        case .addIndexColumnFrom0, .addIndexColumnFrom1, .addCustomColumn,
             .addExtractLength, .addExtractFirstChars, .addExtractLastChars, .addExtractBeforeDelimiter, .addExtractAfterDelimiter, .addExtractBetweenDelimiters,
             .addDateYear, .addDateQuarter, .addDateMonth, .addDateMonthName, .addDateDay, .addDateDayName, .addDateStartOfMonth, .addDateEndOfMonth:
            return .addColumn
        }
    }

    public var isAvailable: Bool {
        return true
    }

    public var symbol: String {
        switch self {
        case .removeColumns: return "xmark.bin"
        case .sortAscending: return "arrow.up"
        case .sortDescending: return "arrow.down"
        case .keepTopRows: return "arrow.up.to.line"
        case .removeTopRows: return "arrow.down.to.line"
        case .removeDuplicates: return "person.2.slash"
        case .promoteHeaders: return "tablecells.fill"
        case .changeTypeWholeNumber: return "number"
        case .changeTypeDecimal: return "number.circle"
        case .changeTypeText: return "textformat"
        case .changeTypeDate: return "calendar"
        case .changeTypeDateTime: return "calendar.badge.clock"
        case .changeTypeLogical: return "checkmark.square"
        case .replaceValue: return "arrow.triangle.2.circlepath"
        case .filterEquals: return "line.3.horizontal.decrease.circle"
        case .reverseRows: return "arrow.up.arrow.down"
        case .fillDown: return "arrow.down.to.line.compact"
        case .fillUp: return "arrow.up.to.line.compact"
        case .replaceErrors: return "exclamationmark.arrow.triangle.2.circlepath"
        case .formatLowercase, .formatUppercase, .formatCapitalizeEachWord, .formatTrim, .formatClean:
            return "textformat"
        case .splitByDelimiter, .splitByNumberOfChars: return "rectangle.split.2x1"
        case .extractLength, .extractFirstChars, .extractLastChars, .extractBeforeDelimiter, .extractAfterDelimiter, .extractBetweenDelimiters,
             .addExtractLength, .addExtractFirstChars, .addExtractLastChars, .addExtractBeforeDelimiter, .addExtractAfterDelimiter, .addExtractBetweenDelimiters:
            return "scissors"
        case .dateYear, .dateQuarter, .dateMonth, .dateMonthName, .dateDay, .dateDayName, .dateStartOfMonth, .dateEndOfMonth,
             .addDateYear, .addDateQuarter, .addDateMonth, .addDateMonthName, .addDateDay, .addDateDayName, .addDateStartOfMonth, .addDateEndOfMonth:
            return "calendar"
        case .groupByCount: return "rectangle.3.group"
        case .unpivotOtherColumns: return "tablecells.badge.ellipsis"
        case .pivot: return "tablecells"
        case .addIndexColumnFrom0, .addIndexColumnFrom1: return "list.number"
        case .addCustomColumn: return "plus.rectangle"
        }
    }

    public var needsParameters: Bool {
        switch self {
        case .keepTopRows, .removeTopRows, .replaceValue, .replaceErrors, .filterEquals,
             .splitByDelimiter, .splitByNumberOfChars,
             .extractFirstChars, .extractLastChars, .extractBeforeDelimiter, .extractAfterDelimiter, .extractBetweenDelimiters,
             .addExtractFirstChars, .addExtractLastChars, .addExtractBeforeDelimiter, .addExtractAfterDelimiter, .addExtractBetweenDelimiters,
             .addCustomColumn, .groupByCount:
            return true
        default:
            return false
        }
    }

    public func stepCommand(context: QueryRibbonContext) -> StepCommand? {
        switch self {
        case .removeColumns:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .removeColumns(context.selectedColumns)

        case .sortAscending:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .sortRows(context.selectedColumns.map { SortKey(column: $0, descending: false) })

        case .sortDescending:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .sortRows(context.selectedColumns.map { SortKey(column: $0, descending: true) })

        case .keepTopRows:
            guard let n = context.rowCount, n >= 1 else { return nil }
            return .keepTopRows(n)

        case .removeTopRows:
            guard let n = context.rowCount, n >= 1 else { return nil }
            return .removeTopRows(n)

        case .removeDuplicates:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .removeDuplicates(context.selectedColumns)

        case .promoteHeaders:
            return .promoteHeaders

        case .changeTypeWholeNumber:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .changeType(context.selectedColumns.map { ColumnTypeChange(column: $0, type: .wholeNumber) })

        case .changeTypeDecimal:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .changeType(context.selectedColumns.map { ColumnTypeChange(column: $0, type: .decimal) })

        case .changeTypeText:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .changeType(context.selectedColumns.map { ColumnTypeChange(column: $0, type: .text) })

        case .changeTypeDate:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .changeType(context.selectedColumns.map { ColumnTypeChange(column: $0, type: .date) })

        case .changeTypeDateTime:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .changeType(context.selectedColumns.map { ColumnTypeChange(column: $0, type: .dateTime) })

        case .changeTypeLogical:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .changeType(context.selectedColumns.map { ColumnTypeChange(column: $0, type: .logical) })

        case .replaceValue:
            guard !context.selectedColumns.isEmpty,
                  let old = context.replaceOld,
                  let new = context.replaceNew else { return nil }
            return .replaceValue(old: .text(old), new: .text(new), columns: context.selectedColumns)

        case .filterEquals:
            guard context.selectedColumns.count == 1,
                  let col = context.selectedColumns.first,
                  let values = context.filterValues,
                  !values.isEmpty else { return nil }
            return .filterEquals(column: col, values: values)

        case .reverseRows:
            return .reverseRows

        case .fillDown:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .fillDown(context.selectedColumns)

        case .fillUp:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .fillUp(context.selectedColumns)

        case .replaceErrors:
            guard !context.selectedColumns.isEmpty, let raw = context.replaceErrorText else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lit: MLiteral
            if trimmed.isEmpty || trimmed.lowercased() == "null" {
                lit = .null
            } else if let num = Double(trimmed) {
                lit = .number(num)
            } else if trimmed.lowercased() == "true" {
                lit = .logical(true)
            } else if trimmed.lowercased() == "false" {
                lit = .logical(false)
            } else {
                lit = .text(raw)
            }
            return .replaceErrors(context.selectedColumns.map { ErrorReplacement(column: $0, value: lit) })

        case .formatLowercase:
            guard !context.selectedColumns.isEmpty,
                  context.selectedColumns.allSatisfy({ context.columnTypes[$0] == .string }) else { return nil }
            return .format(.lowercase, columns: context.selectedColumns)

        case .formatUppercase:
            guard !context.selectedColumns.isEmpty,
                  context.selectedColumns.allSatisfy({ context.columnTypes[$0] == .string }) else { return nil }
            return .format(.uppercase, columns: context.selectedColumns)

        case .formatCapitalizeEachWord:
            guard !context.selectedColumns.isEmpty,
                  context.selectedColumns.allSatisfy({ context.columnTypes[$0] == .string }) else { return nil }
            return .format(.capitalizeEachWord, columns: context.selectedColumns)

        case .formatTrim:
            guard !context.selectedColumns.isEmpty,
                  context.selectedColumns.allSatisfy({ context.columnTypes[$0] == .string }) else { return nil }
            return .format(.trim, columns: context.selectedColumns)

        case .formatClean:
            guard !context.selectedColumns.isEmpty,
                  context.selectedColumns.allSatisfy({ context.columnTypes[$0] == .string }) else { return nil }
            return .format(.clean, columns: context.selectedColumns)

        case .splitByDelimiter:
            guard context.selectedColumns.count == 1,
                  let col = context.selectedColumns.first,
                  context.columnTypes[col] == .string,
                  let d = context.delimiter, !d.isEmpty,
                  let n = context.splitColumnCount, n >= 2 else { return nil }
            let into = (1...n).map { "\(col).\($0)" }
            return .splitByDelimiter(column: col, delimiter: d, into: into)

        case .splitByNumberOfChars:
            guard context.selectedColumns.count == 1,
                  let col = context.selectedColumns.first,
                  context.columnTypes[col] == .string,
                  let len = context.charCount, len >= 1,
                  let n = context.splitColumnCount, n >= 2 else { return nil }
            let into = (1...n).map { "\(col).\($0)" }
            return .splitByRepeatedLengths(column: col, length: len, into: into)

        case .extractLength, .addExtractLength:
            guard context.selectedColumns.count == 1, let col = context.selectedColumns.first, context.columnTypes[col] == .string else { return nil }
            let newName = self == .addExtractLength ? StepFactory.uniqueName("Length", existing: Set(context.allColumns)) : nil
            return .extractText(column: col, kind: .length, newColumnName: newName)

        case .extractFirstChars, .addExtractFirstChars:
            guard context.selectedColumns.count == 1, let col = context.selectedColumns.first, context.columnTypes[col] == .string,
                  let n = context.charCount, n >= 0 else { return nil }
            let newName = self == .addExtractFirstChars ? StepFactory.uniqueName("First Characters", existing: Set(context.allColumns)) : nil
            return .extractText(column: col, kind: .firstCharacters(n), newColumnName: newName)

        case .extractLastChars, .addExtractLastChars:
            guard context.selectedColumns.count == 1, let col = context.selectedColumns.first, context.columnTypes[col] == .string,
                  let n = context.charCount, n >= 0 else { return nil }
            let newName = self == .addExtractLastChars ? StepFactory.uniqueName("Last Characters", existing: Set(context.allColumns)) : nil
            return .extractText(column: col, kind: .lastCharacters(n), newColumnName: newName)

        case .extractBeforeDelimiter, .addExtractBeforeDelimiter:
            guard context.selectedColumns.count == 1, let col = context.selectedColumns.first, context.columnTypes[col] == .string,
                  let d = context.delimiter, !d.isEmpty else { return nil }
            let newName = self == .addExtractBeforeDelimiter ? StepFactory.uniqueName("Text Before Delimiter", existing: Set(context.allColumns)) : nil
            return .extractText(column: col, kind: .beforeDelimiter(d), newColumnName: newName)

        case .extractAfterDelimiter, .addExtractAfterDelimiter:
            guard context.selectedColumns.count == 1, let col = context.selectedColumns.first, context.columnTypes[col] == .string,
                  let d = context.delimiter, !d.isEmpty else { return nil }
            let newName = self == .addExtractAfterDelimiter ? StepFactory.uniqueName("Text After Delimiter", existing: Set(context.allColumns)) : nil
            return .extractText(column: col, kind: .afterDelimiter(d), newColumnName: newName)

        case .extractBetweenDelimiters, .addExtractBetweenDelimiters:
            guard context.selectedColumns.count == 1, let col = context.selectedColumns.first, context.columnTypes[col] == .string,
                  let s = context.delimiter, !s.isEmpty, let e = context.endDelimiter, !e.isEmpty else { return nil }
            let newName = self == .addExtractBetweenDelimiters ? StepFactory.uniqueName("Text Between Delimiters", existing: Set(context.allColumns)) : nil
            return .extractText(column: col, kind: .betweenDelimiters(start: s, end: e), newColumnName: newName)

        case .dateYear, .dateQuarter, .dateMonth, .dateMonthName, .dateDay, .dateDayName, .dateStartOfMonth, .dateEndOfMonth,
             .addDateYear, .addDateQuarter, .addDateMonth, .addDateMonthName, .addDateDay, .addDateDayName, .addDateStartOfMonth, .addDateEndOfMonth:
            guard context.selectedColumns.count == 1, let col = context.selectedColumns.first,
                  context.columnTypes[col] == .dateTime else { return nil }
            let (kind, isAdd): (DateExtractKind, Bool) = switch self {
            case .dateYear: (.year, false)
            case .dateQuarter: (.quarter, false)
            case .dateMonth: (.month, false)
            case .dateMonthName: (.monthName, false)
            case .dateDay: (.day, false)
            case .dateDayName: (.dayOfWeekName, false)
            case .dateStartOfMonth: (.startOfMonth, false)
            case .dateEndOfMonth: (.endOfMonth, false)
            case .addDateYear: (.year, true)
            case .addDateQuarter: (.quarter, true)
            case .addDateMonth: (.month, true)
            case .addDateMonthName: (.monthName, true)
            case .addDateDay: (.day, true)
            case .addDateDayName: (.dayOfWeekName, true)
            case .addDateStartOfMonth: (.startOfMonth, true)
            case .addDateEndOfMonth: (.endOfMonth, true)
            default: (.year, false)
            }
            let newName = isAdd ? StepFactory.uniqueName(kind.defaultColumnName, existing: Set(context.allColumns)) : nil
            return .extractDate(column: col, kind: kind, newColumnName: newName)

        case .groupByCount:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .groupByCount(keys: context.selectedColumns, newColumn: "Count")

        case .unpivotOtherColumns:
            guard !context.selectedColumns.isEmpty else { return nil }
            return .unpivotOtherColumns(keep: context.selectedColumns)

        case .pivot:
            guard context.selectedColumns.count >= 2 else { return nil }
            return .pivot(attributeColumn: context.selectedColumns[0], valueColumn: context.selectedColumns[1])

        case .addIndexColumnFrom0:
            return .addIndexColumn(start: 0, step: 1)

        case .addIndexColumnFrom1:
            return .addIndexColumn(start: 1, step: 1)

        case .addCustomColumn:
            guard let name = context.customColumnName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  let formula = context.customColumnFormula?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !formula.isEmpty else { return nil }
            return .addCustomColumn(name: name, formula: formula)
        }
    }

    public func isEnabled(context: QueryRibbonContext) -> Bool {
        guard isAvailable else { return false }
        if needsParameters {
            switch self {
            case .keepTopRows, .removeTopRows, .addCustomColumn, .groupByCount:
                return true
            case .replaceValue, .replaceErrors:
                return !context.selectedColumns.isEmpty
            case .filterEquals:
                return context.selectedColumns.count == 1
            case .splitByDelimiter, .splitByNumberOfChars,
                 .extractFirstChars, .extractLastChars, .extractBeforeDelimiter, .extractAfterDelimiter, .extractBetweenDelimiters,
                 .addExtractFirstChars, .addExtractLastChars, .addExtractBeforeDelimiter, .addExtractAfterDelimiter, .addExtractBetweenDelimiters:
                guard context.selectedColumns.count == 1, let col = context.selectedColumns.first else { return false }
                return context.columnTypes[col] == .string
            default:
                return true
            }
        } else {
            return stepCommand(context: context) != nil
        }
    }
}
