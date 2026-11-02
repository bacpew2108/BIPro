// Lan truyền bộ lọc qua quan hệ (architecture.md §3.3), đợt 1b (REL).
//
// R(T) là tập dòng của T còn thấy được. Tính bằng điểm bất động lớn nhất: bắt đầu từ local(T) của
// mọi bảng liên quan, rồi thu hẹp lặp lại theo các quan hệ hoạt động (một → nhiều luôn; hai chiều thì
// thêm nhiều → một) tới khi không đổi. Mỗi bước chỉ thu hẹp nên kết thúc. Với đồ thị không có chu trình
// hai chiều, kết quả trùng với công thức §3.3.
//
// Blank row ảo của bảng (chỉ số rowCount) luôn có trong universe nội bộ. Ở quan hệ mà bảng là phía nhiều,
// nó có FK BLANK nên khớp với blank row bên một. Blank row bên một chỉ được giữ khi có quan hệ hoạt động
// trỏ vào bảng và có dòng bên nhiều đang thấy mà khoá không khớp (xem visibleRows).
//
// [SUY ĐOÁN] Lan truyền mơ hồ: nếu từ một bảng có bộ lọc chảy đi có hai đường có hướng khác nhau tới cùng
// một bảng đích thì báo `PropagationError.ambiguousPath`, không đoán. Bảng không có bộ lọc không kiểm tra.
// Đây là tương đương với "hai đường hoạt động" của đề bài. Quan hệ hoạt động trùng cặp bảng bị tắt khi USERELATIONSHIP bật một quan hệ khác cùng cặp
// (theo tài liệu về USERELATIONSHIP). Không chọn đường theo weight.
// [SUY ĐOÁN] CrossFilterBehavior.automatic được coi như một chiều (một → nhiều).
// [SUY ĐOÁN] Lan truyền ngược (nhiều → một, quan hệ hai chiều) chỉ áp khi bên nhiều bị hạn chế bởi một bộ lọc
// (R(M) ≠ toàn bộ). Với bên nhiều không lọc, dòng bên một không có fact vẫn thấy được. Đây là cách đọc
// §3.3 cho phép, và khớp hành vi Power BI thường gặp, nhưng chưa quan sát trực tiếp (O1–O3 chưa có).
// [SUY ĐOÁN] Lọc theo mã trên cột dense không có nghĩa trong đợt này, nên báo `notImplemented`.

/// Lỗi riêng của lan truyền. Không thêm case vào `ColumnStoreError`, để không đổi contract đóng băng.
public enum PropagationError: Error, Sendable, Hashable {
    /// Có hai đường lan truyền khác nhau từ `from` tới `to` trong đồ thị quan hệ hoạt động.
    case ambiguousPath(from: TableID, to: TableID)
    /// Ghi đè trỏ tới quan hệ không có trong model.
    case unknownRelationship(RelationshipID)
}

public enum Propagation {
    /// R(T): các dòng của bảng `table` còn thấy được sau khi áp `localFilters` (lọc theo mã cột)
    /// và `overrides` (USERELATIONSHIP, CROSSFILTER), lan truyền qua mọi quan hệ đang hoạt động.
    ///
    /// Universe của kết quả là số dòng + 1. Chỉ số cuối là blank row ảo, chỉ có khi bảng có dòng không khớp.
    public static func visibleRows(
        in store: ColumnStore,
        table: TableID,
        localFilters: [CodeSet],
        overrides: [RelationshipOverride]
    ) throws -> RowSet {
        try visibleRows(in: store, table: table, localFilters: localFilters, tableFilters: [], overrides: overrides)
    }

