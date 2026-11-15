import CoreGraphics
import Foundation

/// Phase E (T034): vị trí thẻ bảng và thu phóng do người dùng sửa ở Model view, theo từng tab bố cục. Chung ngăn xếp hoàn tác
/// với báo cáo và mô hình; lúc lưu ghép vào `DiagramLayout` (`DiagramLayoutPatch`).
struct DiagramEdits: Equatable {
    /// Tab → bảng → vị trí mới.
    var positions: [String: [String: CGPoint]] = [:]
    /// Tab → bảng → vị trí lúc mở file (hoặc lúc lưu gần nhất ngoài phiên): để kéo về chỗ cũ hoặc hoàn tác sau khi đã lưu.
    var baseline: [String: [String: CGPoint]] = [:]
    /// Tab → phần trăm thu phóng.
    var zoom: [String: Double] = [:]
    /// Tab → thu phóng lúc mở file: để hoàn tác sau khi đã lưu ghi lại được thu phóng cũ.
    var zoomBaseline: [String: Double] = [:]

    /// Một tab bố cục sau khi sửa: `source` là chỉ số tab trong file gốc (nil = tab mới thêm).
    struct Tab: Equatable {
        var name: String
        var source: Int?
    }

    /// Danh sách tab sau khi thêm, đổi tên hoặc xoá (nil = như trong file). Tab đầu ("All tables") cố định tên và không xoá được,
    /// như Desktop.
    var entries: [Tab]?
    /// Tên tab theo thứ tự (nil = như trong file).
    var tabs: [String]? { entries?.map(\.name) }
    /// Tab → bảng do người dùng đặt vào tab (nút mới, chưa có trong file): không có vị trí gốc để "kéo về".
    var added: [String: Set<String>] = [:]
    /// Tab → bảng có nút trong file nhưng đã gỡ khỏi tab ("Remove from diagram"): lưu thì bỏ nút đó, bảng vẫn ở trong mô hình.
    var removed: [String: Set<String>] = [:]

    var isEmpty: Bool { positions.isEmpty && zoom.isEmpty && entries == nil && removed.isEmpty }

    private func current(_ existing: [String]) -> [Tab] {
        entries ?? existing.enumerated().map { Tab(name: $0.element, source: $0.offset) }
    }

    /// Lưu danh sách tab; trùng danh sách trong file thì coi như chưa sửa.
    private mutating func store(_ list: [Tab], existing: [String]) {
        entries = list == existing.enumerated().map({ Tab(name: $0.element, source: $0.offset) }) ? nil : list
    }

    /// Thêm tab trống tên "Layout N" (N nhỏ nhất chưa dùng, như Desktop); trả tên tab mới. `existing`: tên các tab trong file.
    @discardableResult
    mutating func addTab(existing: [String]) -> String {
        var list = current(existing)
        var n = 1
        while list.contains(where: { $0.name.caseInsensitiveCompare("Layout \(n)") == .orderedSame }) { n += 1 }
        let name = "Layout \(n)"
        list.append(Tab(name: name, source: nil))
        store(list, existing: existing)
        return name
    }

    /// Đổi tên tab. Trả lý do bị từ chối hoặc nil. Mọi mục sửa của tab chuyển theo tên mới.
    mutating func renameTab(from old: String, to proposed: String, existing: [String]) -> String? {
        let new = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = current(existing)
        guard let index = list.firstIndex(where: { $0.name == old }) else { return "Không có bố cục “\(old)”." }
        if index == 0 { return "Bố cục “\(old)” không đổi tên được." }
        if new.isEmpty { return "Tên bố cục không được để trống." }
        if new == old { return nil }
        if list.enumerated().contains(where: { $0.offset != index && $0.element.name.caseInsensitiveCompare(new) == .orderedSame }) {
            return "Đã có bố cục tên “\(new)”."
        }
        list[index].name = new
        store(list, existing: existing)
        func rekey<V>(_ dict: inout [String: V]) { if let value = dict.removeValue(forKey: old) { dict[new] = value } }
        rekey(&positions); rekey(&baseline); rekey(&zoom); rekey(&zoomBaseline); rekey(&added); rekey(&removed)
        return nil
    }

