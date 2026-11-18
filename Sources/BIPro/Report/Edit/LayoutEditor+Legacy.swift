import Foundation
import PBIXKit

/// Container của `Report/Layout` đọc một lần khi cần (D7).
private final class LegacyContainerCache {
    private let archive: ZipArchive
    private var loaded: [String: [LegacyLayoutPatch.Container]]?

    init(_ archive: ZipArchive) { self.archive = archive }

    private func all() -> [String: [LegacyLayoutPatch.Container]] {
        if let loaded { return loaded }
        let result = (try? archive.read("Report/Layout")).flatMap { try? LegacyLayoutPatch.containers(in: $0) } ?? [:]
        loaded = result
        return result
    }

    func json(page: String, id: String) -> Data? { all()[page]?.first { $0.name == id }?.json }
}

extension LayoutEditor {
    static let legacyLayoutPath = "Report/Layout"

    /// Editor cho báo cáo định dạng cũ (D7): chỉ bố cục. `sourceJSON` là byte của container trong `Report/Layout`.
    static func readingLegacy(archive: ZipArchive, report: ReportDefinition) -> LayoutEditor {
        let cache = LegacyContainerCache(archive)
        // Chỉ part `Settings` (tuỳ chọn của file, T033): báo cáo cũ không có part PBIR nào để dựng lại.
        return LayoutEditor(report: report, sourceJSON: { page, id in cache.json(page: page, id: id) },
                            openedParts: { prefix in
                                guard prefix == FileSettings.path, let entry = archive.entry(prefix), let data = try? archive.read(entry) else { return [] }
                                return [(prefix, data)]
                            }, isLegacy: true)
    }

    /// Thay đổi cần ghi vào `Report/Layout` của `archive` (file trên đĩa): vị trí đổi, container thêm và xoá, chỉ so với file
    /// nên lưu lần hai không ghi gì. Phần ngoài chỗ sửa nguyên byte (`LegacyLayoutPatch`).
    func makeLegacyChanges(archive: ZipArchive) throws -> PBIXChanges {
        var changes = PBIXChanges()
        let onDisk = try archive.read(Self.legacyLayoutPath)
        let current = try LegacyLayoutPatch.containers(in: onDisk)
        var edits: [LegacyLayoutPatch.SectionEdit] = []
        for pageID in structure.order {
            guard let edit = edited[pageID], let base = basePage(pageID) else { continue }
            let inFile = Dictionary((current[pageID] ?? []).map { ($0.name, $0.json) }, uniquingKeysWith: { first, _ in first })
            var section = LegacyLayoutPatch.SectionEdit(section: pageID)
            func differs(_ a: Double, _ b: Double) -> Bool { abs(a - b) > 1e-6 }
            for visual in edit.visuals where !isLockedByGroup(visual.id) {
                let target = LegacyLayoutPatch.Position(x: visual.x, y: visual.y, width: visual.width, height: visual.height)
                if let json = inFile[visual.id] {
                    let now = try LegacyLayoutPatch.position(of: json)
                    if differs(now.x, target.x) || differs(now.y, target.y) || differs(now.width, target.width) || differs(now.height, target.height) {
                        section.set[visual.id] = target
                    }
                } else if let data = edit.added[visual.id] {
                    section.add.append(try LegacyLayoutPatch.settingPosition(in: data, to: target))
                }
            }
            let present = Set(edit.visuals.map(\.id))
            for id in Set(base.visuals.map(\.id)).union(createdIDs[pageID] ?? []) where !present.contains(id) && inFile[id] != nil {
                section.remove.insert(id)
            }
            if !section.set.isEmpty || !section.add.isEmpty || !section.remove.isEmpty { edits.append(section) }
        }
        guard !edits.isEmpty else { return changes }
        let patched = try LegacyLayoutPatch.apply(edits, to: onDisk)
        if patched != onDisk { changes.reportParts[Self.legacyLayoutPath] = patched }
        return changes
    }
}
