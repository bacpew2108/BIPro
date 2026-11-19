// Phase F (T092): nguồn PostgreSQL theo hợp đồng `DataSource` (specs/010-f-get-data-power-query-t3/contracts/data-source.md).
// Hành vi theo Desktop 2.159 (docs/phase-f-evidence/vm-f7/QUAN-SAT-DB.md): Navigator danh sách phẳng `lược_đồ.bảng`, khung nhìn trước rồi
// bảng theo lược đồ và tên ([SUY ĐOÁN] từ một mẫu), không lược đồ hệ thống; nạp thành bảng tên `lược_đồ bảng`. Có câu SQL thì chỉ một mục
// `Query1`. Kiểu: int2/int4/int8/oid → Int64; numeric, float4, float8 → Double; boolean; date, timestamp → DateTime; text, varchar, char,
// name, uuid, json, jsonb, xml → chữ. VM-F15 (specs/011 T041): timestamptz → ngày giờ theo múi giờ máy (Power Query DateTime.Type);
// time → Time (giờ trong ngày, `sourceType` time); interval → Duration (ngày, tháng = 30 ngày); bytea → Binary (chữ hex, `sourceType` binary,
// mô hình bỏ cột); mảng → chữ dạng PostgreSQL in ra (Text.Type). Kiểu khác báo "chưa hỗ trợ" kèm tên kiểu và tên cột.

import ColumnStore
import Foundation

public struct PostgresSource: DataSource {
    public let kind: SourceKind = .postgres
    public let address: PostgresAddress
    public let credential: PostgresCredential
    /// Câu SQL người dùng nhập (ô "SQL statement" của Desktop); `nil` thì liệt kê bảng và khung nhìn.
    public let query: String?

    public init(address: PostgresAddress, credential: PostgresCredential, query: String? = nil) {
        self.address = address
        self.credential = credential
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    public func items() async throws -> [any SourceItem] {
        let connection = try await PostgresConnection.open(address, credential: credential)
        defer { connection.close() }
        if let query {
            return [PostgresItem(address: address, credential: credential, target: .query(query), rowCountHint: nil)]
        }
        let sql = """
            select t.table_schema, t.table_name, t.table_type,
                   (select c.reltuples::bigint from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
                     where n.nspname = t.table_schema and c.relname = t.table_name)
            from information_schema.tables t
            where t.table_schema not in ('pg_catalog', 'information_schema') and t.table_schema not like 'pg\\_toast%'
            order by case when t.table_type = 'VIEW' then 0 else 1 end, t.table_schema, t.table_name
            """
        return try await connection.rows(sql).compactMap { row -> PostgresItem? in
            guard row.count == 4, let schema = row[0], let table = row[1] else { return nil }
            let isView = row[2] == "VIEW"
            let estimate = row[3].flatMap { Int($0) }
            return PostgresItem(address: address, credential: credential, target: .table(schema: schema, name: table, isView: isView),
                                rowCountHint: isView ? nil : estimate.flatMap { $0 > 0 ? $0 : nil })
        }
    }
}

public struct PostgresItem: SourceItem {
    public enum Target: Sendable, Equatable {
        case table(schema: String, name: String, isView: Bool)
        case query(String)
    }

    let address: PostgresAddress
    let credential: PostgresCredential
    public let target: Target
    public let rowCountHint: Int?
    public var columns: [SourceColumn]? { nil }

    public var name: String {
        switch target {
        case .table(let schema, let name, _): "\(schema).\(name)"
        case .query: "Query1"
        }
    }

    public var loadName: String {
        switch target {
        case .table(let schema, let name, _): "\(schema) \(name)"
        case .query: "Query1"
        }
    }

    public var kind: SourceItemKind {
        switch target {
        case .table(_, _, let isView): isView ? .view : .table
        case .query: .query
        }
    }

    private var selectAll: String {
        switch target {
        case .table(let schema, let name, _): "select * from \(Self.quote(schema)).\(Self.quote(name))"
        case .query(let sql): sql
        }
    }

    public func preview(limit: Int) async throws -> TableData {
        // Câu SQL người dùng chạy nguyên (không bọc được mọi câu lệnh), rồi cắt; bảng thì để máy chủ giới hạn.
        switch target {
        case .table: try await run(selectAll + " limit \(max(limit, 0))", limit: limit, progress: nil)
        case .query: try await run(selectAll, limit: limit, progress: nil)
        }
    }

