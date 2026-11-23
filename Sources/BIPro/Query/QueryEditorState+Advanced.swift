// Phase F (T070/T072): API của Query Editor cho các hộp thoại nâng cao (Merge, Append, Group By, mở cột bảng lồng, Query Dependencies).
// Chỉ đọc: lệnh thêm bước vẫn đi qua `perform(_:)` với `StepCommand.merge/expandColumn/append/groupBy`.

import ColumnStore
import Foundation
import MEngine

/// Một cột kết quả của truy vấn: tên và kiểu (để gợi ý cột khoá, chọn phép tổng hợp phù hợp).
public struct QueryColumnInfo: Sendable, Equatable {
    public let name: String
    public let type: DAXType
}

/// Nút của đồ thị Query Dependencies.
public struct DependencyNode: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case source, query }
    public let id: String
    public let title: String
    public let kind: Kind
    /// Chỉ với truy vấn: có nạp vào mô hình không (Enable load).
    public let enableLoad: Bool
}

public struct DependencyEdge: Sendable, Equatable, Hashable {
    /// Nút bị dùng (nguồn hoặc truy vấn được tham chiếu).
    public let from: String
    /// Truy vấn dùng nó.
    public let to: String
}

public struct DependencyGraphModel: Sendable, Equatable {
    public var nodes: [DependencyNode]
    public var edges: [DependencyEdge]
    /// Đường vòng tham chiếu (nếu có), dạng `[A, B, A]`.
    public var cycle: [String]?
}

extension QueryEditorState {
    /// Các truy vấn khác truy vấn đang chọn mà Merge/Append có thể dùng (theo thứ tự trong danh sách). Không gồm truy vấn có thể tạo vòng
    /// (truy vấn mà chính truy vấn đang chọn đã được nó tham chiếu thì vẫn dùng được; truy vấn đang tham chiếu ngược lại truy vấn đang chọn thì bị loại).
    public var mergeCandidates: [QueryModel] {
        guard let current = selectedQuery else { return [] }
        var byName: [String: MQuery] = [:]
        for query in queries where byName[query.name] == nil { byName[query.name] = query.mquery }
        let graph = QueryDependencies.graph(byName)
        return queries.filter { other in
            guard other.id != current.id else { return false }
            return !((try? QueryDependencies.evaluationOrder(for: other.name, in: graph))?.contains(current.name) ?? false)
        }
    }

    /// Cột (tên, kiểu) của kết quả truy vấn `id` ở bước cuối. `nil` khi truy vấn lỗi hoặc không phải bảng.
    public func resultColumns(ofQuery id: UUID) async -> [QueryColumnInfo]? {
        guard let query = queries.first(where: { $0.id == id }), !query.steps.isEmpty else { return nil }
        guard let table = try? await evaluateFull(query, rowLimit: 1) else { return nil }
        return table.columns.map { QueryColumnInfo(name: $0.name, type: $0.data.type) }
    }

    /// Bảng kết quả của truy vấn `id` ở bước cuối, cắt còn `limit` dòng đầu (xem trước trong hộp Merge/Append). `nil` khi lỗi.
    public func resultPreview(ofQuery id: UUID, limit: Int = 20) async -> TableData? {
        guard let query = queries.first(where: { $0.id == id }), !query.steps.isEmpty else { return nil }
        return try? await evaluateFull(query, rowLimit: limit)
    }

