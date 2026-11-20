import AppKit
import PBIXKit
import SwiftUI

/// Lớp phủ chế độ Sửa trên một trang: chọn, kéo di chuyển, khung chọn, và tám tay nắm đổi cỡ.
///
/// Mọi toạ độ là điểm của trang (chưa nhân tỷ lệ). Trong lúc kéo chỉ đổi `preview` (khung tạm); thả chuột thì
/// `LayoutEditor.apply(frames:)` ghi đúng một bước hoàn tác.
struct EditCanvasOverlay: View {
    let editor: LayoutEditor
    let page: ReportPage
    let scale: Double
    let isHidden: (ReportVisual) -> Bool
    @Binding var preview: [String: Frame]
    /// Gọi sau mỗi thay đổi vùng chọn (để đồng bộ `DocumentState.visualID`).
    var onSelectionChange: () -> Void = {}
    /// Gọi khi người dùng bấm vào canvas (để canvas nhận phím).
    var onInteract: () -> Void = {}

    static let space = "editPage"

    private enum Drag {
        /// `select`: bấm vào con khi nhóm đang chọn: nếu không kéo thì khi thả chọn con (như Desktop, D7).
        case move(startFrames: [(id: String, frame: Frame)], select: String?)
        case marquee(origin: CGPoint, base: Set<String>, extend: Bool)
        case ignored
    }

    @State private var drag: Drag?
    @State private var marquee: Frame?
    /// Khung bóng khi đổi cỡ: visual giữ cỡ cũ (không dựng lại biểu đồ mỗi khung hình, đo ở T020: dựng lại sống
    /// mất 124–134 ms mỗi khung trên biểu đồ combo, sát ngưỡng 150 ms), thả chuột mới áp.
    @State private var ghost: [String: Frame] = [:]

    private var bounds: PageBounds { PageBounds(page) }
    private var snapEnabled: Bool { AppPreferences.shared.snapToGrid && !NSEvent.modifierFlags.contains(.option) }
    private var gridSize: Int { AppPreferences.shared.gridSize }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(canvasGesture)
            chrome
            ForEach(Array(ghost.keys), id: \.self) { id in
                if let f = ghost[id] {
                    Rectangle()
                        .fill(DS.Palette.accent.opacity(0.12))
                        .overlay(Rectangle().strokeBorder(DS.Palette.accent, style: StrokeStyle(lineWidth: 1.5 / scale, dash: [5 / scale, 3 / scale])))
                        .frame(width: CGFloat(f.width), height: CGFloat(f.height))
                        .offset(x: CGFloat(f.x), y: CGFloat(f.y))
                        .allowsHitTesting(false)
                }
            }
            if let marquee {
                Rectangle()
                    .fill(DS.Palette.accent.opacity(0.10))
                    .overlay(Rectangle().strokeBorder(DS.Palette.accent, lineWidth: 1 / scale))
                    .frame(width: CGFloat(marquee.width), height: CGFloat(marquee.height))
                    .offset(x: CGFloat(marquee.x), y: CGFloat(marquee.y))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: page.width, height: page.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
        .contextMenu { arrangeMenu }
    }

    /// Căn lề, phân bố, nhóm cho vùng chọn hiện tại (D7); mục không dùng được thì mờ, `Text` nêu lý do ở menu chính.
    @ViewBuilder private var arrangeMenu: some View {
        Menu("Căn lề") {
            ForEach(AlignCommand.allCases, id: \.self) { command in
                Button(command.title) { align(command) }
                    .disabled(editor.alignBlocker(command) != nil)
            }
        }
        Button("Nhóm visual") { editor.group(); onSelectionChange() }
            .disabled(editor.groupBlocker() != nil)
        Button("Bỏ nhóm") { editor.ungroup(); onSelectionChange() }
            .disabled(editor.ungroupBlocker() != nil)
        Button("Gộp vào nhóm") { editor.mergeIntoGroup(); onSelectionChange() }
            .disabled(editor.mergeBlocker() != nil)
    }

    private func align(_ command: AlignCommand) {
        editor.align(command)
        onSelectionChange()
    }

    // MARK: Khung chọn và tay nắm

    private func frame(of visual: ReportVisual) -> Frame { ghost[visual.id] ?? preview[visual.id] ?? Frame(visual) }

    /// Visual và nhóm của trang (D7): nhóm không vẽ nhưng chọn được, có khung chọn.
    private var items: [ReportVisual] { page.visuals + page.groups }

    private var selectedVisuals: [ReportVisual] {
        items.filter { editor.selection.contains($0.id) && !isHidden($0) }
    }

    @ViewBuilder private var chrome: some View {
        let selected = selectedVisuals
        let line = 1.5 / scale
        ForEach(selected) { visual in
            let f = frame(of: visual)
            Rectangle()
                .strokeBorder(DS.Palette.accent, lineWidth: line)
                .frame(width: CGFloat(f.width), height: CGFloat(f.height))
                .offset(x: CGFloat(f.x), y: CGFloat(f.y))
                .allowsHitTesting(false)
        }
        if selected.count > 1, let box = LayoutGeometry.boundingBox(selected.map(frame(of:))) {
            Rectangle()
                .strokeBorder(DS.Palette.accent.opacity(0.7), style: StrokeStyle(lineWidth: line, dash: [4 / scale, 3 / scale]))
                .frame(width: CGFloat(box.width), height: CGFloat(box.height))
                .offset(x: CGFloat(box.x), y: CGFloat(box.y))
                .allowsHitTesting(false)
        }
        if selected.count == 1, let visual = selected.first, !editor.isLockedByGroup(visual.id) {
            handles(for: visual)
        }
    }

