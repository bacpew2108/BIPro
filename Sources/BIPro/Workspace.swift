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
    let metadata: ModelMetadata?
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
    private lazy var tmdlCache: [TMDLWriter.Document] = metadata.map(TMDLWriter.documents(for:)) ?? []
    private var engineCache: DAXEngine?

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
                (self.abf, self.metadata, modelError) = (abf, metadata, nil)
            } catch {
                (abf, metadata, modelError) = (nil, nil, String(describing: error))
            }
        } else {
            (abf, metadata, modelError) = (nil, nil, "File không có data model nhúng (có thể là báo cáo live connection).")
        }
    }

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

    var tmdlDocuments: [TMDLWriter.Document] { lock.withLock { tmdlCache } }

    /// Engine DAX của mô hình này, tạo lần đầu khi cần rồi dùng chung cho mọi tab truy vấn.
    /// Chỉ đọc lược đồ và metadata; cột được nạp lười khi truy vấn cần. Gọi ngoài main thread.
    func daxEngine() throws -> DAXEngine {
        if let cached = lock.withLock({ engineCache }) { return cached }
        guard let metadata, let abf else {
            throw DAXError(.runtime, modelError ?? "File không có mô hình dữ liệu để chạy truy vấn")
        }
        let store = ColumnStore(source: try PBIXColumnSource(abf: abf, metadata: metadata))
        let engine = DAXEngine(store: store, catalog: Catalog(metadata: metadata))
        return lock.withLock {
            if let cached = engineCache { return cached }
            engineCache = engine
            return engine
        }
    }

    /// Row count from segment metadata only (no column decoding).
    func rowCount(_ table: String) -> Int {
        if let cached = lock.withLock({ rowCountCache[table] }) { return cached }
        guard let metadata, let abf, let storage = metadata.storage(table: table).first else { return 0 }
        let count = (try? VertiPaq.rowCount(storage, abf: abf)) ?? 0
        lock.withLock { rowCountCache[table] = count }
        return count
    }

    var totalRows: Int { userTables.reduce(0) { $0 + rowCount($1.name) } }

    /// Decodes a table (cached). Columns follow the model's column order.
    func table(_ name: String) throws -> [DecodedColumn] {
        if let cached = lock.withLock({ tableCache[name] }) { return cached }
        guard let metadata, let abf else { throw CocoaError(.fileReadUnknown) }
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