    /// Xoá tab (không xoá bảng khỏi mô hình). Trả lý do bị từ chối hoặc nil. Tab đầu ("All tables") không xoá được.
    mutating func deleteTab(_ name: String, existing: [String]) -> String? {
        var list = current(existing)
        guard let index = list.firstIndex(where: { $0.name == name }) else { return "Không có bố cục “\(name)”." }
        if index == 0 { return "Bố cục “\(name)” không xoá được." }
        list.remove(at: index)
        store(list, existing: existing)
        positions[name] = nil; baseline[name] = nil; zoom[name] = nil; zoomBaseline[name] = nil; added[name] = nil; removed[name] = nil
        return nil
    }

    /// Gỡ thẻ bảng khỏi tab (bảng vẫn còn trong mô hình). `inFile`: tab có nút của bảng này trong file.
    mutating func removeTable(_ table: String, from diagram: String, inFile: Bool) {
        positions[diagram]?[table] = nil
        baseline[diagram]?[table] = nil
        if positions[diagram]?.isEmpty == true { positions[diagram] = nil }
        if baseline[diagram]?.isEmpty == true { baseline[diagram] = nil }
        added[diagram]?.remove(table)
        if added[diagram]?.isEmpty == true { added[diagram] = nil }
        if inFile { removed[diagram, default: []].insert(table) }
    }

    /// Đặt bảng vào tab ở `point` (nút mới, cỡ mặc định). Khác `move`: không có vị trí gốc.
    mutating func place(table: String, in diagram: String, at point: CGPoint) {
        positions[diagram, default: [:]][table] = point
        if removed[diagram]?.contains(table) == true {
            // Nút còn trong file: đặt lại thì chỉ bỏ dấu gỡ và dời nút về `point`.
            removed[diagram]?.remove(table)
            if removed[diagram]?.isEmpty == true { removed[diagram] = nil }
        } else {
            added[diagram, default: Set<String>()].insert(table)
        }
    }

    /// Đặt thẻ ở `point`. `original` là vị trí ngay trước lần kéo; chỉ lần đầu của thẻ được nhớ làm vị trí gốc. Kéo về đúng vị
    /// trí gốc thì bỏ mục sửa.
    mutating func move(table: String, in diagram: String, to point: CGPoint, original: CGPoint) {
        if added[diagram]?.contains(table) == true { positions[diagram, default: [:]][table] = point; return }
        if baseline[diagram]?[table] == nil { baseline[diagram, default: [:]][table] = original }
        if baseline[diagram]?[table] == point {
            positions[diagram]?[table] = nil
            baseline[diagram]?[table] = nil
            if positions[diagram]?.isEmpty == true { positions[diagram] = nil }
            if baseline[diagram]?.isEmpty == true { baseline[diagram] = nil }
        } else {
            positions[diagram, default: [:]][table] = point
        }
    }

    /// Đặt thu phóng của tab; chỉ lần đầu nhớ `original`. Về đúng thu phóng gốc thì bỏ mục sửa.
    mutating func setZoom(_ percent: Double, in diagram: String, original: Double) {
        if zoomBaseline[diagram] == nil { zoomBaseline[diagram] = original }
        if zoomBaseline[diagram] == percent {
            zoom[diagram] = nil
            zoomBaseline[diagram] = nil
        } else {
            zoom[diagram] = percent
        }
    }

    /// Bỏ mọi vị trí sửa của một tab (về vị trí trong file).
    mutating func resetPositions(in diagram: String) {
        let keep = added[diagram] ?? []
        positions[diagram] = positions[diagram]?.filter { keep.contains($0.key) }
        if positions[diagram]?.isEmpty == true { positions[diagram] = nil }
        baseline[diagram] = nil
    }
}
