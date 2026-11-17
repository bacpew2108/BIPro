// Phase F, T087 (US7): JSON và giá trị có cấu trúc trong M. Hàm theo chuỗi bước Desktop 2.159 sinh khi nạp JSON
// (`docs/phase-f-evidence/vm-f7/QUAN-SAT.md`): `Json.Document`, `Table.FromList` + `Splitter.SplitByNothing` + `ExtraValues.*`,
// `Table.ExpandRecordColumn`, `Table.ExpandListColumn`; thêm `Table.FromRecords` và `Record.*` theo tài liệu M.
//
// Bản ghi, danh sách trong ô bảng nằm ở `TableData.structured` (cột giữ chỗ "Record"/"List"); `MTables.cell` trả lại giá trị gốc.

import ColumnStore
import Foundation

public enum MJson {
    /// Văn bản JSON (UTF-8, bỏ BOM) → giá trị M: đối tượng → bản ghi (giữ thứ tự khoá như trong tệp, Desktop mở rộng theo thứ tự đó),
    /// mảng → danh sách, số → number, chuỗi → text, true/false → logical, null → null.
    public static func parse(_ data: Data) throws -> MValue {
        var bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        var parser = Parser(bytes: bytes)
        parser.skipSpace()
        let value = try parser.value(depth: 0)
        parser.skipSpace()
        guard parser.index == bytes.count else { throw parser.failure("thừa ký tự sau giá trị JSON") }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        func failure(_ what: String) -> MError {
            MError(reason: "DataFormat.Error", message: "JSON không hợp lệ: \(what) (vị trí \(index))")
        }

        mutating func skipSpace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func value(depth: Int) throws -> MValue {
            guard depth < 512 else { throw failure("lồng quá sâu") }
            guard index < bytes.count else { throw failure("hết dữ liệu") }
            switch bytes[index] {
            case UInt8(ascii: "{"):
                index += 1
                var fields: [MField] = []
                skipSpace()
                if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .record(fields) }
                while true {
                    skipSpace()
                    guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw failure("cần tên trường") }
                    let name = try string()
                    skipSpace()
                    guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw failure("cần dấu ':'") }
                    index += 1
                    skipSpace()
                    let item = try value(depth: depth + 1)
                    // Khoá trùng: giữ giá trị sau cùng ở vị trí đầu (như bản ghi M không cho trùng tên).
                    if let existing = fields.firstIndex(where: { $0.name == name }) { fields[existing] = MField(name: name, value: item) }
                    else { fields.append(MField(name: name, value: item)) }
                    skipSpace()
                    guard index < bytes.count else { throw failure("thiếu '}'") }
                    if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                    if bytes[index] == UInt8(ascii: "}") { index += 1; return .record(fields) }
                    throw failure("cần ',' hoặc '}'")
                }
            case UInt8(ascii: "["):
                index += 1
                var items: [MValue] = []
                skipSpace()
                if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .list(items) }
                while true {
                    skipSpace()
                    items.append(try value(depth: depth + 1))
                    skipSpace()
                    guard index < bytes.count else { throw failure("thiếu ']'") }
                    if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                    if bytes[index] == UInt8(ascii: "]") { index += 1; return .list(items) }
                    throw failure("cần ',' hoặc ']'")
                }
            case UInt8(ascii: "\""):
                return .text(try string())
            case UInt8(ascii: "t"): try literal("true"); return .logical(true)
            case UInt8(ascii: "f"): try literal("false"); return .logical(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default:
                return .number(try number())
            }
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf8)
            guard index + w.count <= bytes.count, Array(bytes[index..<index + w.count]) == w else { throw failure("giá trị lạ") }
            index += w.count
        }

        mutating func number() throws -> Double {
            let start = index
            while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
            guard index > start, let text = String(bytes: bytes[start..<index], encoding: .ascii), let d = Double(text) else {
                index = start
                throw failure("giá trị lạ")
            }
            return d
        }

        mutating func string() throws -> String {
            index += 1   // dấu mở "
            var out = [UInt8]()
            while index < bytes.count {
                let b = bytes[index]
                if b == UInt8(ascii: "\"") {
                    index += 1
                    guard let s = String(bytes: out, encoding: .utf8) else { throw failure("chuỗi không phải UTF-8") }
                    return s
                }
                if b == UInt8(ascii: "\\") {
                    index += 1
                    guard index < bytes.count else { break }
                    let e = bytes[index]
                    index += 1
                    switch e {
                    case UInt8(ascii: "\""): out.append(0x22)
                    case UInt8(ascii: "\\"): out.append(0x5C)
                    case UInt8(ascii: "/"): out.append(0x2F)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        var code = try hex4()
                        if (0xD800...0xDBFF).contains(code), index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                            index += 2
                            let low = try hex4()
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        let scalar = Unicode.Scalar(code) ?? "\u{FFFD}"
                        out.append(contentsOf: Array(String(Character(scalar)).utf8))
                    default: throw failure("ký tự thoát lạ")
                    }
                    continue
                }
                out.append(b)
                index += 1
            }
            throw failure("chuỗi chưa đóng")
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count, let text = String(bytes: bytes[index..<index + 4], encoding: .ascii), let v = UInt32(text, radix: 16) else {
                throw failure("\\u sai")
            }
            index += 4
            return v
        }
    }
}

