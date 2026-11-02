// Hàm thông tin (F-KIT ở đợt 2, F-FILTER ở đợt 3). ISFILTERED, ISCROSSFILTERED, HASONEVALUE và SELECTEDVALUE đọc
// filter context (architecture.md §4.6). Chữ ký do lead khai báo ở đợt 0. ISBLANK cài ở đợt 2.
//
// [SUY ĐOÁN] ISFILTERED(cột) đúng khi có mục cột trực tiếp, hoặc có bộ lọc theo bảng của bảng đó chưa chiếu cột này.
//   Cột nhóm của SUMMARIZECOLUMNS là mục cột trong ô nên cũng tính. Bộ lọc qua quan hệ không tính (không trực tiếp).
// [SUY ĐOÁN] ISCROSSFILTERED(X): R(bảng của X) khi bỏ bộ lọc trực tiếp trên bảng đó khác R(bảng) khi bỏ mọi bộ lọc.
//   Dòng BLANK ảo tính vào R, nên một bộ lọc làm dòng BLANK ảo biến mất cũng được coi là cross-filter.
// [SUY ĐOÁN] SELECTEDVALUE: khi chỉ có đúng một giá trị (kể cả BLANK) thì trả giá trị đó, không trả alt. Không thì trả
//   alt, hoặc BLANK nếu không có alt.
import ColumnStore

public enum InformationFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "ISBLANK", params: [.scalar("value")], impl: .scalar(InformationFunctions.isBlankBody)),
        FunctionSpec(name: "ISFILTERED", params: [.tableOrColumn("tableOrColumnName")], impl: .scalar(isFilteredBody)),
        FunctionSpec(name: "ISCROSSFILTERED", params: [.tableOrColumn("tableOrColumnName")], impl: .scalar(isCrossFilteredBody)),
        FunctionSpec(name: "HASONEVALUE", params: [.column("columnName")], impl: .scalar(hasOneValueBody)),
        FunctionSpec(name: "SELECTEDVALUE", params: [.column("columnName"), .scalar("alternateResult", optional: true)],
                     impl: .scalar(selectedValueBody)),
    ]

    /// ISBLANK chỉ đúng với BLANK thật. ISBLANK(0) là FALSE, ISBLANK("") là FALSE (architecture.md §5.5).
    static func isBlankBody(_ frame: CallFrame) throws(DAXError) -> Value {
        .boolean(try frame.scalar(0).isBlank)
    }

    /// ISFILTERED(cột | bảng): có bộ lọc trực tiếp trên cột, hoặc trên bảng (mục cột hoặc bộ lọc bảng).
    private static let isFilteredBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let evaluator = try fkEvaluator(frame)
        switch try ffTarget(fkArg(frame, 0), evaluator) {
        case .column(let column):
            return .boolean(frame.ctx.filter.isFiltered(column))
        case .table(let table):
            return .boolean(frame.ctx.filter.isFiltered(table: table))
        }
    }

    /// ISCROSSFILTERED(cột | bảng): R(T) có bị bộ lọc từ bảng khác làm thay đổi không. Bộ lọc trực tiếp trên T được bỏ
    /// trước khi so, nên chỉ bộ lọc lan truyền tới T mới làm kết quả TRUE.
    private static let isCrossFilteredBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let evaluator = try fkEvaluator(frame)
        let store = evaluator.store
        let table: TableID
        switch try ffTarget(fkArg(frame, 0), evaluator) {
        case .column(let column): table = column.table
        case .table(let target): table = target
        }
        let columns = try ffSchemaColumns(table, store)
        let withOthers = try frame.ctx.filter.removingColumns(columns)
            .visibleRows(in: store, table: table, overrides: [])
        let unfiltered = try frame.ctx.filter.removingAll()
            .visibleRows(in: store, table: table, overrides: [])
        return .boolean(withOthers != unfiltered)
    }

    /// HASONEVALUE(cột): VALUES(cột) có đúng một giá trị (BLANK được tính là một giá trị).
    private static let hasOneValueBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let evaluator = try fkEvaluator(frame)
        let column = try ffColumnArgument(fkArg(frame, 0))
        return .boolean(try frame.ctx.filter.hasOneValue(column, in: evaluator.store))
    }

    /// SELECTEDVALUE(cột[, alt]): giá trị duy nhất của cột, hoặc alt (BLANK nếu không có alt) khi không có đúng một giá trị.
    private static let selectedValueBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let evaluator = try fkEvaluator(frame)
        let column = try ffColumnArgument(fkArg(frame, 0))
        let values = try frame.ctx.filter.visibleValues(of: column, in: evaluator.store)
        if values.count == 1 { return values[0] }
        if frame.isBlankArgument(1) { return .blank }
        return try frame.scalar(1)
    }
}
