import DAXEngine
import Foundation
import PBIXKit

/// Phase F (T116): cột và bảng tính toán nào phải tính lại, theo thứ tự nào. Desktop tính lại mọi cột/bảng tính toán phụ thuộc khi sửa
/// công thức một cột (VM-F9); BI Pro làm như vậy trong phiên (`ModelRuntime`) và khi lưu (ghi lại dữ liệu của chúng).
///
/// Phụ thuộc đọc bằng lexer DAX: "mạnh" là tham chiếu cột `Bảng[Cột]`/`[Cột]` (kể cả qua measure) và bảng tính toán chứa cột; "yếu" là
/// nhắc tên bảng (`ALL(Sales)`, `COUNTROWS(Sales)`) mà không nêu cột. Phụ thuộc mạnh quyết định thứ tự và vòng phụ thuộc; phụ thuộc yếu
/// chỉ làm nút thành cần tính lại (và được ưu tiên xếp sau), để `RANKX(ALL(Sales), …)` ở hai cột cùng bảng không thành vòng giả.
struct CalculationPlan: Equatable {
    enum Node: Hashable, CustomStringConvertible {
        case column(table: String, name: String)
        case table(String)

        var table: String {
            switch self {
            case .column(let table, _), .table(let table): table
            }
        }

        var description: String {
            switch self {
            case .column(let table, let name): "\(table)[\(name)]"
            case .table(let name): "bảng \(name)"
            }
        }
    }

    /// Nút cần tính, xếp sao cho nút đứng sau mọi nút nó dùng (phụ thuộc mạnh).
    let order: [Node]
    /// Nút nằm trong (hoặc phụ thuộc vào) một vòng phụ thuộc: không tính được.
    let cyclic: [Node]

    static let empty = CalculationPlan(order: [], cyclic: [])

    var all: [Node] { order + cyclic }

    /// Các nút `seeds` cùng mọi nút phụ thuộc chúng (bắc cầu), đã xếp thứ tự.
    static func make(seeds: Set<Node>, metadata: ModelMetadata) -> CalculationPlan {
        guard !seeds.isEmpty else { return .empty }
        let graph = Graph(metadata: metadata)
        var dirty = Set<Node>(), queue = graph.nodes.filter { seeds.contains($0) }
        dirty.formUnion(queue)
        while let node = queue.popLast() {
            for user in graph.users[node, default: []] where !dirty.contains(user) {
                dirty.insert(user)
                queue.append(user)
            }
        }
        // Kahn trên phụ thuộc mạnh giữa các nút cần tính; nút sẵn sàng còn chờ phụ thuộc yếu thì để sau, rồi theo thứ tự trong mô hình.
        let nodes = graph.nodes.filter { dirty.contains($0) }
        var pending = Dictionary(uniqueKeysWithValues: nodes.map { ($0, graph.strong[$0, default: []].intersection(dirty)) })
        var done = Set<Node>(), order: [Node] = []
        while true {
            let ready = nodes.filter { !done.contains($0) && pending[$0]?.isEmpty == true }
            guard !ready.isEmpty else { break }
            let next = ready.first { node in graph.weak[node, default: []].allSatisfy { done.contains($0) || !dirty.contains($0) || $0 == node } }
                ?? ready[0]
            done.insert(next)
            order.append(next)
            for node in nodes { pending[node]?.remove(next) }
        }
        return CalculationPlan(order: order, cyclic: nodes.filter { !done.contains($0) })
    }

    /// Các nút tính toán đọc từ mô hình: cột tính toán và bảng tính toán, theo thứ tự trong mô hình (bảng trước cột của nó).
    struct Graph {
        var nodes: [Node] = []
        /// Nút → các nút nó dùng.
        var strong: [Node: Set<Node>] = [:]
        var weak: [Node: Set<Node>] = [:]
        /// Nút → các nút dùng nó (mạnh hoặc yếu).
        var users: [Node: Set<Node>] = [:]

