import Foundation
import PBIXKit

/// Khung của một visual trên trang, tính bằng điểm ảnh nguyên của trang (như `position` trong file).
struct Frame: Hashable, Sendable {
    var x: Int, y: Int, width: Int, height: Int

    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    init(_ visual: ReportVisual) {
        self.init(x: Int(visual.x.rounded()), y: Int(visual.y.rounded()),
                  width: Int(visual.width.rounded()), height: Int(visual.height.rounded()))
    }

    var right: Int { x + width }
    var bottom: Int { y + height }
}

struct PageBounds: Hashable, Sendable {
    var width: Int, height: Int

    init(width: Int, height: Int) { self.width = width; self.height = height }
    init(_ page: ReportPage) { self.init(width: Int(page.width.rounded()), height: Int(page.height.rounded())) }
}

/// Tám tay nắm đổi cỡ: chữ cái là hướng của cạnh được kéo.
enum ResizeHandle: CaseIterable, Sendable {
    case n, s, e, w, ne, nw, se, sw

    var movesLeft: Bool { self == .w || self == .nw || self == .sw }
    var movesRight: Bool { self == .e || self == .ne || self == .se }
    var movesTop: Bool { self == .n || self == .ne || self == .nw }
    var movesBottom: Bool { self == .s || self == .se || self == .sw }
}

/// Hình học sửa bố cục: hàm thuần, theo `specs/002-d1-canvas-luu-t1/contracts/layout-editing.md`.
/// Các hằng số [SUY ĐOÁN] (so với Power BI Desktop) nằm cả ở đây để đổi một chỗ.
enum LayoutGeometry {
    /// Lưới bám 8 px (kế hoạch dự án; [SUY ĐOÁN] so với Power BI).
    static let grid = 8
    /// Cỡ nhỏ nhất của một visual. [SUY ĐOÁN]
    static let minSize = 16
    /// Phím mũi tên dời 1 px, giữ Shift thì 8 px. [SUY ĐOÁN]
    static let nudge = 1
    static let nudgeBig = 8
    /// Bản sao nằm lệch bản gốc chừng này. [SUY ĐOÁN]
    static let duplicateOffset = 16
    /// Dán lệch nguồn chừng này mỗi lần dán (Power BI Desktop, VM-D7: 24,176 → 34,186 → 44,196).
    static let pasteOffset = 10
    /// Khoảng cách `z` giữa các visual (quan sát trong Nhom6).
    static let zStep = 1000

    /// Bội số gần nhất của `grid` (đúng nửa lưới thì làm tròn lên).
    static func snap(_ value: Int, grid step: Int = grid) -> Int {
        let g = max(1, step)
        return Int((Double(value) / Double(g) + 0.5).rounded(.down)) * g
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int { min(max(value, low), max(low, high)) }

    // MARK: Di chuyển

    /// Dời một khung.
    static func move(_ frame: Frame, dx: Int, dy: Int, page: PageBounds, snap: Bool, grid: Int = grid) -> Frame {
        move([frame], dx: dx, dy: dy, page: page, snap: snap, grid: grid)[0]
    }

    /// Dời cả nhóm: gốc của khung bao bám lưới và kẹp trong trang, mọi khung chịu cùng độ dời,
    /// nên vị trí tương đối giữ nguyên (kể cả khi khung không nằm trên lưới).
    static func move(_ frames: [Frame], dx: Int, dy: Int, page: PageBounds, snap doSnap: Bool, grid: Int = grid) -> [Frame] {
        guard let box = boundingBox(frames) else { return frames }
        var targetX = box.x + dx, targetY = box.y + dy
        if doSnap { targetX = snap(targetX, grid: grid); targetY = snap(targetY, grid: grid) }
        targetX = clamp(targetX, 0, page.width - box.width)
        targetY = clamp(targetY, 0, page.height - box.height)
        let shiftX = targetX - box.x, shiftY = targetY - box.y
        return frames.map { Frame(x: $0.x + shiftX, y: $0.y + shiftY, width: $0.width, height: $0.height) }
    }

    // MARK: Đổi cỡ

    /// Kéo một tay nắm `(dx, dy)` điểm. Chỉ cạnh đang kéo đổi, cạnh đó bám lưới; kết quả kẹp trong trang,
    /// không nhỏ hơn `minSize` và không bị đảo chiều.
    static func resize(_ frame: Frame, handle: ResizeHandle, dx: Int, dy: Int, page: PageBounds, snap doSnap: Bool, grid: Int = grid) -> Frame {
        var left = frame.x, right = frame.right, top = frame.y, bottom = frame.bottom
        func edge(_ value: Int) -> Int { doSnap ? snap(value, grid: grid) : value }
        if handle.movesLeft { left = clamp(edge(frame.x + dx), 0, right - minSize) }
        if handle.movesRight { right = clamp(edge(frame.right + dx), left + minSize, page.width) }
        if handle.movesTop { top = clamp(edge(frame.y + dy), 0, bottom - minSize) }
        if handle.movesBottom { bottom = clamp(edge(frame.bottom + dy), top + minSize, page.height) }
        return Frame(x: left, y: top, width: right - left, height: bottom - top)
    }

    // MARK: Khung bao, chọn

    static func boundingBox(_ frames: [Frame]) -> Frame? {
        guard let first = frames.first else { return nil }
        var left = first.x, top = first.y, right = first.right, bottom = first.bottom
        for f in frames.dropFirst() {
            left = min(left, f.x); top = min(top, f.y); right = max(right, f.right); bottom = max(bottom, f.bottom)
        }
        return Frame(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Mã của visual hiện thấy, nằm trên cùng (z lớn nhất; bằng nhau thì cái đứng sau), chứa điểm `(x, y)`.
    /// Cạnh phải và dưới nằm ngoài khung.
    static func hit(x: Int, y: Int, in visuals: [ReportVisual], isHidden: (ReportVisual) -> Bool) -> String? {
        var best: (z: Double, id: String)?
        for visual in visuals where !isHidden(visual) {
            let f = Frame(visual)
            guard x >= f.x, x < f.right, y >= f.y, y < f.bottom else { continue }
            if best == nil || visual.z >= best!.z { best = (visual.z, visual.id) }
        }
        return best?.id
    }

    /// Mã của visual hiện thấy mà khung của nó giao khung chọn (chạm cạnh thì không tính).
    static func marquee(_ rect: Frame, visuals: [ReportVisual], isHidden: (ReportVisual) -> Bool) -> [String] {
        visuals.compactMap { visual in
            guard !isHidden(visual) else { return nil }
            let f = Frame(visual)
            let overlaps = f.x < rect.right && f.right > rect.x && f.y < rect.bottom && f.bottom > rect.y
            return overlaps ? visual.id : nil
        }
    }
}