    public func load(progress: SourceProgress?) async throws -> TableData {
        try await run(selectAll, limit: nil, progress: progress)
    }

    private func run(_ sql: String, limit: Int?, progress: SourceProgress?) async throws -> TableData {
        let connection = try await PostgresConnection.open(address, credential: credential)
        defer { connection.close() }
        var builder: PostgresTableBuilder?
        let expected = Double(rowCountHint ?? 0)
        var count = 0
        try await connection.query(sql, onDescription: { fields in
            builder = PostgresTableBuilder(fields: fields)
        }, onRow: { row in
            try builder?.append(row)
            count += 1
            if let progress, expected > 0, count & 0xFFF == 0 { progress(min(Double(count) / expected, 0.99)) }
            return limit.map { count < $0 } ?? true   // đủ dòng xem trước thì dừng đọc (T107)
        })
        guard let builder else { throw SourceError.empty }
        if let unsupported = builder.firstUnsupported {
            // Kết nối có thể đã đóng sau khi dừng sớm: hỏi tên kiểu trên kết nối mới.
            let lookup = try? await PostgresConnection.open(address, credential: credential)
            defer { lookup?.close() }
            let typeName = (try? await lookup?.rows("select format_type(\(unsupported.typeOID), \(unsupported.typeModifier))").first?.first ?? nil)
                ?? "oid \(unsupported.typeOID)"
            throw SourceError.unsupported("kiểu PostgreSQL \"\(typeName)\" ở cột \"\(unsupported.name)\"")
        }
        progress?(1)
        return try builder.build()
    }

