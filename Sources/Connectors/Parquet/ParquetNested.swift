// Cột lồng của Parquet (specs/011, US6, T042): struct → bản ghi, LIST → danh sách, dựng lại từ mức lặp (repetition) và mức định nghĩa
// (definition) theo Dremel. Độ sâu lồng tối đa 3 (struct hoặc LIST tính một tầng); sâu hơn, MAP, hay danh sách kiểu cũ không chú thích LIST
// thì báo "Chưa hỗ trợ" kèm tên cột. Ô lồng của bảng giữ chỗ bằng chữ "Record"/"List" kèm giá trị ở `TableData.structured` (như JSON, T087);
// BI Pro đổi `ParquetValue` sang giá trị M ở `Parquet.Document`.
import PBIXKit
import ColumnStore
import Foundation

/// Giá trị một ô của cột lồng.
public indirect enum ParquetValue: Sendable, Equatable {
    case null
    case scalar(StoredValue)
    case record([ParquetField])
    case list([ParquetValue])
}

public struct ParquetField: Sendable, Equatable {
    public let name: String
    public let value: ParquetValue
    public init(name: String, value: ParquetValue) { self.name = name; self.value = value }
}

/// Một nút của cây lược đồ: `definition`/`repetition` là mức tối đa tới nút này (tính cả nó).
final class ParquetNode: @unchecked Sendable {
    let element: ParquetSchemaElement
    let children: [ParquetNode]
    let definition: Int
    let repetition: Int
    let path: [String]

    init(element: ParquetSchemaElement, children: [ParquetNode], definition: Int, repetition: Int, path: [String]) {
        self.element = element; self.children = children; self.definition = definition; self.repetition = repetition; self.path = path
    }

    var isLeaf: Bool { children.isEmpty }
    /// Nhóm chú thích LIST (ConvertedType LIST = 3, hay LogicalType LIST = 3).
    var isList: Bool { !isLeaf && (element.converted == 3 || element.logical == 3) }
    var isMap: Bool { !isLeaf && (element.converted == 1 || element.converted == 2 || element.logical == 2) }

    /// Lá dưới nút này theo thứ tự lược đồ.
    var leaves: [ParquetNode] { isLeaf ? [self] : children.flatMap(\.leaves) }

    /// Phần tử của danh sách: dạng 3 tầng `LIST { repeated group list { element } }`, hoặc 2 tầng (nhóm lặp chính là phần tử).
    var listElement: (repeated: ParquetNode, element: ParquetNode)? {
        guard isList, children.count == 1, children[0].element.repetition == 2 else { return nil }
        let repeated = children[0]
        if !repeated.isLeaf, repeated.children.count == 1, repeated.element.name != "array", !repeated.element.name.hasSuffix("_tuple") {
            return (repeated, repeated.children[0])
        }
        return (repeated, repeated)
    }

    /// Độ sâu lồng logic: struct hay LIST tính một tầng.
    var nesting: Int {
        if isLeaf { return 0 }
        if let (repeated, element) = listElement {
            if element !== repeated { return 1 + element.nesting }
            return 1 + (repeated.isLeaf ? 0 : 1 + (repeated.children.map(\.nesting).max() ?? 0))
        }
        return 1 + (children.map(\.nesting).max() ?? 0)
    }

    /// Cây từ danh sách phẳng (thứ tự trước, `num_children`) bắt đầu ở `index` (dưới gốc).
    static func build(_ elements: [ParquetSchemaElement], _ index: inout Int, parentDefinition: Int, parentRepetition: Int,
                      parentPath: [String]) -> ParquetNode {
        let element = elements[index]
        index += 1
        let definition = parentDefinition + (element.repetition == 0 ? 0 : 1)
        let repetition = parentRepetition + (element.repetition == 2 ? 1 : 0)
        let path = parentPath + [element.name]
        var children: [ParquetNode] = []
        for _ in 0..<element.children where index < elements.count {
            children.append(build(elements, &index, parentDefinition: definition, parentRepetition: repetition, parentPath: path))
        }
        return ParquetNode(element: element, children: children, definition: definition, repetition: repetition, path: path)
    }

    /// Lý do không đọc được cột này, hay `nil`.
    func unsupportedReason() -> String? {
        if isMap { return "Parquet cột \(path.joined(separator: ".")) kiểu MAP" }
        if element.repetition == 2 && !isLeaf && !isList { return "Parquet cột \(path.joined(separator: ".")) lặp không chú thích LIST" }
        if isLeaf, element.repetition == 2, path.count == 1 { return lt("Parquet cột \(element.name) lặp không chú thích LIST", "Parquet column \(element.name) repeats without a LIST annotation") }
        if isList, listElement == nil { return "Parquet cột \(path.joined(separator: ".")) dạng LIST lạ" }
        for child in children {
            // Nhóm lặp trong LIST là khung của danh sách, không xét như cột lặp riêng.
            if isList, child === listElement?.repeated {
                if let element = listElement?.element, element !== child, let reason = element.unsupportedReason() { return reason }
                continue
            }
            if let reason = child.unsupportedReason() { return reason }
        }
        return nil
    }
}

