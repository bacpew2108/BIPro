// Phase F (T063): hàm nguồn của M cho truy vấn đọc từ file: `File.Contents`, `Csv.Document`, `Excel.Workbook`. Gắn vào `MEnvironment.bindings`
// (kiểm trước thư viện) để "Refresh" nạp lại dữ liệu thật từ tệp nguồn và để truy vấn tắt Enable load xem trước được.
//
// - `File.Contents(path)` trả đường dẫn (text) sau khi kiểm tệp có tồn tại; không có kiểu nhị phân trong M của BI Pro. Tệp mất, đổi chỗ hoặc
//   nằm trên máy khác (đường dẫn Windows của file Desktop) thì báo `DataSource.Error` tiếng Việt kèm đường dẫn.
// - `Csv.Document(path, [Delimiter, Encoding, …])`: mọi cột là text tên `Column1…` (Desktop; bước "Promoted Headers" và "Changed Type" lo phần còn lại).
// - `Excel.Workbook(path, useHeaders, _)`: bảng `Name, Data, Item, Kind, Hidden`; `Data` là bảng lồng của từng trang tính/bảng đặt tên, đọc đủ
//   mọi mục một lần ([SUY ĐOÁN] ô lẫn kiểu thành text vì `TableData` chưa có cột `any`).
// - `Json.Document(path)` (T088): đọc tệp JSON, giữ thứ tự khoá. `Parquet.Document(path, options)` (T089). SQLite qua `Odbc.DataSource`, PostgreSQL (T092, T093).

import ColumnStore
import Connectors
import Foundation
import MEngine

enum SourceFunctions {
    /// Hàm nguồn dạng giá trị M, để gộp vào `MEnvironment.bindings`.
    static var bindings: [String: MValue] { bindings(credentials: .shared) }

    /// Như `bindings`, với kho thông tin đăng nhập riêng cho nguồn cơ sở dữ liệu (test dùng kho tạm).
    static func bindings(credentials: CredentialVault) -> [String: MValue] {
        let postgres = postgresDatabase(credentials)
        return [fileContents.name: .function(fileContents), csvDocument.name: .function(csvDocument), excelWorkbook.name: .function(excelWorkbook),
                jsonDocument.name: .function(jsonDocument), parquetDocument.name: .function(parquetDocument),
                postgres.name: .function(postgres), nativeQuery.name: .function(nativeQuery), odbcDataSource.name: .function(odbcDataSource)]
    }

    // MARK: Odbc.DataSource (SQLite)