enum JsonLibrary {
    static let functions: [MFunction] = [jsonDocument, fromList, splitByNothing, fromRecords, expandRecordColumn, expandListColumn,
                                         recordFieldNames, recordFieldValues, recordField, recordFieldCount, recordHasFields]

    /// `Json.Document(jsonText, encoding?)`: văn bản JSON → giá trị M. Nguồn tệp (`File.Contents`) do hàm nguồn của BI Pro đọc rồi gọi `MJson.parse`.
    static let jsonDocument = MFunction(
        name: "Json.Document", parameters: [MParameter(name: "jsonText"), MParameter(name: "encoding", isOptional: true)], observed: true
    ) { args in
        try MJson.parse(Data(try args.text(0, "Json.Document").utf8))
    }

    /// `Splitter.SplitByNothing()`: hàm trả `{giá trị}` (mỗi phần tử thành một cột).
    static let splitByNothing = MFunction(name: "Splitter.SplitByNothing", parameters: [], observed: true) { _ in
        .function(MFunction(name: "Splitter.SplitByNothing_inner", parameters: [MParameter(name: "value")], observed: true) { args in .list([args[0]]) })
    }

    /// `Table.FromList(list, splitter?, columns?, default?, extraValues?)`: mỗi phần tử qua `splitter` thành một hàng. Mặc định tách text theo
    /// dấu phẩy (tài liệu M). Cột: số cột, danh sách tên hoặc null (số cột theo hàng đầu, tên `Column1…`). Hàng ngắn bù `default`;
    /// hàng dài: `ExtraValues.Error` (1, mặc định) báo lỗi ở ô cuối, `Ignore` (2) bỏ phần thừa, `List` (0) gom phần thừa vào ô cuối.
    static let fromList = MFunction(
        name: "Table.FromList",
        parameters: [MParameter(name: "list"), MParameter(name: "splitter", isOptional: true), MParameter(name: "columns", isOptional: true),
                     MParameter(name: "default", isOptional: true), MParameter(name: "extraValues", isOptional: true)],
        observed: true
    ) { args in
        let items = try args.list(0, "Table.FromList")
        let split: (MValue) throws -> [MValue]
        if let splitter = args.optional(1) {
            guard case .function(let f) = splitter else { throw MError.expression("Table.FromList: splitter phải là hàm") }
            split = { item in
                let parts = try f.call([item])
                guard case .list(let values) = parts else { throw MError.expression("Table.FromList: splitter phải trả danh sách") }
                return values
            }
        } else {
            split = { item in
                guard case .text(let s) = item else { throw MError.expression("Table.FromList: phần tử không phải text, cần splitter") }
                return s.split(separator: ",", omittingEmptySubsequences: false).map { .text(String($0)) }
            }
        }
        let rows = try items.map { item -> [MValue] in
            if case .error(let e) = item { return [.error(e)] }
            return try split(item)
        }
        var names: [String]
        switch args.optional(2) {
        case .none: names = (0..<(rows.first?.count ?? 1)).map { "Column\($0 + 1)" }
        case .number(let n)?: names = (0..<max(Int(n), 0)).map { "Column\($0 + 1)" }
        case .list(let list)?: names = try list.map { v in guard case .text(let s) = v else { throw MError.expression("Table.FromList: tên cột phải là text") }; return s }
        case .type(let t)? where t.kind == .table: names = t.fields.map(\.name)
        default: throw MError.expression("Table.FromList: tham số columns không hợp lệ")
        }
        if names.isEmpty { names = ["Column1"] }
        let fill = args.optional(3) ?? .null
        let extra = Int(MOperators.number(args[4]) ?? 1)
        var columns = Array(repeating: [MValue](), count: names.count)
        for row in rows {
            for c in names.indices {
                if c < row.count {
                    if c == names.count - 1, row.count > names.count {
                        switch extra {
                        case 0: columns[c].append(.list(Array(row[c...])))
                        case 2: columns[c].append(row[c])
                        default: columns[c].append(.error(MError.expression("Có \(row.count) giá trị trong khi bảng chỉ có \(names.count) cột")))
                        }
                    } else {
                        columns[c].append(row[c])
                    }
                } else {
                    columns[c].append(fill)
                }
            }
        }
        return .table(try MTables.build(names: names, types: Array(repeating: nil, count: names.count), columns: columns))
    }

