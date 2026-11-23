import Foundation
import PBIXKit

/// Thứ tự lớp (z) của visual và nhóm: Bring forward / Bring to front / Send backward / Send to back (tab Format ▸ Arrange).
enum ZOrderCommand: CaseIterable, Hashable, Sendable {
    case forward, front, backward, back

    @MainActor var title: String {
        switch self {
        case .forward: bi("Đưa lên trước", "Bring forward")
        case .front: bi("Đưa lên trên cùng", "Bring to front")
        case .backward: bi("Đưa xuống sau", "Send backward")
        case .back: bi("Đưa xuống dưới cùng", "Send to back")
        }
    }

    var systemImage: String {
        switch self {
        case .forward: "square.2.layers.3d.top.filled"
        case .front: "square.3.layers.3d.top.filled"
        case .backward: "square.2.layers.3d.bottom.filled"
        case .back: "square.3.layers.3d.bottom.filled"
        }
    }

    /// Nhóm lệnh dùng chung một nút trên Ribbon.
    var isForward: Bool { self == .forward || self == .front }
}

extension LayoutEditor {
    /// Thứ tự mới của `ids` (đã sắp theo z tăng dần) sau khi áp `command` cho các phần tử `moving`. Thuần hàm, có test.
    static func reordered(_ ids: [String], moving: Set<String>, _ command: ZOrderCommand) -> [String] {
        var order = ids
        switch command {
        case .front:
            order = order.filter { !moving.contains($0) } + order.filter { moving.contains($0) }
        case .back:
            order = order.filter { moving.contains($0) } + order.filter { !moving.contains($0) }
        case .forward:
            // Từ trên xuống: mỗi phần tử đang chọn đổi chỗ với phần tử không chọn ngay phía trên nó.
            var i = order.count - 2
            while i >= 0 {
                if moving.contains(order[i]) && !moving.contains(order[i + 1]) { order.swapAt(i, i + 1) }
                i -= 1
            }
        case .backward:
            var i = 1
            while i < order.count {
                if moving.contains(order[i]) && !moving.contains(order[i - 1]) { order.swapAt(i, i - 1) }
                i += 1
            }
        }
        return order
    }

    /// Lý do `command` chưa dùng được, hoặc nil.
    func zOrderBlocker(_ command: ZOrderCommand) -> String? {
        guard let pageID = currentPageID else { return "Chưa mở trang." }
        if selection.isEmpty { return "Chọn một visual để đổi thứ tự lớp." }
        let chosen = items(of: pageID).filter { selection.contains($0.id) }
        if chosen.contains(where: { isLockedByGroup($0.id) }) { return Self.groupLockedMessage }
        if Set(chosen.map { $0.parentGroup ?? "" }).count > 1 { return "Chỉ đổi lớp được các visual cùng cấp (cùng nhóm hoặc cùng ngoài nhóm)." }
        let level = items(of: pageID).filter { ($0.parentGroup ?? "") == (chosen.first?.parentGroup ?? "") }
        let order = Self.reordered(level.map(\.id), moving: selection, command)
        return order == level.map(\.id) ? "Visual đã ở \(command.isForward ? "trên cùng" : "dưới cùng")." : nil
    }

    /// Đổi thứ tự lớp của vùng chọn trong cùng cấp: đúng một bước hoàn tác, giữ nguyên tập giá trị z (chỉ hoán vị).
    @discardableResult
    func reorder(_ command: ZOrderCommand) -> Bool {
        resetMessages()
        guard let pageID = currentPageID else { return false }
        if let reason = zOrderBlocker(command) {
            lockedReason = reason
            return false
        }
        let chosen = items(of: pageID).filter { selection.contains($0.id) }
        let parent = chosen.first?.parentGroup ?? ""
        let level = items(of: pageID).filter { ($0.parentGroup ?? "") == parent }
        let newOrder = Self.reordered(level.map(\.id), moving: selection, command)
        // Giữ tập z cũ, tăng chặt để không còn hai phần tử trùng z.
        var zs: [Double] = []
        for z in level.map(\.z).sorted() { zs.append(zs.last.map { max(z, $0 + 1) } ?? z) }
        var newZ: [String: Double] = [:]
        for (id, z) in zip(newOrder, zs) { newZ[id] = z }
        return commit(pageID: pageID) { edit in
            for i in edit.visuals.indices { if let z = newZ[edit.visuals[i].id] { edit.visuals[i].z = z } }
            for i in edit.groups.indices { if let z = newZ[edit.groups[i].id] { edit.groups[i].z = z } }
        }
    }
}
