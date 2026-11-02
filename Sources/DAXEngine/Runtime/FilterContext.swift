// Ngữ cảnh lọc (FC, đợt 2), architecture.md §4.1, §4.4, §4.6.
//
// Quy ước chung:
// - Mọi thao tác trả `FilterContext` mới (kiểu giá trị, bất biến). Không sửa tại chỗ.
// - `applying(_:)` áp các modifier theo thứ tự. CORE đưa REMOVEFILTERS, ALLSELECTED và USERELATIONSHIP
//   lên trước các `.filter`, đúng thứ tự §5.4 bước 3 rồi bước 4.
// - Vân tay (`fingerprint`, `Hashable`) gồm cả shadow và quan hệ ghi đè, nên dùng làm khoá cache.
//
// Mã hoá: lọc theo giá trị trên cột mã hoá đi qua `ColumnStore.index(_:)` (`code(of:)`, dictionary) để có mã,
// rồi giao cho `Propagation.visibleRows`.
// Cột dense (không có mã, ví dụ Dim_Date[full_date]): quét cột một lần để lấy tập dòng của bảng chứa cột,
// coi như bộ lọc bảng đã biết (RowsFilter). Dòng BLANK (NaN, hoặc blank row ảo) khớp BLANK.
// Mọi bộ lọc theo dòng (cột dense, FILTER(T, …)) đi xuống `Propagation` dưới dạng TableFilter và lan truyền qua
// chỉ mục quan hệ theo từng dòng, nên chính xác kể cả khi khoá quan hệ là cột dense.
//
// [SUY ĐOÁN] Khớp chuỗi trong bộ lọc không phân biệt hoa thường theo `lowercased()`, chưa theo collation của model.
// [SUY ĐOÁN] Bộ lọc theo bảng (FILTER(T, …)) chỉ chiếu thành tập mã từng cột để lan truyền sang bảng khác, nên
// lan truyền qua bảng đó có thể rộng hơn đáp án đúng khi bảng có nhiều cột tương quan. Kết quả trên chính bảng
// đó luôn đúng vì được giao lại với tập dòng chính xác.
// [SUY ĐOÁN] CROSSFILTER(…, None) được coi như tắt quan hệ (isActive = false).

import ColumnStore

/// Thứ tự ổn định của `ColumnID`: theo bảng rồi theo cột.
fileprivate func columnLess(_ a: ColumnID, _ b: ColumnID) -> Bool {
    (a.table.raw, a.index) < (b.table.raw, b.index)
}

/// Bỏ giá trị trùng, giữ thứ tự xuất hiện đầu tiên.
fileprivate func uniqued(_ values: [Value]) -> [Value] {
    var seen = Set<Value>()
    return values.filter { seen.insert($0).inserted }
}

/// Khoá dòng khi chiếu bộ lọc bảng: mã của các cột mã hoá và giá trị của các cột dense còn lại.
fileprivate struct RowKey: Hashable {
    let codes: [Int]
    let values: [StoredValue]
}

/// Bộ lọc theo tập dòng của một bảng (FILTER(T, …) hoặc biến bảng), §4.1 `.rows(TableID, RowSet)`.
/// `removedColumns` là các cột đã bị chiếu bỏ (REMOVEFILTERS hoặc ghi đè trên cột đó), §4.1 "chiếu".
public struct RowsFilter: Sendable, Hashable {
    public let table: TableID
    public let rows: RowSet
    /// Đã sắp và không trùng.
    public let removedColumns: [ColumnID]

    public init(table: TableID, rows: RowSet, removedColumns: [ColumnID] = []) {
        self.table = table
        self.rows = rows
        self.removedColumns = Array(Set(removedColumns)).sorted(by: columnLess)
    }
}

/// Ngữ cảnh lọc của một điểm đánh giá: bộ lọc theo cột, bộ lọc theo bảng, ghi đè quan hệ và shadow.
public struct FilterContext: Sendable, Hashable {
    /// Bộ lọc theo cột (AND giữa các cột). Mỗi cột tối đa một mục, đã sắp để băm ổn định.
    public private(set) var items: [FilterItem]
    /// Bộ lọc theo bảng (AND). Đọc qua `visibleRows`.
    public private(set) var rowFilters: [RowsFilter]
    /// Ghi đè quan hệ (USERELATIONSHIP, CROSSFILTER). Đã sắp theo `RelationshipID.raw`.
    public private(set) var relationshipOverrides: [RelationshipOverride]
    /// Shadow của các iterator đang chạy (ALLSELECTED). Là một phần của vân tay.
    public private(set) var shadows: ShadowStack
    /// Lược đồ quan hệ, để tính expanded table. Đặt bằng `bound(to:)` ở gốc. Rỗng thì expanded chỉ là chính bảng đó.
    public private(set) var relationships: [RelationshipSchema]

