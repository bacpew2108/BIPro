// Phase F (T049): cầu nối giữa giá trị M (`MValue`) và `TableData`, dùng cho `#table`, thư viện `Table.*` và nạp nguồn.

import ColumnStore

public enum MTables {
    /// Giá trị M của một ô. Ô lỗi trả `.error`.
    public static func value(_ stored: StoredValue) -> MValue {
        switch stored {
        case .blank: .null
        case .integer(let v): .number(Double(v))
        case .double(let v): .number(v)
        case .currency(let v): .currency(v)
        case .string(let v): .text(v)
        case .boolean(let v): .logical(v)
        case .dateTime(let v): .dateTime(v)
        }
    }

    /// Giá trị M của ô; ô có cấu trúc (bản ghi, danh sách, bảng của `TableData.structured`) trả nguyên giá trị đó.
    public static func cell(_ table: TableData, row: Int, column: Int) -> MValue {
        if let message = table.error(row: row, column: column) { return .error(MError.expression(message)) }
        if let cells = table.structured[column] {
            if let value = cells[row] as? MValue { return value }
            return .null
        }
        return value(table.value(row: row, column: column))
    }

    /// Một hàng thành bản ghi `[Cột = giá trị, ...]`.
    /// Cột bảng lồng (sau NestedJoin hoặc `Excel.Workbook`) cho giá trị `.table` của dòng đó.
    public static func row(_ table: TableData, _ row: Int) -> MValue {
        .record(table.columns.indices.map { column in
            if let nested = table.nested[column], nested.indices.contains(row) { return MField(name: table.columns[column].name, value: .table(nested[row])) }
            return MField(name: table.columns[column].name, value: cell(table, row: row, column: column))
        })
    }

    /// Chữ hiển thị của giá trị đơn nằm lẫn trong cột có cấu trúc.
    static func scalarText(_ value: MValue) -> String {
        switch value {
        case .text(let s): s
        case .number(let d): d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(d)
        case .logical(let b): b ? "TRUE" : "FALSE"
        default: ""
        }
    }

    /// Giá trị có cấu trúc (không đặt được vào cột thường) và chữ giữ chỗ của nó trong lưới ("Record", "List", "Table" như Desktop).
    static func placeholder(_ value: MValue) -> String? {
        switch value {
        case .record: "Record"
        case .list: "List"
        case .table: "Table"
        case .function: "Function"
        case .type: "Type"
        default: nil
        }
    }

    public static func column(_ table: TableData, _ column: Int) -> MValue {
        .list((0..<table.rowCount).map { cell(table, row: $0, column: column) })
    }

    /// So sánh cấu trúc hai bảng (tên cột, kiểu, từng ô, ô lỗi).
    public static func identical(_ a: TableData, _ b: TableData) -> Bool {
        guard a.rowCount == b.rowCount, a.columns.count == b.columns.count, a.errorMask == b.errorMask else { return false }
        for c in a.columns.indices {
            guard a.columns[c].name == b.columns[c].name, a.columns[c].data.type == b.columns[c].data.type else { return false }
            for r in 0..<a.rowCount where a.value(row: r, column: c) != b.value(row: r, column: c) { return false }
        }
        return true
    }

    /// Dựng bảng từ các hàng giá trị. `types[i] == nil` thì suy kiểu cột từ giá trị (xem `inferType`).
    public static func build(names: [String], types: [MType?], rows: [[MValue]]) throws -> TableData {
        guard names.count == types.count else { throw MError.expression("Số tên cột và số kiểu không khớp") }
        return try build(names: names, types: types, columns: names.indices.map { index in rows.map { $0[index] } })
    }

