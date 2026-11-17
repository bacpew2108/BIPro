// Phase F, T061: truy vấn M mà Desktop 2.159 sinh khi nạp một mục của Navigator (QUAN-SAT VM-F1 mục 3), để ghi vào
// `Partition.QueryDefinition` và làm các bước đầu (khoá) của truy vấn trong Query Editor. CSV, Excel, JSON (VM-F7a, `JsonQuery`) và
// Parquet đã quan sát; named table và SQLite là [SUY ĐOÁN] (chỉ đúng cú pháp M, chưa đối chiếu Desktop).

import ColumnStore
import Connectors
import Foundation
import MEngine

/// Nguồn của một bảng đã nạp: đủ để dựng lại M và nạp lại (Refresh).
public struct LoadedOrigin: Sendable, Equatable {
    public let kind: SourceKind
    public let location: String
    public let itemName: String
    public let itemKind: SourceItemKind

    public init(kind: SourceKind, location: String, itemName: String, itemKind: SourceItemKind) {
        self.kind = kind
        self.location = location
        self.itemName = itemName
        self.itemKind = itemKind
    }
}

enum StepKind {
    static let source = "source"
    static let navigation = "navigation"
    static let promote = "promote"
    static let type = "type"
    static let custom = "custom"
    /// Bước đọc từ file đã có (Desktop viết), không biết lệnh nào sinh ra.
    static let file = "file"
}

enum SourceQuery {
    /// Các bước đầu của truy vấn: ghi vào file, kết quả bằng đúng bảng đã nạp (`data`).
    static func steps(for origin: LoadedOrigin, data: TableData) -> [QueryStep] {
        let path = StepFactory.quote(origin.location)
        var steps: [QueryStep] = []
        var previous = "Source"
        func add(_ name: String, _ expression: String, _ kind: String) {
            steps.append(QueryStep(name: name, expression: expression, kind: kind))
            previous = name
        }
        func promote() {
            add("Promoted Headers", "Table.PromoteHeaders(\(MQuery.reference(to: previous)), [PromoteAllScalars=true])", StepKind.promote)
        }
        switch origin.kind {
        case .csv:
            let format = csvFormat(origin.location)
            add("Source", "Csv.Document(File.Contents(\(path)),[Delimiter=\(StepFactory.quote(format.delimiter)), Columns=\(data.columns.count), "
                + "Encoding=\(format.encoding), QuoteStyle=QuoteStyle.None])", StepKind.source)
            promote()
        case .excel:
            add("Source", "Excel.Workbook(File.Contents(\(path)), null, true)", StepKind.source)
            let isTable = origin.itemKind == .namedTable
            let name = "\(origin.itemName)_\(isTable ? "Table" : "Sheet")"
            let kind = isTable ? "Table" : "Sheet"
            add(name, "Source{[Item=\(StepFactory.quote(origin.itemName)),Kind=\"\(kind)\"]}[Data]", StepKind.navigation)
            if !isTable { promote() }   // [SUY ĐOÁN] bảng đặt tên đã có tiêu đề, Desktop không thăng cấp.
        case .sqlite:
            add("Source", "Sqlite.Database(File.Contents(\(path)), [CreateNavigationProperties=true])", StepKind.source)
            let kind = origin.itemKind == .view ? "View" : "Table"
            add("\(origin.itemName)_\(kind)", "Source{[Name=\(StepFactory.quote(origin.itemName)),Kind=\"\(kind)\"]}[Data]", StepKind.navigation)
        case .json:
            // Chuỗi bước tự mở rộng như Desktop (VM-F7a), gồm cả "Changed Type".
            if let plan = try? JsonQuery.plan(location: origin.location) { return plan.steps }
            add("Source", "Json.Document(File.Contents(\(path)))", StepKind.source)
        case .parquet:
            // Desktop (VM-F7a): một bước, kiểu lấy từ lược đồ tệp, không có "Changed Type".
            return [QueryStep(name: "Source", expression: "Parquet.Document(File.Contents(\(path)), [Compression=null, LegacyColumnNameEncoding=false, MaxDepth=null])",
                              kind: StepKind.source)]
        case .postgres:
            add("Source", "#table({}, {})", StepKind.source)
        }
        let changes = typeChanges(data)
        if !changes.isEmpty {
            let step = StepFactory.steps(for: .changeType(changes), after: previous, existingNames: Set(steps.map(\.name)))[0]
            steps.append(QueryStep(name: step.name, expression: step.expression, kind: StepKind.type))
        }
        return steps
    }

    /// Kiểu cột như Desktop gán ở "Changed Type". Cột ngày chỉ là `date` khi mọi giá trị nguyên ngày (dò 1000 dòng đầu).
    static func typeChanges(_ data: TableData) -> [ColumnTypeChange] {
        data.columns.map { column in
            let type: MColumnType
            switch column.data.type {
            case .integer: type = .wholeNumber
            case .double: type = .decimal
            case .currency: type = .fixedDecimal
            case .boolean: type = .logical
            case .string: type = .text
            case .dateTime:
                var wholeDays = true
                for row in 0..<min(data.rowCount, 1000) {
                    if case .dateTime(let d) = column.data.value(at: row), d != d.rounded(.down) { wholeDays = false; break }
                }
                type = wholeDays ? .date : .dateTime
            }
            return ColumnTypeChange(column: column.name, type: type)
        }
    }

    /// Dấu phân cách và mã hoá (65001 = UTF-8, 1200 = UTF-16) để ghi `Csv.Document`. Đọc 64 KB đầu; không đọc được thì `,` và UTF-8.
    static func csvFormat(_ location: String) -> (delimiter: String, encoding: Int) {
        guard let handle = FileHandle(forReadingAtPath: location) else { return (",", 65001) }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 65_536)) ?? Data()
        let utf16 = head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF])
        let text = String(data: head, encoding: utf16 ? .utf16 : .utf8) ?? String(decoding: head, as: UTF8.self)
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let best = [",", ";", "\t", "|"].map { d in (d, firstLine.filter { String($0) == d }.count) }
            .reduce(nil as (String, Int)?) { best, candidate in candidate.1 > (best?.1 ?? 0) ? candidate : best }
        return (best?.0 ?? ",", utf16 ? 1200 : 65001)
    }
}
