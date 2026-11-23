// D6: bookmark do người dùng thêm → dạng ghi vào file, hoặc "chỉ trong phiên" kèm lý do (research R6).
import DAXEngine
import Foundation
import PBIXKit

enum BookmarkExport {
    /// Tên hợp lệ: không rỗng sau khi bỏ khoảng trắng, không quá 128 ký tự, không trùng tên bookmark khác (`others`).
    static func validateName(_ proposed: String, others: [String]) -> ExportResult<String> {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .sessionOnly(biN("Tên bookmark không được để trống.", "The bookmark name can't be empty.")) }
        if trimmed.count > 128 { return .sessionOnly(biN("Tên bookmark quá dài (tối đa 128 ký tự).", "The bookmark name is too long (128 characters max).")) }
        if others.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) { return .sessionOnly(biN("Đã có bookmark tên \"\(trimmed)\".", "A bookmark named \"\(trimmed)\" already exists.")) }
        return .writable(trimmed)
    }

    /// Dạng tối giản đã được Desktop áp đúng (VM-D6): Display và trang (dạng Nhom6), và Data gồm lựa chọn slicer cột đơn.
    /// Data có lựa chọn điểm dữ liệu, drill, mở nút, hoặc slicer hierarchy đã chọn thì chưa ghi được (kèm lý do).
    static func spec(for bookmark: UserBookmark, name: String, displayName: String, pageVisuals: [ReportVisual]?) -> ExportResult<BookmarkSpec> {
        guard let page = bookmark.pageID, let visuals = pageVisuals else {
            return .sessionOnly(biN("Trang của bookmark không còn trong báo cáo.", "The bookmark's page is no longer in the report."))
        }
        let states = visuals.map { visual in
            BookmarkSpec.VisualState(id: visual.id, type: visual.type, hidden: bookmark.display && bookmark.visibility.isHidden(visual))
        }
        var spec = BookmarkSpec(name: name, displayName: displayName, page: page, visuals: states,
                                suppressActiveSection: !bookmark.currentPage, suppressData: !bookmark.data, suppressDisplay: !bookmark.display)
        guard bookmark.data else { return .writable(spec) }

        if bookmark.drillDepth.values.contains(where: { $0 > 0 }) { return .sessionOnly(biN("Data có drill chưa lưu được vào file; trở về cấp gốc hoặc tắt Data.", "Data with a drill can't be saved to the file yet; return to the top level or turn off Data.")) }
        if !bookmark.slicerExpansion.isEmpty || !bookmark.matrixExpansion.isEmpty {
            return .sessionOnly(biN("Data có nút slicer hoặc matrix đang mở chưa lưu được vào file; đóng nút hoặc tắt Data.", "Data with expanded slicer or matrix nodes can't be saved to the file yet; collapse them or turn off Data."))
        }
        let pageState = bookmark.states[page]
        if let pageState {
            if !pageState.selection.points.isEmpty { return .sessionOnly(biN("Data có điểm dữ liệu đang chọn (lọc chéo) chưa lưu được vào file; bỏ chọn hoặc tắt Data.", "Data with a selected data point (cross-filter) can't be saved to the file yet; clear the selection or turn off Data.")) }
            if !pageState.drillFilters.isEmpty || !pageState.drillthrough.isEmpty { return .sessionOnly(biN("Data có drill hoặc drillthrough chưa lưu được vào file.", "Data with a drill or drillthrough can't be saved to the file yet.")) }
        }
        for visual in visuals where slicerTypes.contains(visual.type) {
            guard let state = pageState?.slicers[visual.id], !state.selection.isEmpty else { continue }
            guard state.columns.count == 1 else { return .sessionOnly(biN("Slicer nhiều cấp đã chọn chưa lưu được vào file.", "A multi-level slicer selection can't be saved to the file yet.")) }
            var literals: [FilterLiteral] = []
            for path in state.selection.paths.sorted(by: { FilterTranslator.valuePrecedes($0[0], $1[0]) }) {
                guard path.count == 1, let literal = FilterExport.literal(path[0]) else {
                    return .sessionOnly(biN("Slicer có giá trị kiểu ngày hoặc tiền tệ chưa lưu được vào file.", "A slicer with date or currency values can't be saved to the file yet."))
                }
                literals.append(literal)
            }
            spec.slicers[visual.id] = BookmarkSpec.SlicerSelection(entity: state.columns[0].table, property: state.columns[0].column, values: literals)
        }
        return .writable(spec)
    }

    static let slicerTypes: Set<String> = ["slicer", "advancedSlicerVisual", "listSlicer", "textSlicer"]
}