    /// `Odbc.DataSource("Driver={…SQLite…};Database=đường_dẫn", [HierarchicalNavigation=true])` (VM-F7b): BI Pro không có ODBC; với driver
    /// SQLite thì đọc thẳng tệp bằng `SQLiteSource`, bất kể tên driver (T044). Có HierarchicalNavigation: một dòng `main` (Kind "Database") chứa bảng điều hướng
    /// `Name, Data, Kind` ("Table"/"View"); không có thì trả thẳng bảng điều hướng đó [SUY ĐOÁN]. `Data` chỉ đọc khi truy cập. Driver khác báo chưa hỗ trợ.
    static let odbcDataSource = MFunction(
        name: "Odbc.DataSource", parameters: [MParameter(name: "connectionString"), MParameter(name: "options", isOptional: true)], observed: true
    ) { args in
        guard case .text(let connection) = args[0] else { throw MError.expression("Odbc.DataSource: chuỗi kết nối phải là text") }
        let properties = SQLiteODBC.properties(connection)
        let driver = properties["driver"] ?? (properties["dsn"].map { "DSN \($0)" } ?? "không rõ")
        let unsupported = MError(reason: "DataSource.Error",
                                 message: "Chưa hỗ trợ ODBC driver \(driver): BI Pro chỉ đọc được tệp SQLite qua chuỗi kết nối có Database=đường_dẫn.")
        guard let path = properties["database"] ?? properties["data source"] else { throw unsupported }
        guard FileManager.default.fileExists(atPath: path) else {
            throw MError(reason: "DataSource.Error",
                         message: "Không tìm thấy tệp SQLite \"\(path)\". Tệp có thể đã bị xoá, đổi tên hoặc nằm trên máy khác.", detail: path)
        }
        // T044: tên driver tuỳ máy (Devart, SQLite3 ODBC Driver…); BI Pro đọc thẳng tệp nên chỉ cần tệp là SQLite thật.
        guard SQLiteODBC.isSQLiteFile(path) else { throw unsupported }
        var hierarchical = false
        if case .record(let fields) = args[1], case .logical(let flag)? = fields.first(where: { $0.name == "HierarchicalNavigation" })?.value {
            hierarchical = flag
        }
        let items = try blocking { try await SQLiteSource(url: URL(fileURLWithPath: path)).items() }
        var cells: [Int: any Sendable] = [:]
        for (row, item) in items.enumerated() {
            cells[row] = MDeferred(tag: nil) { .table(try blocking { try await item.load(progress: nil) }) }
        }
        let tables = try TableData(columns: [
            TableColumn(name: "Name", data: ColumnBuilder.strings(items.map(\.name))),
            TableColumn(name: "Data", data: ColumnBuilder.strings(Array(repeating: "Table", count: items.count))),
            TableColumn(name: "Kind", data: ColumnBuilder.strings(items.map { $0.kind == .view ? "View" : "Table" })),
        ], structured: [1: cells])
        guard hierarchical else { return .table(tables) }
        return .table(try TableData(columns: [
            TableColumn(name: "Name", data: ColumnBuilder.strings(["main"])),
            TableColumn(name: "Data", data: ColumnBuilder.strings(["Table"])),
            TableColumn(name: "Kind", data: ColumnBuilder.strings(["Database"])),
        ], structured: [1: [0: MValue.table(tables)]]))
    }

    // MARK: PostgreSQL.Database, Value.NativeQuery

    /// Mục đích của ô `Data` trễ trong bảng điều hướng PostgreSQL: địa chỉ và thông tin để `Value.NativeQuery` chạy câu SQL trên cùng máy chủ.
    struct PostgresTarget: Sendable {
        let address: PostgresAddress
        let credential: PostgresCredential
    }

    /// `PostgreSQL.Database("máy:cổng", "csdl", [Query=…])` (VM-F7b): bảng điều hướng `Name, Data, Schema, Item, Kind` (khung nhìn trước,
    /// như Navigator); `Data` chỉ đọc khi truy cập (`MDeferred`). Có tuỳ chọn `Query` thì trả thẳng kết quả câu SQL. Thông tin đăng nhập
    /// theo máy chủ từ Keychain/phiên; thiếu thì báo lỗi, không bao giờ đọc mật khẩu từ M.
    static func postgresDatabase(_ credentials: CredentialVault) -> MFunction {
        MFunction(name: "PostgreSQL.Database",
                  parameters: [MParameter(name: "server"), MParameter(name: "database"), MParameter(name: "options", isOptional: true)],
                  observed: true) { args in
            guard case .text(let server) = args[0], case .text(let database) = args[1] else {
                throw MError.expression("PostgreSQL.Database: máy chủ và cơ sở dữ liệu phải là text")
            }
            let address = PostgresAddress(server: server, database: database)
            guard let credential = credentials.credential(for: address.server) else {
                throw MError(reason: "DataSource.Error",
                             message: "Cần thông tin đăng nhập để kết nối tới máy chủ PostgreSQL \(address.server). Hãy mở Get Data ▸ PostgreSQL để nhập.")
            }
            var query: String?
            if case .record(let fields) = args[2], case .text(let sql)? = fields.first(where: { $0.name == "Query" })?.value { query = sql }
            if let query { return try runQuery(PostgresTarget(address: address, credential: credential), sql: query) }
            let items = try blocking { try await PostgresSource(address: address, credential: credential).items() }
            let tables = items.compactMap { $0 as? PostgresItem }
            var schemas: [String] = [], names: [String] = [], kinds: [String] = []
            var cells: [Int: any Sendable] = [:]
            for (row, item) in tables.enumerated() {
                guard case .table(let schema, let name, let isView) = item.target else { continue }
                schemas.append(schema)
                names.append(name)
                kinds.append(isView ? "View" : "Table")
                cells[row] = MDeferred(tag: PostgresTarget(address: address, credential: credential)) {
                    .table(try blocking { try await item.load(progress: nil) })
                }
            }
            let columns = [
                TableColumn(name: "Name", data: ColumnBuilder.strings(names)),
                TableColumn(name: "Data", data: ColumnBuilder.strings(Array(repeating: "Table", count: names.count))),
                TableColumn(name: "Schema", data: ColumnBuilder.strings(schemas)),
                TableColumn(name: "Item", data: ColumnBuilder.strings(names)),
                TableColumn(name: "Kind", data: ColumnBuilder.strings(kinds)),
            ]
            return .table(try TableData(columns: columns, structured: [1: cells]))
        }
    }