    /// Dựng bảng từ các cột giá trị. Cột có bản ghi, danh sách hoặc bảng (kiểu `any`) thành cột giữ chỗ kèm `TableData.structured` (kiểu khai
    /// báo `text` cũng nhận, vì cột giữ chỗ là cột chuỗi khi phép biến đổi khác chép lại kiểu cột).
    public static func build(names: [String], types: [MType?], columns values: [[MValue]], nested: [Int: [TableData]] = [:]) throws -> TableData {
        var columns: [TableColumn] = []
        var mask: [Int: [Int: String]] = [:]
        var structured: [Int: [Int: any Sendable]] = [:]
        for (index, name) in names.enumerated() {
            var values = values[index]
            // Ô có giá trị lỗi (phần tử danh sách lỗi): ô trống kèm thông điệp trong `errorMask` (Desktop: lỗi ở ô, bảng vẫn có).
            for (row, value) in values.enumerated() {
                if case .error(let error) = value { mask[index, default: [:]][row] = error.message; values[row] = .null }
            }
            if values.contains(where: { placeholder($0) != nil }) {
                let declared = types[index]?.kind
                guard declared == nil || declared == .any || declared == .anynonnull || declared == .text || declared == .record || declared == .list || declared == .table else {
                    throw MError.expression("Giá trị không khớp kiểu \(declared!.rawValue) của cột '\(name)'")
                }
                var cells: [Int: any Sendable] = [:]
                var labels: [String?] = []
                for (row, value) in values.enumerated() {
                    if case .null = value { labels.append(nil); continue }
                    if let label = placeholder(value) {
                        cells[row] = value
                        labels.append(label)
                    } else {
                        // Cột lẫn giá trị đơn với bản ghi/danh sách: giữ giá trị đó dạng có cấu trúc, chữ là giá trị của nó.
                        cells[row] = value
                        labels.append(scalarText(value))
                    }
                }
                structured[index] = cells
                columns.append(TableColumn(name: name, data: ColumnBuilder.strings(labels)))
                continue
            }
            columns.append(TableColumn(name: name, data: try column(values, type: types[index], name: name)))
        }
        do {
            return try TableData(columns: columns, errorMask: mask, nested: nested, structured: structured)
        } catch TableDataError.duplicateColumn(let name) {
            throw MError.expression("Tên cột trùng: \(name)")
        } catch TableDataError.emptyColumnName {
            throw MError.expression("Tên cột không được rỗng")
        }
    }

    /// Cột kiểu `any`: suy từ giá trị. Toàn `null` → chuỗi. Lẫn nhiều kiểu → báo chưa hỗ trợ (không đoán).
    static func inferType(_ values: [MValue], name: String) throws -> MType {
        var kind: MType.Kind?
        for value in values {
            let k: MType.Kind
            switch value {
            case .null: continue
            case .number: k = .number
            case .currency: k = .currency
            case .text: k = .text
            case .logical: k = .logical
            case .date, .dateTime: k = .datetime
            case .error(let e): throw e
            default: throw MError.unsupported("cột '\(name)' chứa giá trị không phải số, chuỗi, logic hoặc ngày")
            }
            if let kind, kind != k { throw MError.unsupported("cột '\(name)' lẫn nhiều kiểu (any)") }
            kind = k
        }
        return MType(kind ?? .text, isNullable: true)
    }

    static func column(_ values: [MValue], type declared: MType?, name: String) throws -> ColumnData {
        let explicit = declared.flatMap { $0.kind == .any || $0.kind == .anynonnull ? nil : $0 }
        let type = try explicit ?? inferType(values, name: name)
        func mismatch(_ v: MValue) -> MError { MError.expression("Giá trị không khớp kiểu \(type.kind.rawValue) của cột '\(name)'") }
        func number(_ v: MValue) throws -> Double? {
            switch v {
            case .null: return nil
            case .number(let d): return d
            case .currency(let c): return Double(c) / 10_000
            case .error(let e): throw e
            default: throw mismatch(v)
            }
        }
        switch type.kind {
        case .int64, .int32, .int16, .int8:
            return ColumnBuilder.integers(try values.map { v in
                guard let d = try number(v) else { return nil }
                guard d == d.rounded(), abs(d) < 9.2e18 else { throw MError.expression("Giá trị \(d) không phải số nguyên (cột '\(name)')") }
                return Int64(d)
            })
        case .number, .double, .decimal, .percentage, .any, .anynonnull:
            return ColumnBuilder.doubles(try values.map { try number($0) })
        case .currency:
            return ColumnBuilder.currency(try values.map { v in try number(v).map { Int64(($0 * 10_000).rounded()) } })
        case .text:
            return ColumnBuilder.strings(try values.map { v in
                switch v {
                case .null: nil
                case .text(let s): s
                case .error(let e): throw e
                default: throw mismatch(v)
                }
            })
        case .logical:
            return ColumnBuilder.booleans(try values.map { v in
                switch v {
                case .null: nil
                case .logical(let b): b
                case .error(let e): throw e
                default: throw mismatch(v)
                }
            })
        case .date, .datetime, .datetimezone:
            return ColumnBuilder.dateTimes(try values.map { v in
                switch v {
                case .null: nil
                case .date(let d), .dateTime(let d): d
                case .error(let e): throw e
                default: throw mismatch(v)
                }
            })
        default:
            throw MError.unsupported("kiểu cột \(type.kind.rawValue)")
        }
    }
}
