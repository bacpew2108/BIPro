import Foundation
import PBIXKit

let usage = """
usage: pbix-dump <command> <file.pbix> [args]
  info                    container, report format and data model summary
  files                   files inside the ABF backup
  extract <name> <out>    write one ABF file (e.g. metadata.sqlitedb) to <out>
  tables                  user tables with column/measure counts and row counts
  columns <table>         columns of a table with type and kind
  measures [--dax]        measures (with --dax: as a .dax script)
  relationships           model relationships
  rows <table> [n]        first n rows (default 20) as TSV
  decode-all              decode every column of every user table (smoke test)
  verify                  compare decoded distinct counts with engine statistics
  report                  pages and visuals of the report definition
  roundtrip <in> <out>    rebuild the file with no changes and compare
  set-title <in> <visualID> <title> <out>
  add-measure <in> <table> <name> <expression> <out>
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func formatBytes(_ n: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .binary)
}

struct Model {
    let abf: ABFBackup
    let compression: DataModelStream.Compression
    let metadata: ModelMetadata

    init(_ pbix: PBIXFile) throws {
        (abf, compression) = try pbix.loadDataModel()
        metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    }
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail(usage) }
let command = args[1]
let url = URL(fileURLWithPath: args[2])

do {
    let pbix = try PBIXFile(url: url)
    switch command {
    case "info":
        print("file:          \(url.lastPathComponent)")
        print("version:       \(pbix.version ?? "?")")
        print("report format: \(pbix.reportFormat.rawValue)")
        print("parts:         \(pbix.archive.entries.count)")
        guard pbix.hasDataModel else { print("data model:    none (live connection?)"); break }
        let clock = ContinuousClock()
        var model: Model!
        let elapsed = try clock.measure { model = try Model(pbix) }
        print("compression:   \(model.compression.rawValue)")
        print("abf size:      \(formatBytes(model.abf.data.count)) (decompressed + metadata in \(elapsed))")
        print("abf files:     \(model.abf.files.count)")
        print("tables:        \(model.metadata.userTables.count) user, \(model.metadata.tables.count - model.metadata.userTables.count) system")
        print("measures:      \(model.metadata.measures.count)")
        print("relationships: \(model.metadata.relationships.count)")
        print("calc columns:  \(model.metadata.columns.filter { $0.kind == .calculated }.count)")

    case "files":
        let (abf, _) = try pbix.loadDataModel()
        for file in abf.files {
            print(String(format: "%12d  %@", file.size, file.path))
        }

    case "extract":
        guard args.count >= 5 else { fail(usage) }
        let (abf, _) = try pbix.loadDataModel()
        try abf.contents(named: args[3]).write(to: URL(fileURLWithPath: args[4]))
        print("wrote \(args[4])")

    case "tables":
        let model = try Model(pbix)
        print("table\tcolumns\tmeasures\trows")
        for table in model.metadata.userTables {
            let columns = model.metadata.columns.filter { $0.tableID == table.id && $0.kind != .rowNumber }
            let measures = model.metadata.measures.filter { $0.tableName == table.name }
            let rows = try model.metadata.storage(table: table.name).first
                .map { try VertiPaq.decodeColumn($0, abf: model.abf).count } ?? 0
            print("\(table.name)\t\(columns.count)\t\(measures.count)\t\(rows)")
        }

    case "columns":
        guard args.count >= 4 else { fail(usage) }
        let model = try Model(pbix)
        for column in model.metadata.columns where column.tableName == args[3] && column.kind != .rowNumber {
            let expression = column.expression.map { " = " + $0.replacingOccurrences(of: "\n", with: " ") } ?? ""
            print("\(column.name)\t\(column.dataType)\t\(column.kind)\(expression)")
        }

    case "measures":
        let model = try Model(pbix)
        let asDAX = args.dropFirst(3).contains("--dax")
        for m in model.metadata.measures {
            if asDAX {
                print("-- \(m.tableName)\(m.formatString.map { "  [format: \($0)]" } ?? "")")
                print("MEASURE '\(m.tableName)'[\(m.name)] =\n\(m.expression.trimmingCharacters(in: .whitespacesAndNewlines))\n")
            } else {
                let oneLine = m.expression.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
                print("\(m.tableName)\t\(m.name)\t\(oneLine)")
            }
        }

    case "relationships":
        let model = try Model(pbix)
        for r in model.metadata.relationships {
            let direction = r.crossFilteringBehavior == 2 ? "both" : "single"
            print("\(r.fromTable)[\(r.fromColumn)] \(r.cardinality) \(r.toTable)[\(r.toColumn)]  \(direction)\(r.isActive ? "" : "  (inactive)")")
        }

    case "rows":
        guard args.count >= 4 else { fail(usage) }
        let limit = args.count >= 5 ? Int(args[4]) ?? 20 : 20
        let model = try Model(pbix)
        let columns = try VertiPaq.decodeTable(args[3], metadata: model.metadata, abf: model.abf)
        guard let first = columns.first else { fail("no stored columns for \(args[3])") }
        print(columns.map(\.name).joined(separator: "\t"))
        for row in 0..<min(limit, first.count) {
            print(columns.map { $0[row].description }.joined(separator: "\t"))
        }
        FileHandle.standardError.write(Data("(\(first.count) rows)\n".utf8))

    case "decode-all":
        let model = try Model(pbix)
        let clock = ContinuousClock()
        var failures = 0
        for table in model.metadata.userTables {
            do {
                var columns: [DecodedColumn] = []
                let elapsed = try clock.measure {
                    columns = try VertiPaq.decodeTable(table.name, metadata: model.metadata, abf: model.abf)
                }
                let nulls = columns.map { c in (0..<c.count).reduce(0) { $0 + (c[$1] == .null ? 1 : 0) } }
                print("ok   \(table.name): \(columns.first?.count ?? 0) rows × \(columns.count) cols, nulls \(nulls.reduce(0, +)) (\(elapsed))")
            } catch {
                failures += 1
                print("FAIL \(table.name): \(error)")
            }
        }
        if failures > 0 { exit(2) }

    case "report":
        let report = try pbix.loadReport()
        let theme = pbix.loadTheme(for: report)
        print("active page: \(pbix.activePageID ?? "nil")")
        print("themes: base=\(report.baseThemeName ?? "-") custom=\(report.customThemeName ?? "-") colors=\(theme.dataColors.prefix(4))")
        for page in report.pages {
            print("\(page.displayName)  [\(Int(page.width))×\(Int(page.height))] \(page.visuals.count) visuals\(page.isHidden ? " (hidden)" : "")")
            for v in page.visuals {
                let fields = v.fields.map { "\($0.role):\($0.label)" }.joined(separator: ", ")
                print("  \(v.type.padding(toLength: 34, withPad: " ", startingAt: 0)) @\(Int(v.x)),\(Int(v.y)) \(Int(v.width))×\(Int(v.height))  \(fields)")
            }
        }

    case "verify":
        // Self-check without an external oracle: the engine records each column's
        // distinct count; a mis-decoded column almost never reproduces it.
        let model = try Model(pbix)
        var checked = 0, mismatched = 0
        for table in model.metadata.userTables {
            for column in model.metadata.storage(table: table.name) {
                let decoded = try VertiPaq.decodeColumn(column, abf: model.abf)
                var distinct = Set<CellValue>()
                for row in 0..<decoded.count { distinct.insert(decoded[row]) }
                let nonNull = distinct.subtracting([.null]).count
                checked += 1
                // DistinctStates may or may not count the blank member.
                if nonNull != column.cardinality && distinct.count != column.cardinality {
                    mismatched += 1
                    print("MISMATCH \(table.name)[\(column.columnName)]: decoded \(nonNull) distinct (+null: \(distinct.count)), engine says \(column.cardinality)")
                }
            }
        }
        print("verified \(checked) columns, \(mismatched) mismatches")
        if mismatched > 0 { exit(2) }

    case "roundtrip":
        // roundtrip <in.pbix> <out.pbix>: rebuild the DataModel (ABF + XPress9) with no changes; report what changed.
        guard args.count >= 4 else { fail(usage) }
        let output = URL(fileURLWithPath: args[3])
        let tier = try PBIXWriter.save(source: url, to: output, changes: PBIXChanges(), rebuildModel: true)
        let reopened = try PBIXFile(url: output)
        let original = try PBIXFile(url: url)
        let (abfA, _) = try original.loadDataModel()
        let (abfB, _) = try reopened.loadDataModel()
        print("tier:          \(tier.rawValue)")
        print("members:       \(original.archive.entries.count) -> \(reopened.archive.entries.count)")
        print("abf identical: \(abfA.data == abfB.data)")
        var changed: [String] = []
        for entry in original.archive.entries where try original.archive.read(entry) != reopened.archive.read(entry.path) {
            changed.append(entry.path)
        }
        print("changed members: \(changed.count) \(changed.prefix(5))")
        print("wrote \(args[3])")

    case "set-title":
        // set-title <in.pbix> <visualID> <title> <out.pbix>: T1 save of one visual title.
        guard args.count >= 6 else { fail(usage) }
        let visualID = args[3]
        let title = args[4]
        let output = URL(fileURLWithPath: args[5])
        let suffix = "/visuals/\(visualID)/visual.json"
        guard let entry = pbix.archive.entries.first(where: { $0.path.hasSuffix(suffix) }) else {
            fail("no visual \(visualID) in \(url.lastPathComponent)")
        }
        let patched = try PBIRPatch.setVisualTitle(in: try pbix.archive.read(entry), title: title)
        var changes = PBIXChanges()
        changes.reportParts[entry.path] = patched
        let tier = try PBIXWriter.save(source: url, to: output, changes: changes)
        print("tier \(tier.rawValue): \(entry.path)")
        print("wrote \(args[5])")

    case "add-measure":
        // add-measure <in.pbix> <table> <name> <expression> <out.pbix>: T2 save of one measure.
        guard args.count >= 7 else { fail(usage) }
        var changes = PBIXChanges()
        changes.measures = [NewMeasure(table: args[3], name: args[4], expression: args[5])]
        let tier = try PBIXWriter.save(source: url, to: URL(fileURLWithPath: args[6]), changes: changes)
        print("tier \(tier.rawValue): measure \(args[4]) added to \(args[3])")
        print("wrote \(args[6])")

    default:
        fail(usage)
    }
} catch {
    fail("error: \(error)")
}