    /// Dựng từ bộ lọc theo cột. Mục trùng cột được AND (giao giá trị).
    public init(items: [FilterItem] = []) {
        var merged: [FilterItem] = []
        for item in items {
            if let i = merged.firstIndex(where: { $0.column == item.column }) {
                let kept = merged[i].values.filter { item.values.contains($0) }
                merged[i] = FilterItem(column: item.column, values: uniqued(kept))
            } else {
                merged.append(FilterItem(column: item.column, values: uniqued(item.values)))
            }
        }
        self.items = merged.sorted { columnLess($0.column, $1.column) }
        self.rowFilters = []
        self.relationshipOverrides = []
        self.shadows = ShadowStack()
        self.relationships = []
    }

    /// Ngữ cảnh rỗng (không lọc, không shadow, chưa gắn lược đồ).
    public static let empty = FilterContext()

    // MARK: - Gắn lược đồ

    /// Trả ngữ cảnh cùng nội dung, gắn danh sách quan hệ của model (dùng cho expanded table).
    /// CORE hoặc Engine gọi một lần ở gốc: `EvalContext(filter: FilterContext.empty.bound(to: schema))`.
    public func bound(to schema: ModelSchema) -> FilterContext {
        var out = self
        out.relationships = schema.relationships
        return out
    }

    // MARK: - Áp dụng (CALCULATE)

    /// Áp các modifier theo thứ tự và trả ngữ cảnh mới.
    /// `.filter(item, keep: false)` ghi đè: xoá bộ lọc cũ trên cột và chiếu bộ lọc bảng trên cột đó.
    /// `.filter(item, keep: true)` (KEEPFILTERS) giao giá trị với bộ lọc hiện có, hoặc thêm mới nếu chưa có.
    /// Các modifier khác: xem từng hàm bên dưới.
    public func applying(_ modifiers: [ContextModifier]) -> FilterContext {
        var out = self
        for modifier in modifiers {
            switch modifier {
            case .filter(let item, let keep):
                out = out.applying(item, keep: keep)
            case .removeColumns(let columns):
                out = out.removingColumns(columns)
            case .removeExpandedTable(let table):
                out = out.removingExpandedTable(table)
            case .removeAll:
                out = out.removingAll()
            case .allSelected(let columns):
                out = out.resolvingAllSelected(columns)
            case .useRelationship(let relationship):
                out = out.overriding(RelationshipOverride(relationship: relationship, isActive: true))
            case .crossFilter(let relationship, let mode):
                switch mode {
                case .oneDirection:
                    out = out.overriding(RelationshipOverride(relationship: relationship, crossFilter: .oneDirection))
                case .bothDirections:
                    out = out.overriding(RelationshipOverride(relationship: relationship, crossFilter: .bothDirections))
                case .none:
                    // [SUY ĐOÁN] Tắt lan truyền được coi như tắt quan hệ trong phạm vi này.
                    out = out.overriding(RelationshipOverride(relationship: relationship, isActive: false))
                }
            }
        }
        return out
    }

    /// Áp một bộ lọc theo cột (ghi đè hoặc KEEPFILTERS).
    public func applying(_ item: FilterItem, keep: Bool) -> FilterContext {
        if keep {
            var out = self
            if let i = out.items.firstIndex(where: { $0.column == item.column }) {
                let kept = out.items[i].values.filter { item.values.contains($0) }
                out.items[i] = FilterItem(column: item.column, values: uniqued(kept))
            } else {
                out.items.append(FilterItem(column: item.column, values: uniqued(item.values)))
                out.items.sort { columnLess($0.column, $1.column) }
            }
            return out
        }
        var out = removingColumns([item.column])
        out.items.append(FilterItem(column: item.column, values: uniqued(item.values)))
        out.items.sort { columnLess($0.column, $1.column) }
        return out
    }