    /// `Table.FromRecords(records, columns?, missingField?)`: tên cột theo bản ghi đầu (hoặc `columns`); bản ghi thiếu trường: ô lỗi, hoặc null
    /// khi `MissingField.UseNull` (2).
    static let fromRecords = MFunction(
        name: "Table.FromRecords",
        parameters: [MParameter(name: "records"), MParameter(name: "columns", isOptional: true), MParameter(name: "missingField", isOptional: true)],
        observed: false
    ) { args in
        let items = try args.list(0, "Table.FromRecords")
        let records: [[MField]] = try items.map { item in
            guard case .record(let fields) = item else { throw MError.expression("Table.FromRecords: phần tử không phải bản ghi (\(item.kindName))") }
            return fields
        }
        let names: [String]
        switch args.optional(1) {
        case .none: names = records.first?.map(\.name) ?? []
        case .list(let list)?: names = try list.map { v in guard case .text(let s) = v else { throw MError.expression("Table.FromRecords: tên cột phải là text") }; return s }
        case .type(let t)? where t.kind == .table: names = t.fields.map(\.name)
        default: throw MError.expression("Table.FromRecords: tham số columns không hợp lệ")
        }
        let useNull = MOperators.number(args[2]) == 2
        let columns = names.map { name in
            records.map { fields -> MValue in
                if let field = fields.first(where: { $0.name == name }) { return field.value }
                return useNull ? .null : .error(MError.expression("Không tìm thấy trường '\(name)' của bản ghi"))
            }
        }
        return .table(try MTables.build(names: names, types: Array(repeating: nil, count: names.count), columns: columns))
    }

    /// `Table.ExpandRecordColumn(table, column, fieldNames, newColumnNames?)`: cột bản ghi thay bằng các cột trường, đặt đúng chỗ cột cũ.
    /// Ô null hoặc bản ghi thiếu trường cho null; ô không phải bản ghi là lỗi ở các cột mới.
    static let expandRecordColumn = MFunction(
        name: "Table.ExpandRecordColumn",
        parameters: [MParameter(name: "table"), MParameter(name: "column"), MParameter(name: "fieldNames"), MParameter(name: "newColumnNames", isOptional: true)],
        observed: true
    ) { args in
        let table = try args.table(0, "Table.ExpandRecordColumn")
        let name = try args.text(1, "Table.ExpandRecordColumn")
        guard let column = table.index(ofColumn: name) else { throw MError.expression("Không tìm thấy cột '\(name)' của bảng") }
        let fields = try TableRowsHelper.extractColumnNames(args[2], functionName: "Table.ExpandRecordColumn")
        let renamed = try args.optional(3).map { try TableRowsHelper.extractColumnNames($0, functionName: "Table.ExpandRecordColumn") } ?? fields
        guard renamed.count == fields.count else { throw MError.expression("Table.ExpandRecordColumn: số tên mới khác số trường") }
        var names: [String] = [], columns: [[MValue]] = []
        for (index, col) in table.columns.enumerated() {
            if index != column {
                names.append(col.name)
                columns.append((0..<table.rowCount).map { MTables.cell(table, row: $0, column: index) })
                continue
            }
            let cells = (0..<table.rowCount).map { MTables.cell(table, row: $0, column: index) }
            for (k, field) in fields.enumerated() {
                names.append(renamed[k])
                columns.append(cells.map { cell in
                    switch cell {
                    case .record(let values): values.first { $0.name == field }?.value ?? .null
                    case .null: .null
                    case .error: cell
                    default: .error(MError.expression("Không chuyển được giá trị kiểu \(cell.kindName) thành Record"))
                    }
                })
            }
        }
        if let duplicate = Dictionary(grouping: names, by: { $0 }).first(where: { $0.value.count > 1 })?.key {
            throw MError.expression("Cột '\(duplicate)' của bảng đã có")
        }
        return .table(try MTables.build(names: names, types: types(table, names: names, except: column, added: fields.count), columns: columns))
    }