    private func handles(for visual: ReportVisual) -> some View {
        let f = frame(of: visual)
        return ForEach(ResizeHandle.allCases, id: \.self) { handle in
            let p = Self.anchor(handle, in: f)
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(DS.Palette.accent, lineWidth: 1.5 / scale))
                .frame(width: 7 / scale, height: 7 / scale)
                .padding(4 / scale)              // vùng bấm lớn hơn nút
                .contentShape(Rectangle())
                .position(x: CGFloat(p.x), y: CGFloat(p.y))
                .gesture(resizeGesture(visual: visual, handle: handle))
        }
    }

    static func anchor(_ handle: ResizeHandle, in f: Frame) -> (x: Int, y: Int) {
        let x = handle.movesLeft ? f.x : handle.movesRight ? f.right : f.x + f.width / 2
        let y = handle.movesTop ? f.y : handle.movesBottom ? f.bottom : f.y + f.height / 2
        return (x, y)
    }

    // MARK: Cử chỉ

    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil { begin(at: value.startLocation) }
                update(to: value.location, from: value.startLocation)
            }
            .onEnded { value in
                update(to: value.location, from: value.startLocation)
                finish()
            }
    }

    private func begin(at point: CGPoint) {
        onInteract()
        let extend = NSEvent.modifierFlags.contains(.shift)
        let hit = editor.hitTarget(x: Int(point.x), y: Int(point.y), isHidden: isHidden)
        if var hit {
            var deferred: String?
            // Nhóm đang chọn (và chỉ nhóm đó): bấm vào phần tử bên trong thì kéo vẫn dời nhóm, chọn phần tử đó khi thả nếu
            // không kéo. Nhóm lồng nhau: nhóm đang chọn có thể là tổ tiên ở bất kỳ cấp nào của phần tử bấm trúng.
            if !extend, let group = editor.ancestorIDs(of: hit).first(where: { editor.selection == [$0] }) {
                deferred = hit
                hit = group
            }
            if extend {
                editor.select(hit, extend: true)
            } else if !editor.selection.contains(hit) {
                editor.select(hit)
            }
            onSelectionChange()
            if editor.selection.contains(hit) {
                drag = .move(startFrames: dragStart(), select: deferred)
            } else {
                drag = .ignored
            }
        } else {
            let base = extend ? editor.selection : []
            if !extend { editor.clearSelection(); onSelectionChange() }
            drag = .marquee(origin: point, base: base, extend: extend)
        }
    }

    /// Khung đầu của các phần tử đang chọn khi bắt đầu kéo: nhóm kéo theo khung các con để canvas dời chúng theo.
    private func dragStart() -> [(id: String, frame: Frame)] {
        let selected = items.filter { editor.selection.contains($0.id) && !isHidden($0) }
        var out = selected.map { (id: $0.id, frame: Frame($0)) }
        var seen = Set(out.map(\.id))
        // Mọi hậu duệ của nhóm đang chọn (kể cả nhóm lồng và con của nó) đi theo khi kéo.
        for group in selected where group.isGroup {
            for inner in editor.descendants(ofGroup: group.id) where seen.insert(inner.id).inserted {
                out.append((id: inner.id, frame: Frame(inner)))
            }
        }
        return out
    }

    private func update(to point: CGPoint, from start: CGPoint) {
        switch drag {
        case .move(let frames, _)?:
            let dx = Int((point.x - start.x).rounded()), dy = Int((point.y - start.y).rounded())
            // Chưa kéo đủ xa (bấm chọn) thì chưa tạo khung tạm.
            guard hypot(point.x - start.x, point.y - start.y) * scale >= 3 || !preview.isEmpty else { return }
            let movable = frames.filter { !editor.isLockedByGroup($0.id) }
            guard !movable.isEmpty else { return }
            let moved = LayoutGeometry.move(movable.map(\.frame), dx: dx, dy: dy, page: bounds, snap: snapEnabled, grid: gridSize)
            var next: [String: Frame] = [:]
            for (item, frame) in zip(movable, moved) { next[item.id] = frame }
            preview = next
        case .marquee(let origin, let base, let extend)?:
            let rect = Frame(x: Int(min(origin.x, point.x).rounded()), y: Int(min(origin.y, point.y).rounded()),
                             width: Int(abs(point.x - origin.x).rounded()), height: Int(abs(point.y - origin.y).rounded()))
            marquee = rect
            let known = Set(page.groups.map(\.id))
            // Khung chọn chỉ lấy phần tử cấp ngoài cùng: visual ngoài nhóm và nhóm không nằm trong nhóm khác.
            let top = (page.visuals + page.groups).filter { $0.parentGroup.map { !known.contains($0) } ?? true }
            let ids = LayoutGeometry.marquee(rect, visuals: top, isHidden: isHidden)
            editor.setSelection(Array(base) + ids, extend: false)
            _ = extend
            onSelectionChange()
        default:
            break
        }
    }

    private func finish() {
        if case .move(_, let deferred)? = drag {
            if !preview.isEmpty {
                editor.apply(frames: preview)
            } else if let deferred {
                editor.select(deferred)
            }
        }
        preview = [:]
        marquee = nil
        drag = nil
        onSelectionChange()
    }

    private func resizeGesture(visual: ReportVisual, handle: ResizeHandle) -> some Gesture {
        let start = Frame(visual)
        return DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                onInteract()
                let dx = Int((value.location.x - value.startLocation.x).rounded())
                let dy = Int((value.location.y - value.startLocation.y).rounded())
                ghost = [visual.id: LayoutGeometry.resize(start, handle: handle, dx: dx, dy: dy, page: bounds, snap: snapEnabled, grid: gridSize)]
            }
            .onEnded { _ in
                if !ghost.isEmpty { editor.apply(frames: ghost) }
                ghost = [:]
            }
    }
}
