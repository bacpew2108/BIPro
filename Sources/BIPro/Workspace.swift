import AppKit
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit

/// Everything decoded from one `.pbix`. Immutable after load except for lazy caches.
final class Workspace: @unchecked Sendable {
    let pbix: PBIXFile
    let report: ReportDefinition
    let theme: ReportTheme
    let abf: ABFBackup?
    /// Mô hình hiệu lực (gốc cộng `ModelEdits` của phiên); nil khi file không có mô hình.
    var metadata: ModelMetadata? { runtime?.metadata }
    /// Giữ mô hình hiệu lực và engine (Phase E). nil khi file không có mô hình đọc được.
    let runtime: ModelRuntime?
    let modelError: String?
    let reportFilters: [ReportFilter]
    let pageFilters: [String: [ReportFilter]]
    let visualFilters: [String: [ReportFilter]]
    let bookmarks: [ReportBookmark]
    let diagramLayout: DiagramLayout?
    /// Page that was active when the file was saved (Power BI reopens on it).
    let activePageID: String?

    private let lock = NSLock()
    private var tableCache: [String: [DecodedColumn]] = [:]
    private var imageCache: [String: NSImage] = [:]
    private var rowCountCache: [String: Int] = [:]

    init(data: Data) throws {
        pbix = try PBIXFile(data: data)
        report = (try? pbix.loadReport()) ?? ReportDefinition(pages: [])
        theme = pbix.loadTheme(for: report)
        (reportFilters, pageFilters, visualFilters) = pbix.loadFilters(report: report)
        bookmarks = pbix.loadBookmarks()
        diagramLayout = pbix.loadDiagramLayout()
        activePageID = pbix.activePageID
        if pbix.hasDataModel {
            do {
                let (abf, _) = try pbix.loadDataModel()
                let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
                (self.abf, runtime, modelError) = (abf, ModelRuntime(metadata: metadata, abf: abf), nil)
            } catch {
                (abf, runtime, modelError) = (nil, nil, String(describing: error))
            }
        } else {
            (abf, runtime, modelError) = (nil, nil, "File không có data model nhúng (có thể là báo cáo live connection).")
        }
    }

    /// Trang drillthrough và các cột tham số của nó (đọc từ `pageBinding` của page.json, chỉ định dạng PBIR).
    lazy var drillthroughPages: [(page: ReportPage, columns: [QueryColumn])] = {
        guard pbix.reportFormat == .pbir else { return [] }
        return report.pages.compactMap { page in
            let path = "Report/definition/pages/\(page.id)/page.json"
            guard pbix.archive.entry(path) != nil, var data = try? pbix.archive.read(path) else { return nil }
            if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
            guard let json = try? JSONValue.parse(data), json["pageBinding"]?["type"]?.string == "Drillthrough" else { return nil }
            let columns = (json["pageBinding"]?["parameters"]?.array ?? []).compactMap { p -> QueryColumn? in
                let c = p["fieldExpr"]?["Column"]
                guard let table = c?["Expression"]?["SourceRef"]?["Entity"]?.string, let name = c?["Property"]?.string else { return nil }
                return QueryColumn(table: table, column: name)
            }
            return columns.isEmpty ? nil : (page, columns)
        }
    }()

    var visiblePages: [ReportPage] { report.pages.filter { !$0.isHidden } }

    func page(id: String) -> ReportPage? { report.pages.first { $0.id == id } }

    var userTables: [ModelMetadata.Table] { metadata?.userTables ?? [] }

    func columns(of table: String) -> [ModelMetadata.Column] {
        metadata?.columns.filter { $0.tableName == table && $0.kind != .rowNumber } ?? []
    }

    func measures(of table: String) -> [ModelMetadata.Measure] {
        metadata?.measures.filter { $0.tableName == table } ?? []
    }

    func hierarchies(of table: String) -> [ModelMetadata.Hierarchy] {
        metadata?.hierarchies.filter { $0.tableName == table } ?? []
    }

    func measure(table: String, name: String) -> ModelMetadata.Measure? {
        metadata?.measures.first { $0.name == name && ($0.tableName == table || table.isEmpty) }
            ?? metadata?.measures.first { $0.name == name }
    }

    func column(table: String, name: String) -> ModelMetadata.Column? {
        metadata?.columns.first { $0.tableName == table && $0.name == name }
    }

    var tmdlDocuments: [TMDLWriter.Document] { runtime?.tmdlDocuments ?? [] }

    /// Engine DAX của mô hình này, tạo lần đầu khi cần rồi dùng chung cho mọi tab truy vấn.
    /// Chỉ đọc lược đồ và metadata; cột được nạp lười khi truy vấn cần. Gọi ngoài main thread.
    func daxEngine() throws -> DAXEngine {
        guard let runtime else {
            throw DAXError(.runtime, modelError ?? "File không có mô hình dữ liệu để chạy truy vấn")
        }
        return try runtime.engine()
    }

    /// Tên hiệu lực (sau khi đổi tên cột trong phiên) của các cột lưu trữ `baseNames` của bảng `table`, cùng thứ tự. Cột vẫn là cột
    /// cũ (cùng ID); tên chưa đổi thì giữ nguyên.
    func displayNames(table: String, baseNames: [String]) -> [String] {
        guard let runtime else { return baseNames }
        let base = runtime.base.columns, effective = runtime.metadata.columns
        let byID = Dictionary(effective.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return baseNames.map { name in
            guard let id = base.first(where: { $0.tableName == table && $0.name == name })?.id else { return name }
            return byID[id] ?? name
        }
    }

    /// Row count from segment metadata only (no column decoding).
    func rowCount(_ table: String) -> Int {
        if let cached = lock.withLock({ rowCountCache[table] }) { return cached }
        guard let metadata = runtime?.base, let abf, let storage = metadata.storage(table: table).first else { return 0 }
        let count = (try? VertiPaq.rowCount(storage, abf: abf)) ?? 0
        lock.withLock { rowCountCache[table] = count }
        return count
    }

    var totalRows: Int { userTables.reduce(0) { $0 + rowCount($1.name) } }

    /// Decodes a table (cached). Columns follow the model's column order.
    func table(_ name: String) throws -> [DecodedColumn] {
        if let cached = lock.withLock({ tableCache[name] }) { return cached }
        guard let metadata = runtime?.base, let abf else { throw CocoaError(.fileReadUnknown) }
        let decoded = try VertiPaq.decodeTable(name, metadata: metadata, abf: abf)
        let order = metadata.columns.filter { $0.tableName == name }.map(\.name)
        let sorted = decoded.sorted { (order.firstIndex(of: $0.name) ?? .max) < (order.firstIndex(of: $1.name) ?? .max) }
        lock.withLock { tableCache[name] = sorted }
        return sorted
    }

    func image(named name: String) -> NSImage? {
        if let cached = lock.withLock({ imageCache[name] }) { return cached }
        guard let data = pbix.resource(named: name), let image = NSImage(data: data) else { return nil }
        lock.withLock { imageCache[name] = image }
        return image
    }
}
