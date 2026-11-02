// Gói Q (Phase C, lead): VisualQuerySpec → văn bản DAX theo đúng khuôn Performance Analyzer của Power BI.
//
// Khuôn lấy từ 72 truy vấn thật (C1.md §2.3). Văn bản được so với truy vấn thật SAU KHI CHUẨN HOÁ KHOẢNG TRẮNG
// (`DAXQueryBuilder.normalized`), vì Power BI xuống dòng theo khuôn riêng chứ không theo độ rộng cố định.
// Chỗ xuống dòng ở đây theo dạng Power BI hay dùng, để dễ đọc khi dán vào DAX Query View.
import Foundation

enum DAXQueryBuilder {
    // MARK: - Khung văn bản

    private struct Writer {
        var vars: [(name: String, body: String)] = []
        var statements: [(table: String, orderBy: [String])] = []

        mutating func variable(_ name: String, _ body: String) { vars.append((name, body)) }
        mutating func evaluate(_ table: String, orderBy: [String] = []) { statements.append((table, orderBy)) }

        func text() -> String {
            var out = "// DAX Query\n"
            if !vars.isEmpty {
                out += "DEFINE\n"
                out += vars.map { "\tVAR \($0.name) = \n" + indent($0.body, 2) }.joined(separator: "\n\n") + "\n\n"
            }
            out += statements.map { s in
                var text = "EVALUATE\n" + indent(s.table, 1)
                if !s.orderBy.isEmpty { text += "\n\nORDER BY\n\t" + s.orderBy.joined(separator: ", ") }
                return text
            }.joined(separator: "\n\n")
            return out + "\n"
        }

        private func indent(_ body: String, _ level: Int) -> String {
            let pad = String(repeating: "\t", count: level)
            return body.split(separator: "\n", omittingEmptySubsequences: false).map { pad + $0 }.joined(separator: "\n")
        }
    }

    /// Lời gọi hàm nhiều dòng: `F(\n\targ,\n\targ\n)`.
    private static func call(_ name: String, _ args: [String]) -> String {
        name + "(\n" + args.map { $0.split(separator: "\n", omittingEmptySubsequences: false).map { "\t" + $0 }.joined(separator: "\n") }
            .joined(separator: ",\n") + "\n)"
    }

    private static func inline(_ name: String, _ args: [String]) -> String { name + "(" + args.joined(separator: ", ") + ")" }

    // MARK: - Thành phần

    private static func filterNames(_ spec: VisualQuerySpec) -> [String] {
        spec.filters.indices.map { $0 == 0 ? "__DS0FilterTable" : "__DS0FilterTable\($0 + 1)" }
    }

    private static func filterVar(_ f: QueryFilter) -> String {
        // FILTER(KEEPFILTERS(VALUES(c)), điều kiện) viết nhiều dòng như Power BI.
        let text = f.tableExpression
        guard text.hasPrefix("FILTER("), text.hasSuffix(")"),
              let split = topLevelArguments(String(text.dropFirst(7).dropLast())) else { return text }
        return call("FILTER", split)
    }

