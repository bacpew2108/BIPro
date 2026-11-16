// Phase F (T069): đồ thị phụ thuộc giữa các truy vấn (tham chiếu, Merge, Append) và nguồn dữ liệu bên ngoài, cho Query Dependencies
// và để xác định truy vấn nào phải tính trước. Một truy vấn "dùng" truy vấn khác khi một biểu thức của nó viết tên truy vấn đó
// ở vị trí định danh (không phải tên trường sau `[`, và không bị tên bước cùng tên che).

import Foundation

public enum QueryDependencies {
    /// Tên trong `names` mà `query` tham chiếu tới.
    public static func references(of query: MQuery, among names: Set<String>) -> Set<String> {
        let ownSteps = Set(query.steps.map(\.name))
        var found = Set<String>()
        for step in query.steps {
            guard let tokens = try? MLexer.tokenize(step.expression) else { continue }
            for (k, token) in tokens.enumerated() {
                let name: String
                switch token.kind {
                case .identifier(let n), .quotedIdentifier(let n): name = n
                default: continue
                }
                if k > 0, case .symbol("[") = tokens[k - 1].kind { continue }
                if names.contains(name), !ownSteps.contains(name) { found.insert(name) }
            }
        }
        return found
    }

    /// tên truy vấn → các truy vấn nó dùng (theo thứ tự tên).
    public static func graph(_ queries: [String: MQuery]) -> [String: [String]] {
        let names = Set(queries.keys)
        return queries.mapValues { references(of: $0, among: names).sorted() }
    }

    /// Vòng tham chiếu đầu tiên tìm được, dạng `[A, B, A]`; `nil` khi không có.
    public static func cycle(in graph: [String: [String]]) -> [String]? {
        var state: [String: Int] = [:]   // 1 đang duyệt, 2 xong
        var path: [String] = []
        func visit(_ node: String) -> [String]? {
            state[node] = 1
            path.append(node)
            for next in graph[node] ?? [] {
                if state[next] == 1 { return Array(path[path.firstIndex(of: next)!...]) + [next] }
                if state[next] == nil, let cycle = visit(next) { return cycle }
            }
            path.removeLast()
            state[node] = 2
            return nil
        }
        for node in graph.keys.sorted() where state[node] == nil {
            if let cycle = visit(node) { return cycle }
        }
        return nil
    }

    /// Mọi truy vấn mà `name` phụ thuộc, trực tiếp hay gián tiếp, theo thứ tự nên tính (phụ thuộc trước). Không gồm `name`.
    /// Có vòng thì ném lỗi nêu đường vòng.
    public static func evaluationOrder(for name: String, in graph: [String: [String]]) throws -> [String] {
        if let cycle = cycle(in: graph) { throw MError.expression("Truy vấn tham chiếu vòng: \(cycle.joined(separator: " → "))") }
        var order: [String] = [], seen = Set<String>()
        func visit(_ node: String) {
            for next in graph[node] ?? [] where seen.insert(next).inserted { visit(next); order.append(next) }
        }
        visit(name)
        return order
    }

    /// Nguồn bên ngoài của truy vấn: mỗi lần gọi `File.Contents("…")` cho đường dẫn tệp; `Sql.Database`, `PostgreSQL.Database`… cho máy chủ.
    public static func externalSources(of query: MQuery) -> [String] {
        var out: [String] = []
        for step in query.steps {
            guard let tokens = try? MLexer.tokenize(step.expression) else { continue }
            for (k, token) in tokens.enumerated() {
                guard case .identifier(let name) = token.kind,
                      name == "File.Contents" || name.hasSuffix(".Database") || name == "Web.Contents",
                      k + 2 < tokens.count, case .symbol("(") = tokens[k + 1].kind, case .text(let argument) = tokens[k + 2].kind else { continue }
                if !out.contains(argument) { out.append(argument) }
            }
        }
        return out
    }
}
