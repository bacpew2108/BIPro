import Foundation

/// Serializes model metadata as TMDL (Tabular Model Definition Language), the
/// documented text format Power BI uses for semantic models in `.pbip` projects.
public enum TMDLWriter {
    public struct Document: Sendable, Hashable, Identifiable {
        public var id: String { path }
        /// e.g. `model.tmdl`, `tables/Fact_Loan.tmdl`.
        public let path: String
        public let text: String
    }

    public static func documents(for model: ModelMetadata) -> [Document] {
        var docs: [Document] = []
        docs.append(Document(path: "model.tmdl", text: modelDocument(model)))
        if !model.relationships.isEmpty {
            docs.append(Document(path: "relationships.tmdl", text: relationshipsDocument(model)))
        }
        for table in model.userTables {
            docs.append(Document(path: "tables/\(table.name).tmdl", text: tableDocument(table, model: model)))
        }
        for culture in model.cultures {
            docs.append(Document(path: "cultures/\(culture).tmdl", text: "cultureInfo \(culture)\n"))
        }
        if !model.roles.isEmpty {
            docs.append(Document(path: "roles.tmdl", text: model.roles.map { "role \(name($0))\n\tmodelPermission: read\n" }.joined(separator: "\n")))
        }
        return docs
    }

    // MARK: Documents

    static func modelDocument(_ model: ModelMetadata) -> String {
        var out = "model Model\n"
        if let culture = model.cultures.first { out += "\tculture: \(culture)\n" }
        out += "\tdefaultPowerBIDataSourceVersion: powerBI_V3\n\n"
        for table in model.userTables { out += "ref table \(name(table.name))\n" }
        for culture in model.cultures { out += "\nref cultureInfo \(culture)" }
        return out + "\n"
    }

    static func relationshipsDocument(_ model: ModelMetadata) -> String {
        model.relationships.map { r in
            var out = "relationship \(name(r.name))\n"
            if r.cardinality.hasPrefix("1") { out += "\tfromCardinality: one\n" }
            if r.cardinality.hasSuffix("M") { out += "\ttoCardinality: many\n" }
            if r.crossFilteringBehavior == 2 { out += "\tcrossFilteringBehavior: bothDirections\n" }
            if !r.isActive { out += "\tisActive: false\n" }
            out += "\tfromColumn: \(name(r.fromTable)).\(name(r.fromColumn))\n"
            out += "\ttoColumn: \(name(r.toTable)).\(name(r.toColumn))\n"
            return out
        }.joined(separator: "\n")
    }

    static func tableDocument(_ table: ModelMetadata.Table, model: ModelMetadata) -> String {
        var out = "table \(name(table.name))\n"
        if table.isHidden { out += "\tisHidden\n" }
        if let tag = table.lineageTag { out += "\tlineageTag: \(tag)\n" }

        for m in model.measures where m.tableName == table.name {
            out += "\n" + expressionHeader("measure", m.name, m.expression, depth: 1)
            if let f = m.formatString { out += "\t\tformatString: \(f)\n" }
            if m.isHidden { out += "\t\tisHidden\n" }
            if let d = m.displayFolder { out += "\t\tdisplayFolder: \(d)\n" }
            if let tag = m.lineageTag { out += "\t\tlineageTag: \(tag)\n" }
        }

        for c in model.columns where c.tableID == table.id && c.kind != .rowNumber {
            if c.kind == .calculated, let expression = c.expression {
                out += "\n" + expressionHeader("column", c.name, expression, depth: 1)
            } else {
                out += "\n\tcolumn \(name(c.name))\n"
            }
            out += "\t\tdataType: \(c.dataType.tmdlName)\n"
            if c.isHidden { out += "\t\tisHidden\n" }
            if c.isKey { out += "\t\tisKey\n" }
            if let f = c.formatString { out += "\t\tformatString: \(f)\n" }
            if let d = c.displayFolder { out += "\t\tdisplayFolder: \(d)\n" }
            if let tag = c.lineageTag { out += "\t\tlineageTag: \(tag)\n" }
            if let category = c.dataCategory { out += "\t\tdataCategory: \(category)\n" }
            out += "\t\tsummarizeBy: \(c.summarizeByName == "default" ? "none" : c.summarizeByName)\n"
            if c.kind == .data, let source = c.sourceColumn { out += "\t\tsourceColumn: \(source)\n" }
            if let sortID = c.sortByColumnID, let sortBy = model.column(id: sortID) { out += "\t\tsortByColumn: \(name(sortBy.name))\n" }
        }

        for h in model.hierarchies where h.tableName == table.name {
            out += "\n\thierarchy \(name(h.name))\n"
            if h.isHidden { out += "\t\tisHidden\n" }
            if let tag = h.lineageTag { out += "\t\tlineageTag: \(tag)\n" }
            for level in h.levels {
                out += "\n\t\tlevel \(name(level.name))\n"
                if let tag = level.lineageTag { out += "\t\t\tlineageTag: \(tag)\n" }
                out += "\t\t\tcolumn: \(name(level.columnName))\n"
            }
        }

        if let source = model.partitionQueries[table.name] {
            out += "\n\tpartition \(name(table.name)) = m\n\t\tmode: import\n\t\tsource =\n"
            out += indent(source, depth: 4) + "\n"
        }
        return out
    }

    // MARK: Helpers

    /// `measure 'Name' = expr` on one line, or a multi-line expression indented two levels deeper.
    static func expressionHeader(_ keyword: String, _ objectName: String, _ expression: String, depth: Int) -> String {
        let tabs = String(repeating: "\t", count: depth)
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("\n") {
            return "\(tabs)\(keyword) \(name(objectName)) = \(trimmed)\n"
        }
        return "\(tabs)\(keyword) \(name(objectName)) =\n" + indent(trimmed, depth: depth + 2) + "\n"
    }

    static func indent(_ text: String, depth: Int) -> String {
        let tabs = String(repeating: "\t", count: depth)
        return text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { tabs + $0 }
            .joined(separator: "\n")
    }

    /// TMDL names are quoted with `'…'` unless they are plain identifiers.
    static func name(_ raw: String) -> String {
        let plain = raw.first.map { $0.isLetter || $0 == "_" } == true
            && raw.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        return plain ? raw : "'" + raw.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