    /// `Value.NativeQuery(PostgreSQL.Database(…), "sql", null, [EnableFolding=true])`: chạy câu SQL trên máy chủ của bảng điều hướng.
    /// Tham số câu lệnh chưa hỗ trợ; tuỳ chọn `EnableFolding` nhận nhưng không đổi kết quả.
    static let nativeQuery = MFunction(
        name: "Value.NativeQuery",
        parameters: [MParameter(name: "target"), MParameter(name: "query"), MParameter(name: "parameters", isOptional: true),
                     MParameter(name: "options", isOptional: true)],
        observed: true
    ) { args in
        guard case .text(let sql) = args[1] else { throw MError.expression("Value.NativeQuery: câu truy vấn phải là text") }
        if case .null = args[2] {} else if case .record(let fields) = args[2], fields.isEmpty {} else {
            throw MError(reason: "Expression.Error", message: "Value.NativeQuery: chưa hỗ trợ tham số câu lệnh")
        }
        guard case .table(let navigation) = args[0], let dataColumn = navigation.index(ofColumn: "Data"),
              let target = navigation.structured[dataColumn]?.values.lazy.compactMap({ ($0 as? MDeferred)?.tag as? PostgresTarget }).first
        else {
            throw MError(reason: "Expression.Error", message: "Value.NativeQuery: chỉ chạy được trên kết quả của PostgreSQL.Database (có ít nhất một bảng)")
        }
        return try runQuery(target, sql: sql)
    }

    private static func runQuery(_ target: PostgresTarget, sql: String) throws -> MValue {
        .table(try blocking {
            guard let item = try await PostgresSource(address: target.address, credential: target.credential, query: sql).items().first else {
                throw SourceError.empty
            }
            return try await item.load(progress: nil)
        })
    }

    // MARK: File.Contents

    static let fileContents = MFunction(name: "File.Contents", parameters: [MParameter(name: "path"), MParameter(name: "options", isOptional: true)], observed: false) { args in
        guard case .text(let path) = args[0] else { throw MError.expression("File.Contents: đường dẫn phải là text") }
        guard FileManager.default.fileExists(atPath: path) else {
            throw MError(reason: "DataSource.Error",
                         message: "Không tìm thấy tệp nguồn \"\(path)\". Tệp có thể đã bị xoá, đổi tên hoặc nằm trên máy khác.", detail: path)
        }
        return .text(path)
    }

    // MARK: Csv.Document

