// Gói Q (Phase C, lead): chạy truy vấn của visual ngoài main thread.
//
// - Cache kết quả theo văn bản DAX: cùng trạng thái lọc thì không chạy lại (đổi trang rồi quay lại, Undo slicer…).
// - Giới hạn số truy vấn chạy cùng lúc (mặc định bằng số nhân hiệu năng), để visual đầu tiên có số sớm.
// - Huỷ: gọi trong một Task; khi trạng thái lọc đổi, phần ghép (gói G) huỷ Task cũ. Engine kiểm Task.isCancelled.
import DAXEngine
import Foundation

actor VisualDataLoader {
    struct Loaded: Sendable {
        let view: DataView
        let query: String
        let elapsed: Duration
        let fromCache: Bool
    }

    private let engine: DAXEngine
    private let maxConcurrent: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var cache: [String: QueryResult] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit: Int

    init(engine: DAXEngine, maxConcurrent: Int = ProcessInfo.processInfo.activeProcessorCount, cacheLimit: Int = 512) {
        self.engine = engine
        self.maxConcurrent = max(1, maxConcurrent)
        self.cacheLimit = cacheLimit
    }

    /// Chạy truy vấn của `spec` và trả DataView. Ném `DAXError` (kể cả `.cancelled`).
    func load(_ spec: VisualQuerySpec) async throws -> Loaded {
        // Bản đồ hình có ô Series (Legend): Desktop vẽ chú giải các giá trị của nó dưới bản đồ, có hay chưa có cột vị trí
        // (VM-D15 mục 3, VM-D16 mục 2); chú giải bỏ giá trị mà measure Value để trống (bắt đầu từ 2013, không phải 2011 của bảng ngày).
        guard case .shapeMap = spec.shape, let legendField = spec.secondary.first else { return try await loadPlain(spec) }
        var legendSpec = spec
        legendSpec.shape = .treemap
        legendSpec.primary = [legendField]
        legendSpec.primaryOrder = spec.secondaryOrder
        legendSpec.secondary = []
        legendSpec.measures = spec.measures.filter { $0.field.role == "Value" }.map { var m = $0; m.ignore = false; return m }
        let inner = try await loadPlain(legendSpec)
        guard case .categorical(let source) = inner.view else { return inner }
        let legendValues = source.categories.compactMap(\.values.first)
        if spec.primary.isEmpty {
            let data = CategoricalData(categoryLevels: [], categories: [], seriesField: legendField.field, series: legendValues, measures: [],
                                       values: [], highlights: nil, isReduced: source.isReduced)
            return Loaded(view: .categorical(data), query: inner.query, elapsed: inner.elapsed, fromCache: inner.fromCache)
        }
        let main = try await loadPlain(spec)
        guard case .categorical(var data) = main.view else { return main }
        data.seriesField = legendField.field
        data.series = legendValues
        return Loaded(view: .categorical(data), query: main.query, elapsed: main.elapsed, fromCache: main.fromCache)
    }

    private func loadPlain(_ spec: VisualQuerySpec) async throws -> Loaded {
        // Bản đồ hình chưa có cột vị trí (`Category`), như khi vừa đổi từ biểu đồ khác (VM-D12): không có truy vấn, vẽ bản đồ trơn.
        if case .shapeMap = spec.shape, spec.primary.isEmpty {
            let empty = QueryResult(tables: [ResultTable(columns: [], rows: [])], elapsedNanoseconds: 0)
            return Loaded(view: DataViewMapper.map(empty, spec: spec), query: "", elapsed: .zero, fromCache: false)
        }
        let query = DAXQueryBuilder.build(spec)
        let clock = ContinuousClock()
        let start = clock.now
        if let hit = cache[query] {
            return Loaded(view: DataViewMapper.map(hit, spec: spec), query: query, elapsed: start.duration(to: clock.now), fromCache: true)
        }
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        let result = try await engine.execute(query)
        store(result, for: query)
        return Loaded(view: DataViewMapper.map(result, spec: spec), query: query, elapsed: start.duration(to: clock.now), fromCache: false)
    }

    /// Giá trị phân biệt của một cột (Filters pane liệt kê để chọn), xếp tăng dần, tối đa `limit` giá trị.
    func distinctValues(of column: QueryColumn, limit: Int) async throws -> [Value] {
        let result = try await engine.execute("EVALUATE TOPN(\(limit), VALUES(\(column.dax)), \(column.dax), ASC)\nORDER BY \(column.dax) ASC")
        return (result.tables.first?.rows ?? []).compactMap(\.first)
    }

    /// Biên toàn miền `[MIN, MAX]` của một cột số/ngày (cho slicer chế độ `'Between'`), tôn trọng bộ lọc tĩnh.
    func columnRange(of column: QueryColumn, filters: [QueryFilter]) async throws -> SlicerRange? {
        let query: String
        if filters.isEmpty {
            query = "EVALUATE ROW(\"Min\", MIN(\(column.dax)), \"Max\", MAX(\(column.dax)))"
        } else {
            let names = DAXQueryBuilder.filterNames(count: filters.count)
            let vars = zip(names, filters).map { "\tVAR \($0) = \($1.tableExpression)" }.joined(separator: "\n")
            let args = (names + ["\"Min\", MIN(\(column.dax))", "\"Max\", MAX(\(column.dax))"]).joined(separator: ", ")
            query = "DEFINE\n\(vars)\nEVALUATE SUMMARIZECOLUMNS(\(args))"
        }
        let result: QueryResult
        if let hit = cache[query] {
            result = hit
        } else {
            await acquire()
            defer { release() }
            try Task.checkCancellation()
            result = try await engine.execute(query)
            store(result, for: query)
        }
        guard let row = result.tables.first?.rows.first, row.count >= 2 else { return nil }
        let lo = row[0] == .blank ? nil : row[0]
        let hi = row[1] == .blank ? nil : row[1]
        guard lo != nil || hi != nil else { return nil }
        return SlicerRange(min: lo, max: hi)
    }

    func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    // MARK: - Giới hạn song song

    private func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()   // chuyển suất chạy cho người chờ, `running` giữ nguyên
        }
    }

    private func store(_ result: QueryResult, for query: String) {
        if cache[query] == nil {
            cacheOrder.append(query)
            if cacheOrder.count > cacheLimit { cache.removeValue(forKey: cacheOrder.removeFirst()) }
        }
        cache[query] = result
    }
}
