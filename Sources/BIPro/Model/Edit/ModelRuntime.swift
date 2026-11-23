import ColumnStore
import DAXEngine
import Foundation
import PBIXKit

/// Phase E (R1, R4): mô hình hiệu lực (mô hình gốc + `ModelEdits`) và engine DAX chạy trên nó.
///
/// `ColumnStore` (cột đã giải mã) được dùng chung khi chỉ measure đổi; engine mới chỉ khác `Catalog`, nên bộ nhớ đệm
/// của engine cũ (`MeasureCache`) không dính sang. Đổi quan hệ hoặc cột dựng `ColumnStore` mới từ mô hình hiệu lực
/// (chi phí đo ở spike S2, `measurements.md`).
final class ModelRuntime: @unchecked Sendable {
    /// Mô hình gốc (đúng như file); phần lưu trữ cột (`storage`) luôn đọc theo mô hình này.
    let base: ModelMetadata
    private let abf: ABFBackup
    private let lock = NSLock()
    private var currentEdits = ModelEdits()
    private var effective: ModelMetadata
    private var baseStore: ColumnStore?
    private var cachedEngine: DAXEngine?
    private var tmdl: [TMDLWriter.Document]?
    private var versionValue = 0
    private var overlayCache: [TableID: TableData] = [:]
    private var overlayVersion = -1
    private var calculationErrorsValue: [String: String] = [:]
    private var planValue = CalculationPlan.empty

    init(metadata: ModelMetadata, abf: ABFBackup) {
        base = metadata
        self.abf = abf
        effective = metadata
    }

    /// Mô hình hiệu lực.
    var metadata: ModelMetadata { lock.withLock { effective } }

    var edits: ModelEdits { lock.withLock { currentEdits } }

    /// Tăng mỗi khi mô hình hiệu lực đổi (khoá nạp lại của visual).
    var version: Int { lock.withLock { versionValue } }

    /// Dữ liệu ô của bảng nạp trong bộ nhớ (mới hoặc thay thế) có tên `name` trong mô hình hiệu lực; nil với bảng của file.
    func overlay(named name: String) -> TableData? {
        lock.withLock {
            if overlayVersion != versionValue {
                overlayCache = currentEdits.hasTableEdits ? currentEdits.tableData(in: effective) : [:]
                overlayVersion = versionValue
            }
            guard let table = effective.userTables.first(where: { $0.name == name }) else { return nil }
            return overlayCache[TableID(raw: table.id)]
        }
    }

    /// Văn bản TMDL sinh từ mô hình hiệu lực.
    var tmdlDocuments: [TMDLWriter.Document] {
        lock.withLock {
            if let tmdl { return tmdl }
            let documents = TMDLWriter.documents(for: effective)
            tmdl = documents
            return documents
        }
    }

    /// Kiểm `edits` trên mô hình gốc mà không đổi gì; ném `ModelEditError` khi sai.
    func validate(_ edits: ModelEdits) throws {
        _ = try base.applying(edits)
    }

    /// Kiểm việc tính lại cột/bảng tính toán của `edits` (T116): không có vòng phụ thuộc, và cột/bảng có sẵn trong file phải tính lại thì
    /// lưu được (không nằm trong quan hệ, phân cấp…). Ném `ModelEditError` kèm lý do.
    func validateCalculations(_ edits: ModelEdits) throws {
        let metadata = try base.applying(edits)
        let plan = Self.plan(for: edits, metadata: metadata, base: base)
        if !plan.cyclic.isEmpty {
            throw ModelEditError(biN("Phụ thuộc vòng giữa ", "Circular dependency between ") + plan.cyclic.map(\.description).joined(separator: ", "))
        }
        let inFile = plan.order.filter { node in
            switch node {
            case .column(let table, let name):
                guard let column = metadata.columns.first(where: { $0.tableName == table && $0.name == name }) else { return false }
                return base.columns.contains { $0.id == column.id }
            case .table(let name):
                guard let table = metadata.tables.first(where: { $0.name == name }) else { return false }
                return base.tables.contains { $0.id == table.id }
            }
        }
        let blockers = CalculationPlan.saveBlockers(inFile, metadata: metadata)
        if !blockers.isEmpty {
            throw ModelEditError(biN("Chưa tính lại và lưu được cột/bảng tính toán có sẵn: ", "Can't recalculate and save the existing calculated columns/tables yet: ") + blockers.joined(separator: "; ")
                                 + biN(" (BI Pro chưa thay được dữ liệu bảng tính toán có quan hệ, phân cấp hay cột tính toán)", " (BI Pro can't replace the data of calculated tables that have relationships, hierarchies or calculated columns yet)"))
        }
    }

