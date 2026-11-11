import Foundation
import PBIXKit

extension LayoutEditor {
    /// Lý do không nhóm được vùng chọn, hoặc nil khi nhóm được (từ 2 visual cùng trang, chưa nằm trong nhóm nào).
    func groupBlocker() -> String? {
        guard let pageID = currentPageID else { return "Chưa mở trang." }
        let chosen = items(of: pageID).filter { selection.contains($0.id) }
        if chosen.count < 2 { return "Nhóm cần chọn từ 2 visual." }
        if chosen.contains(where: \.isGroup) { return "Nhóm lồng nhau chưa hỗ trợ (chưa quan sát ở Power BI Desktop)." }
        if chosen.contains(where: { $0.parentGroup != nil || isLockedByGroup($0.id) }) {
            return "Có visual đã nằm trong nhóm; bỏ nhóm trước (nhóm lồng nhau chưa hỗ trợ)."
        }
        return nil
    }

    /// Nhóm các visual đang chọn (⌘G): container nhóm mới theo đúng dạng Desktop ghi (VM-D7), các con giữ toạ độ tuyệt đối
    /// trong mô hình. Trả mã nhóm, hoặc nil khi bị chặn (lý do ở `lockedReason`).
    @discardableResult
    func group() -> String? {
        resetMessages()
        if let reason = groupBlocker() { lockedReason = reason; return nil }
        guard let pageID = currentPageID else { return nil }
        let members = visuals(of: pageID).filter { selection.contains($0.id) }
        guard members.count >= 2 else { return nil }
        let minX = members.map(\.x).min()!, minY = members.map(\.y).min()!
        let maxRight = members.map { $0.x + $0.width }.max()!, maxBottom = members.map { $0.y + $0.height }.max()!
        // Trên mọi con (Desktop: `z` lớn nhất của con + 1); tránh trùng `z` của visual khác để chọn không mơ hồ.
        var z = members.map(\.z).max()! + 1
        let taken = Set(items(of: pageID).map(\.z))
        while taken.contains(z) { z += 1 }
        let id = reserveVisualID()
        let name = PBIRGroupPatch.nextDisplayName(avoiding: Set(groups(of: pageID).compactMap(\.groupDisplayName)))
        guard let json = try? PBIRGroupPatch.groupJSON(name: id, displayName: name, x: minX, y: minY,
                                                       width: maxRight - minX, height: maxBottom - minY, z: z),
              let raw = try? JSONValue.parse(json) else {
            lockedReason = "Không dựng được nhóm."
            return nil
        }
        let group = ReportVisual(id: id, type: ReportVisual.groupType, x: minX, y: minY, z: z, width: maxRight - minX,
                                 height: maxBottom - minY, raw: raw)
        let memberIDs = Set(members.map(\.id))
        let changed = commit(pageID: pageID) { edit in
            edit.groups.append(group)
            edit.added[id] = json
            for index in edit.visuals.indices where memberIDs.contains(edit.visuals[index].id) { edit.visuals[index].parentGroup = id }
        }
        guard changed else { return nil }
        registerCreatedVisuals([id], page: pageID)
        setSelection([id], extend: false)
        return id
    }

    /// Lý do không bỏ nhóm được, hoặc nil: vùng chọn có nhóm, hoặc có visual con của một nhóm.
    func ungroupBlocker() -> String? {
        guard let pageID = currentPageID else { return "Chưa mở trang." }
        return groupsToUngroup(pageID).isEmpty ? "Chưa chọn nhóm." : nil
    }

    private func groupsToUngroup(_ pageID: String) -> Set<String> {
        let known = Set(groups(of: pageID).map(\.id))
        var ids = Set<String>()
        for item in items(of: pageID) where selection.contains(item.id) {
            if item.isGroup { ids.insert(item.id) } else if let parent = item.parentGroup, known.contains(parent) { ids.insert(parent) }
        }
        return ids
    }

    /// Bỏ nhóm (⇧⌘G): các con về trang (toạ độ tuyệt đối), nhóm bị xoá. Trả mã các con, được chọn.
    @discardableResult
    func ungroup() -> [String] {
        resetMessages()
        guard let pageID = currentPageID, let base = basePage(pageID) else { return [] }
        let targets = groupsToUngroup(pageID).filter { !isLockedByGroup($0) }
        guard !targets.isEmpty else { lockedReason = "Chưa chọn nhóm."; return [] }
        let baselineGroups = Set(base.groups.map(\.id))
        let freed = visuals(of: pageID).filter { $0.parentGroup.map(targets.contains) ?? false }.map(\.id)
        let changed = commit(pageID: pageID) { edit in
            edit.groups.removeAll { targets.contains($0.id) }
            for index in edit.visuals.indices where edit.visuals[index].parentGroup.map(targets.contains) ?? false {
                edit.visuals[index].parentGroup = nil
            }
            for id in targets {
                if edit.added[id] != nil { edit.added[id] = nil } else if baselineGroups.contains(id) { edit.deleted.insert(id) }
            }
        }
        guard changed else { return [] }
        setSelection(freed, extend: false)
        return freed
    }

    /// Phần tử bấm trúng tại (`x`, `y`) trên trang: bấm vào visual trong nhóm thì chọn nhóm trước; khi nhóm (hoặc một con)
    /// đã được chọn thì bấm lần nữa chọn con (như Desktop). Phần tử đè lên nhóm có `z` cao hơn vẫn được chọn trước.
    func hitTarget(x: Int, y: Int, isHidden: (ReportVisual) -> Bool) -> String? {
        guard let pageID = currentPageID else { return nil }
        let all = items(of: pageID)
        guard let hit = LayoutGeometry.hit(x: x, y: y, in: all, isHidden: isHidden), let hitItem = all.first(where: { $0.id == hit }) else { return nil }
        let known = Set(groups(of: pageID).map(\.id))
        func focused(_ group: String) -> Bool {
            selection.contains(group) || selection.contains { id in visuals(of: pageID).first { $0.id == id }?.parentGroup == group }
        }
        if hitItem.isGroup {
            if focused(hit), let child = LayoutGeometry.hit(x: x, y: y, in: children(ofGroup: hit, page: pageID), isHidden: isHidden) { return child }
            return hit
        }
        if let parent = hitItem.parentGroup, known.contains(parent) { return focused(parent) ? hit : parent }
        return hit
    }
}
