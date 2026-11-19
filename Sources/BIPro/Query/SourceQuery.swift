// Phase F, T061: truy vấn M mà Desktop 2.159 sinh khi nạp một mục của Navigator (QUAN-SAT VM-F1 mục 3), để ghi vào
// `Partition.QueryDefinition` và làm các bước đầu (khoá) của truy vấn trong Query Editor. CSV, Excel, JSON (VM-F7a, `JsonQuery`) và
// Parquet, SQLite (qua ODBC, VM-F7b) và PostgreSQL đã quan sát; named table là [SUY ĐOÁN] (chỉ đúng cú pháp M, chưa đối chiếu Desktop).

import ColumnStore
import Connectors
import Foundation
import MEngine

/// Nguồn của một bảng đã nạp: đủ để dựng lại M và nạp lại (Refresh).
public struct LoadedOrigin: Sendable, Equatable {
    public let kind: SourceKind
    public let location: String
    public let itemName: String
    public let itemKind: SourceItemKind
    /// Câu SQL người dùng nhập (PostgreSQL, mục `Query1`); `nil` cho mục bảng/tệp.
    public let nativeQuery: String?
    /// Tên driver ODBC ghi vào M của nguồn SQLite (T044); `nil` là driver mặc định.
    public let odbcDriver: String?

    public init(kind: SourceKind, location: String, itemName: String, itemKind: SourceItemKind, nativeQuery: String? = nil, odbcDriver: String? = nil) {
        self.kind = kind
        self.location = location
        self.itemName = itemName
        self.itemKind = itemKind
        self.nativeQuery = nativeQuery
        self.odbcDriver = odbcDriver
    }
}

enum StepKind {
    static let source = "source"
    static let navigation = "navigation"
    static let promote = "promote"
    static let type = "type"
    static let custom = "custom"
    /// Bước đọc từ file đã có (Desktop viết), không biết lệnh nào sinh ra.
    static let file = "file"
}

/// Chuỗi kết nối ODBC Desktop ghi cho tệp SQLite. Desktop không có connector SQLite: Get Data ▸ ODBC với driver người dùng cài (VM-F7b quan sát
/// với "Devart ODBC Driver for SQLite"). BI Pro đọc thẳng tệp, tên driver chỉ để Desktop Refresh được: người dùng chọn driver có trên máy
/// Desktop (T044), BI Pro nhớ ở `UserDefaults["bipro.sqlite.odbcDriver"]`.
enum SQLiteODBC {
    static let defaultDriver = "Devart ODBC Driver for SQLite"
    static let defaultsKey = "bipro.sqlite.odbcDriver"
    /// Gợi ý trong ô chọn (vẫn nhập tự do được). `[SUY ĐOÁN]` tên thường gặp của các driver SQLite trên Windows.
    static let commonDrivers = [defaultDriver, "SQLite3 ODBC Driver", "SQLite ODBC Driver", "CData ODBC Driver for SQLite"]