    /// Áp một bộ lọc theo bảng (FILTER(T, …) làm đối số của CALCULATE).
    /// `keep: false`: bỏ mọi mục cột và bộ lọc bảng cũ trên T, rồi thêm `rows`. `keep: true`: AND thêm.
    public func applying(rows: RowsFilter, keep: Bool) -> FilterContext {
        var out = keep ? self : clearingTable(rows.table)
        out.rowFilters.append(rows)
        return out
    }

    /// Phần ghi đè của một bộ lọc bảng trên T: bỏ mọi mục cột và bộ lọc bảng cũ trên T (không đụng bảng khác).
    public func clearingTable(_ table: TableID) -> FilterContext {
        var out = self
        out.items.removeAll { $0.column.table == table }
        out.rowFilters.removeAll { $0.table == table }
        return out
    }

    // MARK: - Chiếu và xoá

    /// REMOVEFILTERS(col…): xoá mục cột và chiếu bộ lọc bảng trên các cột đó.
    public func removingColumns(_ columns: [ColumnID]) -> FilterContext {
        guard !columns.isEmpty else { return self }
        var out = self
        let drop = Set(columns)
        out.items.removeAll { drop.contains($0.column) }
        out.rowFilters = out.rowFilters.map { filter in
            let hits = columns.filter { $0.table == filter.table }
            if hits.isEmpty { return filter }
            return RowsFilter(table: filter.table, rows: filter.rows,
                              removedColumns: filter.removedColumns + hits)
        }
        return out
    }

    /// REMOVEFILTERS(T): xoá mọi bộ lọc trên các cột của expanded T (T và các bảng phía một tới được qua quan hệ,
    /// kể cả inactive), và mọi bộ lọc bảng trên các bảng đó. Chưa gắn lược đồ thì chỉ coi T là chính nó.
    public func removingExpandedTable(_ table: TableID) -> FilterContext {
        let expanded = expandedTables(of: table)
        var out = self
        out.items.removeAll { expanded.contains($0.column.table) }
        out.rowFilters.removeAll { expanded.contains($0.table) }
        return out
    }

    /// REMOVEFILTERS(): xoá mọi bộ lọc cột và bộ lọc bảng. Giữ ghi đè quan hệ và shadow.
    public func removingAll() -> FilterContext {
        var out = self
        out.items = []
        out.rowFilters = []
        return out
    }

    // MARK: - Shadow (ALLSELECTED, §4.5)

    /// Đẩy shadow khi iterator bắt đầu lặp: ghi lại ngữ cảnh hiện tại (không kèm shadow).
    public func pushingShadow() -> FilterContext {
        var snapshot = self
        snapshot.shadows = ShadowStack()
        snapshot.relationships = []
        var out = self
        out.shadows = shadows.pushing(snapshot)
        return out
    }

    /// Bỏ shadow trên cùng khi iterator kết thúc.
    public func poppingShadow() -> FilterContext {
        var out = self
        out.shadows = shadows.popping()
        return out
    }

    // MARK: - Đọc

    /// Các giá trị được phép trên cột. `nil` nghĩa là không có mục cột (bộ lọc bảng không tính).
    public func values(for column: ColumnID) -> [Value]? {
        items.first { $0.column == column }?.values
    }

    /// ISFILTERED(col): có mục cột trực tiếp chứa `column`, hoặc có bộ lọc bảng của bảng đó chưa chiếu cột này.
    public func isFiltered(_ column: ColumnID) -> Bool {
        if items.contains(where: { $0.column == column }) { return true }
        return rowFilters.contains { $0.table == column.table && !$0.removedColumns.contains(column) }
    }

    /// ISFILTERED(T): có cột nào của T bị lọc trực tiếp (mục cột hoặc bộ lọc bảng).
    public func isFiltered(table: TableID) -> Bool {
        items.contains { $0.column.table == table } || rowFilters.contains { $0.table == table }
    }