    static let csvDocument = MFunction(name: "Csv.Document", parameters: [MParameter(name: "source"), MParameter(name: "options", isOptional: true)], observed: false) { args in
        guard case .text(let path) = args[0] else { throw MError.expression("Csv.Document: nguồn phải là kết quả của File.Contents") }
        var delimiter: Character?
        var encoding: String.Encoding?
        if case .record(let fields) = args[1] {
            for field in fields {
                switch (field.name, field.value) {
                case ("Delimiter", .text(let s)): delimiter = s.first
                case ("Encoding", .number(let n)): encoding = stringEncoding(codePage: Int(n))
                default: break
                }
            }
        }
        let options = CSVSource.Options(delimiter: delimiter, encoding: encoding, promoteHeaders: false, detectTypes: false)
        let table = try blocking {
            let source = CSVSource(url: URL(fileURLWithPath: path), options: options)
            guard let item = try await source.items().first else { throw SourceError.empty }
            return try await item.load(progress: nil)
        }
        return .table(table)
    }

    /// Mã trang → `String.Encoding` (65001 UTF-8, 1200 UTF-16, 1252 Windows-1252, 28591 Latin-1, 20127 ASCII); khác thì tự dò.
    private static func stringEncoding(codePage: Int) -> String.Encoding? {
        switch codePage {
        case 65001: .utf8
        case 1200: .utf16LittleEndian
        case 1201: .utf16BigEndian
        case 1252: .windowsCP1252
        case 28591: .isoLatin1
        case 20127: .ascii
        default: nil
        }
    }

    // MARK: Json.Document

