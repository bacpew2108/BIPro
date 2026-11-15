import Foundation
import ColumnStore
import PBIXKit

public struct ExcelSource: DataSource {
    public struct Options: Sendable, Equatable {
        public var promoteHeaders = true
        public var detectTypes = true
        public var trimLeadingEmpty = false

        public init(
            promoteHeaders: Bool = true,
            detectTypes: Bool = true,
            trimLeadingEmpty: Bool = false
        ) {
            self.promoteHeaders = promoteHeaders
            self.detectTypes = detectTypes
            self.trimLeadingEmpty = trimLeadingEmpty
        }
    }

    public let kind: SourceKind = .excel
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

        let zip: ZipArchive
        do {
            zip = try ZipArchive(url: url)
        } catch {
            throw SourceError.unreadable("Không thể mở file Excel: \(url.lastPathComponent)")
        }

        // 1. Đọc workbook.xml và workbook.xml.rels để lấy danh sách trang tính theo thứ tự
        guard let wbData = try? zip.read("xl/workbook.xml") else {
            throw SourceError.unreadable("Không tìm thấy workbook.xml trong file Excel")
        }

        let wbParser = WorkbookParser()
        let wbXML = XMLParser(data: wbData)
        wbXML.delegate = wbParser
        wbXML.parse()

        var relsMap: [String: String] = [:]
        if let relsData = try? zip.read("xl/_rels/workbook.xml.rels") {
            let relsParser = RelsParser()
            let relsXML = XMLParser(data: relsData)
            relsXML.delegate = relsParser
            relsXML.parse()
            relsMap = relsParser.rels
        }

        var sheetInfos: [ExcelSheetInfo] = []
        for sheet in wbParser.sheets {
            var target = relsMap[sheet.rId] ?? "worksheets/sheet\(sheet.sheetId).xml"
            if !target.hasPrefix("xl/") && !target.hasPrefix("/") {
                target = "xl/" + target
            } else if target.hasPrefix("/") {
                target = String(target.dropFirst())
            }
            sheetInfos.append(ExcelSheetInfo(name: sheet.name, sheetId: sheet.sheetId, rId: sheet.rId, targetPath: target))
        }

        // 2. Tìm các bảng đặt tên trong xl/tables/*.xml
        var tableInfos: [ExcelTableInfo] = []
        let tableEntries = zip.entries.filter { $0.path.hasPrefix("xl/tables/") && $0.path.hasSuffix(".xml") }
        for entry in tableEntries {
            if let tableData = try? zip.read(entry) {
                let tParser = TableXMLParser()
                let tXML = XMLParser(data: tableData)
                tXML.delegate = tParser
                tXML.parse()

                // Tìm sheet chứa table này qua worksheet rels
                var matchingSheetPath = ""
                for sInfo in sheetInfos {
                    let sheetDir = (sInfo.targetPath as NSString).deletingLastPathComponent
                    let sheetFile = (sInfo.targetPath as NSString).lastPathComponent
                    let sheetRelsPath = "\(sheetDir)/_rels/\(sheetFile).rels"
                    if let sRelsData = try? zip.read(sheetRelsPath) {
                        let sRelsParser = RelsParser()
                        let sXML = XMLParser(data: sRelsData)
                        sRelsXMLDelegate: do {
                            sXML.delegate = sRelsParser
                            sXML.parse()
                        }
                        for (_, target) in sRelsParser.rels {
                            if target.contains(entry.path.split(separator: "/").last ?? "") {
                                matchingSheetPath = sInfo.targetPath
                                break
                            }
                        }
                    }
                    if !matchingSheetPath.isEmpty { break }
                }
                if matchingSheetPath.isEmpty {
                    matchingSheetPath = sheetInfos.first?.targetPath ?? ""
                }

                tableInfos.append(ExcelTableInfo(
                    name: tParser.name,
                    displayName: tParser.displayName,
                    ref: tParser.ref,
                    columnNames: tParser.columns,
                    sheetPath: matchingSheetPath
                ))
            }
        }

