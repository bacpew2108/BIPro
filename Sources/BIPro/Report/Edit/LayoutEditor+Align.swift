import Foundation
import PBIXKit

extension LayoutEditor {
    /// Lý do `command` không dùng được với vùng chọn hiện tại, hoặc nil khi dùng được.
    func alignBlocker(_ command: AlignCommand) -> String? {
        guard let pageID = currentPageID else { return "Chưa mở trang." }
        let ids = alignable(pageID)
        if selection.count < command.minimumCount {
            return command.minimumCount == 3 ? "Phân bố cần chọn từ 3 visual." : "Căn lề cần chọn từ 2 visual."
        }
        if ids.count < selection.count { return mixedLevelsReason(pageID) }
        return nil
    }

    /// Căn lề hoặc phân bố vùng chọn: đúng một bước hoàn tác, không đổi gì thì không tạo bước.
    @discardableResult
    func align(_ command: AlignCommand) -> Bool {
        resetMessages()
        guard let pageID = currentPageID, let pageBounds = basePage(pageID).map(PageBounds.init) else { return false }
        if let reason = alignBlocker(command) {
            lockedReason = reason
            return false
        }
        let chosen = items(of: pageID).filter { alignable(pageID).contains($0.id) }
        // Con của một nhóm căn trong khung nhóm (toạ độ tương đối so với nhóm), còn lại căn trong trang.
        let parent = chosen.first?.parentGroup.flatMap { id in groups(of: pageID).first { $0.id == id } }
        let origin = (x: Int(parent?.x.rounded(.up) ?? 0), y: Int(parent?.y.rounded(.up) ?? 0))
        let bounds = parent.map { PageBounds(width: Int(($0.x + $0.width).rounded(.down)) - origin.x, height: Int(($0.y + $0.height).rounded(.down)) - origin.y) } ?? pageBounds
        let shifted = chosen.map { item -> Frame in var f = Frame(item); f.x -= origin.x; f.y -= origin.y; return f }
        let target = LayoutGeometry.align(command, frames: shifted, page: bounds).map { f -> Frame in var g = f; g.x += origin.x; g.y += origin.y; return g }
        var frames: [String: Frame] = [:]
        for (item, frame) in zip(chosen, target) where frame != Frame(item) { frames[item.id] = frame }
        guard !frames.isEmpty else { return false }
        apply(frames: frames)
        return true
    }

    /// Phần tử của vùng chọn căn được: không bị khoá, cùng cấp (cùng nhóm cha hoặc cùng ở ngoài nhóm).
    private func alignable(_ pageID: String) -> Set<String> {
        let chosen = items(of: pageID).filter { selection.contains($0.id) && !isLockedByGroup($0.id) }
        let parents = Set(chosen.map { $0.parentGroup ?? "" })
        return parents.count == 1 ? Set(chosen.map(\.id)) : []
    }

    private func mixedLevelsReason(_ pageID: String) -> String {
        let chosen = items(of: pageID).filter { selection.contains($0.id) }
        if chosen.contains(where: { isLockedByGroup($0.id) }) { return Self.groupLockedMessage }
        return "Chỉ căn được các visual cùng cấp (cùng trong một nhóm hoặc cùng ngoài nhóm)."
    }
}