    static func savedDriver(in defaults: UserDefaults = .standard) -> String {
        let value = defaults.string(forKey: defaultsKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? defaultDriver : value
    }

    static func save(driver: String, in defaults: UserDefaults = .standard) {
        let value = driver.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { defaults.removeObject(forKey: defaultsKey) } else { defaults.set(value, forKey: defaultsKey) }
    }

    /// `Driver={tên};Database=đường_dẫn` như Desktop ghi. Thoát theo quy tắc chuỗi kết nối ODBC (`[SUY ĐOÁN]`, Desktop chưa quan sát với tên
    /// lạ): tên driver luôn trong ngoặc nhọn; đường dẫn chỉ bọc ngoặc khi có `;`, `{` hoặc `}`; trong ngoặc, `}` viết thành `}}`.
    static func connectionString(path: String, driver: String = defaultDriver) -> String {
        "Driver=\(braced(driver));Database=\(path.contains(where: { $0 == ";" || $0 == "{" || $0 == "}" }) ? braced(path) : path)"
    }

    /// Tệp bắt đầu bằng chữ ký "SQLite format 3".
    static func isSQLiteFile(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 16)) == Data("SQLite format 3\0".utf8)
    }

    private static func braced(_ value: String) -> String { "{" + value.replacingOccurrences(of: "}", with: "}}") + "}" }

    /// Các cặp khoá=giá trị của chuỗi kết nối ODBC (khoá viết thường). Giá trị trong ngoặc nhọn được mở ngoặc (`}}` thành `}`, `;` bên trong
    /// không tách).
    static func properties(_ connection: String) -> [String: String] {
        var out: [String: String] = [:]
        let chars = Array(connection)
        var i = 0
        while i < chars.count {
            var key = ""
            while i < chars.count, chars[i] != "=", chars[i] != ";" { key.append(chars[i]); i += 1 }
            guard i < chars.count, chars[i] == "=" else { i += 1; continue }
            i += 1
            while i < chars.count, chars[i] == " " { i += 1 }
            var value = ""
            if i < chars.count, chars[i] == "{" {
                i += 1
                while i < chars.count {
                    if chars[i] == "}" {
                        if i + 1 < chars.count, chars[i + 1] == "}" { value.append("}"); i += 2; continue }
                        i += 1
                        break
                    }
                    value.append(chars[i]); i += 1
                }
                while i < chars.count, chars[i] != ";" { i += 1 }
            } else {
                while i < chars.count, chars[i] != ";" { value.append(chars[i]); i += 1 }
                value = value.trimmingCharacters(in: .whitespaces)
            }
            i += 1
            let k = key.trimmingCharacters(in: .whitespaces).lowercased()
            if !k.isEmpty { out[k] = value }
        }
        return out
    }
}

enum SourceQuery {
    /// Các bước đầu của truy vấn: ghi vào file, kết quả bằng đúng bảng đã nạp (`data`).
    static func steps(for origin: LoadedOrigin, data: TableData) -> [QueryStep] {
        let path = StepFactory.quote(origin.location)
        var steps: [QueryStep] = []
        var previous = "Source"
        func add(_ name: String, _ expression: String, _ kind: String) {
            steps.append(QueryStep(name: name, expression: expression, kind: kind))
            previous = name
        }
        func promote() {
            add("Promoted Headers", "Table.PromoteHeaders(\(MQuery.reference(to: previous)), [PromoteAllScalars=true])", StepKind.promote)
        }
        switch origin.kind {
        case .csv:
            let format = csvFormat(origin.location)
            add("Source", "Csv.Document(File.Contents(\(path)),[Delimiter=\(StepFactory.quote(format.delimiter)), Columns=\(data.columns.count), "
                + "Encoding=\(format.encoding), QuoteStyle=QuoteStyle.None])", StepKind.source)
            promote()
        case .excel:
            add("Source", "Excel.Workbook(File.Contents(\(path)), null, true)", StepKind.source)
            let isTable = origin.itemKind == .namedTable
            let name = "\(origin.itemName)_\(isTable ? "Table" : "Sheet")"
            let kind = isTable ? "Table" : "Sheet"
            add(name, "Source{[Item=\(StepFactory.quote(origin.itemName)),Kind=\"\(kind)\"]}[Data]", StepKind.navigation)
            if !isTable { promote() }   // [SUY ĐOÁN] bảng đặt tên đã có tiêu đề, Desktop không thăng cấp.
        case .sqlite:
            // Desktop không có connector SQLite riêng: Get Data ▸ ODBC với driver SQLite (VM-F7b, Devart; driver chọn được, T044), điều hướng theo cấp `main`,
            // không có "Changed Type" (kiểu lấy từ driver).
            let kind = origin.itemKind == .view ? "View" : "Table"
            return [QueryStep(name: "Source", expression: "Odbc.DataSource(\(StepFactory.quote(SQLiteODBC.connectionString(path: origin.location, driver: origin.odbcDriver ?? SQLiteODBC.defaultDriver))), [HierarchicalNavigation=true])",
                              kind: StepKind.source),
                    QueryStep(name: "main_Database", expression: "Source{[Name=\"main\",Kind=\"Database\"]}[Data]", kind: StepKind.navigation),
                    QueryStep(name: "\(origin.itemName)_\(kind)", expression: "main_Database{[Name=\(StepFactory.quote(origin.itemName)),Kind=\"\(kind)\"]}[Data]",
                              kind: StepKind.navigation)]
        case .json:
            // Chuỗi bước tự mở rộng như Desktop (VM-F7a), gồm cả "Changed Type".
            if let plan = try? JsonQuery.plan(location: origin.location) { return plan.steps }
            add("Source", "Json.Document(File.Contents(\(path)))", StepKind.source)
        case .parquet:
            // Desktop (VM-F7a): một bước, kiểu lấy từ lược đồ tệp, không có "Changed Type".
            return [QueryStep(name: "Source", expression: "Parquet.Document(File.Contents(\(path)), [Compression=null, LegacyColumnNameEncoding=false, MaxDepth=null])",
                              kind: StepKind.source)]
        case .postgres:
            return postgresSteps(origin)
        }
        let changes = typeChanges(data)
        if !changes.isEmpty {
            let step = StepFactory.steps(for: .changeType(changes), after: previous, existingNames: Set(steps.map(\.name)))[0]
            steps.append(QueryStep(name: step.name, expression: step.expression, kind: StepKind.type))
        }
        return steps
    }