        // Thứ tự của Navigator trong Desktop 2.159 (quan sát 2026-11-15, `docs/phase-f-evidence/vm-f1/QUAN-SAT.md`):
        // bảng đặt tên trước, rồi các trang tính theo thứ tự chữ cái (không theo thứ tự trong workbook).
        var result: [any SourceItem] = []
        for tInfo in tableInfos.sorted(by: { Self.alphabetical($0.displayName.isEmpty ? $0.name : $0.displayName, $1.displayName.isEmpty ? $1.name : $1.displayName) }) {
            result.append(ExcelTableItem(url: url, info: tInfo, options: options))
        }
        for sInfo in sheetInfos.sorted(by: { Self.alphabetical($0.name, $1.name) }) {
            var item = ExcelSheetItem(url: url, info: sInfo, options: options)
            item.rowCountHint = Self.dimensionRowCount(zip: zip, path: sInfo.targetPath, promoteHeaders: options.promoteHeaders)
            result.append(item)
        }

        return result
    }

    static func alphabetical(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive], range: nil, locale: Locale(identifier: "en_US")) == .orderedAscending
    }

    /// Số dòng dữ liệu của trang, chỉ là gợi ý cho Navigator (không đọc ô). Ưu tiên `<dimension ref="A1:H501"/>` ở đầu XML;
    /// Excel thật có khi bỏ phần tử này (file mẫu không có) nên dự phòng bằng số thứ tự của `<row r="N">` đầu và cuối.
    /// Trang rỗng thì `nil`.
    static func dimensionRowCount(zip: ZipArchive, path: String, promoteHeaders: Bool) -> Int? {
        guard let xml = try? zip.read(path) else { return nil }
        func attribute(_ name: String, after marker: [UInt8], in bytes: Data, from start: Data.Index) -> String? {
            guard let at = bytes.range(of: Data(marker), in: start..<bytes.endIndex) else { return nil }
            let key = Data((name + "=\"").utf8)
            guard let k = bytes.range(of: key, in: at.upperBound..<min(bytes.endIndex, at.upperBound + 200)),
                  let e = bytes.range(of: Data("\"".utf8), in: k.upperBound..<bytes.endIndex) else { return nil }
            return String(decoding: bytes[k.upperBound..<e.lowerBound], as: UTF8.self)
        }
        var rows: Int?
        let head = xml.prefix(4096)
        if let ref = attribute("ref", after: Array("<dimension".utf8), in: head, from: head.startIndex),
           let range = ExcelRefParser.parseRangeRef(ref) {
            rows = range.maxRow - range.minRow + 1
        } else if let first = attribute("r", after: Array("<row".utf8), in: xml, from: xml.startIndex).flatMap(Int.init) {
            // Dòng cuối: `<row` cuối cùng trong file (tìm ngược, nên dòng dài vẫn đúng).
            var last: Int?
            if let at = xml.range(of: Data("<row".utf8), options: .backwards) {
                last = attribute("r", after: Array("<row".utf8), in: xml, from: at.lowerBound).flatMap(Int.init)
            }
            rows = max(1, (last ?? first) - first + 1)
        }
        guard let total = rows else { return nil }
        return promoteHeaders ? max(0, total - 1) : total
    }
}

// MARK: - DataLoader

enum ExcelDataLoader {
    static func loadWorkbookData(url: URL) throws -> (zip: ZipArchive, sharedStrings: [String], isDateStyle: [Int: Bool], date1904: Bool) {
        let zip = try ZipArchive(url: url)

        var sharedStrings: [String] = []
        if let sstData = try? zip.read("xl/sharedStrings.xml") {
            let sstParser = SharedStringsParser()
            let sstXML = XMLParser(data: sstData)
            sstXML.delegate = sstParser
            sstXML.parse()
            sharedStrings = sstParser.strings
        }

        var isDateStyle: [Int: Bool] = [:]
        if let stylesData = try? zip.read("xl/styles.xml") {
            let stylesParser = StylesParser()
            let stylesXML = XMLParser(data: stylesData)
            stylesXML.delegate = stylesParser
            stylesXML.parse()
            isDateStyle = stylesParser.isDateStyle
        }

        var date1904 = false
        if let wbData = try? zip.read("xl/workbook.xml") {
            let wbParser = WorkbookParser()
            let wbXML = XMLParser(data: wbData)
            wbXML.delegate = wbParser
            wbXML.parse()
            date1904 = wbParser.date1904
        }

        return (zip, sharedStrings, isDateStyle, date1904)
    }

