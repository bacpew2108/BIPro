import Foundation

struct CrossColumn: Hashable, Sendable {
    var queryRef: String
    var column: QueryColumn

    init(queryRef: String, column: QueryColumn) {
        self.queryRef = queryRef
        self.column = column
    }
}

struct SelectionState: Hashable, Sendable {
    private(set) var sourceVisualID: String?
    private(set) var sourceVisualType: String?
    private(set) var points: Set<DataPointID> = []
    private(set) var columns: [CrossColumn] = []

    init(
        sourceVisualID: String? = nil,
        sourceVisualType: String? = nil,
        points: Set<DataPointID> = [],
        columns: [CrossColumn] = []
    ) {
        self.sourceVisualID = sourceVisualID
        self.sourceVisualType = sourceVisualType
        self.points = points
        self.columns = columns
    }

    mutating func select(
        _ point: DataPointID?,
        additive: Bool,
        from source: InteractionTarget,
        columns: [CrossColumn]
    ) {
        // point == nil (bấm chỗ trống) → xoá lựa chọn
        guard let point else {
            clear()
            return
        }

        if !additive {
            // Nhấn thường (additive == false)
            if sourceVisualID != source.visualID {
                // Khác visual nguồn hoặc chưa có nguồn → thay thế mọi lựa chọn trước
                sourceVisualID = source.visualID
                sourceVisualType = source.visualType
                points = [point]
                self.columns = columns
            } else {
                // Cùng visual nguồn
                if points == [point] {
                    // Điểm đang là điểm chọn duy nhất của chính visual này → bỏ chọn
                    clear()
                } else if points.contains(point) {
                    // Điểm đang được chọn cùng nhiều điểm khác → chỉ giữ điểm này // [SUY ĐOÁN]
                    points = [point]
                    self.columns = columns
                } else {
                    // Điểm chưa được chọn → lựa chọn mới chỉ gồm điểm này
                    points = [point]
                    self.columns = columns
                }
            }
        } else {
            // Nhấn kèm Ctrl/⌘ (additive == true)
            if sourceVisualID != source.visualID {
                // Khác visual nguồn thì thay thế như nhấn thường
                sourceVisualID = source.visualID
                sourceVisualType = source.visualType
                points = [point]
                self.columns = columns
            } else {
                // Cùng visual nguồn thì bật/tắt điểm đó trong tập chọn (tập rỗng thì xoá nguồn)
                self.columns = columns
                if points.contains(point) {
                    points.remove(point)
                    if points.isEmpty {
                        clear()
                    }
                } else {
                    points.insert(point)
                }
            }
        }
    }

    mutating func clear() {
        sourceVisualID = nil
        sourceVisualType = nil
        points = []
        columns = []
    }

    /// Điểm đang chọn của CHÍNH visual này (đưa vào `VisualRenderContext.selection`); rỗng nếu visual khác là nguồn.
    func points(forVisual visualID: String) -> Set<DataPointID> {
        guard sourceVisualID == visualID else { return [] }
        return points
    }
}
