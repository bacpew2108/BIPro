import DAXEngine
import Foundation

/// Một ô tiêu đề cột ở một tầng: gộp các cột liền nhau cùng nút cha (Midwest › Iowa) thành một ô như Power BI.
struct MatrixHeaderSegment {
    var cols: Range<Int>
    var label: String
    var bold: Bool
    /// Nút +/−: đường của nút và đang mở hay không.
    var toggle: (path: [Value], expanded: Bool)?
    /// Đường dùng để chọn (lọc chéo) khi bấm vào nhãn.
    var path: [Value]
}

extension MatrixData {
    /// Các ô của tầng `tier`. Tầng nút cha: một ô gộp mọi cột con và cột tổng của nút; tầng của chính cột: nhãn cột
    /// (cột tổng của nút đang mở ghi "Total"); các tầng dưới cột để trống.
    func headerSegments(tier: Int, lastTier: Int) -> [MatrixHeaderSegment] {
        var out: [MatrixHeaderSegment] = []
        var c = 0
        while c < columns.count {
            let col = columns[c]
            if col.isGrandTotal {
                out.append(MatrixHeaderSegment(cols: c..<c + 1, label: tier == lastTier ? "Total" : "", bold: true, toggle: nil, path: []))
                c += 1
                continue
            }
            let leaf = MatrixLayout.leafTier(col)
            if tier < leaf, tier < col.path.count {
                let key = Array(col.path.prefix(tier + 1))
                var e = c + 1
                while e < columns.count, !columns[e].isGrandTotal, MatrixLayout.leafTier(columns[e]) > tier,
                      Array(columns[e].path.prefix(tier + 1)) == key { e += 1 }
                out.append(MatrixHeaderSegment(cols: c..<e, label: columnLevels.text(key[tier], at: tier), bold: false,
                                               toggle: (key, true), path: key))
                c = e
                continue
            }
            if tier == leaf {
                if col.isExpanded {
                    out.append(MatrixHeaderSegment(cols: c..<c + 1, label: "Total", bold: true, toggle: nil, path: col.path))
                } else {
                    out.append(MatrixHeaderSegment(cols: c..<c + 1, label: columnLevels.text(col.path[tier], at: tier),
                                                   bold: col.level >= 1 && col.hasChildren,
                                                   toggle: col.hasChildren ? (col.path, false) : nil, path: col.path))
                }
            } else {
                out.append(MatrixHeaderSegment(cols: c..<c + 1, label: "", bold: false, toggle: nil, path: []))
            }
            c += 1
        }
        return out
    }
}