    /// `Json.Document(File.Contents(path))`: đọc tệp rồi phân tích (`MJson.parse`, giữ thứ tự khoá). Đối số không phải đường dẫn tệp có thật
    /// thì là văn bản JSON (như `Json.Document` của thư viện).
    static let jsonDocument = MFunction(
        name: "Json.Document", parameters: [MParameter(name: "jsonText"), MParameter(name: "encoding", isOptional: true)], observed: true
    ) { args in
        // Enter Data (T028): `Json.Document(Binary.Decompress(…))` truyền nhị phân.
        if case .binary(let data) = args[0] { return try MJson.parse(data) }
        guard case .text(let text) = args[0] else { throw MError.expression("Json.Document: nguồn phải là kết quả của File.Contents hoặc text") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasPrefix("{"), !trimmed.hasPrefix("["), FileManager.default.fileExists(atPath: text) {
            let data: Data
            do { data = try Data(contentsOf: URL(fileURLWithPath: text)) } catch {
                throw MError(reason: "DataSource.Error", message: "Không đọc được tệp \"\(text)\".", detail: text)
            }
            return try MJson.parse(data)
        }
        return try MJson.parse(Data(text.utf8))
    }

    // MARK: Parquet.Document

    /// `Parquet.Document(File.Contents(path), [Compression, LegacyColumnNameEncoding, MaxDepth])` (T089): bảng của tệp, kiểu theo lược đồ.
    /// Tuỳ chọn của Desktop được nhận nhưng không đổi kết quả (BI Pro tự nhận codec, chỉ đọc lược đồ phẳng).
    static let parquetDocument = MFunction(
        name: "Parquet.Document", parameters: [MParameter(name: "binary"), MParameter(name: "options", isOptional: true)], observed: true
    ) { args in
        guard case .text(let path) = args[0] else { throw MError.expression("Parquet.Document: nguồn phải là kết quả của File.Contents") }
        let table = try blocking {
            try ParquetFile(url: URL(fileURLWithPath: path)).read(rowLimit: nil, progress: nil)
        }
        guard !table.structured.isEmpty else { return .table(table) }
        // Cột lồng (T042): ô struct thành bản ghi M, ô list thành danh sách M (Table.ExpandRecordColumn, Table.ExpandListColumn dùng được).
        var structured: [Int: [Int: any Sendable]] = [:]
        for (column, cells) in table.structured {
            structured[column] = cells.compactMapValues { ($0 as? ParquetValue).map(mValue) }
        }
        return .table(try TableData(columns: table.columns, errorMask: table.errorMask, nested: table.nested, structured: structured))
    }

    static func mValue(_ value: ParquetValue) -> MValue {
        switch value {
        case .null: return .null
        case .record(let fields): return .record(fields.map { MField(name: $0.name, value: mValue($0.value)) })
        case .list(let items): return .list(items.map(mValue))
        case .scalar(let stored):
            switch stored {
            case .blank: return .null
            case .integer(let v): return .number(Double(v))
            case .double(let v): return .number(v)
            case .currency(let v): return .currency(v)
            case .boolean(let v): return .logical(v)
            case .string(let v): return .text(v)
            case .dateTime(let v): return .dateTime(v)
            }
        }
    }

    // MARK: Excel.Workbook

    static let excelWorkbook = MFunction(
        name: "Excel.Workbook", parameters: [MParameter(name: "workbook"), MParameter(name: "useHeaders", isOptional: true), MParameter(name: "delayTypes", isOptional: true)],
        observed: false
    ) { args in
        guard case .text(let path) = args[0] else { throw MError.expression("Excel.Workbook: nguồn phải là kết quả của File.Contents") }
        let useHeaders: Bool
        if case .logical(let flag) = args[1] { useHeaders = flag } else { useHeaders = false }
        let loaded: [(name: String, kind: String, data: TableData)] = try blocking {
            let source = ExcelSource(url: URL(fileURLWithPath: path), options: .init(promoteHeaders: useHeaders, detectTypes: true))
            var out: [(String, String, TableData)] = []
            for item in try await source.items() {
                let data: TableData
                do { data = try await item.load(progress: nil) } catch SourceError.empty { data = try TableData(columns: []) }
                out.append((item.name, item.kind == .namedTable ? "Table" : "Sheet", data))
            }
            return out
        }
        // Cột: Name, Data (bảng lồng), Item, Kind, Hidden (như Desktop).
        let names = loaded.map(\.name)
        let columns = [
            TableColumn(name: "Name", data: ColumnBuilder.strings(names)),
            TableColumn(name: "Data", data: ColumnBuilder.strings(Array(repeating: nil, count: loaded.count))),
            TableColumn(name: "Item", data: ColumnBuilder.strings(names)),
            TableColumn(name: "Kind", data: ColumnBuilder.strings(loaded.map(\.kind))),
            TableColumn(name: "Hidden", data: ColumnBuilder.booleans(Array(repeating: false, count: loaded.count))),
        ]
        return .table(try TableData(columns: columns, nested: [1: loaded.map(\.data)]))
    }

    // MARK: Cầu nối đồng bộ

    private final class Box<T: Sendable>: @unchecked Sendable {
        var result: Result<T, Error>?
    }

    /// Chạy việc bất đồng bộ của Connectors ngay trong hàm M đồng bộ. Bộ chạy M chạy trên hàng đợi GCD riêng (`MCancellation`, T110), nên
    /// chờ ở đây không giữ luồng của pool hợp tác; việc đọc ở một Task riêng chạy trên pool.
    private static func blocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
        let box = Box<T>()
        let done = DispatchSemaphore(value: 0)
        let task = Task.detached(priority: .userInitiated) {
            do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
            done.signal()
        }
        // Huỷ lan sang việc đọc nguồn (lỗi T096): lần chạy M bị huỷ (đóng Query Editor, làm mới khác) thì huỷ Task đọc và trả về ngay,
        // không chờ đọc hết bảng.
        while done.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
            if MCancellation.isCancelled {
                task.cancel()
                throw CancellationError()
            }
        }
        do { return try box.result!.get() } catch let error as SourceError {
            throw MError(reason: "DataSource.Error", message: message(for: error))
        }
    }

    private static func message(for error: SourceError) -> String {
        switch error {
        case .unreadable(let text), .encoding(let text), .unsupported(let text), .authentication(let text), .insecureConnection(let text): text
        case .empty: "Nguồn không có dữ liệu."
        case .cancelled: "Đã huỷ."
        }
    }
}
