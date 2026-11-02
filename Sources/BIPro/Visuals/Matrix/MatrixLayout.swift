import AppKit
import DAXEngine
import Foundation

struct MatrixLayout: Sendable {
    /// Số tầng tiêu đề cột
    let headerTiers: Int
    /// Số tầng tiêu đề đang hiển thị theo dữ liệu columns
    let activeHeaderTiers: Int
    /// Độ rộng của cột tiêu đề hàng bên trái
    let rowHeaderWidth: CGFloat
    /// Độ rộng của từng cột giá trị
    let columnWidths: [CGFloat]
    /// Chiều cao mỗi dòng giá trị
    let rowHeight: CGFloat
    /// Chiều cao mỗi tầng tiêu đề cột
    let headerHeight: CGFloat
    /// Tổng độ rộng toàn bảng
    let totalWidth: CGFloat
    /// Tổng chiều cao toàn bảng
    let totalHeight: CGFloat

    init(data: MatrixData, format: VisualFormat) {
        // Số tầng tiêu đề
        let levelsCount = data.columnLevels.count
        self.headerTiers = max(1, levelsCount)
        let maxActive = data.columns.filter { !$0.isGrandTotal }.map(\.level).max() ?? -1
        self.activeHeaderTiers = max(1, maxActive + 1)

        // Chiều cao dòng và tiêu đề
        let valFontSize = CGFloat(format.matrix.valuesFontSize ?? 10)
        let padding = CGFloat(format.matrix.rowPadding ?? 3)
        self.rowHeight = max(24, valFontSize + padding * 2 + 10)
        let headerFontSize = CGFloat(format.matrix.columnHeaderFontSize ?? 10)
        self.headerHeight = max(26, headerFontSize + padding * 2 + 8)

        // Độ rộng cột tiêu đề hàng (trái)
        let rowQueryRef = data.rowLevels.first?.queryRef
        if let ref = rowQueryRef, let w = format.matrix.columnWidths[ref] {
            self.rowHeaderWidth = CGFloat(w)
        } else {
            // Tự tính theo nhãn cấp hàng và nội dung hàng
            var maxChars = data.rowLevels.first?.displayName.count ?? 8
            for r in data.rows {
                let text = r.isGrandTotal ? "Total" : (r.path.last?.asText() ?? "")
                maxChars = max(maxChars, text.count + (r.level > 0 ? r.level * 2 : 0))
            }
            self.rowHeaderWidth = max(110, min(240, CGFloat(maxChars * 8 + 36)))
        }

        // Độ rộng các cột giá trị
        let colCount = data.columnCount
        var widths: [CGFloat] = []

        for c in 0..<colCount {
            var assignedWidth: CGFloat?

            // 1. Kiểm tra theo columnLevels[level].queryRef nếu có
            if !data.columns.isEmpty && c < data.columns.count {
                let colHeader = data.columns[c]
                if colHeader.level >= 0 && colHeader.level < data.columnLevels.count {
                    let qRef = data.columnLevels[colHeader.level].queryRef
                    if let w = format.matrix.columnWidths[qRef] {
                        assignedWidth = CGFloat(w)
                    }
                }
            }

            // 2. Kiểm tra theo bất kỳ queryRef nào trong columnLevels
            if assignedWidth == nil {
                for lvl in data.columnLevels {
                    if let w = format.matrix.columnWidths[lvl.queryRef] {
                        assignedWidth = CGFloat(w)
                        break
                    }
                }
            }

            // 3. Kiểm tra theo measure
            if assignedWidth == nil {
                for m in data.measures {
                    if let w = format.matrix.columnWidths[m.queryRef] {
                        assignedWidth = CGFloat(w)
                        break
                    }
                }
            }

            if let w = assignedWidth {
                widths.append(w)
            } else {
                // Tự tính theo tiêu đề cột và nội dung ô
                var maxChars = 6
                if !data.columns.isEmpty && c < data.columns.count {
                    let colHeader = data.columns[c]
                    let text = colHeader.isGrandTotal ? "Total" : (colHeader.path.last?.asText() ?? "")
                    maxChars = max(maxChars, text.count)
                }
                for m in data.measures {
                    maxChars = max(maxChars, m.displayName.count)
                }
                widths.append(max(75, min(180, CGFloat(maxChars * 8 + 24))))
            }
        }

        self.columnWidths = widths
        self.totalWidth = rowHeaderWidth + widths.reduce(0, +)
        self.totalHeight = headerHeight * CGFloat(headerTiers) + rowHeight * CGFloat(data.rows.count)
    }

    func width(forColumn index: Int) -> CGFloat {
        guard index >= 0 && index < columnWidths.count else { return 80 }
        return columnWidths[index]
    }
}