    /// Khoá cache: băm mọi trường, gồm shadow và ghi đè quan hệ. Chỉ ổn định trong một tiến trình.
    public var fingerprint: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }

    /// R(T): dòng của `table` còn thấy được trong ngữ cảnh này. Mục cột mã hoá dịch sang mã qua `ColumnStore.index`
    /// rồi gọi `Propagation.visibleRows`. Mục cột dense được quét thành tập dòng (xem đầu file). `overrides` được ghép sau
    /// các ghi đè của ngữ cảnh. Ném `DAXError`: `.ambiguousPath` khi lan truyền mơ hồ, `.runtime` khi thiếu cột hoặc bảng.
    public func visibleRows(in store: ColumnStore, table: TableID,
                            overrides: [RelationshipOverride]) throws(DAXError) -> RowSet {
        var localFilters: [CodeSet] = []
        var exact: [RowsFilter] = []
        for item in items {
            if let codes = try encodedCodeSet(for: item, store: store) {
                localFilters.append(codes)
                continue
            }
            // Cột dense: tập dòng của bảng chứa cột, là bộ lọc theo dòng chính xác.
            exact.append(RowsFilter(table: item.column.table, rows: try denseRows(for: item, store: store)))
        }
        for filter in rowFilters {
            exact.append(RowsFilter(table: filter.table, rows: try localRows(of: filter, store: store)))
        }
        // Bộ lọc theo dòng đi thẳng xuống Propagation (TableFilter) và lan truyền qua chỉ mục quan hệ theo từng dòng.
        // Trước đây chúng được chiếu thành tập mã từng cột, rộng hơn đáp án khi các cột tương quan (golden G0/G1:
        // nhóm Δ của Fact_Loan và Fact_CRM_Complaint lọt thêm ngày đầu tháng 12).
        let tableFilters = exact.map { TableFilter(table: $0.table, rows: $0.rows) }
        let merged = relationshipOverrides + overrides
        var result = try guarded {
            try Propagation.visibleRows(in: store, table: table, localFilters: localFilters,
                                        tableFilters: tableFilters, overrides: merged)
        }
        for filter in exact where filter.table == table {
            result = result.intersection(filter.rows)
        }
        return result
    }

    /// VALUES(col): các giá trị phân biệt của cột trên các dòng thấy được của bảng chứa cột. Có thể có BLANK.
    /// Thứ tự theo `ColumnIndex.sortRank` (cột mã hoá) hoặc theo dòng (cột dense).
    public func visibleValues(of column: ColumnID, in store: ColumnStore) throws(DAXError) -> [Value] {
        guard store.schema.column(column) != nil else {
            throw DAXError(.runtime, "Không có cột \(column) trong model")
        }
        let rows = try visibleRows(in: store, table: column.table, overrides: [])
        let index = try guarded { try store.index(column) }
        if index.column.isEncoded {
            // Đọc mã qua ColumnIndex: sortRank để sắp, dictionary để đổi mã thành giá trị.
            var codes = Set<Int>()
            rows.forEach { codes.insert(index.column.code(atRow: $0) ?? 0) }
            let ordered = codes.sorted { (index.sortRank(ofCode: $0) ?? 0) < (index.sortRank(ofCode: $1) ?? 0) }
            return ordered.compactMap { code -> Value? in
                if code == 0 { return .blank }
                return index.column.dictionaryValue(code: code).map { Value(stored: $0) }
            }
        }
        let data = try guarded { try store.column(column) }
        var seen = Set<StoredValue>()
        var out: [Value] = []
        rows.forEach { row in
            let stored = data.value(at: row)
            if seen.insert(stored).inserted { out.append(Value(stored: stored)) }
        }
        return out
    }

    /// HASONEVALUE(col) ⇔ VALUES(col) có đúng 1 giá trị.
    public func hasOneValue(_ column: ColumnID, in store: ColumnStore) throws(DAXError) -> Bool {
        try visibleValues(of: column, in: store).count == 1
    }

    // MARK: - Nội bộ: ghi đè quan hệ

    private func overriding(_ new: RelationshipOverride) -> FilterContext {
        var out = self
        if let i = out.relationshipOverrides.firstIndex(where: { $0.relationship == new.relationship }) {
            let old = out.relationshipOverrides[i]
            out.relationshipOverrides[i] = RelationshipOverride(
                relationship: new.relationship,
                isActive: new.isActive ?? old.isActive,
                crossFilter: new.crossFilter ?? old.crossFilter)
        } else {
            out.relationshipOverrides.append(new)
        }
        out.relationshipOverrides.sort { $0.relationship.raw < $1.relationship.raw }
        return out
    }

    // MARK: - Nội bộ: ALLSELECTED

    /// ALLSELECTED(cols) hoặc ALLSELECTED(): với mỗi cột, thay bộ lọc hiện tại bằng bộ lọc của shadow gần nhất.
    /// Không có shadow nào lọc cột đó thì cột thành mọi giá trị. ALLSELECTED() xét mọi cột của ngữ cảnh và shadow.
    private func resolvingAllSelected(_ columns: [ColumnID]?) -> FilterContext {
        var out = self
        guard let columns else {
            let all = Array(Set(items.map(\.column)).union(shadows.columnsWithFilters())).sorted(by: columnLess)
            out.rowFilters = []
            for column in all {
                out = out.resolvingColumn(column)
            }
            for table in shadows.tablesWithRowFilters() {
                if let filter = shadows.nearestRowFilter(on: table) {
                    out.rowFilters.append(RowsFilter(table: table, rows: filter.rows,
                                                     removedColumns: filter.removedColumns))
                }
            }
            return out
        }
        for column in columns {
            out = out.resolvingColumn(column)
        }
        return out
    }

    private func resolvingColumn(_ column: ColumnID) -> FilterContext {
        var out = removingColumns([column])
        if let item = shadows.nearestItem(on: column) {
            out.items.append(FilterItem(column: column, values: uniqued(item.values)))
            out.items.sort { columnLess($0.column, $1.column) }
        }
        return out
    }

    // MARK: - Nội bộ: expanded table

    /// Expanded(T): T cùng các bảng phía một tới được từ T qua quan hệ (kể cả inactive, theo tài liệu).
    private func expandedTables(of table: TableID) -> Set<TableID> {
        var result: Set<TableID> = [table]
        var changed = true
        while changed {
            changed = false
            for relationship in relationships
            where result.contains(relationship.manyColumn.table)
                && !result.contains(relationship.oneColumn.table) {
                result.insert(relationship.oneColumn.table)
                changed = true
            }
        }
        return result
    }

    // MARK: - Nội bộ: mã hoá và lan truyền

    /// Chuyển `Value` sang kiểu lưu của cột (ví dụ số nguyên sang currency nhân 10^4).
    fileprivate static func storedValue(_ value: Value, as type: DAXType) -> StoredValue {
        switch (value, type) {
        case (.blank, _):
            return .blank
        case (.integer(let i), .double):
            return .double(Double(i))
        case (.integer(let i), .currency):
            return .currency(i &* 10_000)
        case (.integer(let i), .dateTime):
            return .dateTime(Double(i))
        case (.integer(let i), _):
            return .integer(i)
        case (.double(let d), .integer):
            if d == d.rounded(), abs(d) < 9.0e18 { return .integer(Int64(d)) }
            return .double(d)
        case (.double(let d), .currency):
            return .currency(Int64((d * 10_000).rounded()))
        case (.double(let d), .dateTime):
            return .dateTime(d)
        case (.double(let d), _):
            return .double(d)
        case (.currency(let c), .double):
            return .double(Double(c) / 10_000)
        case (.currency(let c), .integer):
            return c % 10_000 == 0 ? .integer(c / 10_000) : .currency(c)
        case (.currency(let c), _):
            return .currency(c)
        case (.string(let s), _):
            return .string(s)
        case (.boolean(let b), _):
            return .boolean(b)
        case (.dateTime(let d), _):
            return .dateTime(d)
        }
    }

    /// Dịch một mục cột mã hoá thành tập mã của cột, qua `ColumnStore.index`. Trả `nil` khi cột là dense.
    private func encodedCodeSet(for item: FilterItem, store: ColumnStore) throws(DAXError) -> CodeSet? {
        guard let meta = store.schema.column(item.column) else {
            throw DAXError(.runtime, "Không có cột \(item.column) trong model")
        }
        let index = try guarded { try store.index(item.column) }
        guard index.column.isEncoded else { return nil }
        var codes = Set<UInt32>()
        var texts = Set<String>()
        for value in item.values {
            let stored = FilterContext.storedValue(value, as: meta.type)
            if let code = index.code(of: stored) {
                codes.insert(UInt32(code))
            }
            if case .string(let s) = stored {
                texts.insert(s.lowercased())
            }
        }
        if !texts.isEmpty {
            // [SUY ĐOÁN] So chuỗi không phân biệt hoa thường: quét dictionary một lần cho mọi giá trị chuỗi.
            for code in stride(from: 1, through: index.column.dictionaryCount, by: 1) {
                if case .string(let s)? = index.column.dictionaryValue(code: code), texts.contains(s.lowercased()) {
                    codes.insert(UInt32(code))
                }
            }
        }
        return CodeSet(column: item.column, codes: codes.sorted())
    }

    /// Quét cột dense để lấy tập dòng khớp giá trị của mục cột. Dòng NaN là BLANK. Dòng BLANK ảo (chỉ số rowCount)
    /// khớp khi mục có BLANK, như dòng mã 0 ở cột mã hoá. Universe là số dòng + 1.
    private func denseRows(for item: FilterItem, store: ColumnStore) throws(DAXError) -> RowSet {
        guard let meta = store.schema.column(item.column) else {
            throw DAXError(.runtime, "Không có cột \(item.column) trong model")
        }
        let rowCount = try guarded { try store.rowCount(item.column.table) }
        var targets = Set<StoredValue>()
        for value in item.values {
            targets.insert(FilterContext.storedValue(value, as: meta.type))
        }
        // Không có BLANK trong mục: tra chỉ mục theo giá trị (cùng kết quả với quét, không đọc từng dòng).
        if !targets.contains(.blank) {
            let index = try guarded { try store.index(item.column) }
            if let matched = index.denseRows(matching: Array(targets)) {
                return RowSet(universe: rowCount + 1, sortedRows: matched)
            }
        }
        let data = try guarded { try store.column(item.column) }
        var matched: [UInt32] = []
        for row in 0...rowCount where targets.contains(data.value(at: row)) {
            matched.append(UInt32(row))
        }
        return RowSet(universe: rowCount + 1, sortedRows: matched)
    }

    /// Dòng thật của bộ lọc theo bảng sau khi chiếu các cột đã bỏ. Không chiếu thì là chính `rows`.
    /// Dòng khớp khi khoá trên các cột còn lại (mã của cột mã hoá, giá trị của cột dense) trùng với một dòng của `rows`.
    /// Universe là số dòng + 1.
    private func localRows(of filter: RowsFilter, store: ColumnStore) throws(DAXError) -> RowSet {
        if filter.removedColumns.isEmpty { return filter.rows }
        let rowCount = try guarded { try store.rowCount(filter.table) }
        let universe = rowCount + 1
        guard let meta = store.schema.table(filter.table) else {
            throw DAXError(.runtime, "Không có bảng \(filter.table) trong model")
        }
        var encoded: [ColumnData] = []
        var dense: [ColumnData] = []
        for column in meta.columns where !filter.removedColumns.contains(column.id) {
            let data = try guarded { try store.column(column.id) }
            if data.isEncoded { encoded.append(data) } else { dense.append(data) }
        }
        if encoded.isEmpty && dense.isEmpty {
            // Không còn cột nào để ràng buộc: mọi dòng thật, cộng blank row nếu bộ lọc gốc có.
            var rows = RowSet.all(rowCount: rowCount)
            if filter.rows.contains(rowCount) {
                rows = rows.union(RowSet(universe: universe, sortedRows: [UInt32(rowCount)]))
            }
            return rows
        }
        func key(_ row: Int) -> RowKey {
            RowKey(codes: encoded.map { $0.code(atRow: row) ?? 0 }, values: dense.map { $0.value(at: row) })
        }
        var keys = Set<RowKey>()
        filter.rows.forEach { row in keys.insert(key(row)) }
        var matched: [UInt32] = []
        for row in 0...rowCount where keys.contains(key(row)) {
            matched.append(UInt32(row))
        }
        return RowSet(universe: universe, sortedRows: matched)
    }

    /// Đổi lỗi của ColumnStore và lan truyền sang `DAXError`. Lỗi lan truyền mơ hồ giữ đúng `kind`.
    private func guarded<T>(_ body: () throws -> T) throws(DAXError) -> T {
        do {
            return try body()
        } catch let error as DAXError {
            throw error
        } catch let error as PropagationError {
            switch error {
            case .ambiguousPath(let from, let to):
                throw DAXError(.ambiguousPath, "Lan truyền bộ lọc mơ hồ từ \(from) tới \(to)")
            case .unknownRelationship(let relationship):
                throw DAXError(.runtime, "Không có quan hệ \(relationship.raw) trong model")
            }
        } catch {
            throw DAXError(.runtime, "\(error)")
        }
    }
}
