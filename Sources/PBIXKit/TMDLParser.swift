import Foundation

// Phase E (T036): bộ phân tích tập con TMDL áp dụng được (specs/009-e-mo-hinh-hoa-luu-t2/contracts/tmdl-subset.md) và bộ tính
// `ModelEdits` từ văn bản đã sửa so với văn bản `TMDLWriter` sinh ra. Áp dụng nguyên khối: có lỗi hay mục ngoài phạm vi thì
// không có thao tác nào.

public struct TMDLParseError: Error, Equatable, CustomStringConvertible {
    public let path: String
    /// Dòng (đếm từ 1) trong tài liệu.
    public let line: Int
    public let message: String
    public var description: String { lt("\(path) dòng \(line): \(message)", "\(path) line \(line): \(message)") }
}

public struct TMDLIssue: Sendable, Hashable, CustomStringConvertible {
    public let path: String
    public let line: Int?
    public let message: String
    public init(path: String, line: Int?, message: String) {
        self.path = path
        self.line = line
        self.message = message
    }
    public var description: String { line.map { lt("\(path) dòng \($0): \(message)", "\(path) line \($0): \(message)") } ?? "\(path): \(message)" }
}

public struct TMDLApplyResult: Sendable {
    public let edits: ModelEdits
    public let issues: [TMDLIssue]
    public init(edits: ModelEdits, issues: [TMDLIssue]) {
        self.edits = edits
        self.issues = issues
    }
}

/// Mô hình đọc từ TMDL (chỉ phần thuộc phạm vi áp dụng, phần còn lại giữ làm văn bản `opaque` để biết có bị sửa không).
public struct TMDLModel: Sendable, Equatable {
    public struct Measure: Sendable, Equatable {
        public var name: String
        public var expression: String
        public var formatString: String?
        public var displayFolder: String?
        public var description: String?
        public var isHidden = false
        public var other: [String: String] = [:]
        public var line = 0
    }

    public struct Column: Sendable, Equatable {
        public var name: String
        public var expression: String?
        public var dataType: String?
        public var isHidden = false
        public var isKey = false
        public var formatString: String?
        public var displayFolder: String?
        public var dataCategory: String?
        public var summarizeBy: String?
        public var sourceColumn: String?
        public var sortByColumn: String?
        public var description: String?
        public var other: [String: String] = [:]
        public var line = 0
        public var isCalculated: Bool { expression != nil }
    }

    public struct Table: Sendable, Equatable {
        public var path: String
        public var name: String
        public var isHidden = false
        public var description: String?
        public var other: [String: String] = [:]
        public var measures: [Measure] = []
        public var columns: [Column] = []
        /// Hierarchy, partition và các khối khác chưa áp dụng được: văn bản chuẩn hoá để so sánh.
        public var opaque: [String] = []
        public var line = 0
    }

    public struct Relationship: Sendable, Equatable {
        public var path: String
        public var name: String
        public var fromTable = "", fromColumn = "", toTable = "", toColumn = ""
        public var isActive = true
        public var crossFilteringBehavior = 1
        public var fromCardinality: String?
        public var toCardinality: String?
        public var other: [String: String] = [:]
        public var line = 0
    }

    public var tables: [Table] = []
    public var relationships: [Relationship] = []
    /// Tài liệu không phải bảng hay quan hệ (model.tmdl, vai trò, ngôn ngữ): văn bản chuẩn hoá theo đường dẫn.
    public var otherDocuments: [String: String] = [:]
}

public enum TMDLParser {
    // MARK: Phân tích

    private struct Line {
        var number: Int
        var depth: Int
        var text: String        // đã bỏ thụt đầu dòng, giữ nguyên phần còn lại
    }

    public static func parse(documents: [(path: String, text: String)]) throws -> TMDLModel {
        var model = TMDLModel()
        for doc in documents {
            let lines = try split(doc.text, path: doc.path)
            guard let first = lines.first(where: { !$0.text.hasPrefix("///") }) else { continue }
            let keyword = first.text.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            switch keyword {
            case "table":
                model.tables.append(try parseTable(lines, path: doc.path))
            case "relationship":
                model.relationships += try parseRelationships(lines, path: doc.path)
            default:
                guard ["model", "role", "cultureInfo", "ref", "expression", "perspective", "dataSource", "function"].contains(keyword) else {
                    throw TMDLParseError(path: doc.path, line: first.number, message: lt("không nhận ra khối '\(first.text.prefix(30))' (cần table hoặc relationship)", "unrecognized block '\(first.text.prefix(30))' (expected table or relationship)"))
                }
                model.otherDocuments[doc.path] = lines.map { String(repeating: "\t", count: $0.depth) + $0.text }.joined(separator: "\n")
            }
        }
        return model
    }