    /// Kiểm cú pháp công thức của Custom Column (phần sau `each`). Trả lý do tiếng Việt kèm dòng/cột, `nil` khi hợp lệ.
    public func formulaError(_ formula: String) -> String? {
        let text = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return biN("Công thức không được để trống.", "The formula can't be empty.") }
        do { _ = try MParser.parse("each \(text)") } catch let error as MSyntaxError {
            return biN("Dòng \(error.line), cột \(max(error.column - 5, 1)): \(error.message)", "Line \(error.line), column \(max(error.column - 5, 1)): \(error.message)")
        } catch { return "\(error)" }
        return nil
    }

    /// Loại cột mở rộng được trong xem trước: bảng lồng (Merge), bản ghi hoặc danh sách (JSON). `nil` khi cột thường hoặc lẫn loại.
    public enum ExpandableKind: Sendable, Equatable { case table, record, list }

    public func expandableKind(of column: String) -> ExpandableKind? {
        guard let preview, let index = preview.index(ofColumn: column) else { return nil }
        if preview.nested[index] != nil { return .table }
        guard preview.structured[index] != nil else { return nil }
        var kinds = Set<ExpandableKind>()
        for row in 0..<preview.rowCount {
            switch MTables.cell(preview, row: row, column: index) {
            case .record: kinds.insert(.record)
            case .list: kinds.insert(.list)
            case .table: kinds.insert(.table)
            case .null: continue
            default: return nil
            }
        }
        return kinds.count == 1 ? kinds.first : nil
    }

    /// Cột của bảng lồng (sau Merge, hoặc ô bảng) hay trường của cột bản ghi (hợp theo thứ tự xuất hiện) trong cột `column` của bước đang xem:
    /// lấy từ xem trước. `nil` khi không mở rộng được bằng hộp chọn cột.
    public func nestedColumns(of column: String) -> [QueryColumnInfo]? {
        guard let preview, let index = preview.index(ofColumn: column) else { return nil }
        if let first = preview.nested[index]?.first { return first.columns.map { QueryColumnInfo(name: $0.name, type: $0.data.type) } }
        guard preview.structured[index] != nil else { return nil }
        var out: [QueryColumnInfo] = []
        var seen = Set<String>()
        for row in 0..<preview.rowCount {
            switch MTables.cell(preview, row: row, column: index) {
            case .record(let fields):
                for field in fields where seen.insert(field.name).inserted { out.append(QueryColumnInfo(name: field.name, type: .string)) }
            case .table(let t):
                for c in t.columns where seen.insert(c.name).inserted { out.append(QueryColumnInfo(name: c.name, type: c.data.type)) }
            default: continue
            }
        }
        return out.isEmpty ? nil : out
    }

    /// Cột có chứa bảng lồng (kết quả Merge chưa mở), bản ghi hoặc danh sách trong xem trước hiện tại.
    public var nestedColumnNames: [String] {
        guard let preview else { return [] }
        return Set(preview.nested.keys).union(preview.structured.keys).sorted().map { preview.columns[$0].name }
    }

    /// Đồ thị cho cửa sổ Query Dependencies: nguồn bên ngoài → truy vấn, truy vấn → truy vấn dùng nó.
    public var dependencyGraph: DependencyGraphModel {
        var byName: [String: MQuery] = [:]
        for query in queries where byName[query.name] == nil { byName[query.name] = query.mquery }
        var nodes: [DependencyNode] = []
        var edges: [DependencyEdge] = []
        var sources: [String] = []
        for query in queries {
            nodes.append(DependencyNode(id: "query:\(query.name)", title: query.name, kind: .query, enableLoad: query.enableLoad))
            for source in QueryDependencies.externalSources(of: query.mquery) {
                if !sources.contains(source) { sources.append(source) }
                edges.append(DependencyEdge(from: "source:\(source)", to: "query:\(query.name)"))
            }
        }
        let graph = QueryDependencies.graph(byName)
        for query in queries {
            for used in graph[query.name] ?? [] { edges.append(DependencyEdge(from: "query:\(used)", to: "query:\(query.name)")) }
        }
        let sourceNodes = sources.map { DependencyNode(id: "source:\($0)", title: $0, kind: .source, enableLoad: true) }
        return DependencyGraphModel(nodes: sourceNodes + nodes, edges: edges, cycle: QueryDependencies.cycle(in: graph))
    }
}