    /// `Table.ExpandListColumn(table, column)`: mỗi phần tử danh sách thành một dòng (các cột khác lặp lại); danh sách rỗng hoặc null cho
    /// một dòng null; giá trị khác giữ nguyên.
    static let expandListColumn = MFunction(
        name: "Table.ExpandListColumn", parameters: [MParameter(name: "table"), MParameter(name: "column")], observed: true
    ) { args in
        let table = try args.table(0, "Table.ExpandListColumn")
        let name = try args.text(1, "Table.ExpandListColumn")
        guard let column = table.index(ofColumn: name) else { throw MError.expression("Không tìm thấy cột '\(name)' của bảng") }
        var sourceRows: [Int] = []
        var expanded: [MValue] = []
        for row in 0..<table.rowCount {
            let cell = MTables.cell(table, row: row, column: column)
            if case .list(let items) = cell, !items.isEmpty {
                for item in items { sourceRows.append(row); expanded.append(item) }
            } else {
                sourceRows.append(row)
                if case .list = cell { expanded.append(.null) } else { expanded.append(cell) }
            }
        }
        var columns: [[MValue]] = []
        for index in table.columns.indices {
            columns.append(index == column ? expanded : sourceRows.map { MTables.cell(table, row: $0, column: index) })
        }
        let names = table.columns.map(\.name)
        return .table(try MTables.build(names: names, types: types(table, names: names, except: column, added: 1), columns: columns))
    }

    /// Kiểu khai báo cho bảng dựng lại: cột giữ nguyên kiểu cũ (cột có cấu trúc để suy lại), cột mới (`added` cột ở vị trí `except`) suy từ giá trị.
    private static func types(_ table: TableData, names: [String], except column: Int, added: Int) -> [MType?] {
        var out: [MType?] = []
        for (index, col) in table.columns.enumerated() {
            if index == column { out.append(contentsOf: Array(repeating: nil, count: added)); continue }
            out.append(table.structured[index] != nil || table.nested[index] != nil ? nil : MType(col.data.type.mTypeKind, isNullable: true))
        }
        return out
    }

    // MARK: Record.*

    private static func record(_ args: [MValue], _ function: String) throws -> [MField] {
        guard case .record(let fields) = args[0] else { throw MError.expression("\(function): đối số 1 phải là bản ghi, nhận \(args[0].kindName)") }
        return fields
    }

    static let recordFieldNames = MFunction(name: "Record.FieldNames", parameters: [MParameter(name: "record")], observed: false) { args in
        .list(try record(args, "Record.FieldNames").map { .text($0.name) })
    }

    static let recordFieldValues = MFunction(name: "Record.FieldValues", parameters: [MParameter(name: "record")], observed: false) { args in
        .list(try record(args, "Record.FieldValues").map(\.value))
    }

    static let recordFieldCount = MFunction(name: "Record.FieldCount", parameters: [MParameter(name: "record")], observed: false) { args in
        .number(Double(try record(args, "Record.FieldCount").count))
    }

    static let recordField = MFunction(name: "Record.Field", parameters: [MParameter(name: "record"), MParameter(name: "field")], observed: false) { args in
        let fields = try record(args, "Record.Field")
        let name = try args.text(1, "Record.Field")
        guard let field = fields.first(where: { $0.name == name }) else { throw MError.expression("Không tìm thấy trường '\(name)' của bản ghi") }
        return field.value
    }

    static let recordHasFields = MFunction(name: "Record.HasFields", parameters: [MParameter(name: "record"), MParameter(name: "fields")], observed: false) { args in
        let fields = Set(try record(args, "Record.HasFields").map(\.name))
        let wanted = try TableRowsHelper.extractColumnNames(args[1], functionName: "Record.HasFields")
        return .logical(wanted.allSatisfy { fields.contains($0) })
    }
}