    /// Cột và bảng tính toán engine của phiên tính (thứ tự phụ thuộc), theo mô hình hiệu lực.
    var calculationPlan: CalculationPlan { lock.withLock { planValue } }

    private static func plan(for edits: ModelEdits, metadata: ModelMetadata, base: ModelMetadata) -> CalculationPlan {
        guard edits.hasCalculatedEdits || edits.hasTableEdits else { return .empty }
        let reloaded = Set(edits.tableData(in: metadata).keys.compactMap { id in metadata.tables.first { $0.id == id.raw }?.name })
        return CalculationPlan.make(seeds: CalculationPlan.sessionSeeds(metadata: metadata, base: base, reloadedTables: reloaded), metadata: metadata)
    }

    /// Đặt danh sách thao tác (đầy đủ, không cộng dồn). Ném `ModelEditError` thì mô hình giữ nguyên.
    func setEdits(_ edits: ModelEdits) throws {
        let isSame = lock.withLock { edits == currentEdits }
        if isSame { return }
        let result = try base.applying(edits)
        let plan = Self.plan(for: edits, metadata: result, base: base)
        lock.withLock {
            currentEdits = edits
            effective = result
            planValue = plan
            cachedEngine = nil
            tmdl = nil
            versionValue += 1
        }
    }

    /// Lỗi tính của cột/bảng tính toán thêm trong phiên, theo `Bảng[Cột]` hoặc tên bảng (sau lần dựng engine gần nhất). Cột lỗi có giá
    /// trị trống, như Desktop giữ mô hình dùng được khi một cột tính toán lỗi.
    var calculationErrors: [String: String] { lock.withLock { calculationErrorsValue } }

    /// Engine cho mô hình hiệu lực. Tạo lười; gọi ngoài luồng chính. Nếu mô hình đổi trong lúc dựng thì bỏ engine cũ và dựng lại,
    /// để không bao giờ cất engine của phiên bản đã lỗi thời.
    func engine() throws -> DAXEngine {
        while true {
            let (cached, metadata, edits, builtVersion, plan) = lock.withLock { (cachedEngine, effective, currentEdits, versionValue, planValue) }
            if let cached { return cached }
            var store: ColumnStore
            if edits.hasTableEdits {
                // Bảng nạp mới/thay thế chồng lên kho gốc; bảng còn lại dùng lại cột đã giải mã.
                let overlays = edits.tableData(in: metadata)
                store = ColumnStore(source: OverlayColumnSource(base: try rootStore(), schema: ModelSchema(metadata: metadata), tables: overlays))
            } else if edits.hasCalculatedEdits {
                // Cột và bảng tính toán: đọc mọi cột khác từ kho gốc (lớp `ComputedColumnSource` mang lược đồ hiệu lực).
                store = try rootStore()
            } else if edits.touchesSchema {
                // Lược đồ mới (quan hệ, cột) nhưng cột đã giải mã dùng lại từ kho gốc; không được thì dựng từ file.
                let root = try rootStore()
                if let source = ReschematedColumnSource(base: root, schema: ModelSchema(metadata: metadata)) {
                    store = ColumnStore(source: source)
                } else {
                    store = ColumnStore(source: try PBIXColumnSource(abf: abf, metadata: metadata))
                }
            } else {
                store = try rootStore()
            }
            var errors: [String: String] = [:]
            let engine: DAXEngine
            if !plan.all.isEmpty {
                let computed = ComputedColumnSource(base: store, schema: ModelSchema(metadata: metadata))
                store = ColumnStore(source: computed)
                engine = DAXEngine(store: store, catalog: Catalog(metadata: metadata))
                errors = Self.compute(plan, metadata: metadata, engine: engine, into: computed)
            } else {
                engine = DAXEngine(store: store, catalog: Catalog(metadata: metadata))
            }
            let stored: DAXEngine? = lock.withLock {
                if let cached = cachedEngine, versionValue == builtVersion { return cached }
                guard versionValue == builtVersion else { return nil }
                cachedEngine = engine
                calculationErrorsValue = errors
                return engine
            }
            if let stored { return stored }
        }
    }

