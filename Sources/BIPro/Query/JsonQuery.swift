// Phase F, T088 (US7): nạp JSON như Desktop 2.159 (VM-F7a, `docs/phase-f-evidence/vm-f7/QUAN-SAT.md`): Get Data ▸ JSON mở thẳng Query Editor
// với chuỗi bước tự mở rộng:
//   Source = Json.Document(File.Contents(path))
//   Converted to Table = Table.FromList(Source, Splitter.SplitByNothing(), null, null, ExtraValues.Error)     (gốc là mảng)
//   Expanded Column1 = Table.ExpandRecordColumn(…, "Column1", {trường}, {trường})                            (không tiền tố)
//   Expanded <cột> = Table.ExpandRecordColumn(…, cột, {trường}, {"cột.trường"}) | Table.ExpandListColumn(…, cột)
//   Changed Type = Table.TransformColumnTypes(…, {{cột, Int64.Type | type number | type text | type logical}})
// Mỗi vòng mở cột có cấu trúc trái nhất (bản ghi: hợp trường theo thứ tự xuất hiện; danh sách: thành dòng mới); tên bước trùng thêm số
// ("Expanded Lines1"). Cột lẫn bản ghi với danh sách/giá trị đơn để nguyên. [SUY ĐOÁN] gốc là bản ghi: một dòng `Table.FromRecords({Source})`;
// gốc là giá trị đơn: bảng một cột "Value". Kiểu: số nguyên hết → Int64 (Desktop: số JSON nguyên thành `Int64.Type`).

import ColumnStore
import Connectors
import Foundation
import MEngine
import Synchronization

enum JsonQuery {
    struct Plan: @unchecked Sendable {
        let steps: [QueryStep]
        let data: TableData
    }