    /// Như trên, thêm `tableFilters`: tập dòng đã biết của từng bảng (bộ lọc trên cột dense, FILTER(T, …)).
    /// Tập dòng được giao vào local(T) rồi lan truyền qua chỉ mục quan hệ như mọi bộ lọc khác, nên chính xác
    /// theo từng dòng. Không chiếu thành tập mã từng cột (cách đó rộng hơn đáp án khi các cột tương quan).
    public static func visibleRows(
        in store: ColumnStore,
        table: TableID,
        localFilters: [CodeSet],
        tableFilters: [TableFilter],
        overrides: [RelationshipOverride]
    ) throws -> RowSet {
        guard store.schema.table(table) != nil else { throw ColumnStoreError.unknownTable(table) }
        for filter in localFilters where store.schema.column(filter.column) == nil {
            throw ColumnStoreError.unknownColumn(filter.column)
        }
        for filter in tableFilters where store.schema.table(filter.table) == nil {
            throw ColumnStoreError.unknownTable(filter.table)
        }

        let links = try resolve(store.schema.relationships, overrides)
        let active = links.filter { $0.isActive }
        // Mơ hồ chỉ quan trọng khi có bộ lọc thật sự chảy đi từ bảng đó, nên chỉ kiểm nguồn có bộ lọc.
        let sources = Set(localFilters.map { $0.column.table }).union(tableFilters.map(\.table))
        try checkUnambiguous(active, sources: sources)

        // Chỉ các bảng ảnh hưởng tới R(table): tổ tiên của `table` trên đồ thị lan truyền (một → nhiều, thêm
        // nhiều → một nếu hai chiều), cộng tổ tiên của các bảng phía nhiều trỏ vào `table` (cần cho blank row).
        // Tập này đóng với phép lấy tổ tiên nên mọi tập trong đó bằng đúng giá trị khi tính trên cả model, mà bỏ
        // được các nhánh không liên quan (vd Fact_Transaction ~1 triệu dòng khi chỉ cần Fact_Loan).
        var feeders: [TableID: [TableID]] = [:]   // bảng → các bảng đẩy bộ lọc trực tiếp vào nó
        for link in active {
            feeders[link.many, default: []].append(link.one)
            if link.bothDirections { feeders[link.one, default: []].append(link.many) }
        }
        var roots: [TableID] = [table]
        for link in active where link.one == table { roots.append(link.many) }
        var involved: Set<TableID> = []
        while let next = roots.popLast() {
            guard involved.insert(next).inserted else { continue }
            roots.append(contentsOf: feeders[next] ?? [])
        }
        let relevant = active.filter { involved.contains($0.one) && involved.contains($0.many) }

        var sets: [TableID: RowSet] = [:]
        for t in involved.sorted(by: { $0.raw < $1.raw }) {
            var rows = try localRows(in: store, table: t, localFilters: localFilters)
            for filter in tableFilters where filter.table == t {
                rows = rows.intersection(try aligned(filter.rows, universe: rows.universe))
            }
            sets[t] = rows
        }

        // Điểm bất động lớn nhất: mọi bước chỉ thu hẹp, nên lặp tới khi không đổi.
        // Mỗi tập có một phiên bản, tăng khi tập đó thu hẹp. Quan hệ chỉ được xử lý lại khi phiên bản hai đầu
        // đã đổi từ lần xử lý trước, vì xử lý lại khi không đổi gì thì không thu hẹp thêm. Kết quả vẫn là điểm
        // bất động lớn nhất (các bước đơn điệu thu hẹp, nên thứ tự xử lý không đổi kết quả).
        var version: [TableID: Int] = [:]
        var processed = [(Int, Int)?](repeating: nil, count: relevant.count)
        var changed = true
        while changed {
            changed = false
            for (i, link) in relevant.enumerated() {
                let stamp = (version[link.one, default: 0], version[link.many, default: 0])
                if let last = processed[i], last == stamp { continue }
                processed[i] = stamp
                let index = try store.relationshipIndex(link.schema)
                let oneSet = sets[link.one]!
                let manySet = sets[link.many]!
                // Bên một đầy đủ (mọi dòng và blank row) thì mọi dòng bên nhiều đều khớp: bước này không thu hẹp gì.
                if oneSet.count < oneSet.universe {
                    let newMany = index.manyRows(from: oneSet, restrictedTo: manySet)
                    if newMany.count != manySet.count {
                        sets[link.many] = newMany
                        version[link.many, default: 0] += 1
                        changed = true
                    }
                }
                // Lan truyền ngược chỉ áp khi bên nhiều đã bị hạn chế. Bên nhiều không lọc thì không ẩn dòng bên một,
                // kể cả dòng không có dòng fact nào (xem ghi chú [SUY ĐOÁN] ở đầu file).
                if link.bothDirections, sets[link.many]!.count < sets[link.many]!.universe {
                    let oneNow = sets[link.one]!
                    let newOne = oneNow.intersection(index.oneRows(from: sets[link.many]!))
                    if newOne.count != oneNow.count {
                        sets[link.one] = newOne
                        version[link.one, default: 0] += 1
                        changed = true
                    }
                }
            }
        }

        // Blank row ảo của `table` chỉ thấy được khi có quan hệ hoạt động trỏ vào `table` và có dòng bên nhiều
        // đang thấy mà khoá không khớp (§3.3). Quan hệ không hoạt động không tạo dòng này.
        let result = sets[table]!
        var blankVisible = false
        for link in active where link.one == table {
            if try store.relationshipIndex(link.schema).hasUnmatched(in: sets[link.many]!) {
                blankVisible = true
                break
            }
        }
        if blankVisible {
            return result
        }
        // Bỏ blank row ảo (chỉ số rowCount) khi nó có trong kết quả. Tương đương giao với RowSet.all(rowCount).
        guard result.contains(try store.rowCount(table)) else { return result }
        let blank = UInt32(try store.rowCount(table))
        return RowSet(universe: result.universe, sortedRows: result.rows.filter { $0 < blank })
    }