    /// Tính cột và bảng tính toán theo `plan` (thứ tự phụ thuộc, T116). Lỗi của một mục không chặn mục khác: cột lỗi để trống, bảng lỗi
    /// không có dòng; mục trong vòng phụ thuộc cũng vậy.
    private static func compute(_ plan: CalculationPlan, metadata: ModelMetadata, engine: DAXEngine, into source: ComputedColumnSource) -> [String: String] {
        var errors: [String: String] = [:]
        let schema = source.schema
        func key(_ node: CalculationPlan.Node) -> String {
            switch node {
            case .column(let table, let name): "\(table)[\(name)]"
            case .table(let name): name
            }
        }
        for node in plan.cyclic {
            errors[key(node)] = biN("phụ thuộc vòng", "circular dependency")
            switch node {
            case .table(let name):
                guard let table = schema.table(named: name) else { continue }
                source.setTable(table.id, rowCount: 0, columns: Dictionary(uniqueKeysWithValues: table.columns.map { ($0.name, Self.blankColumn(type: $0.type, count: 0)) }))
            case .column(let tableName, let name):
                guard let column = schema.column(table: tableName, name: name) else { continue }
                source.setColumn(column.id, Self.blankColumn(type: column.type, count: (try? engine.store.rowCount(column.id.table)) ?? 0))
            }
        }
        // Bảng ngày của Auto date/time (T032) tính trên lược đồ không có quan hệ ngày: quan hệ `T[c]` → bảng cục bộ làm engine đọc chính bảng
        // đang tính. Biểu thức chỉ dùng cột nguồn (MIN, MAX) nên kết quả như Desktop.
        let autoDate = metadata.autoDateTables
        let withoutDateRelationships: DAXEngine? = autoDate.isEmpty ? nil : {
            let reduced = ModelSchema(culture: schema.culture, tables: schema.tables, relationships: schema.relationships.filter { !$0.joinsOnDatePart })
            let store = ColumnStore(source: SchemaOverrideSource(schema: reduced, base: source))
            return DAXEngine(store: store, catalog: Catalog(schema: reduced, measures: []))
        }()
        for node in plan.order {
            switch node {
            case .table(let name):
                guard let table = schema.table(named: name), let expression = metadata.calculatedTableExpressions[name] else { continue }
                let engine = autoDate.contains(name) ? (withoutDateRelationships ?? engine) : engine
                // Chỉ các cột kết quả của biểu thức (`Type = 4`); cột tính toán trên bảng này là nút riêng, tính sau.
                let resultNames = Set(metadata.columns.filter { $0.tableName == name && $0.kind == .calculatedTableColumn }.map(\.name))
                let resultColumns = table.columns.filter { resultNames.contains($0.name) }
                var columns: [String: ColumnData] = [:], rowCount = 0
                do {
                    let result = try engine.calculatedTable(expression: expression)
                    rowCount = result.rows.count
                    for column in resultColumns {
                        guard let index = result.columns.firstIndex(where: { $0.caseInsensitiveCompare(column.name) == .orderedSame }) else {
                            throw DAXError(.runtime, biN("kết quả không có cột \(column.name)", "the result has no column \(column.name)"))
                        }
                        columns[column.name] = try CalculatedData.columnData(result.rows.map { $0[index] }, type: column.type)
                    }
                } catch {
                    errors[name] = (error as? DAXError)?.message ?? "\(error)"
                    rowCount = 0
                    columns = Dictionary(uniqueKeysWithValues: resultColumns.map { ($0.name, Self.blankColumn(type: $0.type, count: 0)) })
                }
                source.setTable(table.id, rowCount: rowCount, columns: columns)
            case .column(let tableName, let name):
                guard let column = schema.column(table: tableName, name: name),
                      let expression = metadata.columns.first(where: { $0.tableName == tableName && $0.name == name })?.expression else { continue }
                let count = (try? engine.store.rowCount(column.id.table)) ?? 0
                do {
                    let values = try engine.calculatedColumn(table: tableName, expression: expression)
                    source.setColumn(column.id, try CalculatedData.columnData(values, type: column.type))
                } catch {
                    errors["\(tableName)[\(column.name)]"] = (error as? DAXError)?.message ?? "\(error)"
                    source.setColumn(column.id, Self.blankColumn(type: column.type, count: count))
                }
            }
        }
        return errors
    }