    /// [SUY ĐOÁN] Dựng TableData từ ma trận ô Excel theo các quy tắc kiểu dữ liệu của Excel:
    /// ngày → dateTime, logic → boolean, số nguyên → integer, số thực → double, chuỗi → string,
    /// lẫn kiểu → string với số viết dạng bất biến locale.
    static func buildTable(
        grid: [[ExcelCellType?]],
        headers: [String],
        options: ExcelSource.Options
    ) throws -> TableData {
        let rowCount = grid.count
        let colCount = headers.count

        if rowCount == 0 {
            let emptyCols = headers.map { TableColumn(name: $0, data: ColumnBuilder.strings([])) }
            return try TableData(columns: emptyCols)
        }

        var columns: [TableColumn] = []
        var errorMask: [Int: [Int: String]] = [:]

        for col in 0..<colCount {
            var colCells: [ExcelCellType?] = []
            colCells.reserveCapacity(rowCount)
            for row in 0..<rowCount {
                colCells.append(col < grid[row].count ? grid[row][col] : nil)
            }

            var colErrors: [Int: String] = [:]
            for (r, cell) in colCells.enumerated() {
                if case .error(let errCode) = cell {
                    colErrors[r] = "Lỗi ô Excel: \(errCode)"
                }
            }
            if !colErrors.isEmpty {
                errorMask[col] = colErrors
            }

            if !options.detectTypes {
                // Toàn bộ thành chuỗi
                let strValues: [String?] = colCells.map { cell in
                    guard let cell = cell else { return nil }
                    return stringify(cell)
                }
                columns.append(TableColumn(name: headers[col], data: ColumnBuilder.strings(strValues)))
                continue
            }

            var hasDate = false
            var hasBool = false
            var hasInt = false
            var hasDouble = false
            var hasString = false

            for cell in colCells {
                guard let cell = cell else { continue }
                switch cell {
                case .dateTime: hasDate = true
                case .boolean: hasBool = true
                case .integer: hasInt = true
                case .double: hasDouble = true
                case .string: hasString = true
                case .error: break
                }
            }

            let typeCount = (hasDate ? 1 : 0) + (hasBool ? 1 : 0) + ((hasInt || hasDouble) ? 1 : 0) + (hasString ? 1 : 0)

            if typeCount == 0 {
                // Toàn ô trống hoặc lỗi
                columns.append(TableColumn(name: headers[col], data: ColumnBuilder.strings(Array(repeating: nil, count: rowCount))))
            } else if typeCount > 1 {
                // [SUY ĐOÁN] Lẫn kiểu thành string, số viết bất biến locale
                let strValues: [String?] = colCells.map { cell in
                    guard let cell = cell else { return nil }
                    return stringify(cell)
                }
                columns.append(TableColumn(name: headers[col], data: ColumnBuilder.strings(strValues)))
            } else if hasDate {
                let dateValues: [Double?] = colCells.map { cell in
                    if case .dateTime(let d) = cell { return d }
                    return nil
                }
                columns.append(TableColumn(name: headers[col], data: ColumnBuilder.dateTimes(dateValues)))
            } else if hasBool {
                let boolValues: [Bool?] = colCells.map { cell in
                    if case .boolean(let b) = cell { return b }
                    return nil
                }
                columns.append(TableColumn(name: headers[col], data: ColumnBuilder.booleans(boolValues)))
            } else if hasInt || hasDouble {
                if hasDouble {
                    let dblValues: [Double?] = colCells.map { cell in
                        if case .double(let d) = cell { return d }
                        if case .integer(let i) = cell { return Double(i) }
                        return nil
                    }
                    columns.append(TableColumn(name: headers[col], data: ColumnBuilder.doubles(dblValues)))
                } else {
                    let intValues: [Int64?] = colCells.map { cell in
                        if case .integer(let i) = cell { return i }
                        return nil
                    }
                    columns.append(TableColumn(name: headers[col], data: ColumnBuilder.integers(intValues)))
                }
            } else {
                let strValues: [String?] = colCells.map { cell in
                    if case .string(let s) = cell { return s }
                    return nil
                }
                columns.append(TableColumn(name: headers[col], data: ColumnBuilder.strings(strValues)))
            }
        }

        return try TableData(columns: columns, errorMask: errorMask)
    }