    /// Tách đối số cấp ngoài cùng theo dấu phẩy (bỏ qua ngoặc, ngoặc nhọn, chuỗi).
    static func topLevelArguments(_ text: String) -> [String]? {
        var parts: [String] = []
        var depth = 0
        var current = ""
        var inString = false
        for ch in text {
            if ch == "\"" { inString.toggle() }
            if !inString {
                if "({[".contains(ch) { depth += 1 }
                if ")}]".contains(ch) { depth -= 1 }
                if ch == ",", depth == 0 {
                    parts.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    continue
                }
            }
            current.append(ch)
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return depth == 0 ? parts : nil
    }

    private static func groupColumns(_ groups: [GroupField]) -> [String] {
        groups.flatMap { [$0.column.dax] + ($0.sortBy.map { [$0.dax] } ?? []) }
    }

    private static func measureArgs(_ measures: [QueryMeasure]) -> [String] {
        measures.map { m in
            let ref = "\(QueryColumn(table: m.table, column: m.measure).dax)"
            return "\"\(m.resultName)\", " + (m.ignore ? "IGNORE(\(ref))" : ref)
        }
    }

    private static func key(_ k: QuerySortKey) -> String {
        switch k.target {
        case .column(let c): c.dax
        case .result(let name): "[\(name)]"
        }
    }

    private static func topnKeys(_ keys: [QuerySortKey]) -> [String] {
        keys.flatMap { [key($0), $0.ascending ? "1" : "0"] }
    }

    private static func orderBy(_ keys: [QuerySortKey]) -> [String] {
        keys.map { key($0) + ($0.ascending ? "" : " DESC") }
    }

    // MARK: - Dựng truy vấn

    static func build(_ spec: VisualQuerySpec) -> String {
        var w = Writer()
        let filters = filterNames(spec)
        for (name, f) in zip(filters, spec.filters) { w.variable(name, filterVar(f)) }

        switch spec.shape {
        case .card:
            w.evaluate(call("SUMMARIZECOLUMNS", filters + measureArgs(spec.measures)))

        case .slicer(let top):
            guard let g = spec.primary.first else { break }
            let source = g.sortBy.map { inline("SUMMARIZE", ["VALUES('\(g.column.table)')", g.column.dax, $0.dax]) }
                ?? "VALUES(\(g.column.dax))"
            let core = filters.isEmpty ? source
                : call("CALCULATETABLE", [source] + filters.map { "KEEPFILTERS(\($0))" })
            w.variable("__DS0Core", core)
            w.variable("__DS0PrimaryWindowed", inline("TOPN", ["\(top)", "__DS0Core"] + topnKeys(spec.primaryOrder)))
            w.evaluate("__DS0PrimaryWindowed", orderBy: orderBy(spec.primaryOrder))

        case .donut:
            guard let g = spec.primary.first else { break }
            let rollup = inline("ROLLUPADDISSUBTOTAL", [g.column.dax, "\"IsGrandTotalRowTotal\""])
            w.variable("__DS0Core", call("SUMMARIZECOLUMNS", [rollup] + filters + measureArgs(spec.measures)))
            let keys = [QuerySortKey(target: .result("IsGrandTotalRowTotal"), ascending: false)] + spec.primaryOrder
            w.variable("__DS0BodyLimited", inline("TOPN", ["1002", "__DS0Core"] + topnKeys(keys)))
            w.evaluate("__DS0BodyLimited", orderBy: orderBy(keys))

        case .treemap:
            w.variable("__DS0Core", call("SUMMARIZECOLUMNS", groupColumns(spec.primary) + filters + measureArgs(spec.measures)))
            w.variable("__DS0BodyLimited", inline("TOPN", ["1002", "__DS0Core"] + topnKeys(spec.primaryOrder)))
            w.evaluate("__DS0BodyLimited", orderBy: orderBy(spec.primaryOrder))

        case .shapeMap:
            guard let g = spec.primary.first else { break }
            let inner = call("SUMMARIZECOLUMNS", groupColumns(spec.primary) + filters + measureArgs(spec.measures))
            w.variable("__DS0Core", call("FILTER", [call("KEEPFILTERS", [inner]), "NOT(ISBLANK(\(g.column.dax)))"]))
            w.variable("__DS0BodyLimited", inline("TOPN", ["3502", "__DS0Core"] + topnKeys(spec.primaryOrder)))
            w.evaluate("__DS0BodyLimited", orderBy: orderBy(spec.primaryOrder))

        case .matrix:
            buildMatrix(spec, filters: filters, into: &w)

        case .hundredPercent:
            buildHundredPercent(spec, filters: filters, into: &w)

        case .chart:
            if spec.secondary.isEmpty {
                buildSingleAxis(spec, filters: filters, into: &w)
            } else {
                buildTwoAxis(spec, filters: filters, into: &w)
            }
        }
        return w.text()
    }

    private static func buildSingleAxis(_ spec: VisualQuerySpec, filters: [String], into w: inout Writer) {
        w.variable("__DS0Core", call("SUMMARIZECOLUMNS", groupColumns(spec.primary) + filters + measureArgs(spec.measures)))
        switch spec.reduction {
        case .binnedLine(let size, let minRes, let maxRes, let maxIter):
            let axis = spec.primary.first?.column.dax ?? ""
            let firstValue = spec.measures.first { !$0.ignore }.map { "[\($0.resultName)]" } ?? ""
            w.variable("__DS0IntersectionCount", "CALCULATE(COUNTROWS(__DS0Core))")
            w.variable("__DS0BodyBinnedSample", inline("SAMPLEAXISWITHLOCALMINMAX",
                ["\(size)", "__DS0Core", axis, firstValue, "\(minRes)", "", "ALPHABETICAL", "ASC", "\(maxRes)", "\(maxIter)"]))
            w.evaluate(call("ROW", ["\"DS0IntersectionCount\", __DS0IntersectionCount"]))
            w.evaluate("__DS0BodyBinnedSample", orderBy: orderBy(spec.primaryOrder))
        case .sample(let n):
            w.variable("__DS0BodyLimited", inline("SAMPLE", ["\(n)", "__DS0Core"] + topnKeys(spec.primaryOrder)))
            w.evaluate("__DS0BodyLimited", orderBy: orderBy(spec.primaryOrder))
        default:
            let n: Int = { if case .top(let n) = spec.reduction { n } else { 1001 } }()
            w.variable("__DS0PrimaryWindowed", inline("TOPN", ["\(n)", "__DS0Core"] + topnKeys(spec.primaryOrder)))
            w.evaluate("__DS0PrimaryWindowed", orderBy: orderBy(spec.primaryOrder))
        }
    }

    /// Hai trục (Category × Series): primary TOPN(201), secondary TOPN(62), SUBSTITUTEWITHINDEX (PA-D3-1, D3-bar-nhomkh).
    private static func buildTwoAxis(_ spec: VisualQuerySpec, filters: [String], into w: inout Writer) {
        let primaryCols = groupColumns(spec.primary)
        let secondaryCols = groupColumns(spec.secondary)
        if spec.scopedMeasures.isEmpty {
            w.variable("__DS0Core", call("SUMMARIZECOLUMNS", primaryCols + secondaryCols + filters + measureArgs(spec.measures)))
        } else {
            w.variable("__ScopedCoreI0", call("SUMMARIZECOLUMNS", primaryCols + secondaryCols + filters + measureArgs(spec.measures)))
            w.variable("__ScopedCoreDM0", call("SUMMARIZECOLUMNS", primaryCols + filters + measureArgs(spec.scopedMeasures)))
            w.variable("__DS0Core", call("NATURALLEFTOUTERJOIN", ["__ScopedCoreI0", "__ScopedCoreDM0"]))
        }
        let (pTop, sTop): (Int, Int) = { if case .window(let p, let s) = spec.reduction { (p, s) } else { (201, 62) } }()
        w.variable("__DS0PrimaryWindowed", inline("TOPN", ["\(pTop)", inline("SUMMARIZE", ["__DS0Core"] + primaryCols)]
            + topnKeys(spec.primaryOrder)))
        w.variable("__DS0SecondaryBase", inline("SUMMARIZE", ["__DS0Core"] + secondaryCols))
        w.variable("__DS0Secondary", inline("TOPN", ["\(sTop)", "__DS0SecondaryBase"] + topnKeys(spec.secondaryOrder)))
        w.variable("__DS0BodyLimited", call("NATURALLEFTOUTERJOIN", ["__DS0PrimaryWindowed",
            call("SUBSTITUTEWITHINDEX", ["__DS0Core", "\"ColumnIndex\"", "__DS0Secondary"]
                + spec.secondaryOrder.flatMap { [key($0), $0.ascending ? "ASC" : "DESC"] })]))
        w.evaluate("__DS0Secondary", orderBy: orderBy(spec.secondaryOrder))
        w.evaluate("__DS0BodyLimited", orderBy: orderBy(spec.primaryOrder) + ["[ColumnIndex]"])
    }

    /// Matrix (PA-D1-2, D1-matrix-gio-thu).
    private static func buildMatrix(_ spec: VisualQuerySpec, filters: [String], into w: inout Writer) {
        let rowCols = groupColumns(spec.primary)
        let colCols = groupColumns(spec.secondary)
        func rollup(_ groups: [GroupField], _ flag: String) -> String {
            let cols = groupColumns(groups)
            let inner = cols.count > 1 ? inline("ROLLUPGROUP", cols) : cols.first ?? ""
            return inline("ROLLUPADDISSUBTOTAL", [inner, "\"\(flag)\""])
        }
        let rowGroup = spec.rowTotals ? [rollup(spec.primary, "IsGrandTotalRowTotal")] : rowCols
        let colGroup = spec.columnTotals && !spec.secondary.isEmpty ? [rollup(spec.secondary, "IsGrandTotalColumnTotal")] : colCols
        w.variable("__DS0Core", call("SUMMARIZECOLUMNS", rowGroup + colGroup + filters + measureArgs(spec.measures)))

        let rowFlag = QuerySortKey(target: .result("IsGrandTotalRowTotal"), ascending: false)
        let colFlag = QuerySortKey(target: .result("IsGrandTotalColumnTotal"), ascending: true)
        let rowKeys = (spec.rowTotals ? [rowFlag] : []) + spec.primaryOrder
        let colKeys = (spec.columnTotals ? [colFlag] : []) + spec.secondaryOrder
        let (pTop, sTop): (Int, Int) = { if case .window(let p, let s) = spec.reduction { (p, s) } else { (102, 102) } }()

        w.variable("__DS0PrimaryWindowed", inline("TOPN", ["\(pTop)",
            inline("SUMMARIZE", ["__DS0Core"] + rowCols + (spec.rowTotals ? ["[IsGrandTotalRowTotal]"] : []))]
            + topnKeys(rowKeys)))
        if !spec.secondary.isEmpty {
            w.variable("__DS0SecondaryBase", inline("SUMMARIZE", ["__DS0Core"] + colCols + (spec.columnTotals ? ["[IsGrandTotalColumnTotal]"] : [])))
            w.variable("__DS0Secondary", inline("TOPN", ["\(sTop)", "__DS0SecondaryBase"] + topnKeys(colKeys)))
            w.variable("__DS0BodyLimited", call("NATURALLEFTOUTERJOIN", ["__DS0PrimaryWindowed",
                call("SUBSTITUTEWITHINDEX", ["__DS0Core", "\"ColumnIndex\"", "__DS0Secondary"]
                    + colKeys.flatMap { [key($0), $0.ascending ? "ASC" : "DESC"] })]))
        }
        var minMaxSource = "__DS0Core"
        if !spec.gradientInputs.isEmpty, spec.rowTotals || spec.columnTotals {
            var conds: [String] = []
            if spec.rowTotals { conds.append("[IsGrandTotalRowTotal] = FALSE") }
            if spec.columnTotals && !spec.secondary.isEmpty { conds.append("[IsGrandTotalColumnTotal] = FALSE") }
            let predicate = conds.count == 1 ? conds[0] : inline("AND", conds)
            w.variable("__DS0CoreNoInstanceFiltersNoTotals", call("FILTER", ["KEEPFILTERS(__DS0Core)", predicate]))
            minMaxSource = "__DS0CoreNoInstanceFiltersNoTotals"
        }
        if !spec.gradientInputs.isEmpty {
            w.evaluate(call("GROUPBY", [minMaxSource] + spec.gradientInputs.flatMap {
                ["\"Min\($0)\", MINX(CURRENTGROUP(), [\($0)])", "\"Max\($0)\", MAXX(CURRENTGROUP(), [\($0)])"]
            }))
        }
        if !spec.secondary.isEmpty {
            w.evaluate("__DS0Secondary", orderBy: orderBy(colKeys))
            w.evaluate("__DS0BodyLimited", orderBy: orderBy(rowKeys) + ["[ColumnIndex]"])
        } else {
            w.evaluate("__DS0PrimaryWindowed", orderBy: orderBy(rowKeys))
        }
    }

    /// Cột chồng 100%: chép nguyên khuôn giảm dữ liệu động của Power BI (D2-100pct.dax).
    private static func buildHundredPercent(_ spec: VisualQuerySpec, filters: [String], into w: inout Writer) {
        let primaryCols = groupColumns(spec.primary)
        let secondaryCols = groupColumns(spec.secondary)
        w.variable("__DS0Core", call("SUMMARIZECOLUMNS", primaryCols + secondaryCols + filters + measureArgs(spec.measures)))
        w.variable("__DS0PrimaryBase", inline("SUMMARIZE", ["__DS0Core"] + primaryCols))
        w.variable("__DS0SecondaryBase", inline("SUMMARIZE", ["__DS0Core"] + secondaryCols))
        for (name, body) in hundredPercentTemplate { w.variable(name, body) }
        w.variable("__DS0Primary", inline("SAMPLE", ["__DS0TargetPrimaryCount + 2", "__DS0PrimaryBase"] + topnKeys(spec.primaryOrder)))
        w.variable("__DS0Secondary", inline("TOPN", ["__DS0TargetSecondaryCount + 1", "__DS0SecondaryBase"] + topnKeys(spec.secondaryOrder)))
        w.variable("__DS0BodyLimited", call("NATURALLEFTOUTERJOIN", ["__DS0Primary",
            call("SUBSTITUTEWITHINDEX", ["__DS0Core", "\"ColumnIndex\"", "__DS0Secondary"]
                + spec.secondaryOrder.flatMap { [key($0), $0.ascending ? "ASC" : "DESC"] })]))
        w.evaluate(call("ROW", [
            "\"DS0IntersectionCount\", __DS0IntersectionCount", "\"DS0PrimaryCount\", __DS0PrimaryCount",
            "\"DS0TargetPrimaryCount\", __DS0TargetPrimaryCount", "\"DS0SecondaryCount\", __DS0SecondaryCount",
            "\"DS0TargetSecondaryCount\", __DS0TargetSecondaryCount",
        ]))
        w.evaluate("__DS0Secondary", orderBy: orderBy(spec.secondaryOrder))
        w.evaluate("__DS0BodyLimited", orderBy: orderBy(spec.primaryOrder) + ["[ColumnIndex]"])
    }

    /// Các VAR đếm và mục tiêu của khuôn 100% (nguyên văn D2-100pct.dax, không phụ thuộc trường).
    private static let hundredPercentTemplate: [(String, String)] = [
        ("__DS0IntersectionCount", "CALCULATE(COUNTROWS(__DS0Core))"),
        ("__DS0PrimaryCount", "CALCULATE(COUNTROWS(__DS0PrimaryBase))"),
        ("__DS0SecondaryCount", "CALCULATE(COUNTROWS(__DS0SecondaryBase))"),
        ("__DS0SpaceCount", "(__DS0PrimaryCount * __DS0SecondaryCount)"),
        ("__DS0SparseFactor", "MIN(5, DIVIDE(__DS0SpaceCount, __DS0IntersectionCount))"),
        ("__DS0TargetIntersectionCount", "CEILING(3500 * __DS0SparseFactor, 1)"),
        ("__DS0InitTargetPrimaryCount", """
            IF(__DS0IntersectionCount <= 3500, IF(__DS0SpaceCount <= __DS0TargetIntersectionCount, 3500, \
            FLOOR(SQRT(__DS0TargetIntersectionCount * DIVIDE(__DS0PrimaryCount, __DS0SecondaryCount)), 1)), \
            IF(AND(__DS0PrimaryCount > 800, __DS0SecondaryCount > 60), CEILING(DIVIDE(__DS0TargetIntersectionCount, 60), 1), \
            IF(__DS0SecondaryCount > 60, __DS0PrimaryCount, CEILING(DIVIDE(__DS0TargetIntersectionCount, __DS0SecondaryCount), 1))))
            """),
        ("__DS0InitTargetSecondaryCount", """
            IF(__DS0IntersectionCount <= 3500, IF(__DS0SpaceCount <= __DS0TargetIntersectionCount, 3500, \
            FLOOR(DIVIDE(__DS0TargetIntersectionCount, FLOOR(SQRT(__DS0TargetIntersectionCount * DIVIDE(__DS0PrimaryCount, __DS0SecondaryCount)), 1)), 1)), \
            IF(AND(__DS0PrimaryCount > 800, __DS0SecondaryCount > 60), 60, \
            IF(__DS0SecondaryCount > 60, CEILING(DIVIDE(__DS0TargetIntersectionCount, __DS0PrimaryCount), 1), __DS0SecondaryCount)))
            """),
        ("__DS0MinPrimaryCount", "MIN(10, __DS0PrimaryCount)"),
        ("__DS0MinSecondaryCount", "MIN(10, __DS0SecondaryCount)"),
        ("__DS0TargetPrimaryCount", """
            IF(__DS0InitTargetPrimaryCount < __DS0MinPrimaryCount, __DS0MinPrimaryCount, \
            IF(__DS0InitTargetSecondaryCount < __DS0MinSecondaryCount, CEILING(DIVIDE(__DS0TargetIntersectionCount, __DS0MinSecondaryCount), 1), \
            __DS0InitTargetPrimaryCount))
            """),
        ("__DS0TargetSecondaryCount", """
            IF(__DS0InitTargetPrimaryCount < __DS0MinPrimaryCount, CEILING(DIVIDE(__DS0TargetIntersectionCount, __DS0MinPrimaryCount), 1), \
            IF(__DS0InitTargetSecondaryCount < __DS0MinSecondaryCount, __DS0MinSecondaryCount, __DS0InitTargetSecondaryCount))
            """),
    ]

    // MARK: - So khớp

    /// Chuẩn hoá để so với truy vấn Power BI: bỏ dòng `// DAX Query`, gộp mọi khoảng trắng,
    /// bỏ khoảng trắng sát trong ngoặc và trước dấu phẩy.
    static func normalized(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("// DAX Query") }
        var s = lines.joined(separator: " ")
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([\(\{]) "#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #" ([\)\},])"#, with: "$1", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}