        init(metadata: ModelMetadata) {
            // Bảng tính toán của người dùng, và bảng ngày cục bộ của Auto date/time (T032: engine tính trong phiên, giá trị lưu cùng file).
            let localDate = metadata.autoDateTables
            let tables = metadata.tables.filter {
                (($0.isUserTable && $0.isCalculatedUserTable) || localDate.contains($0.name)) && metadata.calculatedTableExpressions[$0.name] != nil
            }
            let calculatedTables = Set(tables.map(\.name))
            let columns = metadata.columns.filter { $0.kind == .calculated && $0.expression != nil }
            let tableNodes = tables.map { Node.table($0.name) }
            let columnNodes = columns.map { Node.column(table: $0.tableName, name: $0.name) }
            nodes = tableNodes + columnNodes
            var expressions: [Node: String] = [:]
            for table in tables { expressions[.table(table.name)] = metadata.calculatedTableExpressions[table.name] }
            for column in columns { expressions[.column(table: column.tableName, name: column.name)] = column.expression }
            // Theo tên chữ thường: cột tính toán của từng bảng, và mọi cột tính toán cùng tên (tham chiếu `[Cột]` không có bảng).
            var byTable: [String: [Node]] = [:], byName: [String: [Node]] = [:]
            var byQualified: [String: Node] = [:]
            for column in columns {
                let node = Node.column(table: column.tableName, name: column.name)
                byTable[column.tableName.lowercased(), default: []].append(node)
                byName[column.name.lowercased(), default: []].append(node)
                byQualified[column.tableName.lowercased() + "\u{0}" + column.name.lowercased()] = node
            }
            let tableByName = Dictionary(tables.map { ($0.name.lowercased(), Node.table($0.name)) }, uniquingKeysWith: { a, _ in a })
            // Cột kết quả của bảng tính toán thuộc nút bảng.
            var resultColumns: [String: Node] = [:]
            for column in metadata.columns where column.kind == .calculatedTableColumn && calculatedTables.contains(column.tableName) {
                resultColumns[column.tableName.lowercased() + "\u{0}" + column.name.lowercased()] = .table(column.tableName)
            }
            let measures = Dictionary(metadata.measures.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
            var ownColumns: [String: Set<String>] = [:]
            for column in metadata.columns { ownColumns[column.tableName.lowercased(), default: []].insert(column.name.lowercased()) }

            for node in nodes {
                guard let expression = expressions[node] else { continue }
                var references: [DAXNameReference] = [], names = Set<String>()
                var seen = Set<String>(), texts = [expression]
                while let text = texts.popLast() {
                    let found = DAXEngine.references(in: text)
                    references += found
                    names.formUnion(DAXEngine.tableNames(in: text) ?? [])
                    for reference in found {
                        let key = reference.name.lowercased()
                        guard let measure = measures[key], !seen.contains(key) else { continue }
                        if let table = reference.table, table.lowercased() != measure.tableName.lowercased() { continue }
                        seen.insert(key)
                        texts.append(measure.expression)
                    }
                }
                var strongSet = Set<Node>(), weakSet = Set<Node>()
                // Cột tính toán: `[Cột]` không ghi bảng mà bảng của chính nó có cột tên đó thì là cột ấy (ngữ cảnh dòng), không phải mọi cột
                // cùng tên ở bảng khác (bảng ngày cục bộ nào cũng có `[Date]`, T066). Tên không có ở bảng mình thì vẫn xét mọi bảng.
                var ownTable: String?
                if case .column(let table, _) = node { ownTable = table.lowercased() }
                for reference in references {
                    let name = reference.name.lowercased()
                    if reference.table == nil, let own = ownTable, ownColumns[own]?.contains(name) == true {
                        if let target = byQualified[own + "\u{0}" + name] { strongSet.insert(target) }
                        if let target = resultColumns[own + "\u{0}" + name] { strongSet.insert(target) }
                        continue
                    }
                    if let table = reference.table?.lowercased() {
                        if let target = byQualified[table + "\u{0}" + name] { strongSet.insert(target) }
                        if let target = resultColumns[table + "\u{0}" + name] { strongSet.insert(target) }
                    } else {
                        strongSet.formUnion(byName[name] ?? [])
                        for (key, target) in resultColumns where key.hasSuffix("\u{0}" + name) { strongSet.insert(target) }
                    }
                }
                for name in names {
                    if let target = tableByName[name] { strongSet.insert(target) }
                    weakSet.formUnion(byTable[name] ?? [])
                }
                // Cột tính toán trên bảng tính toán cần dữ liệu (số dòng) của bảng.
                if case .column(let table, _) = node, calculatedTables.contains(table) { strongSet.insert(.table(table)) }
                weakSet.remove(node)
                weakSet.subtract(strongSet)
                strong[node] = strongSet
                weak[node] = weakSet
                for target in strongSet.union(weakSet) { users[target, default: []].insert(node) }
            }
        }
    }
}

extension CalculationPlan {
    /// Nút đã đổi so với mô hình gốc `base` (file lúc mở): cột/bảng tính toán thêm hoặc sửa công thức trong phiên, và cột tính toán của bảng
    /// có dữ liệu nạp mới (`reloadedTables`).
    static func sessionSeeds(metadata: ModelMetadata, base: ModelMetadata, reloadedTables: Set<String>) -> Set<Node> {
        var seeds = Set<Node>()
        let baseColumns = Dictionary(base.columns.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for column in metadata.columns where column.kind == .calculated {
            let before = baseColumns[column.id]
            if before == nil || before?.kind != .calculated || before?.expression != column.expression || before?.tableName != column.tableName
                || reloadedTables.contains(column.tableName) {
                seeds.insert(.column(table: column.tableName, name: column.name))
            }
        }
        let baseTables = Dictionary(base.tables.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for table in metadata.tables where table.isCalculatedUserTable {
            guard let expression = metadata.calculatedTableExpressions[table.name] else { continue }
            let before = baseTables[table.id]
            if before == nil || before?.isCalculatedUserTable != true || base.calculatedTableExpressions[before?.name ?? ""] != expression {
                seeds.insert(.table(table.name))
            }
        }
        // Bảng ngày của Auto date/time thêm trong phiên (T032).
        for name in metadata.autoDateTables {
            guard let table = metadata.tables.first(where: { $0.name == name }), let expression = metadata.calculatedTableExpressions[name] else { continue }
            if baseTables[table.id] == nil || base.calculatedTableExpressions[name] != expression { seeds.insert(.table(name)) }
        }
        return seeds
    }

    /// Nút do các thao tác `edits` thêm hoặc sửa công thức, cùng cột tính toán của bảng chúng nạp lại (khi lưu: phần đổi của lần lưu này).
    static func editSeeds(_ edits: ModelEdits, metadata: ModelMetadata) -> Set<Node> {
        var seeds = Set<Node>()
        for edit in edits.items {
            switch edit {
            case .addCalculatedColumn(let table, let name, _, _), .updateCalculatedColumn(let table, let name, _, _):
                seeds.insert(.column(table: table, name: name.trimmingCharacters(in: .whitespacesAndNewlines)))
            case .addCalculatedTable(let name, _, _), .updateCalculatedTable(let name, _, _):
                seeds.insert(.table(name.trimmingCharacters(in: .whitespacesAndNewlines)))
            case .addTable(let table), .replaceTable(_, let table):
                for column in metadata.columns where column.kind == .calculated && column.tableName == table.name {
                    seeds.insert(.column(table: column.tableName, name: column.name))
                }
            default:
                continue
            }
        }
        return seeds
    }

    /// Lý do không lưu được việc tính lại các nút `nodes` đang có trong file: bảng tính toán có quan hệ, phân cấp hay cột tính toán thì
    /// chưa thay được (bộ ghi từ chối). Cột tính toán trong quan hệ, phân cấp hay là cột sắp xếp thì bộ ghi dựng lại chỉ mục (US4).
    static func saveBlockers(_ nodes: [Node], metadata: ModelMetadata) -> [String] {
        var lines: [String] = []
        for node in nodes {
            switch node {
            case .column(let table, let name):
                // Bộ ghi dựng lại `R$` cho quan hệ nhiều–một và một–một (US4); quan hệ nhiều–nhiều thì chưa.
                let stuck = metadata.relationships.filter {
                    (($0.fromTable == table && $0.fromColumn == name) || ($0.toTable == table && $0.toColumn == name)) && !["M:1", "1:1"].contains($0.cardinality)
                }
                if !stuck.isEmpty { lines.append("\(node): quan hệ \(stuck.map(\.name).joined(separator: ", ")) chưa dựng lại được chỉ mục") }
            case .table(let name):
                var uses: [String] = []
                if metadata.relationships.contains(where: { $0.fromTable == name || $0.toTable == name }) { uses.append("bảng có quan hệ") }
                if metadata.hierarchies.contains(where: { $0.tableName == name }) { uses.append("bảng có phân cấp") }
                if metadata.columns.contains(where: { $0.tableName == name && $0.kind == .calculated }) { uses.append("bảng có cột tính toán") }
                if !uses.isEmpty { lines.append("\(node): " + uses.joined(separator: "; ")) }
            }
        }
        return lines
    }

    /// Thao tác ghi lại dữ liệu cho các nút cần tính lại mà không có thao tác riêng trong `edits` (cột/bảng phụ thuộc đang có trong file).
    static func recalculationEdits(for edits: ModelEdits, metadata: ModelMetadata) -> [ModelEdit] {
        let seeds = editSeeds(edits, metadata: metadata)
        let plan = make(seeds: seeds, metadata: metadata)
        return plan.order.filter { !seeds.contains($0) }.compactMap { node in
            switch node {
            case .column(let table, let name):
                guard let column = metadata.columns.first(where: { $0.tableName == table && $0.name == name }), let expression = column.expression else { return nil }
                return .updateCalculatedColumn(table: table, name: name, expression: expression, dataType: column.dataType)
            case .table(let name):
                guard let expression = metadata.calculatedTableExpressions[name] else { return nil }
                let columns = metadata.columns.filter { $0.tableName == name && $0.kind == .calculatedTableColumn }
                    .map { ColumnSignature(name: $0.name, dataType: $0.dataType, sourceColumn: $0.sourceColumn) }
                return .updateCalculatedTable(name: name, expression: expression, columns: columns)
            }
        }
    }
}