/// Các mục (mức lặp, mức định nghĩa, chỉ số giá trị) của một lá trong một row group.
struct ParquetLeafEntries {
    var repetition: [Int32] = []
    var definition: [Int32] = []
    var values: [StoredValue] = []
}

enum ParquetAssembler {
    /// Dựng `rows` ô đầu của cột lồng `node` từ các mục của mỗi lá (khoá là đường dẫn lá).
    static func assemble(_ node: ParquetNode, entries: [[String]: ParquetLeafEntries], rows: Int) -> [ParquetValue] {
        let leaves = node.leaves
        // Ranh giới dòng của mỗi lá: mục có mức lặp 0 bắt đầu dòng mới.
        var starts: [[String]: [Int]] = [:]
        for leaf in leaves {
            let reps = entries[leaf.path]?.repetition ?? []
            starts[leaf.path] = reps.indices.filter { reps[$0] == 0 }
        }
        var valueIndex: [[String]: [Int]] = [:]
        for leaf in leaves {
            let defs = entries[leaf.path]?.definition ?? []
            var next = 0
            valueIndex[leaf.path] = defs.map { d in
                defer { if Int(d) == leaf.definition { next += 1 } }
                return Int(d) == leaf.definition ? next : -1
            }
        }
        var out: [ParquetValue] = []
        out.reserveCapacity(rows)
        for row in 0..<rows {
            var slices: [[String]: Range<Int>] = [:]
            for leaf in leaves {
                let list = starts[leaf.path] ?? []
                guard row < list.count else { slices[leaf.path] = 0..<0; continue }
                let end = row + 1 < list.count ? list[row + 1] : (entries[leaf.path]?.repetition.count ?? 0)
                slices[leaf.path] = list[row]..<end
            }
            out.append(value(node, slices, entries, valueIndex))
        }
        return out
    }

    private static func firstDefinition(_ node: ParquetNode, _ slices: [[String]: Range<Int>], _ entries: [[String]: ParquetLeafEntries]) -> Int {
        guard let leaf = node.leaves.first, let range = slices[leaf.path], let first = range.first,
              let defs = entries[leaf.path]?.definition else { return 0 }
        return Int(defs[first])
    }

    private static func value(_ node: ParquetNode, _ slices: [[String]: Range<Int>], _ entries: [[String]: ParquetLeafEntries],
                              _ valueIndex: [[String]: [Int]]) -> ParquetValue {
        if node.isLeaf {
            guard let range = slices[node.path], let first = range.first,
                  let index = valueIndex[node.path]?[first], index >= 0, let entry = entries[node.path], index < entry.values.count else { return .null }
            return .scalar(entry.values[index])
        }
        let definition = firstDefinition(node, slices, entries)
        if node.element.repetition != 0, definition < node.definition { return .null }
        if let (repeated, element) = node.listElement {
            if definition < repeated.definition { return .list([]) }
            // Tách mỗi lá theo mục có mức lặp bằng tầng lặp của danh sách.
            var parts: [[[String]: Range<Int>]] = []
            for leaf in repeated.leaves {
                guard let range = slices[leaf.path], let reps = entries[leaf.path]?.repetition else { continue }
                var pieceStart = range.lowerBound
                var index = 0
                for i in range where i > range.lowerBound && Int(reps[i]) == repeated.repetition {
                    if parts.count <= index { parts.append([:]) }
                    parts[index][leaf.path] = pieceStart..<i
                    pieceStart = i
                    index += 1
                }
                if parts.count <= index { parts.append([:]) }
                parts[index][leaf.path] = pieceStart..<range.upperBound
            }
            return .list(parts.map { part in
                if element === repeated {
                    // Dạng 2 tầng: nhóm lặp là phần tử (bản ghi các con), hay lá lặp.
                    return element.isLeaf ? value(element, part, entries, valueIndex)
                        : .record(element.children.map { ParquetField(name: $0.element.name, value: value($0, part, entries, valueIndex)) })
                }
                return value(element, part, entries, valueIndex)
            })
        }
        return .record(node.children.map { ParquetField(name: $0.element.name, value: value($0, slices, entries, valueIndex)) })
    }
}

extension ParquetValue {
    /// Chữ giữ chỗ trong cột của bảng ("Record", "List"), `nil` với null.
    var placeholder: String? {
        switch self {
        case .null: nil
        case .record: "Record"
        case .list: "List"
        case .scalar(let v): "\(v)"
        }
    }
}
