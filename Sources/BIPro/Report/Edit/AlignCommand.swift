import Foundation

/// Lệnh căn lề và phân bố (D7). Công thức theo Power BI Desktop, VM-D7 (`docs/phase-d-evidence/vm-d7/QUAN-SAT.md` §5).
enum AlignCommand: CaseIterable, Hashable, Sendable {
    case left, centerH, right, top, middleV, bottom, distributeH, distributeV

    var title: String {
        switch self {
        case .left: biN("Căn trái", "Align left")
        case .centerH: biN("Căn giữa ngang", "Align center")
        case .right: biN("Căn phải", "Align right")
        case .top: biN("Căn trên", "Align top")
        case .middleV: biN("Căn giữa dọc", "Align middle")
        case .bottom: biN("Căn dưới", "Align bottom")
        case .distributeH: biN("Phân bố ngang", "Distribute horizontally")
        case .distributeV: biN("Phân bố dọc", "Distribute vertically")
        }
    }

    var systemImage: String {
        switch self {
        case .left: "align.horizontal.left"
        case .centerH: "align.horizontal.center"
        case .right: "align.horizontal.right"
        case .top: "align.vertical.top"
        case .middleV: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        case .distributeH: "distribute.horizontal.center"
        case .distributeV: "distribute.vertical.center"
        }
    }

    /// Số phần tử tối thiểu: căn cần 2, phân bố cần 3 (Desktop làm mờ Distribute khi chỉ chọn 2).
    var minimumCount: Int { self == .distributeH || self == .distributeV ? 3 : 2 }
}

extension LayoutGeometry {
    /// Khung mới của các phần tử khi áp `command`; cùng thứ tự với `frames`, kích thước không đổi, kẹp trong trang.
    /// - Trái, phải, trên, dưới: theo mép xa nhất của vùng chọn.
    /// - Giữa ngang, giữa dọc: mọi tâm về **trung bình các tâm** (không phải tâm hộp bao; VM-D7).
    /// - Phân bố: hai phần tử ngoài cùng giữ nguyên, khoảng hở giữa các phần tử kề nhau bằng nhau.
    static func align(_ command: AlignCommand, frames: [Frame], page: PageBounds) -> [Frame] {
        guard frames.count >= command.minimumCount else { return frames }
        var out = frames
        func clampX(_ v: Int, _ f: Frame) -> Int { min(max(v, 0), max(0, page.width - f.width)) }
        func clampY(_ v: Int, _ f: Frame) -> Int { min(max(v, 0), max(0, page.height - f.height)) }
        switch command {
        case .left:
            let edge = frames.map(\.x).min()!
            for i in out.indices { out[i].x = clampX(edge, out[i]) }
        case .right:
            let edge = frames.map(\.right).max()!
            for i in out.indices { out[i].x = clampX(edge - out[i].width, out[i]) }
        case .top:
            let edge = frames.map(\.y).min()!
            for i in out.indices { out[i].y = clampY(edge, out[i]) }
        case .bottom:
            let edge = frames.map(\.bottom).max()!
            for i in out.indices { out[i].y = clampY(edge - out[i].height, out[i]) }
        case .centerH:
            let mean = frames.map { Double($0.x) + Double($0.width) / 2 }.reduce(0, +) / Double(frames.count)
            for i in out.indices { out[i].x = clampX(Int((mean - Double(out[i].width) / 2).rounded()), out[i]) }
        case .middleV:
            let mean = frames.map { Double($0.y) + Double($0.height) / 2 }.reduce(0, +) / Double(frames.count)
            for i in out.indices { out[i].y = clampY(Int((mean - Double(out[i].height) / 2).rounded()), out[i]) }
        case .distributeH:
            let order = frames.indices.sorted { (frames[$0].x, $0) < (frames[$1].x, $1) }
            let first = frames[order.first!]
            let span = Double(frames.map(\.right).max()! - first.x)
            let gap = max(0, (span - Double(order.reduce(0) { $0 + frames[$1].width })) / Double(order.count - 1))
            var cursor = Double(first.x)
            for i in order {
                out[i].x = clampX(Int(cursor.rounded()), out[i])
                cursor += Double(frames[i].width) + gap
            }
            out[order.first!].x = first.x
        case .distributeV:
            let order = frames.indices.sorted { (frames[$0].y, $0) < (frames[$1].y, $1) }
            let first = frames[order.first!]
            let span = Double(frames.map(\.bottom).max()! - first.y)
            let gap = max(0, (span - Double(order.reduce(0) { $0 + frames[$1].height })) / Double(order.count - 1))
            var cursor = Double(first.y)
            for i in order {
                out[i].y = clampY(Int(cursor.rounded()), out[i])
                cursor += Double(frames[i].height) + gap
            }
            out[order.first!].y = first.y
        }
        return out
    }
}
