import Foundation
import PBIXKit

extension LayoutEditor {
    /// Lý do không nhóm được vùng chọn, hoặc nil khi nhóm được: từ 2 phần tử cùng trang, đều ở ngoài nhóm. Phần tử có thể
    /// là nhóm: Desktop cho nhóm lồng nhau (VM-D8 mục 1).
    func groupBlocker() -> String? {
        guard let pageID = currentPageID else { return "Chưa mở trang." }
        let chosen = items(of: pageID).filter { selection.contains($0.id) }
        if chosen.count < 2 { return "Nhóm cần chọn từ 2 visual." }
        if chosen.contains(where: { isLockedByGroup($0.id) }) { return Self.groupLockedMessage }
        if chosen.contains(where: { $0.parentGroup != nil }) {
            return "Chỉ nhóm được các phần tử cùng cấp ở ngoài nhóm; chọn cả nhóm, hoặc bỏ nhóm trước."
        }
        return nil
    }

    /// Nhóm các phần tử đang chọn (⌘G): container nhóm mới theo đúng dạng Desktop ghi (VM-D7), các thành viên giữ toạ độ
    /// tuyệt đối trong mô hình. Thành viên là nhóm thì thành nhóm lồng bên trong (VM-D8). Trả mã nhóm, hoặc nil khi bị chặn
    /// (lý do ở `lockedReason`).
    @discardableResult
    func group() -> String? {
        resetMessages()
        if let reason = groupBlocker() { lockedReason = reason; return nil }
        guard let pageID = currentPageID else { return nil }
        let members = items(of: pageID).filter { selection.contains($0.id) }
        guard members.count >= 2 else { return nil }
        let minX = members.map(\.x).min()!, minY = members.map(\.y).min()!
        let maxRight = members.map { $0.x + $0.width }.max()!, maxBottom = members.map { $0.y + $0.height }.max()!
        // Trên mọi thành viên (Desktop: `z` lớn nhất + 1); tránh trùng `z` của phần tử khác để chọn không mơ hồ.
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
            for index in edit.visuals.indices where memberIDs.contains(edit.visuals[index].id) { edit.visuals[index].parentGroup = id }
            for index in edit.groups.indices where memberIDs.contains(edit.groups[index].id) { edit.groups[index].parentGroup = id }
            edit.groups.append(group)
            edit.added[id] = json
        }
        guard changed else { return nil }
        registerCreatedVisuals([id], page: pageID)
        setSelection([id], extend: false)
        return id
    }

    // MARK: Merge (VM-D8 mục 1)

    /// Nhóm đích và các visual sẽ gộp vào: vùng chọn có đúng một nhóm ở ngoài nhóm khác và ít nhất một visual ngoài nhóm.
    private func mergePlan(_ pageID: String) -> (group: ReportVisual, visuals: [ReportVisual])? {
        let chosen = items(of: pageID).filter { selection.contains($0.id) }
        let groups = chosen.filter(\.isGroup), others = chosen.filter { !$0.isGroup }
        guard groups.count == 1, let group = groups.first, group.parentGroup == nil, !others.isEmpty,
              others.allSatisfy({ $0.parentGroup == nil }) else { return nil }
        return (group, others)
    }

    /// Lý do không gộp được vùng chọn vào nhóm, hoặc nil.
    func mergeBlocker() -> String? {
        guard let pageID = currentPageID else { return "Chưa mở trang." }
        if selection.contains(where: isLockedByGroup) { return Self.groupLockedMessage }
        return mergePlan(pageID) == nil ? "Gộp vào nhóm cần chọn đúng một nhóm và ít nhất một visual ở ngoài nhóm." : nil
    }

    /// Gộp các visual đang chọn vào nhóm đang chọn (lệnh Merge của Desktop): nhóm giữ mã và tên, khung nhóm thành hợp của
    /// khung cũ và các visual mới; toạ độ tuyệt đối của mọi con không đổi (toạ độ tương đối trong file đổi theo gốc mới).
    /// Trả mã nhóm, hoặc nil khi bị chặn.
    @discardableResult
    func mergeIntoGroup() -> String? {
        resetMessages()
        if let reason = mergeBlocker() { lockedReason = reason; return nil }
        guard let pageID = currentPageID, let plan = mergePlan(pageID) else { return nil }
        let all = [plan.group] + plan.visuals
        let minX = all.map(\.x).min()!, minY = all.map(\.y).min()!
        let maxRight = all.map { $0.x + $0.width }.max()!, maxBottom = all.map { $0.y + $0.height }.max()!
        let joining = Set(plan.visuals.map(\.id)), id = plan.group.id
        let changed = commit(pageID: pageID) { edit in
            for index in edit.visuals.indices where joining.contains(edit.visuals[index].id) { edit.visuals[index].parentGroup = id }
            guard let index = edit.groups.firstIndex(where: { $0.id == id }) else { return }
            edit.groups[index].x = minX
            edit.groups[index].y = minY
            edit.groups[index].width = maxRight - minX
            edit.groups[index].height = maxBottom - minY
        }
        guard changed else { return nil }
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

    /// Bỏ nhóm (⇧⌘G): nhóm bị xoá, các thành viên trực tiếp (visual và nhóm lồng) lên cấp của nhóm đó: về trang, hoặc vào
    /// nhóm ngoài nếu nhóm bị bỏ nằm trong nhóm khác. Nhóm lồng bên trong giữ nguyên con của nó (VM-D8). Trả mã các thành
    /// viên được thả, được chọn.
    @discardableResult
    func ungroup() -> [String] {
        resetMessages()
        guard let pageID = currentPageID, let base = basePage(pageID) else { return [] }
        let targets = groupsToUngroup(pageID).filter { !isLockedByGroup($0) }
        guard !targets.isEmpty else { lockedReason = "Chưa chọn nhóm."; return [] }
        let baselineGroups = Set(base.groups.map(\.id))
        let freed = items(of: pageID).filter { ($0.parentGroup.map(targets.contains) ?? false) && !targets.contains($0.id) }.map(\.id)
        let changed = commit(pageID: pageID) { edit in
            // Cấp mới của thành viên: nhóm tổ tiên gần nhất không bị bỏ.
            let before = edit.groups
            func survivingParent(_ item: ReportVisual) -> String? {
                Self.ancestorIDs(of: item, in: before).first { !targets.contains($0) }
            }
            for index in edit.visuals.indices where edit.visuals[index].parentGroup.map(targets.contains) ?? false {
                edit.visuals[index].parentGroup = survivingParent(edit.visuals[index])
            }
            for index in edit.groups.indices where edit.groups[index].parentGroup.map(targets.contains) ?? false {
                edit.groups[index].parentGroup = survivingParent(edit.groups[index])
            }
            edit.groups.removeAll { targets.contains($0.id) }
            for id in targets {
                if edit.added[id] != nil { edit.added[id] = nil } else if baselineGroups.contains(id) { edit.deleted.insert(id) }
            }
        }
        guard changed else { return [] }
        setSelection(freed, extend: false)
        return freed
    }

    /// Phần tử bấm trúng tại (`x`, `y`) trên trang: bấm vào visual trong nhóm thì chọn nhóm ngoài cùng trước; mỗi lần bấm
    /// tiếp khi nhóm (hoặc một phần tử bên trong) đang được chọn thì vào sâu một cấp (như Desktop). Phần tử đè lên nhóm có
    /// `z` cao hơn vẫn được chọn trước.
    func hitTarget(x: Int, y: Int, isHidden: (ReportVisual) -> Bool) -> String? {
        guard let pageID = currentPageID else { return nil }
        let all = items(of: pageID)
        guard let hit = LayoutGeometry.hit(x: x, y: y, in: all, isHidden: isHidden), let hitItem = all.first(where: { $0.id == hit }) else { return nil }
        let groups = groups(of: pageID)
        /// Nhóm đang được chọn, hoặc có phần tử bên trong đang được chọn.
        func focused(_ group: String) -> Bool {
            selection.contains(group) || !selection.isDisjoint(with: Self.descendantIDs(of: group, in: all))
        }
        func resolve(_ group: String) -> String {
            guard focused(group), let inner = LayoutGeometry.hit(x: x, y: y, in: all.filter { $0.parentGroup == group }, isHidden: isHidden) else { return group }
            return all.first { $0.id == inner }?.isGroup == true ? resolve(inner) : inner
        }
        let top = Self.ancestorIDs(of: hitItem, in: groups).last ?? hit
        return all.first { $0.id == top }?.isGroup == true ? resolve(top) : hit
    }
}
