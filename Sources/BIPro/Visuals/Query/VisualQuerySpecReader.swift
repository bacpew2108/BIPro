// Gói Q (Phase C, lead): visual.json + metadata của model + bộ lọc → VisualQuerySpec.
//
// Quy tắc lấy từ 72 truy vấn Performance Analyzer thật của Nhom6 (docs/phase-c-evidence/C1.md §2, observe-c1/, observe2/).
// Đây là trạng thái MẶC ĐỊNH của visual (chưa chọn, chưa drill). Tương tác (slicer, lọc chéo, tô sáng, drill) là gói I/G.
import DAXEngine
import Foundation
import PBIXKit

struct VisualQuerySpecReader {
    let metadata: ModelMetadata

    /// Tên cột của model (chữ thường), để thêm hậu tố "2" khi tên cột kết quả trùng (C1.md §2.1).
    private let modelColumnNames: Set<String>
    private let columnsByID: [Int: ModelMetadata.Column]

    init(metadata: ModelMetadata) {
        self.metadata = metadata
        self.modelColumnNames = Set(metadata.columns.map { $0.name.lowercased() })
        self.columnsByID = Dictionary(metadata.columns.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    enum ReadError: Error, Equatable {
        case notDataBound
        case unsupported(String)
    }

    /// `filters`: bộ lọc áp lên visual theo thứ tự Power BI đặt tên `__DS0FilterTable[n]`:
    /// cấp visual, rồi cấp trang, rồi cấp report (C1.md §2.2).
    func spec(for visual: ReportVisual, filters: [ReportFilter]) throws -> VisualQuerySpec {
        let body = visual.raw["visual"] ?? visual.raw
        guard let queryState = body["query"]?["queryState"] else { throw ReadError.notDataBound }
        let type = visual.type
        let format = VisualFormat(objects: visual.objects)
        let shape = Self.shape(of: type)

        var spec = VisualQuerySpec(visualID: visual.id, visualType: type)
        spec.shape = shape
        spec.filters = filters.compactMap(Self.translate)

        // Trục.
        switch shape {
        case .slicer:
            spec.primary = Array(groupFields(queryState["Values"], role: "Values", activeOnly: false).prefix(1))
            let levels = queryState["Values"]?["projections"]?.array.count ?? 0
            spec.shape = .slicer(top: levels > 1 ? 501 : 101)
            let active = groupFields(queryState["Values"], role: "Values", activeOnly: true)
            if active.count >= 2 {
                spec.drillLevels = active
                spec.expanded = Self.expandedRoots(body["expansionStates"])
            }
        case .matrix:
            let allRows = groupFields(queryState["Rows"], role: "Rows", activeOnly: false)
            spec.primary = Array(allRows.prefix(1))
            if allRows.count >= 2 {
                spec.rowDrillLevels = allRows
                spec.rowExpandedPaths = Self.expandedPaths(in: body["expansionStates"], role: "Rows")
            }
            spec.secondary = Array(groupFields(queryState["Columns"], role: "Columns", activeOnly: false).prefix(1))
        case .treemap:
            spec.primary = Array(groupFields(queryState["Group"], role: "Group", activeOnly: false).prefix(1))
        case .donut:
            spec.primary = Array(groupFields(queryState["Category"], role: "Category", activeOnly: false).prefix(1))
        case .table, .multiRowCard:
            spec.primary = groupFields(queryState["Values"], role: "Values", activeOnly: false)
        case .kpi:
            spec.primary = groupFields(queryState["TrendLine"], role: "TrendLine", activeOnly: false)
        case .gauge:
            spec.primary = []
            spec.secondary = []
        case .scatter:
            spec.primary = groupFields(queryState["Category"], role: "Category", activeOnly: true)
            spec.secondary = groupFields(queryState["Series"], role: "Series", activeOnly: true)
        default:
            spec.primary = groupFields(queryState["Category"], role: "Category", activeOnly: true)
            // Thác nước dùng ô Breakdown thay cho Series (VM-D16: Category, Breakdown, Y).
            let legendRole = type == "waterfallChart" ? "Breakdown" : "Series"
            spec.secondary = groupFields(queryState[legendRole], role: legendRole, activeOnly: true)
        }

        // Measure theo thứ tự vai trò. Card, gauge và shape map: mọi measure IGNORE; Tooltips luôn IGNORE.
        var used = Set<String>()
        var values: [QueryMeasure] = []
        var scoped: [QueryMeasure] = []
        let roleOrder = ["Y", "Y2", "X", "Size", "MinValue", "MaxValue", "TargetValue", "Indicator", "Goal", "Values", "Data", "Value", "Tooltips"]
        let allIgnored = shape == .card || shape == .shapeMap || shape == .gauge
        let splitScope = shape == .chart && !spec.secondary.isEmpty && queryState["Y2"] != nil
        for role in roleOrder where !(shape.isSlicer) {
            for projection in queryState[role]?["projections"]?.array ?? [] {
                if let aggregated = implicitAggregation(projection, role: role, ignore: allIgnored || role == "Tooltips",
                                                        used: &used) {
                    if splitScope && role == "Y2" { scoped.append(aggregated) } else { values.append(aggregated) }
                    if (shape == .table || shape == .multiRowCard) && role == "Values" {
                        spec.orderedFields.append(aggregated.field)
                    }
                    continue
                }
                if let (table, name) = Self.measureRef(projection["field"]) {
                    let field = FieldInfo(queryRef: projection["queryRef"]?.string ?? "\(table).\(name)",
                                          displayName: projection["displayName"]?.string ?? name, role: role,
                                          formatString: metadataMeasure(table, name)?.formatString, isMeasure: true)
                    let ignore = allIgnored || role == "Tooltips"
                    let group = measureWithFormat(table: table, name: name, field: field, ignore: ignore,
                                                  purpose: role == "Tooltips" ? .tooltip : .value, used: &used)
                    if splitScope && role == "Y2" { scoped += group } else { values += group }
                    if (shape == .table || shape == .multiRowCard) && role == "Values" {
                        spec.orderedFields.append(field)
                    }
                } else if (shape == .table || shape == .multiRowCard) && role == "Values",
                          let col = column(of: projection["field"]) {
                    let meta = metadataColumn(col.table, col.column)
                    let field = FieldInfo(queryRef: projection["queryRef"]?.string ?? "\(col.table).\(col.column)",
                                          displayName: projection["displayName"]?.string ?? col.column, role: role,
                                          formatString: meta?.formatString, isMeasure: false)
                    spec.orderedFields.append(field)
                }
            }
        }
        // Thuộc tính lấy từ measure (màu, icon). Card: đứng trước giá trị (D1-card-tienvao-delta, D3-card-khachhang-sub).
        var driven: [QueryMeasure] = []
        for property in format.measureDriven {
            let already = (values + scoped + driven).contains { $0.table == property.sourceTable && $0.measure == property.sourceMeasure }
            if already { continue }
            let field = FieldInfo(queryRef: "\(property.sourceTable).\(property.sourceMeasure)",
                                  displayName: property.sourceMeasure, role: "Format", formatString: nil, isMeasure: true)
            driven.append(QueryMeasure(field: field, table: property.sourceTable, measure: property.sourceMeasure,
                                       resultName: resultName(property.sourceMeasure, used: &used), ignore: true,
                                       purpose: .formatting(property)))
        }
        if shape == .card {
            // [SUY ĐOÁN] Hai mẫu card Δ đều đặt measure màu trước measure nhãn; có thể là thứ tự A–Z.
            spec.measures = (driven + values).sorted { $0.resultName < $1.resultName }
        } else {
            spec.measures = values + driven
        }
        spec.scopedMeasures = scoped

        // Matrix: tổng và thang màu.
        if shape == .matrix {
            spec.rowTotals = format.matrix.rowSubtotals ?? true
            spec.columnTotals = format.matrix.columnSubtotals ?? true
            spec.gradientInputs = format.gradients.compactMap { rule in
                spec.measures.first { $0.table == rule.inputTable && $0.measure == rule.inputMeasure }?.resultName
            }
        }

        // Matrix: các cấp hierarchy ở Columns, để mở nút (+) cấp gốc xuống cấp kế.
        if shape == .matrix {
            let levels = groupFields(queryState["Columns"], role: "Columns", activeOnly: false)
            if levels.count > 1 { spec.drillLevels = levels }
        }

        // Drill: mọi cấp của hierarchy ở trục danh mục (chart, donut và treemap; treemap dùng ô Group, VM 2026-11-23).
        if shape == .chart || shape == .donut {
            let levels = groupFields(queryState["Category"], role: "Category", activeOnly: false)
            if levels.count > 1 { spec.drillLevels = levels }
        } else if shape == .treemap {
            let levels = groupFields(queryState["Group"], role: "Group", activeOnly: false)
            if levels.count > 1 { spec.drillLevels = levels }
        }

        // Sắp xếp và giảm dữ liệu.
        spec.primaryOrder = order(for: spec, sortDefinition: body["query"]?["sortDefinition"], shape: shape)
        spec.secondaryOrder = spec.secondary.flatMap(Self.ascendingKeys)
        spec.reduction = reduction(for: spec, format: format)
        spec.includeIntersectionCount = { if case .binnedLine = spec.reduction { true } else { false } }()
        return spec
    }

    // MARK: - Trường

    private static func shape(of type: String) -> QueryShape {
        switch type {
        case "card", "cardVisual": .card
        case "slicer", "advancedSlicerVisual", "listSlicer", "textSlicer": .slicer(top: 101)
        case "donutChart", "pieChart": .donut
        case "treemap": .treemap
        case "shapeMap", "filledMap": .shapeMap
        case "pivotTable", "matrix": .matrix
        case "tableEx", "table": .table
        case "scatterChart": .scatter
        case "gauge": .gauge
        case "kpi": .kpi
        case "multiRowCard": .multiRowCard
        case "hundredPercentStackedColumnChart", "hundredPercentStackedBarChart": .hundredPercent
        default: .chart
        }
    }

    private static func measureRef(_ field: JSONValue?) -> (String, String)? {
        guard let m = field?["Measure"], let table = m["Expression"]?["SourceRef"]?["Entity"]?.string,
              let name = m["Property"]?.string else { return nil }
        return (table, name)
    }

    private func metadataMeasure(_ table: String, _ name: String) -> ModelMetadata.Measure? {
        metadata.measures.first { $0.tableName == table && $0.name == name }
    }

    private func metadataColumn(_ table: String, _ name: String) -> ModelMetadata.Column? {
        metadata.columns.first { $0.tableName == table && $0.name == name }
    }

    /// Cột của một projection: cột trực tiếp, hoặc cấp hierarchy quy về cột của cấp đó.
    private func column(of field: JSONValue?) -> QueryColumn? {
        if let c = field?["Column"], let table = c["Expression"]?["SourceRef"]?["Entity"]?.string,
           let name = c["Property"]?.string {
            return QueryColumn(table: table, column: name)
        }
        if let level = field?["HierarchyLevel"], let levelName = level["Level"]?.string {
            let hierarchy = level["Expression"]?["Hierarchy"]
            let hierarchyName = hierarchy?["Hierarchy"]?.string
            // Phân cấp ngày của Auto date/time (VM-F11b): `PropertyVariationSource` trỏ cột ngày; `Variation` của cột đó dẫn tới bảng ngày
            // cục bộ, mỗi cấp là cột cùng tên của bảng ấy (mẫu `AutoDateTime.hierarchyLevels`).
            if let variation = hierarchy?["Expression"]?["PropertyVariationSource"] {
                guard let table = variation["Expression"]?["SourceRef"]?["Entity"]?.string, let property = variation["Property"]?.string,
                      let target = metadata.variations.first(where: {
                          $0.table == table && $0.column == property && $0.name == (variation["Name"]?.string ?? $0.name)
                              && (hierarchyName == nil || $0.hierarchy.name == hierarchyName)
                      }) else { return nil }
                let local = target.hierarchy.table
                let h = metadata.hierarchies.first { $0.tableName == local && $0.name == target.hierarchy.name }
                let columnName = h?.levels.first(where: { $0.name == levelName })?.columnName ?? levelName
                guard metadataColumn(local, columnName) != nil else { return nil }
                return QueryColumn(table: local, column: columnName)
            }
            guard let table = hierarchy?["Expression"]?["SourceRef"]?["Entity"]?.string else { return nil }
            let h = metadata.hierarchies.first { $0.tableName == table && (hierarchyName == nil || $0.name == hierarchyName) }
            guard let columnName = h?.levels.first(where: { $0.name == levelName })?.columnName else { return nil }
            return QueryColumn(table: table, column: columnName)
        }
        return nil
    }

    /// Các trường nhóm của một vai trò. `activeOnly`: với trục có nhiều cấp hierarchy (drill), chỉ lấy cấp `active`
    /// (không có cờ thì cấp đầu).
    private func groupFields(_ state: JSONValue?, role: String, activeOnly: Bool) -> [GroupField] {
        var projections = state?["projections"]?.array ?? []
        if activeOnly, projections.count > 1, projections.contains(where: { $0["active"] != nil }) {
            projections = projections.filter { $0["active"]?.bool == true }
            if projections.isEmpty { projections = Array((state?["projections"]?.array ?? []).prefix(1)) }
        }
        return projections.compactMap { p in
            guard let col = column(of: p["field"]) else { return nil }
            let meta = metadataColumn(col.table, col.column)
            let sortBy = meta?.sortByColumnID.flatMap { columnsByID[$0] }.map { QueryColumn(table: $0.tableName, column: $0.name) }
            let field = FieldInfo(queryRef: p["queryRef"]?.string ?? "\(col.table).\(col.column)",
                                  displayName: p["displayName"]?.string ?? col.column, role: role,
                                  formatString: meta?.formatString, isMeasure: false)
            return GroupField(field: field, column: col, sortBy: sortBy)
        }
    }

    // MARK: - Phép gộp ngầm

    /// Trường `Aggregation` (cột kèm phép gộp, VM-F10). Nhãn: tên đổi riêng của visual nếu có, không thì nhãn tiếng Việt theo phép gộp.
    private func implicitAggregation(_ projection: JSONValue, role: String, ignore: Bool, used: inout Set<String>) -> QueryMeasure? {
        guard let aggregation = projection["field"]?["Aggregation"],
              let column = aggregation["Expression"]?["Column"],
              let table = column["Expression"]?["SourceRef"]?["Entity"]?.string,
              let name = column["Property"]?.string,
              let code = aggregation["Function"]?.number, let function = AggregateFunction(rawValue: Int(code)) else { return nil }
        let meta = metadataColumn(table, name)
        let kind = Self.kind(of: meta?.dataType)
        let keepsFormat: Set<AggregateFunction> = [.sum, .average, .min, .max, .median]
        let field = FieldInfo(queryRef: projection["queryRef"]?.string ?? "\(function.resultPrefix)(\(table).\(name))",
                              displayName: projection["displayName"]?.string ?? function.label(column: name, kind: kind, language: appResolvedLanguage()), role: role,
                              formatString: keepsFormat.contains(function) ? meta?.formatString : nil, isMeasure: true)
        return QueryMeasure(field: field, table: table, measure: name, resultName: resultName(function.resultPrefix + name, used: &used),
                            ignore: ignore, purpose: role == "Tooltips" ? .tooltip : .value, aggregation: function)
    }

    static func kind(of type: ModelMetadata.DataType?) -> AggregateFunction.ColumnKind {
        switch type {
        case .string?: .text
        case .dateTime?: .date
        default: .number
        }
    }

    // MARK: - Measure

    /// Tên cột kết quả theo quy tắc C1.md §2.1.
    func resultName(_ measure: String, used: inout Set<String>) -> String {
        var base = String(measure.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        if let first = base.first, !first.isLetter { base = "v" + base }
        var name = base
        var n = 1
        // [SUY ĐOÁN] So với mọi cột của model (mọi bảng), không phân biệt hoa thường; trùng tiếp thì tăng số.
        while modelColumnNames.contains(name.lowercased()) || used.contains(name.lowercased()) {
            n += 1
            name = base + String(n)
        }
        used.insert(name.lowercased())
        return name
    }

    /// Measure, kèm cột định dạng động ngay sau nếu measure có `formatStringDefinition`.
    private func measureWithFormat(table: String, name: String, field: FieldInfo, ignore: Bool,
                                   purpose: QueryMeasure.Purpose, used: inout Set<String>) -> [QueryMeasure] {
        var out = [QueryMeasure(field: field, table: table, measure: name, resultName: resultName(name, used: &used),
                                ignore: ignore, purpose: purpose)]
        if let def = metadataMeasure(table, name)?.formatStringDefinition, !def.isEmpty {
            let hidden = "_\(name) FormatString"
            let fmtField = FieldInfo(queryRef: "\(table).\(hidden)", displayName: hidden, role: "Format",
                                     formatString: nil, isMeasure: true)
            out.append(QueryMeasure(field: fmtField, table: table, measure: hidden, resultName: resultName(hidden, used: &used),
                                    ignore: true, purpose: .formatString(of: field.queryRef)))
        }
        return out
    }

    // MARK: - Drill

    /// Giá trị cấp gốc đang mở nút trong `expansionStates` của slicer (nút `isToggled`).
    static func expandedRoots(_ states: JSONValue?) -> [Value] {
        expandedPaths(in: states, role: "Values").compactMap(\.first)
    }

    /// Đọc toàn bộ đường giá trị đang mở (`isToggled: true`) trong `expansionStates` theo vai trò (`"Rows"`, `"Columns"`, `"Values"` — VM-V11B).
    static func expandedPaths(in states: JSONValue?, role: String) -> [[Value]] {
        guard let list = states?.array else { return [] }
        let matched = list.first { entry in
            let roles = entry["roles"]?.array.compactMap(\.string) ?? []
            return roles.contains(role) || (role == "Values" && roles.isEmpty)
        } ?? (role == "Values" ? list.first : nil)
        guard let root = matched?["root"] else { return [] }
        var out: [[Value]] = []
        func decode(_ raw: String) -> Value? {
            switch ReportLiteral(literal: raw) {
            case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? .integer(Int64(n)) : .double(n)
            case .string(let t): return .string(t)
            case .bool(let b): return .boolean(b)
            default: return nil
            }
        }
        func walk(_ node: JSONValue, prefix: [Value]) {
            for child in node["children"]?.array ?? [] {
                guard let raw = child["identityValues"]?[0]?["Literal"]?["Value"]?.string,
                      let val = decode(raw) else { continue }
                let path = prefix + [val]
                if child["isToggled"]?.bool == true { out.append(path) }
                walk(child, prefix: path)
            }
        }
        walk(root, prefix: [])
        return out
    }

    /// Đưa spec xuống cấp `depth` của hierarchy (0 = cấp gốc). Chart nhóm theo mọi cấp từ gốc tới `depth` (C1.md §2.2:
    /// `year, quarter_name, quarter_num`); donut chỉ hiện cấp `depth`, các cấp trên thành bộ lọc drill.
    static func applyDrill(_ spec: inout VisualQuerySpec, depth: Int) {
        guard depth > 0, spec.drillLevels.count > depth else { return }
        if case .donut = spec.shape {
            spec.primary = [spec.drillLevels[depth]]
        } else if case .treemap = spec.shape {
            // Desktop: treemap sau drill chỉ vẽ cấp con của điểm đã chọn (cấp trên thành bộ lọc drill).
            spec.primary = [spec.drillLevels[depth]]
        } else {
            spec.primary = Array(spec.drillLevels.prefix(depth + 1))
        }
        spec.primaryOrder = spec.primary.flatMap(ascendingKeys)
    }

    // MARK: - Sắp xếp, giảm dữ liệu

    static func ascendingKeys(_ g: GroupField) -> [QuerySortKey] {
        (g.sortBy.map { [QuerySortKey(target: .column($0), ascending: true)] } ?? [])
            + [QuerySortKey(target: .column(g.column), ascending: true)]
    }

    private func order(for spec: VisualQuerySpec, sortDefinition: JSONValue?, shape: QueryShape) -> [QuerySortKey] {
        let byAxis = spec.primary.flatMap(Self.ascendingKeys)
        if let first = sortDefinition?["sort"]?[0] {
            let ascending = first["direction"]?.string != "Descending"
            if let (table, name) = Self.measureRef(first["field"]),
               let m = spec.measures.first(where: { $0.table == table && $0.measure == name }) {
                return [QuerySortKey(target: .result(m.resultName), ascending: ascending)] + byAxis
            }
            // Sắp theo trường gộp ngầm (VM-F10: mặc định giảm dần theo giá trị đầu, `isDefaultSort`).
            if let aggregation = first["field"]?["Aggregation"], let column = aggregation["Expression"]?["Column"],
               let table = column["Expression"]?["SourceRef"]?["Entity"]?.string, let name = column["Property"]?.string,
               let code = aggregation["Function"]?.number,
               let m = spec.measures.first(where: { $0.table == table && $0.measure == name && $0.aggregation?.rawValue == Int(code) }) {
                return [QuerySortKey(target: .result(m.resultName), ascending: ascending)] + byAxis
            }
            if let col = column(of: first["field"]), let g = spec.primary.first(where: { $0.column == col }) {
                return Self.ascendingKeys(g).map { QuerySortKey(target: $0.target, ascending: ascending) }
            }
        }
        // Treemap mặc định theo giá trị giảm dần (D3-treemap); phễu cũng vậy (VM-D15 mục 4: 2018 đứng đầu vì lớn nhất).
        if shape == .treemap || spec.visualType == "funnel" || spec.visualType == "waterfallChart", let m = spec.measures.first(where: { !$0.ignore }) {
            return [QuerySortKey(target: .result(m.resultName), ascending: false)] + byAxis
        }
        return byAxis
    }

    private func reduction(for spec: VisualQuerySpec, format: VisualFormat) -> DataReduction {
        switch spec.shape {
        case .card, .gauge: return .none
        case .slicer(let top): return .top(top)
        case .donut, .treemap: return .top(1002)
        case .shapeMap, .scatter: return .top(3502)
        case .table, .multiRowCard: return .top(501)
        case .kpi: return .top(1001)
        case .matrix: return .window(primary: spec.rowTotals ? 102 : 101, secondary: 102)
        case .hundredPercent: return .none
        case .chart:
            if !spec.secondary.isEmpty { return .window(primary: 201, secondary: 62) }
            // Trục liên tục: một cột số/ngày, không ép Categorical.
            if spec.primary.count == 1, format.categoryAxis.axisType != "Categorical",
               let meta = metadataColumn(spec.primary[0].column.table, spec.primary[0].column.column),
               meta.dataType.isNumeric || meta.dataType == .dateTime {
                if spec.visualType == "lineChart" || spec.visualType == "areaChart" {
                    return .binnedLine(size: 3500, minResolution: 350, maxResolution: 105_000, maxIterations: 60)
                }
                return .sample(3502)
            }
            return .top(1001)
        }
    }

    // MARK: - Bộ lọc tĩnh (Categorical In / Not In). Gói I sẽ mở rộng (slicer, lọc chéo, drillthrough).

    static func translate(_ filter: ReportFilter) -> QueryFilter? {
        guard let sf = staticFilter(filter, scope: .report) else { return nil }
        return QueryFilter(tableExpression: "FILTER(KEEPFILTERS(VALUES(\(sf.column.dax))), \(sf.predicate))")
    }

    /// Bộ lọc report/page/visual trên một cột, dạng cột + vị từ DAX (để `FilterTranslator.assemble` ghép với tương tác).
    static func staticFilter(_ filter: ReportFilter, scope: FilterScope) -> StaticFilter? {
        // Bộ lọc Advanced: dịch qua cùng mô hình với Filters pane, để file và giao diện ra cùng văn bản DAX.
        // Top N cũng vậy. Thẻ measure không phải bộ lọc cột (lọc dòng kết quả, xem `ReportInteraction.valueFilters`).
        if filter.type == "Advanced" || filter.type == "TopN" {
            guard let user = UserFilter.from(filter), !user.isMeasure, let predicate = user.predicate else { return nil }
            return StaticFilter(column: user.column, predicate: predicate, scope: scope)
        }
        let raw = filter.raw
        guard let conditions = raw["filter"]?["Where"]?.array, !conditions.isEmpty,
              let field = raw["field"]?["Column"], let table = field["Expression"]?["SourceRef"]?["Entity"]?.string,
              let name = field["Property"]?.string else { return nil }
        let column = QueryColumn(table: table, column: name)
        let parts = conditions.compactMap { condition(($0["Condition"]), column: column) }
        guard !parts.isEmpty else { return nil }
        let predicate = parts.count == 1 ? parts[0] : "AND(" + parts.joined(separator: ", ") + ")"
        return StaticFilter(column: column, predicate: predicate, scope: scope)
    }

    private static func condition(_ json: JSONValue?, column: QueryColumn) -> String? {
        guard let json else { return nil }
        if let inner = json["Not"]?["Expression"] {
            return condition(inner, column: column).map { "NOT(\($0))" }
        }
        if let values = json["In"]?["Values"]?.array {
            let literals = values.compactMap { $0[0].flatMap(literal) }
            return "\(column.dax) IN {\(literals.joined(separator: ", "))}"
        }
        return nil
    }

    /// Literal của bộ lọc PBIR → DAX: `9999L` → 9999, `'Unknown'` → "Unknown", `true` → TRUE.
    static func literal(_ json: JSONValue) -> String? {
        guard let raw = json["Literal"]?["Value"]?.string else { return nil }
        switch ReportLiteral(literal: raw) {
        case .string(let s): return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "TRUE" : "FALSE"
        case .null: return "BLANK()"
        default: return nil
        }
    }
}

extension QueryShape {
    var isSlicer: Bool { if case .slicer = self { true } else { false } }
}