    static func quote(_ identifier: String) -> String { "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}

/// Dồn các dòng chữ của máy chủ thành cột có kiểu. Mỗi cột một lớp giữ mảng để thêm dòng không chép lại mảng.
struct PostgresTableBuilder {
    enum Kind { case integer, double, boolean, dateTime, zonedDateTime, time, interval, binary, text, unsupported }

    private final class Column {
        let field: PostgresField
        let kind: Kind
        var integers: [Int64?] = []
        var doubles: [Double?] = []
        var booleans: [Bool?] = []
        var strings: [String?] = []

        init(field: PostgresField) {
            self.field = field
            kind = PostgresTableBuilder.kind(of: field.typeOID)
        }
    }

    private let columns: [Column]

    init(fields: [PostgresField]) {
        columns = fields.map(Column.init)
    }

    var firstUnsupported: PostgresField? { columns.first { $0.kind == .unsupported }?.field }

    static func kind(of oid: UInt32) -> Kind {
        switch oid {
        case 20, 21, 23, 26: .integer                  // int8, int2, int4, oid
        case 700, 701, 1700: .double                   // float4, float8, numeric (Desktop: Double, VM-F7b)
        case 16: .boolean
        case 1082, 1114: .dateTime                     // date, timestamp
        case 25, 1043, 1042, 18, 19, 2950, 114, 3802, 142: .text   // text, varchar, char, "char", name, uuid, json, jsonb, xml
        case 1184: .zonedDateTime                      // timestamptz
        case 1083: .time                               // time without time zone
        case 1186: .interval
        case 17: .binary                               // bytea
        // Mảng của các kiểu thường gặp (bool, int, float, numeric, chữ, ngày giờ, uuid, json…): Desktop đọc thành chữ.
        case 1000, 1005, 1007, 1016, 1021, 1022, 1231, 1009, 1015, 1014, 1002, 1003, 1182, 1115, 1185, 1183, 1187, 2951, 199, 3807, 1001, 143:
            .text
        default: .unsupported
        }
    }

    func append(_ row: [String?]) throws {
        for (index, column) in columns.enumerated() {
            let text = index < row.count ? row[index] : nil
            switch column.kind {
            case .integer: column.integers.append(text.flatMap { Int64($0) })
            case .double: column.doubles.append(text.flatMap(Self.double))
            case .boolean: column.booleans.append(text.map { $0 == "t" })
            case .dateTime:
                let value = text.flatMap { DateHelper.parseDateTime($0) }
                if let text, value == nil {
                    throw SourceError.unsupported("giá trị ngày \"\(text)\" ở cột \"\(column.field.name)\"")
                }
                column.doubles.append(value)
            case .zonedDateTime:
                let value = text.flatMap { Self.localDateTime($0, zone: .current) }
                if let text, value == nil { throw SourceError.unsupported("giá trị ngày giờ \"\(text)\" ở cột \"\(column.field.name)\"") }
                column.doubles.append(value)
            case .time: column.doubles.append(text.flatMap(Self.timeOfDay))
            case .interval:
                let value = text.flatMap(Self.intervalDays)
                if let text, value == nil { throw SourceError.unsupported("khoảng thời gian \"\(text)\" ở cột \"\(column.field.name)\"") }
                column.doubles.append(value)
            case .binary, .text: column.strings.append(text)
            case .unsupported: break
            }
        }
    }

    /// `HH:MM:SS[.ffffff]` → phần của ngày.
    static func timeOfDay(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
        return (h * 3600 + m * 60 + s) / 86_400
    }

    /// timestamptz dạng chữ của máy chủ (`2026-03-01 01:30:00.25+00`, `…+05:30`) → ngày OLE theo giờ địa phương của `zone`, như Desktop đổi
    /// về giờ máy (VM-F15). `[SUY ĐOÁN]` năm âm hay "BC", `infinity` chưa xét.
    static func localDateTime(_ text: String, zone: TimeZone) -> Double? {
        guard let sign = text.lastIndex(where: { $0 == "+" || $0 == "-" }), text.distance(from: text.startIndex, to: sign) >= 19 else { return nil }
        let body = String(text[..<sign]), offsetText = text[text.index(after: sign)...]
        let pieces = offsetText.split(separator: ":").compactMap { Int($0) }
        guard !pieces.isEmpty else { return nil }
        let offset = (pieces[0] * 3600 + (pieces.count > 1 ? pieces[1] * 60 : 0) + (pieces.count > 2 ? pieces[2] : 0)) * (text[sign] == "-" ? -1 : 1)
        guard let wall = DateHelper.parseDateTime(body) else { return nil }
        let utc = wall - Double(offset) / 86_400
        // Ngày OLE → Date (UTC) để lấy độ lệch múi giờ của thời điểm đó.
        let date = Date(timeIntervalSince1970: (utc - 25_569) * 86_400)
        return utc + Double(zone.secondsFromGMT(for: date)) / 86_400
    }

    /// interval kiểu chữ mặc định của PostgreSQL (`1 year 2 mons -3 days 04:05:06.5`) → số ngày; năm = 12 tháng, tháng = 30 ngày
    /// (VM-F15: `-1 year -2 mons 3 days` → -417).
    static func intervalDays(_ text: String) -> Double? {
        var days = 0.0
        let tokens = text.split(separator: " ").map(String.init)
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if token.contains(":") {
                let negative = token.hasPrefix("-")
                let clean = token.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
                guard let fraction = timeOfDay(clean) else { return nil }
                days += negative ? -fraction : fraction
                i += 1
                continue
            }
            guard i + 1 < tokens.count, let n = Double(token) else { return nil }
            switch tokens[i + 1] {
            case "year", "years": days += n * 360
            case "mon", "mons": days += n * 30
            case "day", "days": days += n
            default: return nil
            }
            i += 2
        }
        return days
    }

    private static func double(_ text: String) -> Double? {
        switch text {
        case "NaN": .nan
        case "Infinity": .infinity
        case "-Infinity": -.infinity
        default: Double(text)
        }
    }

    func build() throws -> TableData {
        try TableData(columns: columns.map { column in
            let data: ColumnData
            switch column.kind {
            case .integer: data = ColumnBuilder.integers(column.integers)
            case .double: data = ColumnBuilder.doubles(column.doubles)
            case .boolean: data = ColumnBuilder.booleans(column.booleans)
            case .dateTime, .zonedDateTime, .time: data = ColumnBuilder.dateTimes(column.doubles)
            case .interval: data = ColumnBuilder.doubles(column.doubles)
            case .binary, .text, .unsupported: data = ColumnBuilder.strings(column.strings)
            }
            let source: MSourceType? = switch column.kind {
            case .time: .time
            case .interval: .duration
            case .binary: .binary
            default: nil
            }
            return TableColumn(name: column.field.name, data: data, sourceType: source)
        })
    }
}
