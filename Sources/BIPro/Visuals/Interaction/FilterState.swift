import DAXEngine
import Foundation

struct SlicerState: Hashable, Sendable {
    var columns: [QueryColumn] // một cột cho mỗi cấp của slicer (Năm › Quý › Tháng)
    var selection: SlicerSelection

    init(columns: [QueryColumn], selection: SlicerSelection) {
        self.columns = columns
        self.selection = selection
    }
}

struct ColumnValues: Hashable, Sendable {
    var column: QueryColumn
    var values: [Value]

    init(column: QueryColumn, values: [Value]) {
        self.column = column
        self.values = values
    }
}

struct FilterState: Hashable, Sendable {
    var slicers: [String: SlicerState] = [:] // khoá = visualID
    var slicerOrder: [String] = [] // thứ tự slicer trên trang; lead điền theo thứ tự visual
    var selection = SelectionState() // lựa chọn điểm (lọc chéo / tô sáng)
    var drillthrough: [ColumnValues] = [] // tham số drillthrough đã có giá trị
    var drillFilters: [String: [ColumnValues]] = [:] // visualID → bộ lọc do drill down sinh ra
    var overrides: [InteractionOverride] = [] // Edit interactions của người dùng

    init(
        slicers: [String: SlicerState] = [:],
        slicerOrder: [String] = [],
        selection: SelectionState = SelectionState(),
        drillthrough: [ColumnValues] = [],
        drillFilters: [String: [ColumnValues]] = [:],
        overrides: [InteractionOverride] = []
    ) {
        self.slicers = slicers
        self.slicerOrder = slicerOrder
        self.selection = selection
        self.drillthrough = drillthrough
        self.drillFilters = drillFilters
        self.overrides = overrides
    }

    mutating func setSlicer(visualID: String, columns: [QueryColumn], selection: SlicerSelection) {
        slicers[visualID] = SlicerState(columns: columns, selection: selection)
        if !slicerOrder.contains(visualID) {
            slicerOrder.append(visualID)
        }
    }
}
