// Hợp đồng Phase C (đợt 0, lead): renderer báo sự kiện ra ngoài, nhận trạng thái chọn vào.
//
// Renderer không tự sửa bộ lọc. Renderer chỉ:
// - vẽ trạng thái chọn/tô sáng theo `VisualRenderContext.selection`;
// - gọi `VisualActions` khi người dùng bấm, rê chuột, chuột phải, drill.
// `FilterState`/`SelectionState` (gói I) và phần ghép (gói G) quyết định việc chạy lại truy vấn.
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

/// Định danh một điểm dữ liệu: queryRef → giá trị, gồm các cấp danh mục và series của điểm đó.
/// Ví dụ cột 2016 của series "Female": ["Dim_Date.year": 2016, "Dim_Client.gender": "Female"].
struct DataPointID: Hashable, Sendable {
    var values: [String: Value]

    init(_ values: [String: Value]) { self.values = values }
}

/// Lựa chọn của một slicer. Mỗi phần tử là một đường dẫn trong cây (ví dụ [2016] chọn cả năm, [2016, "Q1"] chỉ chọn quý).
struct SlicerSelection: Hashable, Sendable {
    var paths: Set<[Value]>

    init(_ paths: Set<[Value]> = []) { self.paths = paths }

    var isEmpty: Bool { paths.isEmpty }
}

enum DrillRequest: Hashable, Sendable {
    /// Drill down vào một điểm (drill mode bật, bấm vào điểm).
    case down(DataPointID)
    case up
    /// "Show next level" (đi xuống một cấp cho toàn bộ trục).
    case nextLevel
    /// "Expand all down one level".
    case expandAll
    /// Matrix: bấm +/− trên một tiêu đề.
    case toggle(axis: MatrixAxis, path: [Value])
}

enum MatrixAxis: Hashable, Sendable { case rows, columns }

/// Các hành động renderer gọi ra. Mặc định không làm gì, để renderer chạy được trong test và preview.
struct VisualActions {
    /// Bấm một điểm; `nil` là bấm vào chỗ trống (bỏ chọn). `additive` = giữ Ctrl/⌘.
    var select: (_ point: DataPointID?, _ additive: Bool) -> Void = { _, _ in }
    /// Rê chuột lên một điểm (hoặc rời khỏi: `nil`). `location` theo toạ độ của visual.
    var hover: (_ point: DataPointID?, _ location: CGPoint) -> Void = { _, _ in }
    /// Chuột phải lên một điểm (hoặc chỗ trống). `location` theo toạ độ của visual.
    var contextMenu: (_ point: DataPointID?, _ location: CGPoint) -> Void = { _, _ in }
    var drill: (DrillRequest) -> Void = { _ in }
    /// Slicer đổi lựa chọn.
    var slicerChanged: (SlicerSelection) -> Void = { _ in }

    static let none = VisualActions()
}

/// Mọi thứ renderer cần, ngoài `DataView`.
struct VisualRenderContext {
    var theme: ReportTheme
    var format: VisualFormat
    /// Điểm đang được chọn trong CHÍNH visual này. Rỗng = không chọn gì. Khi khác rỗng, các điểm khác vẽ mờ (opacity 0,4)
    /// như Power BI [SUY ĐOÁN: độ mờ chính xác sẽ đo từ ảnh O-C4].
    var selection: Set<DataPointID>
    /// Lựa chọn hiện tại khi visual là slicer.
    var slicerSelection: SlicerSelection
    var actions: VisualActions

    init(theme: ReportTheme = .fallback, format: VisualFormat = VisualFormat(), selection: Set<DataPointID> = [],
         slicerSelection: SlicerSelection = SlicerSelection(), actions: VisualActions = .none) {
        self.theme = theme
        self.format = format
        self.selection = selection
        self.slicerSelection = slicerSelection
        self.actions = actions
    }
}