    private static func blankColumn(type: DAXType, count: Int) -> ColumnData {
        (try? CalculatedData.columnData(Array(repeating: .blank, count: count), type: type)) ?? ColumnBuilder.strings(Array(repeating: nil, count: count))
    }

    /// Kho cột gốc (lược đồ của file), dựng một lần; mọi engine dùng lại cột đã giải mã của nó.
    private func rootStore() throws -> ColumnStore {
        if let shared = lock.withLock({ baseStore }) { return shared }
        let store = ColumnStore(source: try PBIXColumnSource(abf: abf, metadata: base))
        return lock.withLock {
            if let shared = baseStore { return shared }
            baseStore = store
            return store
        }
    }
}

extension ModelEdits {
    /// Có thao tác đổi lược đồ mà `ColumnStore` dựng từ (quan hệ, cột), không chỉ measure.
    var touchesSchema: Bool {
        items.contains {
            switch $0 {
            case .updateRelationship, .updateColumn, .addRelationship, .deleteRelationship, .updateTable,
                 .addTable, .replaceTable, .dropTable, .addCalculatedColumn, .addCalculatedTable,
                 .updateCalculatedColumn, .deleteCalculatedColumn, .updateCalculatedTable,
                 .addHierarchy, .dropHierarchy, .addVariation, .dropVariation: true
            case .addMeasure, .updateMeasure, .deleteMeasure, .setQuery, .dropQuery, .setModelAnnotation,
                 .upsertRole, .deleteRole: false
            }
        }
    }
}

extension ModelEdits {
    /// Có cột hoặc bảng tính toán thêm, sửa hay xoá trong phiên (engine phải tính giá trị).
    var hasCalculatedEdits: Bool {
        items.contains {
            switch $0 {
            case .addCalculatedColumn, .addCalculatedTable, .updateCalculatedColumn, .deleteCalculatedColumn, .updateCalculatedTable: true
            default: false
            }
        }
    }

    /// Có thao tác thêm, thay hoặc xoá bảng (nguồn cột phải chồng dữ liệu trong bộ nhớ).
    var hasTableEdits: Bool {
        items.contains {
            switch $0 {
            case .addTable, .replaceTable, .dropTable: true
            default: false
            }
        }
    }

    /// Dữ liệu ô của các bảng đang có hiệu lực, theo `Table.ID` của mô hình hiệu lực `metadata`. Duyệt theo thứ tự thao tác:
    /// thêm/thay đặt dữ liệu theo tên bảng mới (`NewTable.attachment`), xoá bỏ.
    func tableData(in metadata: ModelMetadata) -> [TableID: TableData] {
        var byName: [String: TableData] = [:]
        func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        for item in items {
            switch item {
            case .addTable(let table):
                if table.enableLoad, let data = table.attachment as? TableData { byName[key(table.name)] = data }
            case .replaceTable(let old, let table):
                byName[key(old)] = nil
                if table.enableLoad, let data = table.attachment as? TableData { byName[key(table.name)] = data }
            case .dropTable(let name):
                byName[key(name)] = nil
            case .updateTable(let old, let patch):
                if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !renamed.isEmpty, renamed.lowercased() != old.lowercased(),
                   let existing = byName.removeValue(forKey: key(old)) {
                    byName[key(renamed)] = existing
                }
            case .updateColumn(let table, let old, let patch):
                if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !renamed.isEmpty, renamed != old,
                   let existing = byName[key(table)] {
                    let cols = existing.columns.map { col in
                        col.name == old ? TableColumn(name: renamed, data: col.data) : col
                    }
                    if let updated = try? TableData(columns: cols) {
                        byName[key(table)] = updated
                    }
                }
            default:
                break
            }
        }
        var result: [TableID: TableData] = [:]
        for table in metadata.userTables {
            if let data = byName[key(table.name)] { result[TableID(raw: table.id)] = data }
        }
        return result
    }
}

/// Nguồn cột mang lược đồ khác (bớt quan hệ) nhưng đọc dữ liệu từ nguồn gốc: tính bảng ngày của Auto date/time (T032).
private struct SchemaOverrideSource: ColumnSource {
    let schema: ModelSchema
    let base: any ColumnSource
    func rowCount(_ table: TableID) throws -> Int { try base.rowCount(table) }
    func loadColumn(_ id: ColumnID) throws -> ColumnData { try base.loadColumn(id) }
}