    /// Desktop (VM-F7b): không có "Changed Type" (kiểu lấy từ máy chủ). Bảng/khung nhìn: `Source = PostgreSQL.Database("máy:cổng", "csdl")`
    /// rồi bước điều hướng tên `lược_đồ_bảng` (Applied Steps hiện "Navigation"); câu SQL: một bước `Value.NativeQuery(…, null, [EnableFolding=true])`.
    static func postgresSteps(_ origin: LoadedOrigin) -> [QueryStep] {
        let address = PostgresAddress(location: origin.location) ?? PostgresAddress(server: origin.location, database: "")
        let database = "PostgreSQL.Database(\(StepFactory.quote(address.server)), \(StepFactory.quote(address.database)))"
        if let sql = origin.nativeQuery {
            return [QueryStep(name: "Source", expression: "Value.NativeQuery(\(database), \(StepFactory.quote(sql)), null, [EnableFolding=true])",
                              kind: StepKind.source)]
        }
        let dot = origin.itemName.firstIndex(of: ".") ?? origin.itemName.startIndex
        let schema = String(origin.itemName[..<dot])
        let table = String(origin.itemName[origin.itemName.index(dot, offsetBy: dot == origin.itemName.endIndex ? 0 : 1)...])
        return [QueryStep(name: "Source", expression: database, kind: StepKind.source),
                QueryStep(name: "\(schema)_\(table)".replacingOccurrences(of: " ", with: "_"),
                          expression: "Source{[Schema=\(StepFactory.quote(schema)),Item=\(StepFactory.quote(table))]}[Data]", kind: StepKind.navigation)]
    }

    /// Kiểu cột như Desktop gán ở "Changed Type". Cột ngày chỉ là `date` khi mọi giá trị nguyên ngày (dò 1000 dòng đầu).
    static func typeChanges(_ data: TableData) -> [ColumnTypeChange] {
        data.columns.map { column in
            let type: MColumnType
            switch column.data.type {
            case .integer: type = .wholeNumber
            case .double: type = .decimal
            case .currency: type = .fixedDecimal
            case .boolean: type = .logical
            case .string: type = .text
            case .dateTime:
                var wholeDays = true
                for row in 0..<min(data.rowCount, 1000) {
                    if case .dateTime(let d) = column.data.value(at: row), d != d.rounded(.down) { wholeDays = false; break }
                }
                type = wholeDays ? .date : .dateTime
            }
            return ColumnTypeChange(column: column.name, type: type)
        }
    }

    /// Dấu phân cách và mã hoá (65001 = UTF-8, 1200 = UTF-16) để ghi `Csv.Document`. Đọc 64 KB đầu; không đọc được thì `,` và UTF-8.
    static func csvFormat(_ location: String) -> (delimiter: String, encoding: Int) {
        guard let handle = FileHandle(forReadingAtPath: location) else { return (",", 65001) }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 65_536)) ?? Data()
        let utf16 = head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF])
        let text = String(data: head, encoding: utf16 ? .utf16 : .utf8) ?? String(decoding: head, as: UTF8.self)
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let best = [",", ";", "\t", "|"].map { d in (d, firstLine.filter { String($0) == d }.count) }
            .reduce(nil as (String, Int)?) { best, candidate in candidate.1 > (best?.1 ?? 0) ? candidate : best }
        return (best?.0 ?? ",", utf16 ? 1200 : 65001)
    }
}
