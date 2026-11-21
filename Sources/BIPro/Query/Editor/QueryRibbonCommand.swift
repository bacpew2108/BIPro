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
    public var splitColumnCount: Int?
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
        splitColumnCount: Int? = nil,
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
        self.splitColumnCount = splitColumnCount
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
    case formatLowercase
    case formatUppercase
    case formatCapitalizeEachWord
    case formatTrim
    case formatClean
    case splitByDelimiter
    case groupByCount
    case unpivotOtherColumns
    case pivot

    // Thêm cột (Add Column)
    case addIndexColumnFrom0
    case addIndexColumnFrom1
    case addCustomColumn

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
        case .formatLowercase: return en ? "lowercase" : "chữ thường"
        case .formatUppercase: return en ? "UPPERCASE" : "CHỮ HOA"
        case .formatCapitalizeEachWord: return en ? "Capitalize Each Word" : "Viết Hoa Mỗi Từ"
        case .formatTrim: return en ? "Trim" : "Cắt khoảng trắng"
        case .formatClean: return en ? "Clean" : "Làm sạch"
        case .splitByDelimiter: return en ? "Split Column by Delimiter" : "Tách cột theo dấu phân cách"
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
        case .reverseRows, .fillDown, .fillUp, .formatLowercase, .formatUppercase,
             .formatCapitalizeEachWord, .formatTrim, .formatClean, .splitByDelimiter,
             .groupByCount, .unpivotOtherColumns, .pivot:
            return .transform
        case .addIndexColumnFrom0, .addIndexColumnFrom1, .addCustomColumn:
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
        case .formatLowercase, .formatUppercase, .formatCapitalizeEachWord, .formatTrim, .formatClean:
            return "textformat"
        case .splitByDelimiter: return "rectangle.split.2x1"
        case .groupByCount: return "rectangle.3.group"
        case .unpivotOtherColumns: return "tablecells.badge.ellipsis"
        case .pivot: return "tablecells"
        case .addIndexColumnFrom0, .addIndexColumnFrom1: return "list.number"
        case .addCustomColumn: return "plus.rectangle"
        }
    }

    public var needsParameters: Bool {
        switch self {
        case .keepTopRows, .removeTopRows, .replaceValue, .filterEquals, .splitByDelimiter, .addCustomColumn, .groupByCount:
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
            case .replaceValue:
                return !context.selectedColumns.isEmpty
            case .filterEquals:
                return context.selectedColumns.count == 1
            case .splitByDelimiter:
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