    // MARK: - Quan hệ và ghi đè

    private struct Link: Sendable {
        let schema: RelationshipSchema
        var isActive: Bool
        var bothDirections: Bool

        var many: TableID { schema.manyColumn.table }
        var one: TableID { schema.oneColumn.table }
    }

    /// Áp ghi đè theo thứ tự. USERELATIONSHIP bật quan hệ và tắt mọi quan hệ hoạt động khác cùng cặp bảng.
    private static func resolve(_ relationships: [RelationshipSchema],
                                _ overrides: [RelationshipOverride]) throws -> [Link] {
        var links = relationships.map {
            Link(schema: $0, isActive: $0.isActive, bothDirections: $0.crossFilter == .bothDirections)
        }
        for override in overrides {
            guard let i = links.firstIndex(where: { $0.schema.id == override.relationship }) else {
                throw PropagationError.unknownRelationship(override.relationship)
            }
            if let active = override.isActive {
                if active {
                    links[i].isActive = true
                    let pair = tablePair(links[i])
                    for j in links.indices where j != i && tablePair(links[j]) == pair {
                        links[j].isActive = false
                    }
                } else {
                    links[i].isActive = false
                }
            }
            if let crossFilter = override.crossFilter {
                links[i].bothDirections = crossFilter == .bothDirections
            }
        }
        return links
    }

    private static func tablePair(_ link: Link) -> Set<TableID> {
        [link.many, link.one]
    }

    /// Đếm đường có hướng từ mỗi nguồn có bộ lọc. Hai đường khác nhau cùng tới một đích thì báo lỗi.
    /// Đường được đếm là đường đơn (không lặp đỉnh), nên chu trình hai chiều không tự gây lỗi.
    private static func checkUnambiguous(_ active: [Link], sources: Set<TableID>) throws {
        var out: [TableID: [TableID]] = [:]
        for link in active {
            out[link.one, default: []].append(link.many)
            if link.bothDirections {
                out[link.many, default: []].append(link.one)
            }
        }
        for source in sources.sorted(by: { $0.raw < $1.raw }) {
            var counts: [TableID: Int] = [:]
            var onPath: Set<TableID> = [source]
            try walk(from: source, source: source, out: out, counts: &counts, onPath: &onPath)
        }
    }

