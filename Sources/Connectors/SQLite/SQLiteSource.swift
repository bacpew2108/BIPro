import Foundation
import ColumnStore
#if canImport(Darwin)
import Darwin
#endif
import SQLite3

// Thứ tự như Navigator của Desktop qua ODBC (VM-F7b): khung nhìn trước, rồi bảng theo tên.
public struct SQLiteSource: DataSource {
    public let kind: SourceKind = .sqlite
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func items() async throws -> [any SourceItem] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SourceError.unreadable("File không tồn tại: \(url.lastPathComponent)")
        }

        var db: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK, let db = db else {
            if let db = db { sqlite3_close(db) }
            throw SourceError.unreadable("Không thể mở cơ sở dữ liệu SQLite: \(url.lastPathComponent)")
        }
        defer { sqlite3_close(db) }

        let query = """
        SELECT type, name FROM sqlite_master
        WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'
        ORDER BY CASE type WHEN 'view' THEN 0 ELSE 1 END, name;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SourceError.unreadable("Lỗi truy vấn sqlite_master: \(msg)")
        }
        defer { sqlite3_finalize(stmt) }

        var items: [SQLiteItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let typeStr = sqlite3_column_text(stmt, 0),
                  let nameStr = sqlite3_column_text(stmt, 1) else { continue }
            let itemType = String(cString: typeStr)
            let itemName = String(cString: nameStr)

            let kind: SourceItemKind = (itemType == "view") ? .view : .table
            let (columns, rowCountHint) = try fetchMetadata(db: db, name: itemName, kind: kind)
            items.append(SQLiteItem(name: itemName, kind: kind, url: url, columns: columns, rowCountHint: rowCountHint))
        }

        return items
    }

    private func fetchMetadata(db: OpaquePointer, name: String, kind: SourceItemKind) throws -> ([SourceColumn], Int?) {
        let quotedName = SQLiteHelper.quoteIdentifier(name)

        // Lấy danh sách cột và kiểu khai báo qua PRAGMA table_info
        let pragmaSQL = "PRAGMA table_info(\(quotedName));"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, pragmaSQL, -1, &stmt, nil) == SQLITE_OK else {
            return ([], nil)
        }
        defer { sqlite3_finalize(stmt) }

        var columns: [SourceColumn] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let colNamePtr = sqlite3_column_text(stmt, 1) else { continue }
            let colName = String(cString: colNamePtr)
            let colType: String
            if let colTypePtr = sqlite3_column_text(stmt, 2) {
                colType = String(cString: colTypePtr)
            } else {
                colType = ""
            }
            let daxType = SQLiteHelper.mapDeclaredType(colType)
            columns.append(SourceColumn(name: colName, type: daxType))
        }

        // Số dòng lúc liệt kê (T108, SC-003): `MAX(rowid)` tra cây B nên rẻ; chỉ khi nó không quá `countLimit` mới đếm đúng bằng COUNT(*)
        // (quét tối đa chừng đó dòng). Bảng lớn hơn, khung nhìn và bảng WITHOUT ROWID không có số dòng lúc liệt kê; nạp cả bảng mới đếm.
        let countHint = kind == .table ? SQLiteHelper.cheapRowCount(db: db, quotedName: quotedName, limit: SQLiteHelper.countLimit) : nil

        return (columns, countHint)
    }
}

enum SQLiteHelper {
    /// Bảng có `MAX(rowid)` không quá ngưỡng này mới được đếm lúc liệt kê (T108).
    static let countLimit = 100_000

    /// Số dòng của bảng. Với `limit`: chỉ đếm khi `MAX(rowid)` không quá `limit` (bảng WITHOUT ROWID không có rowid: nil), để không
    /// quét bảng lớn; nil là không giới hạn. Lỗi trả nil (số dòng chỉ để hiển thị và báo tiến độ).
    static func cheapRowCount(db: OpaquePointer, quotedName: String, limit: Int?) -> Int? {
        func scalar(_ sql: String) -> Int64?? {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { sqlite3_finalize(stmt); return nil }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return .some(sqlite3_column_type(stmt, 0) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 0))
        }
        if let limit {
            guard let maxRowid = scalar("SELECT MAX(rowid) FROM \(quotedName);") else { return nil }
            if let maxRowid, maxRowid > Int64(limit) { return nil }
        }
        guard let count = scalar("SELECT COUNT(*) FROM \(quotedName);"), let count else { return nil }
        return Int(count)
    }

    /// [SUY ĐOÁN] Trích dẫn tên bảng/cột SQLite: nhân đôi dấu ngoặc kép
    static func quoteIdentifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// [SUY ĐOÁN] Ánh xạ kiểu SQLite theo chuỗi con của kiểu khai báo (không phân biệt hoa thường):
    /// chứa INT → integer; REAL, FLOA, DOUB, NUMERIC, DECIMAL → double; BOOL → boolean;
    /// DATE, TIME → dateTime; còn lại → string.
    static func mapDeclaredType(_ declared: String) -> DAXType {
        let u = declared.uppercased()
        if u.contains("INT") {
            return .integer
        }
        if u.contains("REAL") || u.contains("FLOA") || u.contains("DOUB") || u.contains("NUMERIC") || u.contains("DECIMAL") {
            return .double
        }
        if u.contains("BOOL") {
            return .boolean
        }
        if u.contains("DATE") || u.contains("TIME") {
            return .dateTime
        }
        return .string
    }
}

private struct SQLiteItem: SourceItem, Sendable {
    let name: String
    let kind: SourceItemKind
    let url: URL
    let columns: [SourceColumn]?
    let rowCountHint: Int?

    func preview(limit: Int) async throws -> TableData {
        try await readData(limit: limit, progress: nil)
    }

    func load(progress: SourceProgress?) async throws -> TableData {
        try await readData(limit: nil, progress: progress)
    }

    private func readData(limit: Int?, progress: SourceProgress?) async throws -> TableData {
        if Task.isCancelled { throw SourceError.cancelled }

        var db: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK, let db = db else {
            if let db = db { sqlite3_close(db) }
            throw SourceError.unreadable("Không thể mở cơ sở dữ liệu SQLite: \(url.lastPathComponent)")
        }
        defer { sqlite3_close(db) }

        let quotedName = SQLiteHelper.quoteIdentifier(name)

        // Kiểm tra cấu trúc cột và từ chối BLOB
        let pragmaSQL = "PRAGMA table_info(\(quotedName));"
        var pStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, pragmaSQL, -1, &pStmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SourceError.unreadable("Lỗi đọc schema: \(msg)")
        }

        var colInfos: [(name: String, type: DAXType)] = []
        while sqlite3_step(pStmt) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(pStmt, 1) else { continue }
            let cName = String(cString: namePtr)
            let cType = sqlite3_column_text(pStmt, 2).map { String(cString: $0) } ?? ""
            if cType.uppercased().contains("BLOB") {
                sqlite3_finalize(pStmt)
                throw SourceError.unsupported("cột BLOB '\(cName)' không được hỗ trợ")
            }
            let daxType = SQLiteHelper.mapDeclaredType(cType)
            colInfos.append((cName, daxType))
        }
        sqlite3_finalize(pStmt)

        if colInfos.isEmpty {
            return try TableData(columns: [])
        }

        let selectCols = colInfos.map { SQLiteHelper.quoteIdentifier($0.name) }.joined(separator: ", ")
        var selectSQL = "SELECT \(selectCols) FROM \(quotedName)"
        if let limit = limit {
            selectSQL += " LIMIT \(limit)"
        }
        selectSQL += ";"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SourceError.unreadable("Lỗi thực thi truy vấn: \(msg)")
        }
        defer { sqlite3_finalize(stmt) }

        progress?(0.0)
        // Tiến độ khi nạp cả bảng: số dòng lúc liệt kê, không có (bảng lớn) thì đếm bây giờ (rẻ so với đọc cả bảng). Khung nhìn không đếm.
        let total = rowCountHint ?? (limit == nil && progress != nil && kind == .table
            ? SQLiteHelper.cheapRowCount(db: db, quotedName: quotedName, limit: nil) : nil)

        // Thu thập giá trị theo từng cột
        var intBuilders: [[Int64?]] = []
        var doubleBuilders: [[Double?]] = []
        var boolBuilders: [[Bool?]] = []
        var dateBuilders: [[Double?]] = []
        var strBuilders: [[String?]] = []
        var errorMask: [Int: [Int: String]] = [:]

        for info in colInfos {
            switch info.type {
            case .integer:
                intBuilders.append([])
            case .double, .currency:
                doubleBuilders.append([])
            case .boolean:
                boolBuilders.append([])
            case .dateTime:
                dateBuilders.append([])
            case .string:
                strBuilders.append([])
            }
        }

        var rowIdx = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            if rowIdx % 1000 == 0 && Task.isCancelled {
                sqlite3_interrupt(db)
                throw SourceError.cancelled
            }

            var intIdx = 0
            var dblIdx = 0
            var boolIdx = 0
            var dateIdx = 0
            var strIdx = 0

            for col in 0..<colInfos.count {
                let colType = colInfos[col].type
                let isNull = sqlite3_column_type(stmt, Int32(col)) == SQLITE_NULL

                switch colType {
                case .integer:
                    if isNull {
                        intBuilders[intIdx].append(nil)
                    } else {
                        intBuilders[intIdx].append(sqlite3_column_int64(stmt, Int32(col)))
                    }
                    intIdx += 1

                case .double, .currency:
                    if isNull {
                        doubleBuilders[dblIdx].append(nil)
                    } else {
                        doubleBuilders[dblIdx].append(sqlite3_column_double(stmt, Int32(col)))
                    }
                    dblIdx += 1

                case .boolean:
                    if isNull {
                        boolBuilders[boolIdx].append(nil)
                    } else {
                        let ctype = sqlite3_column_type(stmt, Int32(col))
                        if ctype == SQLITE_INTEGER {
                            boolBuilders[boolIdx].append(sqlite3_column_int64(stmt, Int32(col)) != 0)
                        } else {
                            let text = String(cString: sqlite3_column_text(stmt, Int32(col)))
                            boolBuilders[boolIdx].append(text.caseInsensitiveCompare("true") == .orderedSame || text == "1")
                        }
                    }
                    boolIdx += 1

                case .dateTime:
                    if isNull {
                        dateBuilders[dateIdx].append(nil)
                    } else {
                        let text = String(cString: sqlite3_column_text(stmt, Int32(col)))
                        if let serial = DateHelper.parseDateTime(text) {
                            dateBuilders[dateIdx].append(serial)
                        } else {
                            dateBuilders[dateIdx].append(nil)
                            if errorMask[col] == nil { errorMask[col] = [:] }
                            errorMask[col]![rowIdx] = "Không thể chuyển '\(text)' sang ngày giờ"
                        }
                    }
                    dateIdx += 1

                case .string:
                    if isNull {
                        strBuilders[strIdx].append(nil)
                    } else {
                        strBuilders[strIdx].append(String(cString: sqlite3_column_text(stmt, Int32(col))))
                    }
                    strIdx += 1
                }
            }

            rowIdx += 1
            if let hint = total, hint > 0, rowIdx % 500 == 0 {
                let p = min(0.99, Double(rowIdx) / Double(hint))
                progress?(p)
            }
        }

        var tableCols: [TableColumn] = []
        tableCols.reserveCapacity(colInfos.count)

        var intIdx = 0
        var dblIdx = 0
        var boolIdx = 0
        var dateIdx = 0
        var strIdx = 0

        for col in 0..<colInfos.count {
            let name = colInfos[col].name
            let colType = colInfos[col].type
            let colData: ColumnData
            switch colType {
            case .integer:
                colData = ColumnBuilder.integers(intBuilders[intIdx])
                intIdx += 1
            case .double, .currency:
                colData = ColumnBuilder.doubles(doubleBuilders[dblIdx])
                dblIdx += 1
            case .boolean:
                colData = ColumnBuilder.booleans(boolBuilders[boolIdx])
                boolIdx += 1
            case .dateTime:
                colData = ColumnBuilder.dateTimes(dateBuilders[dateIdx])
                dateIdx += 1
            case .string:
                colData = ColumnBuilder.strings(strBuilders[strIdx])
                strIdx += 1
            }
            tableCols.append(TableColumn(name: name, data: colData))
        }

        progress?(1.0)
        return try TableData(columns: tableCols, errorMask: errorMask)
    }
}
