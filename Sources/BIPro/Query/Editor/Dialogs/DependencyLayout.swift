import Foundation

public struct DependencyPosition: Sendable, Equatable, Hashable {
    public let column: Int
    public let row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

/// Logic tính toán layout đồ thị phụ thuộc truy vấn (Query Dependencies).
public struct DependencyLayout: Sendable, Equatable {
    public let graph: DependencyGraphModel
    private var depths: [String: Int] = [:]
    private var positions: [String: DependencyPosition] = [:]

    public init(graph: DependencyGraphModel) {
        self.graph = graph
        self.compute()
    }

    public func depth(of id: String) -> Int {
        depths[id] ?? (graph.nodes.first(where: { $0.id == id })?.kind == .source ? 0 : 1)
    }

    public func position(of id: String) -> DependencyPosition {
        positions[id] ?? DependencyPosition(column: depth(of: id), row: 0)
    }

    public var maxColumn: Int {
        positions.values.map(\.column).max() ?? 0
    }

    public var maxRow: Int {
        positions.values.map(\.row).max() ?? 0
    }

    public func nodes(inColumn col: Int) -> [DependencyNode] {
        graph.nodes.filter { position(of: $0.id).column == col }
    }

    /// Tập các nút thượng nguồn (nguồn hoặc truy vấn mà nút này trực tiếp hoặc gián tiếp phụ thuộc vào), không gồm chính nó.
    public func upstream(of id: String) -> Set<String> {
        var result = Set<String>()
        var queue = [id]
        var visited = Set<String>([id])

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let incoming = graph.edges.filter { $0.to == current }.map(\.from)
            for from in incoming {
                if visited.insert(from).inserted {
                    result.insert(from)
                    queue.append(from)
                }
            }
        }
        return result
    }

    /// Tập các nút hạ nguồn (truy vấn trực tiếp hoặc gián tiếp dùng nút này), không gồm chính nó.
    public func downstream(of id: String) -> Set<String> {
        var result = Set<String>()
        var queue = [id]
        var visited = Set<String>([id])

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let outgoing = graph.edges.filter { $0.from == current }.map(\.to)
            for to in outgoing {
                if visited.insert(to).inserted {
                    result.insert(to)
                    queue.append(to)
                }
            }
        }
        return result
    }

    private mutating func compute() {
        // Nguồn dữ liệu (kind == .source) luôn có độ sâu 0.
        for node in graph.nodes where node.kind == .source {
            depths[node.id] = 0
        }

        // Truy vấn (kind == .query) có độ sâu = 1 + max(độ sâu các nút nó dùng).
        // Nếu có vòng tham chiếu, gán độ sâu theo thứ tự duyệt và không treo.
        var visiting = Set<String>()
        for node in graph.nodes where node.kind == .query {
            _ = resolveDepth(for: node.id, visiting: &visiting)
        }

        // Vị trí (column, row) ổn định theo thứ tự xuất hiện trong nodes
        var rowCountForDepth: [Int: Int] = [:]
        for node in graph.nodes {
            let col = depths[node.id] ?? 0
            let row = rowCountForDepth[col, default: 0]
            positions[node.id] = DependencyPosition(column: col, row: row)
            rowCountForDepth[col] = row + 1
        }
    }

    private mutating func resolveDepth(for id: String, visiting: inout Set<String>) -> Int {
        if let d = depths[id] { return d }
        if visiting.contains(id) {
            // Phát hiện vòng tham chiếu: ngắt vòng để không treo
            return 0
        }
        visiting.insert(id)
        defer { visiting.remove(id) }

        let incoming = graph.edges.filter { $0.to == id }.map(\.from)
        if incoming.isEmpty {
            depths[id] = 1
            return 1
        }

        var maxUsed = 0
        for from in incoming {
            let d = resolveDepth(for: from, visiting: &visiting)
            maxUsed = max(maxUsed, d)
        }
        let res = maxUsed + 1
        depths[id] = res
        return res
    }
}
