// VM-D12: tài nguyên (bản đồ hình, ảnh) chỉ trang đã xoá còn dùng bị dọn khỏi file như Power BI Desktop.
// Quan sát: `docs/phase-d-evidence/vm-d12/QUAN-SAT.md` mục 2; hợp đồng: `specs/005-d5-quan-ly-trang/contracts/page-save.md` (bổ sung VM-D12).
import Foundation
import PBIXKit

extension LayoutEditor {
    /// Thêm vào `changes` việc bỏ (hoặc đưa lại) mục tài nguyên bản đồ hình / ảnh và file của nó trong `Report/StaticResources/`.
    ///
    /// Mục tài nguyên (loại `ShapeMap`, `Image`) mà các trang của file lúc mở nhắc tới (`"ItemName":"<tên>"`) bị bỏ khi mọi trang
    /// nhắc tới nó đều đã xoá và không còn phần nào còn lại của báo cáo nhắc tới. Còn trang nào nhắc tới thì mục giữ (và được
    /// đưa lại nếu một lần lưu trước của phiên đã bỏ nó rồi người dùng hoàn tác trang xoá). Chủ đề và mục không trang nào nhắc
    /// tới không bị đụng. Tính lại từ đầu mỗi lần lưu nên lưu lần hai không ghi gì.
    func addResourceChanges(to changes: inout PBIXChanges, archive: ZipArchive) throws {
        if isLegacy { return }
        guard let opened = openedParts(Self.reportJSONPath).first(where: { $0.path == Self.reportJSONPath })?.data else { return }
        let cleanable = PBIRResourcePatch.items(in: opened).filter(\.isCleanable)
        guard !cleanable.isEmpty, let disk = current(Self.reportJSONPath, in: changes, archive: archive) else { return }
        let order = Set(structure.order)
        let gone = Set(baseline.pages.map(\.id)).subtracting(order)
        let onDisk = Set(PBIRResourcePatch.items(in: disk).map(\.key))
        // Không có gì để dọn hay đưa lại: không trang nào bị xoá và file trên đĩa còn đủ mục lúc mở.
        guard !gone.isEmpty || cleanable.contains(where: { !onDisk.contains($0.key) }) else { return }

        // Trang của file lúc mở nhắc tới mục nào.
        var referencedBy: [String: Set<String>] = [:]   // khoá mục → mã trang
        for page in baseline.pages {
            var text = ""
            for part in openedParts("\(Self.pagesFolder)\(page.id)/") { text += String(decoding: part.data, as: UTF8.self) }
            for item in cleanable where text.contains(item.reference) { referencedBy[item.key, default: []].insert(page.id) }
        }
        // Mục chỉ các trang đã xoá nhắc tới; rồi loại mục mà phần còn lại của báo cáo vẫn nhắc.
        var candidates = cleanable.filter { item in
            guard let pages = referencedBy[item.key] else { return false }
            return pages.isDisjoint(with: order)
        }
        if !candidates.isEmpty {
            var paths = Set(archive.entries.map(\.path)).union(changes.addedParts.keys)
            paths = paths.filter { $0.hasPrefix("Report/definition/") && $0.hasSuffix(".json") }
            for path in paths.sorted() where !candidates.isEmpty {
                guard let data = current(path, in: changes, archive: archive) else { continue }
                let text = String(decoding: data, as: UTF8.self)
                candidates.removeAll { text.contains($0.reference) }
            }
        }
        let orphans = Set(candidates.map(\.key))

        let patched = try PBIRResourcePatch.settingItems(removing: orphans, baseline: opened, in: disk)
        if patched != disk { store(patched, at: Self.reportJSONPath, changes: &changes, archive: archive) }

        for item in cleanable where referencedBy[item.key] != nil {
            let path = item.partPath
            if orphans.contains(item.key) {
                if archive.entry(path) != nil {
                    changes.reportParts[path] = nil
                    changes.removedParts.insert(path)
                } else {
                    changes.addedParts[path] = nil
                }
            } else if archive.entry(path) == nil, !changes.removedParts.contains(path), changes.addedParts[path] == nil,
                      let data = openedParts(path).first(where: { $0.path == path })?.data {
                changes.addedParts[path] = data
            }
        }
    }
}