    /// Chuỗi bước và bảng kết quả cho tệp JSON. Kết quả nhớ theo (đường dẫn, ngày sửa, cỡ) nên gọi lại rẻ.
    static func plan(location: String) throws -> Plan {
        let attributes = try? FileManager.default.attributesOfItem(atPath: location)
        let key = "\(location)|\((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\((attributes?[.size] as? Int) ?? -1)"
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: location)) } catch {
            throw SourceError.unreadable("Không thể đọc file: \(URL(fileURLWithPath: location).lastPathComponent)")
        }
        guard !data.isEmpty else { throw SourceError.empty }
        let root: MValue
        do { root = try MJson.parse(data) } catch let error as MError { throw SourceError.unreadable(error.message) }
        let plan = try build(root: root, sourceExpression: "Json.Document(File.Contents(\(StepFactory.quote(location))))")
        cache.withLock { $0[key] = plan }
        return plan
    }

    private static let cache = Mutex<[String: Plan]>([:])

    /// Dựng chuỗi bước từ giá trị JSON đã đọc. Mỗi bước tính trên kết quả bước trước (gắn tên bước trước vào môi trường), không đọc lại tệp.
    static func build(root: MValue, sourceExpression: String) throws -> Plan {
        var steps = [QueryStep(name: "Source", expression: sourceExpression, kind: StepKind.source)]
        var current: TableData
        var bindings: [String: MValue] = ["Source": root]
        func apply(_ step: MStep, kind: String) throws -> TableData {
            let value: MValue
            do { value = try MEvaluator(environment: MEnvironment(bindings: bindings)).evaluateNow(source: step.expression) } catch let error as MError {
                throw SourceError.unreadable("Bước \(step.name): \(error.message)")
            }
            guard case .table(let table) = value else { throw SourceError.unreadable("Bước \(step.name) không ra bảng") }
            steps.append(QueryStep(name: step.name, expression: step.expression, kind: kind))
            bindings[step.name] = value
            return table
        }
        let names = { Set(steps.map(\.name)) }
        switch root {
        case .list:
            current = try apply(MStep(name: "Converted to Table",
                                      expression: "Table.FromList(Source, Splitter.SplitByNothing(), null, null, ExtraValues.Error)"), kind: StepKind.navigation)
        case .record:
            current = try apply(MStep(name: "Converted to Table", expression: "Table.FromRecords({Source})"), kind: StepKind.navigation)
        default:
            current = try apply(MStep(name: "Converted to Table", expression: "#table({\"Value\"}, {{Source}})"), kind: StepKind.navigation)
        }
        var unprefixed = root.isList ? "Column1" : nil
        for _ in 0..<64 {
            guard let (column, command) = nextExpansion(current, unprefixed: unprefixed) else { break }
            if column == unprefixed { unprefixed = nil }
            let step = StepFactory.steps(for: command, after: steps.last!.name, existingNames: names())[0]
            current = try apply(step, kind: StepKind.navigation)
        }
        let changes = typeChanges(current)
        if !changes.isEmpty {
            let step = StepFactory.steps(for: .changeType(changes), after: steps.last!.name, existingNames: names())[0]
            current = try apply(step, kind: StepKind.type)
        }
        return Plan(steps: steps, data: current)
    }

    /// Lệnh mở cho cột có cấu trúc trái nhất mở được: mọi ô khác null là bản ghi (mở trường) hoặc là danh sách (thành dòng).
    private static func nextExpansion(_ table: TableData, unprefixed: String?) -> (String, StepCommand)? {
        for (index, column) in table.columns.enumerated() {
            guard let cells = table.structured[index], !cells.isEmpty else { continue }
            var fields: [String] = []
            var seen = Set<String>()
            var records = 0, lists = 0, others = 0
            for row in 0..<table.rowCount {
                switch MTables.cell(table, row: row, column: index) {
                case .record(let values):
                    records += 1
                    for field in values where seen.insert(field.name).inserted { fields.append(field.name) }
                case .list: lists += 1
                case .null: continue
                default: others += 1
                }
            }
            if records > 0, lists == 0, others == 0, !fields.isEmpty {
                return (column.name, .expandRecord(column: column.name, fields: fields, prefixed: column.name != unprefixed))
            }
            if lists > 0, records == 0, others == 0 { return (column.name, .expandList(column: column.name)) }
        }
        return nil
    }

    /// Kiểu Desktop gán ở "Changed Type": số nguyên hết → Int64, số → number, chữ → text, logic → logical; cột toàn null hoặc còn cấu trúc thì bỏ.
    static func typeChanges(_ table: TableData) -> [ColumnTypeChange] {
        table.columns.enumerated().compactMap { index, column in
            guard table.structured[index] == nil, table.nested[index] == nil else { return nil }
            let rows = 0..<table.rowCount
            let values = rows.map { column.data.value(at: $0) }.filter { $0 != .blank }
            guard !values.isEmpty else { return nil }
            let type: MColumnType
            switch column.data.type {
            case .double:
                type = values.allSatisfy { if case .double(let d) = $0 { d == d.rounded() && abs(d) < 9.2e18 } else { false } } ? .wholeNumber : .decimal
            case .integer: type = .wholeNumber
            case .currency: type = .fixedDecimal
            case .string: type = .text
            case .boolean: type = .logical
            case .dateTime: type = .dateTime
            }
            return ColumnTypeChange(column: column.name, type: type)
        }
    }
}

private extension MValue {
    var isList: Bool { if case .list = self { true } else { false } }
}

/// Nguồn JSON của Get Data: một mục (tên tệp) mà kết quả là bảng sau chuỗi bước Desktop (`JsonQuery`).
struct JsonQuerySource: DataSource {
    let kind: SourceKind = .json
    let url: URL

    func items() async throws -> [any SourceItem] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SourceError.unreadable("File không tồn tại: \(url.lastPathComponent)")
        }
        return [JsonQueryItem(name: url.deletingPathExtension().lastPathComponent, url: url)]
    }
}

private struct JsonQueryItem: SourceItem {
    let name: String
    let kind: SourceItemKind = .record
    let columns: [SourceColumn]? = nil
    let rowCountHint: Int? = nil
    let url: URL

    func preview(limit: Int) async throws -> TableData { try await load(progress: nil).prefix(limit) }

    func load(progress: SourceProgress?) async throws -> TableData {
        if Task.isCancelled { throw SourceError.cancelled }
        progress?(0)
        let path = url.path
        let plan = try await Task.detached(priority: .userInitiated) { try JsonQuery.plan(location: path) }.value
        progress?(1)
        return plan.data
    }
}