    private static func split(_ text: String, path: String) throws -> [Line] {
        var result: [Line] = []
        for (index, raw) in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var line = String(raw)
            while line.hasSuffix(" ") || line.hasSuffix("\t") { line.removeLast() }
            if line.isEmpty { continue }
            var depth = 0
            var rest = Substring(line)
            while true {
                if rest.hasPrefix("\t") { depth += 1; rest = rest.dropFirst() }
                else if rest.hasPrefix("    ") { depth += 1; rest = rest.dropFirst(4) }
                else { break }
            }
            result.append(Line(number: index + 1, depth: depth, text: String(rest)))
        }
        return result
    }

    /// Đọc tên (trong nháy đơn hoặc trần) ở đầu `text`; trả tên và phần còn lại.
    private static func readName(_ text: String, path: String, line: Int, stopAtDot: Bool = false) throws -> (name: String, rest: String) {
        let chars = Array(text)
        if chars.first == "'" {
            var name = "", i = 1
            while i < chars.count {
                if chars[i] == "'" {
                    if i + 1 < chars.count, chars[i + 1] == "'" { name.append("'"); i += 2; continue }
                    return (name, String(chars[(i + 1)...]).trimmingCharacters(in: .whitespaces))
                }
                name.append(chars[i]); i += 1
            }
            throw TMDLParseError(path: path, line: line, message: lt("tên trong nháy đơn không đóng", "unterminated single-quoted name"))
        }
        var name = "", i = 0
        while i < chars.count, !chars[i].isWhitespace, chars[i] != "=", !(stopAtDot && chars[i] == ".") { name.append(chars[i]); i += 1 }
        return (name, String(chars[i...]).trimmingCharacters(in: .whitespaces))
    }

    private static func parseProperty(_ text: String) -> (key: String, value: String?) {
        if let colon = text.firstIndex(of: ":"), !text.prefix(upTo: colon).contains(" ") {
            return (String(text[..<colon]), String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }
        return (text, nil)
    }

    /// Các dòng con (sâu hơn `depth`) bắt đầu ngay sau chỉ số `index`.
    private static func children(of index: Int, in lines: [Line]) -> Range<Int> {
        let depth = lines[index].depth
        var end = index + 1
        while end < lines.count, lines[end].depth > depth { end += 1 }
        return (index + 1)..<end
    }

    private static func parseTable(_ all: [Line], path: String) throws -> TMDLModel.Table {
        guard let headerIndex = all.firstIndex(where: { !$0.text.hasPrefix("///") }) else { throw TMDLParseError(path: path, line: 1, message: lt("tài liệu rỗng", "empty document")) }
        let header = all[headerIndex]
        guard header.depth == 0 else { throw TMDLParseError(path: path, line: header.number, message: lt("thụt lề không đúng ở đầu khối", "incorrect indentation at the start of the block")) }
        let (name, _) = try readName(String(header.text.dropFirst("table".count)).trimmingCharacters(in: .whitespaces), path: path, line: header.number)
        var table = TMDLModel.Table(path: path, name: name, line: header.number)
        table.description = docComment(before: headerIndex, in: all)
        let lines = Array(all[(headerIndex + 1)...])
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.text.hasPrefix("///") { i += 1; continue }
            guard line.depth == 1 else {
                throw TMDLParseError(path: path, line: line.number, message: lt("thụt lề không đúng (cần một cấp dưới table)", "incorrect indentation (one level below table expected)"))
            }
            let body = children(of: i, in: lines)
            let keyword = line.text.split(separator: " ", maxSplits: 1).first.map(String.init) ?? line.text
            switch keyword {
            case "measure":
                table.measures.append(try parseMeasure(lines, at: i, body: body, path: path))
            case "column":
                table.columns.append(try parseColumn(lines, at: i, body: body, path: path))
            case "hierarchy", "partition", "annotation", "calculationGroup", "changedProperty", "extendedProperty", "refreshPolicy":
                table.opaque.append(normalized(lines[i..<body.upperBound]))
            default:
                let (key, value) = parseProperty(line.text)
                if body.count > 0 { table.opaque.append(normalized(lines[i..<body.upperBound])) }
                else if key == "isHidden", value == nil || value == "true" { table.isHidden = true }
                else { table.other[key] = value ?? "" }
            }
            i = body.upperBound
        }
        return table
    }

    private static func normalized(_ lines: ArraySlice<Line>) -> String {
        lines.map { String(repeating: "\t", count: $0.depth) + $0.text }.joined(separator: "\n")
    }

    private static func docComment(before index: Int, in lines: [Line]) -> String? {
        var comments: [String] = []
        var j = index - 1
        while j >= 0, lines[j].text.hasPrefix("///"), lines[j].depth == lines[index].depth {
            comments.append(String(lines[j].text.dropFirst(3)).trimmingCharacters(in: CharacterSet(charactersIn: " ")))
            j -= 1
        }
        return comments.isEmpty ? nil : comments.reversed().joined(separator: "\n")
    }

    /// Biểu thức nhiều dòng: các dòng sâu hơn `depth + 1` (hai cấp dưới đối tượng); bỏ thụt lề chung.
    private static func multilineExpression(_ lines: [Line], body: Range<Int>, depth: Int) -> (text: String, consumed: Set<Int>) {
        var consumed = Set<Int>()
        var parts: [String] = []
        for k in body where lines[k].depth >= depth + 2 {
            consumed.insert(k)
            parts.append(String(repeating: "\t", count: lines[k].depth - depth - 2) + lines[k].text)
        }
        return (parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), consumed)
    }

    private static func parseMeasure(_ lines: [Line], at index: Int, body: Range<Int>, path: String) throws -> TMDLModel.Measure {
        let line = lines[index]
        let (name, rest) = try readName(String(line.text.dropFirst("measure".count)).trimmingCharacters(in: .whitespaces), path: path, line: line.number)
        guard !name.isEmpty else { throw TMDLParseError(path: path, line: line.number, message: lt("measure thiếu tên", "measure has no name")) }
        guard rest.hasPrefix("=") else { throw TMDLParseError(path: path, line: line.number, message: lt("thiếu dấu '=' và biểu thức sau tên measure \(name)", "missing '=' and expression after measure name \(name)")) }
        var measure = TMDLModel.Measure(name: name, expression: String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines), line: line.number)
        measure.description = docComment(before: index, in: lines)
        let multi = multilineExpression(lines, body: body, depth: line.depth)
        if measure.expression.isEmpty { measure.expression = multi.text }
        for k in body where !multi.consumed.contains(k) {
            let prop = lines[k]
            if prop.text.hasPrefix("///") { continue }
            let (key, value) = parseProperty(prop.text)
            switch key {
            case "formatString": measure.formatString = value
            case "displayFolder": measure.displayFolder = value
            case "isHidden": measure.isHidden = value == nil || value == "true"
            default: measure.other[key] = value ?? ""
            }
        }
        return measure
    }

    private static func parseColumn(_ lines: [Line], at index: Int, body: Range<Int>, path: String) throws -> TMDLModel.Column {
        let line = lines[index]
        let (name, rest) = try readName(String(line.text.dropFirst("column".count)).trimmingCharacters(in: .whitespaces), path: path, line: line.number)
        guard !name.isEmpty else { throw TMDLParseError(path: path, line: line.number, message: lt("column thiếu tên", "column has no name")) }
        var column = TMDLModel.Column(name: name, line: line.number)
        column.description = docComment(before: index, in: lines)
        var multi: (text: String, consumed: Set<Int>) = ("", [])
        if rest.hasPrefix("=") {
            column.expression = String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            multi = multilineExpression(lines, body: body, depth: line.depth)
            if column.expression?.isEmpty == true { column.expression = multi.text }
        } else if !rest.isEmpty {
            throw TMDLParseError(path: path, line: line.number, message: lt("sau tên cột chỉ được có '=' và biểu thức", "only '=' and an expression may follow a column name"))
        }
        for k in body where !multi.consumed.contains(k) {
            let prop = lines[k]
            if prop.text.hasPrefix("///") { continue }
            let (key, value) = parseProperty(prop.text)
            switch key {
            case "dataType": column.dataType = value
            case "isHidden": column.isHidden = value == nil || value == "true"
            case "isKey": column.isKey = value == nil || value == "true"
            case "formatString": column.formatString = value
            case "displayFolder": column.displayFolder = value
            case "dataCategory": column.dataCategory = value
            case "summarizeBy": column.summarizeBy = value
            case "sourceColumn": column.sourceColumn = value
            case "sortByColumn": column.sortByColumn = try value.map { try readName($0, path: path, line: prop.number).name }
            default: column.other[key] = value ?? ""
            }
        }
        return column
    }

    private static func parseRelationships(_ all: [Line], path: String) throws -> [TMDLModel.Relationship] {
        var result: [TMDLModel.Relationship] = []
        var i = 0
        while i < all.count {
            let line = all[i]
            if line.text.hasPrefix("///") { i += 1; continue }
            guard line.depth == 0, line.text.hasPrefix("relationship") else {
                throw TMDLParseError(path: path, line: line.number, message: lt("cần khối relationship", "a relationship block is required"))
            }
            let (name, _) = try readName(String(line.text.dropFirst("relationship".count)).trimmingCharacters(in: .whitespaces), path: path, line: line.number)
            var relationship = TMDLModel.Relationship(path: path, name: name, line: line.number)
            let body = children(of: i, in: all)
            for k in body {
                let (key, value) = parseProperty(all[k].text)
                switch key {
                case "fromColumn", "toColumn":
                    let (table, column) = try splitColumnRef(value ?? "", path: path, line: all[k].number)
                    if key == "fromColumn" { relationship.fromTable = table; relationship.fromColumn = column }
                    else { relationship.toTable = table; relationship.toColumn = column }
                case "isActive": relationship.isActive = value != "false"
                case "crossFilteringBehavior": relationship.crossFilteringBehavior = value == "bothDirections" ? 2 : 1
                case "fromCardinality": relationship.fromCardinality = value
                case "toCardinality": relationship.toCardinality = value
                default: relationship.other[key] = value ?? ""
                }
            }
            result.append(relationship)
            i = body.upperBound
        }
        return result
    }

    /// `Bảng.Cột` với mỗi phần trần hoặc trong nháy đơn.
    private static func splitColumnRef(_ text: String, path: String, line: Int) throws -> (table: String, column: String) {
        let (table, rest) = try readName(text, path: path, line: line, stopAtDot: true)
        guard rest.hasPrefix("."), !table.isEmpty else { throw TMDLParseError(path: path, line: line, message: lt("cần dạng Bảng.Cột", "the form Table.Column is required")) }
        let (column, tail) = try readName(String(rest.dropFirst()), path: path, line: line, stopAtDot: true)
        guard !column.isEmpty, tail.isEmpty else { throw TMDLParseError(path: path, line: line, message: lt("cần dạng Bảng.Cột", "the form Table.Column is required")) }
        return (table, column)
    }

    // MARK: So sánh và tính thao tác

    private static func summarizeCode(_ name: String) -> Int? {
        ["default": 1, "none": 2, "sum": 3, "min": 4, "max": 5, "count": 6, "average": 7, "distinctCount": 8][name]
    }

    /// Thao tác đưa mô hình viết bằng `old` thành mô hình viết bằng `new`. Có lỗi cú pháp hoặc mục ngoài phạm vi thì `edits` rỗng
    /// và `issues` liệt kê từng mục (áp nguyên khối).
    public static func edits(old: [(path: String, text: String)], new: [(path: String, text: String)]) -> TMDLApplyResult {
        var issues: [TMDLIssue] = []
        let oldModel: TMDLModel
        do { oldModel = try parse(documents: old) } catch let error as TMDLParseError {
            return TMDLApplyResult(edits: ModelEdits(), issues: [TMDLIssue(path: error.path, line: error.line, message: lt("văn bản gốc không đọc được: \(error.message)", "the original text can't be read: \(error.message)"))])
        } catch { return TMDLApplyResult(edits: ModelEdits(), issues: [TMDLIssue(path: "", line: nil, message: "\(error)")]) }
        // Phân tích từng tài liệu mới riêng để báo lỗi đúng tệp.
        var newDocs: [(path: String, text: String)] = []
        for doc in new {
            do { _ = try parse(documents: [doc]); newDocs.append(doc) } catch let error as TMDLParseError {
                issues.append(TMDLIssue(path: error.path, line: error.line, message: error.message))
            } catch { issues.append(TMDLIssue(path: doc.path, line: nil, message: "\(error)")) }
        }
        guard issues.isEmpty, let newModel = try? parse(documents: newDocs) else { return TMDLApplyResult(edits: ModelEdits(), issues: issues) }

        var edits = ModelEdits()
        func issue(_ path: String, _ line: Int?, _ message: String) { issues.append(TMDLIssue(path: path, line: line, message: message)) }

        for (path, text) in newModel.otherDocuments where oldModel.otherDocuments[path] != text {
            issue(path, nil, lt("tài liệu này (model, vai trò, ngôn ngữ) chưa áp dụng được", "this document (model, roles, cultures) can't be applied yet"))
        }
        let oldTables = Dictionary(oldModel.tables.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let newTableNames = Set(newModel.tables.map(\.name))
        for t in oldModel.tables where !newTableNames.contains(t.name) { issue(t.path, nil, lt("xoá bảng \(t.name) chưa được hỗ trợ", "deleting table \(t.name) isn't supported yet")) }
        for table in newModel.tables {
            guard let before = oldTables[table.name] else {
                issue(table.path, table.line, lt("bảng mới \(table.name) cần nguồn dữ liệu, hãy tạo qua Get Data hoặc Bảng mới", "the new table \(table.name) needs a data source; create it through Get Data or New table"))
                continue
            }
            diffTable(before, table, edits: &edits, issue: issue)
        }

        // Quan hệ
        let oldRel = Dictionary(oldModel.relationships.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let newRelNames = Set(newModel.relationships.map(\.name))
        for r in oldModel.relationships where !newRelNames.contains(r.name) { edits.append(.deleteRelationship(name: r.name)) }
        for r in newModel.relationships {
            guard let before = oldRel[r.name] else {
                if r.fromCardinality == "one" { issue(r.path, r.line, lt("quan hệ một-một chưa được hỗ trợ", "one-to-one relationships aren't supported yet")) }
                else if r.toCardinality == "many" { issue(r.path, r.line, lt("quan hệ nhiều-nhiều chưa được hỗ trợ", "many-to-many relationships aren't supported yet")) }
                else if r.fromTable.isEmpty || r.toTable.isEmpty { issue(r.path, r.line, lt("quan hệ \(r.name) thiếu fromColumn hoặc toColumn", "relationship \(r.name) is missing fromColumn or toColumn")) }
                else {
                    edits.append(.addRelationship(NewRelationship(name: r.name, fromTable: r.fromTable, fromColumn: r.fromColumn, toTable: r.toTable,
                                                                  toColumn: r.toColumn, fromMany: true, toMany: false, isActive: r.isActive,
                                                                  crossFilteringBehavior: r.crossFilteringBehavior)))
                }
                continue
            }
            if (before.fromTable, before.fromColumn, before.toTable, before.toColumn) != (r.fromTable, r.fromColumn, r.toTable, r.toColumn) {
                issue(r.path, r.line, lt("đổi cột đầu quan hệ \(r.name) chưa được hỗ trợ (xoá rồi tạo quan hệ mới)", "changing the end columns of relationship \(r.name) isn't supported yet (delete it and create a new one)"))
            }
            if before.fromCardinality != r.fromCardinality || before.toCardinality != r.toCardinality {
                issue(r.path, r.line, lt("đổi bản số quan hệ \(r.name) chưa được hỗ trợ", "changing the cardinality of relationship \(r.name) isn't supported yet"))
            }
            if before.other != r.other { issue(r.path, r.line, lt("thuộc tính khác của quan hệ \(r.name) chưa được hỗ trợ", "other properties of relationship \(r.name) aren't supported yet")) }
            var patch = RelationshipPatch()
            if before.isActive != r.isActive { patch.isActive = r.isActive }
            if before.crossFilteringBehavior != r.crossFilteringBehavior { patch.crossFilteringBehavior = r.crossFilteringBehavior }
            if patch != RelationshipPatch() { edits.append(.updateRelationship(name: r.name, patch: patch)) }
        }
        return TMDLApplyResult(edits: issues.isEmpty ? edits : ModelEdits(), issues: issues)
    }

    private static func assign(_ old: String?, _ new: String?) -> Assignment<String>? {
        old == new ? nil : (new.map { .set($0) } ?? .clear)
    }

    private static func diffTable(_ old: TMDLModel.Table, _ new: TMDLModel.Table, edits: inout ModelEdits,
                                  issue: (String, Int?, String) -> Void) {
        if old.isHidden != new.isHidden { edits.append(.updateTable(name: new.name, patch: TablePatch(isHidden: new.isHidden))) }
        if old.other != new.other { issue(new.path, new.line, lt("thuộc tính của bảng \(new.name) (ví dụ lineageTag) chưa sửa được", "properties of table \(new.name) (for example lineageTag) can't be edited yet")) }
        if old.description != new.description { issue(new.path, new.line, lt("mô tả bảng \(new.name) chưa sửa được", "the description of table \(new.name) can't be edited yet")) }
        if old.opaque != new.opaque {
            let kind = new.opaque.first(where: { !old.opaque.contains($0) }) ?? old.opaque.first(where: { !new.opaque.contains($0) }) ?? ""
            let word = kind.split(separator: " ").first.map(String.init) ?? lt("khối", "block")
            issue(new.path, nil, lt("\(word) của bảng \(new.name) đã đổi nhưng chưa áp dụng được (partition, hierarchy chưa sửa được)", "\(word) of table \(new.name) changed but can't be applied yet (partitions and hierarchies can't be edited yet)"))
        }
        // Measure
        let oldM = Dictionary(old.measures.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let newMNames = Set(new.measures.map(\.name))
        for m in old.measures where !newMNames.contains(m.name) { edits.append(.deleteMeasure(table: new.name, name: m.name)) }
        for m in new.measures {
            guard let before = oldM[m.name] else {
                if !m.other.isEmpty { issue(new.path, m.line, lt("measure mới \(m.name) có thuộc tính chưa hỗ trợ: \(m.other.keys.sorted().joined(separator: ", "))", "new measure \(m.name) has unsupported properties: \(m.other.keys.sorted().joined(separator: ", "))")) }
                edits.append(.addMeasure(NewMeasure(table: new.name, name: m.name, expression: m.expression, formatString: m.formatString,
                                                    displayFolder: m.displayFolder, description: m.description, isHidden: m.isHidden)))
                continue
            }
            if before.other != m.other { issue(new.path, m.line, lt("thuộc tính khác của measure \(m.name) (ví dụ lineageTag) chưa sửa được", "other properties of measure \(m.name) (for example lineageTag) can't be edited yet")) }
            var patch = MeasurePatch()
            if before.expression != m.expression { patch.expression = m.expression }
            patch.formatString = assign(before.formatString, m.formatString)
            patch.displayFolder = assign(before.displayFolder, m.displayFolder)
            patch.description = assign(before.description, m.description)
            if before.isHidden != m.isHidden { patch.isHidden = m.isHidden }
            if patch != MeasurePatch() { edits.append(.updateMeasure(table: new.name, name: m.name, patch: patch)) }
        }
        // Cột
        let oldC = Dictionary(old.columns.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let newCNames = Set(new.columns.map(\.name))
        for c in old.columns where !newCNames.contains(c.name) { issue(new.path, nil, lt("xoá cột \(c.name) chưa được hỗ trợ", "deleting column \(c.name) isn't supported yet")) }
        for c in new.columns {
            guard let before = oldC[c.name] else { issue(new.path, c.line, lt("cột mới \(c.name) cần dữ liệu, hãy tạo qua Power Query hoặc Cột mới", "the new column \(c.name) needs data; create it through Power Query or New column")); continue }
            if before.dataType != c.dataType { issue(new.path, c.line, lt("đổi kiểu dữ liệu của cột \(c.name) chưa được hỗ trợ", "changing the data type of column \(c.name) isn't supported yet")) }
            if before.expression != c.expression { issue(new.path, c.line, lt("cột tính toán \(c.name) chỉ xem, chưa sửa được công thức", "calculated column \(c.name) is read-only; its formula can't be edited yet")) }
            if before.isKey != c.isKey || before.sourceColumn != c.sourceColumn { issue(new.path, c.line, lt("isKey và sourceColumn của cột \(c.name) chưa sửa được", "isKey and sourceColumn of column \(c.name) can't be edited yet")) }
            if before.other != c.other { issue(new.path, c.line, lt("thuộc tính khác của cột \(c.name) (ví dụ lineageTag) chưa sửa được", "other properties of column \(c.name) (for example lineageTag) can't be edited yet")) }
            var patch = ColumnPatch()
            if before.isHidden != c.isHidden { patch.isHidden = c.isHidden }
            patch.formatString = assign(before.formatString, c.formatString)
            patch.displayFolder = assign(before.displayFolder, c.displayFolder)
            patch.description = assign(before.description, c.description)
            patch.dataCategory = assign(before.dataCategory, c.dataCategory)
            patch.sortBy = assign(before.sortByColumn, c.sortByColumn)
            if before.summarizeBy != c.summarizeBy {
                if let name = c.summarizeBy, let code = summarizeCode(name) { patch.summarizeBy = code }
                else { issue(new.path, c.line, lt("summarizeBy của cột \(c.name) không hợp lệ", "summarizeBy of column \(c.name) isn't valid")) }
            }
            if patch != ColumnPatch() { edits.append(.updateColumn(table: new.name, name: c.name, patch: patch)) }
        }
    }
}