    private static func stringify(_ cell: ExcelCellType) -> String? {
        switch cell {
        case .string(let s): return s
        case .integer(let i): return "\(i)"
        case .double(let d):
            return (floor(d) == d && d >= Double(Int64.min) && d <= Double(Int64.max)) ? "\(Int64(d))" : "\(d)"
        case .dateTime(let d): return "\(d)"
        case .boolean(let b): return b ? "true" : "false"
        case .error: return nil
        }
    }
}

// MARK: - ExcelSheetItem

private struct ExcelSheetItem: SourceItem, Sendable {
    let name: String
    let kind: SourceItemKind = .sheet
    let columns: [SourceColumn]? = nil
    var rowCountHint: Int?

    let url: URL
    let info: ExcelSheetInfo
    let options: ExcelSource.Options

    init(url: URL, info: ExcelSheetInfo, options: ExcelSource.Options) {
        self.name = info.name
        self.url = url
        self.info = info
        self.options = options
        self.rowCountHint = nil
    }

    func preview(limit: Int) async throws -> TableData {
        let table = try await loadTable(progress: nil)
        return table.prefix(limit)
    }

    func load(progress: SourceProgress?) async throws -> TableData {
        try await loadTable(progress: progress)
    }

    private func loadTable(progress: SourceProgress?) async throws -> TableData {
        if Task.isCancelled { throw SourceError.cancelled }
        progress?(0.0)

        let (zip, sharedStrings, isDateStyle, date1904) = try ExcelDataLoader.loadWorkbookData(url: url)
        guard let sheetData = try? zip.read(info.targetPath) else {
            throw SourceError.unreadable("Không thể đọc trang tính: \(info.name)")
        }

        let sheetParser = SheetParser(sharedStrings: sharedStrings, isDateStyle: isDateStyle, date1904: date1904)
        let xml = XMLParser(data: sheetData)
        xml.delegate = sheetParser
        xml.parse()

        if Task.isCancelled { throw SourceError.cancelled }

        let cells = sheetParser.cells
        if cells.isEmpty {
            return try TableData(columns: [])
        }

        let minCol: Int
        let minRow: Int
        let maxCol: Int
        let maxRow: Int

        if options.trimLeadingEmpty {
            minCol = cells.map(\.col).min() ?? 0
            minRow = cells.map(\.row).min() ?? 0
            maxCol = cells.map(\.col).max() ?? 0
            maxRow = cells.map(\.row).max() ?? 0
        } else {
            minCol = 0
            minRow = 0
            maxCol = cells.map(\.col).max() ?? 0
            maxRow = cells.map(\.row).max() ?? 0
        }

        let width = maxCol - minCol + 1
        let height = maxRow - minRow + 1

        var cellMap: [Int: [Int: ExcelCellType]] = [:]
        for cell in cells where cell.col >= minCol && cell.col <= maxCol && cell.row >= minRow && cell.row <= maxRow {
            let r = cell.row - minRow
            let c = cell.col - minCol
            if cellMap[r] == nil { cellMap[r] = [:] }
            cellMap[r]![c] = cell.value
        }

        let headers: [String]
        let dataStartRow: Int

        if options.promoteHeaders {
            var rawHeaders: [String?] = []
            for c in 0..<width {
                if let val = cellMap[0]?[c] {
                    switch val {
                    case .string(let s): rawHeaders.append(s)
                    case .integer(let i): rawHeaders.append("\(i)")
                    case .double(let d): rawHeaders.append("\(d)")
                    default: rawHeaders.append(nil)
                    }
                } else {
                    rawHeaders.append(nil)
                }
            }
            headers = ColumnNaming.unique(rawHeaders)
            dataStartRow = 1
        } else {
            headers = (1...width).map { "Column\($0)" }
            dataStartRow = 0
        }

        var grid: [[ExcelCellType?]] = []
        if dataStartRow < height {
            for r in dataStartRow..<height {
                var rowCells: [ExcelCellType?] = []
                rowCells.reserveCapacity(width)
                for c in 0..<width {
                    rowCells.append(cellMap[r]?[c])
                }
                grid.append(rowCells)
            }
        }

        let table = try ExcelDataLoader.buildTable(grid: grid, headers: headers, options: options)
        progress?(1.0)
        return table
    }
}