    private static func walk(from node: TableID, source: TableID, out: [TableID: [TableID]],
                             counts: inout [TableID: Int], onPath: inout Set<TableID>) throws {
        for next in out[node] ?? [] where !onPath.contains(next) {
            let n = (counts[next] ?? 0) + 1
            counts[next] = n
            if n > 1 {
                throw PropagationError.ambiguousPath(from: source, to: next)
            }
            onPath.insert(next)
            try walk(from: next, source: source, out: out, counts: &counts, onPath: &onPath)
            onPath.remove(next)
        }
    }

    // MARK: - Dòng cục bộ

    /// local(T): mọi dòng của T (kể cả blank row ảo) AND các bộ lọc trên cột của T.
    /// Bộ lọc theo mã: dòng có mã trong `codes`. Mã 0 khớp dòng BLANK, và blank row ảo có mã 0 ở mọi cột.
    private static func localRows(in store: ColumnStore, table: TableID,
                                  localFilters: [CodeSet]) throws -> RowSet {
        let rowCount = try store.rowCount(table)
        let universe = rowCount + 1
        let blankRow = UInt32(rowCount)
        // Các bộ lọc là giao nên thứ tự không đổi kết quả. Áp bộ lọc có ít dòng khớp trước.
        var steps: [(index: ColumnIndex, codes: [UInt32], estimate: Int)] = []
        for filter in localFilters where filter.column.table == table {
            let index = try store.index(filter.column)
            guard index.column.isEncoded else {
                throw ColumnStoreError.notImplemented("Lọc theo mã trên cột dense \(filter.column)")
            }
            let codes = Array(Set(filter.codes)).sorted()
            var estimate = codes.contains(0) ? 1 : 0
            for code in codes {
                if let slice = index.postings(forCode: Int(code)) {
                    estimate += slice.count
                }
            }
            steps.append((index, codes, estimate))
        }
        steps.sort { $0.estimate < $1.estimate }

        // nil nghĩa là chưa có bộ lọc nào: tập là mọi dòng cộng blank row ảo.
        var rows: RowSet?
        for step in steps {
            if let current = rows, current.count <= step.estimate {
                // Ít dòng hiện có hơn số dòng khớp: giữ các dòng có mã thuộc bộ mã. Blank row ảo có mã 0.
                var kept: [UInt32] = []
                current.forEach { r in
                    let code = r < rowCount ? UInt32(step.index.column.code(atRow: r) ?? 0) : 0
                    if containsSorted(step.codes, code) { kept.append(UInt32(r)) }
                }
                rows = RowSet(universe: universe, sortedRows: kept)
            } else {
                var matched: [UInt32] = []
                for code in step.codes {
                    if let slice = step.index.postings(forCode: Int(code)) {
                        matched.append(contentsOf: slice)
                    }
                }
                matched.sort()
                if step.codes.contains(0) {
                    matched.append(blankRow)
                }
                let set = RowSet(universe: universe, sortedRows: matched)
                rows = rows.map { $0.intersection(set) } ?? set
            }
        }
        return rows ?? RowSet.all(rowCount: rowCount)
            .union(RowSet(universe: universe, sortedRows: [blankRow]))
    }

    /// Đưa tập dòng về đúng universe của bảng (số dòng + 1). Tập dựng không kèm blank row ảo (universe = số dòng)
    /// được nới ra; dòng nằm ngoài universe là lỗi của người gọi.
    private static func aligned(_ rows: RowSet, universe: Int) throws -> RowSet {
        if rows.universe == universe { return rows }
        let kept = rows.rows
        guard kept.allSatisfy({ Int($0) < universe }) else {
            throw ColumnStoreError.notImplemented("TableFilter có dòng ngoài phạm vi bảng (universe \(rows.universe) > \(universe))")
        }
        return RowSet(universe: universe, sortedRows: kept)
    }

    /// `codes` đã sắp tăng dần, không trùng. Tìm nhị phân.
    private static func containsSorted(_ codes: [UInt32], _ x: UInt32) -> Bool {
        var lo = 0, hi = codes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if codes[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        return lo < codes.count && codes[lo] == x
    }

}
