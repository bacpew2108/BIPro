import Foundation
import ColumnStore

public struct CSVSource: DataSource {
    public struct Options: Sendable, Equatable {
        public var delimiter: Character?        // nil = tự dò trong {",", ";", "\t", "|"}
        public var encoding: String.Encoding?   // nil = tự dò (BOM UTF-8/UTF-16, rồi UTF-8, rồi Windows-1252)
        public var promoteHeaders = true        // hàng đầu thành tên cột; false = Column1, Column2, ...
        public var detectTypes = true           // false = mọi cột là chuỗi

        public init(
            delimiter: Character? = nil,
            encoding: String.Encoding? = nil,
            promoteHeaders: Bool = true,
            detectTypes: Bool = true
        ) {
            self.delimiter = delimiter
            self.encoding = encoding
            self.promoteHeaders = promoteHeaders
            self.detectTypes = detectTypes
        }
    }

    public let kind: SourceKind = .csv
    public let url: URL
    public let options: Options

    public init(url: URL, options: Options = Options()) {
        self.url = url
        self.options = options
    }

    public func items() async throws -> [any SourceItem] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SourceError.unreadable("File không tồn tại: \(url.lastPathComponent)")
        }
        let name = url.deletingPathExtension().lastPathComponent
        return [CSVItem(name: name, url: url, options: options)]
    }
}

private struct CSVItem: SourceItem, Sendable {
    let name: String
    let kind: SourceItemKind = .file
    let columns: [SourceColumn]? = nil
    let rowCountHint: Int? = nil

    let url: URL
    let options: CSVSource.Options

    func preview(limit: Int) async throws -> TableData {
        try await parse(limit: limit, progress: nil)
    }

    func load(progress: SourceProgress?) async throws -> TableData {
        try await parse(limit: nil, progress: progress)
    }

    private func parse(limit: Int?, progress: SourceProgress?) async throws -> TableData {
        if Task.isCancelled { throw SourceError.cancelled }

        let detection = try CSVParser.detectEncoding(url: url, preferred: options.encoding)
        let delimiter: Character
        if let d = options.delimiter {
            delimiter = d
        } else {
            delimiter = try CSVParser.detectDelimiter(url: url, encoding: detection.encoding, bomLength: detection.bomLength)
        }

        let readLimit = limit.map { options.promoteHeaders ? ($0 + 1) : $0 }
        let allRows = try await CSVParser.readRows(
            url: url,
            delimiter: delimiter,
            encoding: detection.encoding,
            bomLength: detection.bomLength,
            limit: readLimit,
            progress: progress
        )

        if allRows.isEmpty {
            throw SourceError.empty
        }

        let headers: [String]
        var dataRows: [[String?]]

        if options.promoteHeaders {
            let rawHeaders = allRows[0]
            headers = ColumnNaming.unique(rawHeaders)
            dataRows = Array(allRows.dropFirst())
            if let limit = limit, dataRows.count > limit {
                dataRows = Array(dataRows.prefix(limit))
            }
            for (i, row) in dataRows.enumerated() {
                if row.count > headers.count {
                    throw SourceError.unreadable("Dòng \(i + 2) có nhiều cột hơn tiêu đề (\(row.count) so với \(headers.count))")
                } else if row.count < headers.count {
                    dataRows[i].append(contentsOf: repeatElement(nil, count: headers.count - row.count))
                }
            }
        } else {
            let numCols = allRows.first?.count ?? 0
            headers = (1...numCols).map { "Column\($0)" }
            dataRows = allRows
            if let limit = limit, dataRows.count > limit {
                dataRows = Array(dataRows.prefix(limit))
            }
            for (i, row) in dataRows.enumerated() {
                if row.count > headers.count {
                    throw SourceError.unreadable("Dòng \(i + 1) có nhiều cột hơn tiêu đề (\(row.count) so với \(headers.count))")
                } else if row.count < headers.count {
                    dataRows[i].append(contentsOf: repeatElement(nil, count: headers.count - row.count))
                }
            }
        }

        if dataRows.isEmpty {
            // File chỉ có tiêu đề → bảng 0 dòng, kiểu cột string
            let emptyCols = headers.map { TableColumn(name: $0, data: ColumnBuilder.strings([])) }
            return try TableData(columns: emptyCols)
        }

        var tableCols: [TableColumn] = []
        tableCols.reserveCapacity(headers.count)
        var errorMask: [Int: [Int: String]] = [:]

        for colIdx in 0..<headers.count {
            let colStrings = dataRows.map { $0[colIdx] }
            if options.detectTypes {
                let (data, errors) = ColumnTypeDetector.column(from: colStrings, name: headers[colIdx])
                tableCols.append(TableColumn(name: headers[colIdx], data: data))
                if !errors.isEmpty {
                    errorMask[colIdx] = errors
                }
            } else {
                let data = ColumnBuilder.strings(colStrings)
                tableCols.append(TableColumn(name: headers[colIdx], data: data))
            }
        }

        return try TableData(columns: tableCols, errorMask: errorMask)
    }
}