// MARK: - ExcelTableItem

private struct ExcelTableItem: SourceItem, Sendable {
    let name: String
    let kind: SourceItemKind = .namedTable
    let columns: [SourceColumn]?
    let rowCountHint: Int?

    let url: URL
    let info: ExcelTableInfo
    let options: ExcelSource.Options

    init(url: URL, info: ExcelTableInfo, options: ExcelSource.Options) {
        self.name = info.displayName.isEmpty ? info.name : info.displayName
        self.url = url
        self.info = info
        self.options = options
        self.columns = info.columnNames.map { SourceColumn(name: $0, type: .string) }
        if let range = ExcelRefParser.parseRangeRef(info.ref) {
            let totalRows = range.maxRow - range.minRow + 1
            self.rowCountHint = options.promoteHeaders ? max(0, totalRows - 1) : totalRows
        } else {
            self.rowCountHint = nil
        }
    }

    func preview(limit: Int) async throws -> TableData {
        let table = try await loadTable(progress: nil)
        return table.prefix(limit)
    }

    func load(progress: SourceProgress?) async throws -> TableData {
        try await loadTable(progress: progress)
    }

    private func loadTable(progress: SourceProgress?) async throws -> TableData {
        if Task.isCancelled { throw SourceError.cancelled }
        progress?(0.0)

        guard let bounds = ExcelRefParser.parseRangeRef(info.ref) else {
            throw SourceError.unreadable("Vùng ref không hợp lệ: \(info.ref)")
        }

        let (zip, sharedStrings, isDateStyle, date1904) = try ExcelDataLoader.loadWorkbookData(url: url)
        guard let sheetData = try? zip.read(info.sheetPath) else {
            throw SourceError.unreadable("Không thể đọc sheet chứa bảng: \(info.sheetPath)")
        }

        let sheetParser = SheetParser(sharedStrings: sharedStrings, isDateStyle: isDateStyle, date1904: date1904)
        let xml = XMLParser(data: sheetData)
        xml.delegate = sheetParser
        xml.parse()

        if Task.isCancelled { throw SourceError.cancelled }

        let width = bounds.maxCol - bounds.minCol + 1
        let height = bounds.maxRow - bounds.minRow + 1

        var cellMap: [Int: [Int: ExcelCellType]] = [:]
        for cell in sheetParser.cells where cell.col >= bounds.minCol && cell.col <= bounds.maxCol && cell.row >= bounds.minRow && cell.row <= bounds.maxRow {
            let r = cell.row - bounds.minRow
            let c = cell.col - bounds.minCol
            if cellMap[r] == nil { cellMap[r] = [:] }
            cellMap[r]![c] = cell.value
        }

        // [SUY ĐOÁN] Bảng đặt tên: cột lấy tên từ tableColumn của bảng
        let headers: [String]
        if info.columnNames.count == width {
            headers = info.columnNames
        } else {
            var rawHeaders: [String?] = []
            for c in 0..<width {
                if let val = cellMap[0]?[c], case .string(let s) = val {
                    rawHeaders.append(s)
                } else {
                    rawHeaders.append(nil)
                }
            }
            headers = ColumnNaming.unique(rawHeaders)
        }

        let dataStartRow = options.promoteHeaders ? 1 : 0
        var grid: [[ExcelCellType?]] = []
        if dataStartRow < height {
            for r in dataStartRow..<height {
                var rowCells: [ExcelCellType?] = []
                rowCells.reserveCapacity(width)
                for c in 0..<width {
                    rowCells.append(cellMap[r]?[c])
                }
                grid.append(rowCells)
            }
        }

        let table = try ExcelDataLoader.buildTable(grid: grid, headers: headers, options: options)
        progress?(1.0)
        return table
    }
}
