import DAXEngine
import Foundation

enum SlicerCheckState: Hashable, Sendable {
    case on
    case off
    case mixed
}

enum SlicerTree {
    /// Tìm nút tương ứng với `path` trong `roots`.
    static func findNode(path: [Value], in roots: [SlicerNode]) -> SlicerNode? {
        guard let first = path.first else { return nil }
        guard let root = roots.first(where: { $0.value == first }) else { return nil }
        var current = root
        for val in path.dropFirst() {
            guard let child = current.children.first(where: { $0.value == val }) else {
                return nil
            }
            current = child
        }
        return current
    }

    /// Lấy tất cả đường dẫn lá (leaf paths) dưới `node` với tiền tố `prefix`.
    static func allLeafPaths(node: SlicerNode, prefix: [Value]) -> [[Value]] {
        if node.children.isEmpty {
            return [prefix]
        }
        var result: [[Value]] = []
        for child in node.children {
            result.append(contentsOf: allLeafPaths(node: child, prefix: prefix + [child.value]))
        }
        return result
    }

    /// Trạng thái chọn của một nút (`.on`, `.off`, `.mixed`):
    /// - `.on`: toàn bộ các lá thuộc nhánh đều được chọn;
    /// - `.off`: không có lá nào thuộc nhánh được chọn;
    /// - `.mixed`: một số lá được chọn, một số lá không.
    static func state(
        of path: [Value],
        in selection: SlicerSelection,
        roots: [SlicerNode]
    ) -> SlicerCheckState {
        guard let node = findNode(path: path, in: roots) else {
            return .off
        }
        if selection.isEmpty {
            return .off
        }

        let leaves = allLeafPaths(node: node, prefix: path)
        var coveredCount = 0
        for leaf in leaves {
            if selection.paths.contains(where: { leaf.starts(with: $0) }) {
                coveredCount += 1
            }
        }

        if coveredCount == leaves.count {
            return .on
        } else if coveredCount == 0 {
            return .off
        } else {
            return .mixed
        }
    }

    /// Chọn / bỏ chọn một nút theo Power BI:
    /// - `additive == false`: bấm một dòng thì chỉ chọn dòng đó; bấm lại chính dòng duy nhất đang chọn thì bỏ chọn;
    /// - `additive == true` (giữ ⌘ hoặc Ctrl): thêm hoặc bớt mục đó.
    static func toggle(
        selection: SlicerSelection,
        path: [Value],
        additive: Bool,
        roots: [SlicerNode]? = nil
    ) -> SlicerSelection {
        if !additive {
            if selection.paths == [path] {
                return SlicerSelection([])
            } else {
                return SlicerSelection([path])
            }
        }

        var newPaths = selection.paths

        if newPaths.contains(path) {
            newPaths.remove(path)
            return SlicerSelection(newPaths)
        }

        // Bỏ mọi con cháu của `path` vì nút cha bao hàm toàn bộ nhánh con
        newPaths = newPaths.filter { existing in
            !(existing.count > path.count && existing.starts(with: path))
        }

        // Nếu một tổ tiên của `path` đang có trong `newPaths`, gỡ tổ tiên đó và mở rộng các lá anh em
        if let ancestor = newPaths.first(where: { path.starts(with: $0) && $0 != path }) {
            newPaths.remove(ancestor)
            if let roots {
                let siblings = allLeafDescendantsExcept(ancestor: ancestor, target: path, roots: roots)
                newPaths.formUnion(siblings)
            }
        } else {
            newPaths.insert(path)
            if let roots {
                newPaths = simplifySelection(newPaths, roots: roots)
            }
        }

        return SlicerSelection(newPaths)
    }

    /// Văn bản tóm tắt lựa chọn khi slicer ở trạng thái đóng:
    /// - "All" khi chưa chọn gì (hoặc rỗng);
    /// - Tên giá trị khi chọn 1 mục;
    /// - "Nhiều lựa chọn" khi chọn từ 2 mục trở lên.
    static func summary(
        selection: SlicerSelection,
        roots: [SlicerNode]
    ) -> String {
        if selection.isEmpty {
            return "All"
        }
        if selection.paths.count == 1, let singlePath = selection.paths.first {
            guard let lastVal = singlePath.last else { return "All" }
            if case .blank = lastVal {
                return "(Trống)"
            }
            return NumberDisplay.plain(DataCell(lastVal))
        }
        return "Nhiều lựa chọn"
    }

    // MARK: - Trợ giúp thu gọn & phân rã nhánh

    private static func allLeafDescendantsExcept(
        ancestor: [Value],
        target: [Value],
        roots: [SlicerNode]
    ) -> Set<[Value]> {
        guard let node = findNode(path: ancestor, in: roots) else { return [] }
        let allLeaves = allLeafPaths(node: node, prefix: ancestor)
        let filtered = allLeaves.filter { !($0.starts(with: target)) }
        return Set(filtered)
    }

    private static func simplifySelection(_ paths: Set<[Value]>, roots: [SlicerNode]) -> Set<[Value]> {
        var current = paths
        var changed = true

        while changed {
            changed = false
            // Tìm các nhóm có chung cha mà tất cả các con đều có trong current
            for root in roots {
                if let simplified = trySimplify(node: root, prefix: [root.value], in: current) {
                    current = simplified
                    changed = true
                    break
                }
            }
        }

        return current
    }

    private static func trySimplify(
        node: SlicerNode,
        prefix: [Value],
        in paths: Set<[Value]>
    ) -> Set<[Value]>? {
        if node.children.isEmpty { return nil }

        // Thử thu gọn các con trước
        for child in node.children {
            if let nested = trySimplify(node: child, prefix: prefix + [child.value], in: paths) {
                return nested
            }
        }

        // Kiểm tra xem tất cả các con trực tiếp có trong paths không
        let childPaths = node.children.map { prefix + [$0.value] }
        if childPaths.allSatisfy({ paths.contains($0) }) {
            var next = paths
            for cp in childPaths { next.remove(cp) }
            next.insert(prefix)
            return next
        }

        return nil
    }
}
