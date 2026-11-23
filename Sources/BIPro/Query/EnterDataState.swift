import ColumnStore
import Connectors
import Foundation
import MEngine

/// Bảng của hộp "Tạo bảng" (Enter Data), như Desktop 2.159 (VM-F11a, `docs/phase-f2-evidence/vm-f11/QUAN-SAT.md` mục a):
/// - lưới bắt đầu một cột "Column1", một dòng trống; mọi ô là chuỗi, ô trống là `""`;
/// - dán TSV vào lưới trống thì dòng đầu thành tiêu đề (Desktop hiện "Undo Headers");
/// - clipboard quá 3 000 ô (đếm cả dòng tiêu đề) bị từ chối, lưới giữ nguyên;
/// - M: `Source = Table.FromRows(Json.Document(Binary.Decompress(Binary.FromText("<Base64 của Deflate thô của JSON các dòng>", …)), …),
///   let _t = ((type nullable text) meta [Serialized.Text = true]) in type table [A = _t, …])` rồi `Changed Type`. Trùng từng byte với M
///   Desktop của hai bảng VM-F11 (`EnterDataStateTests`).
struct EnterDataTable: Equatable {
    enum PasteError: Error, Equatable {
        case tooLarge

        var message: String {
            switch self {
            case .tooLarge:
                biN("Dữ liệu dán quá lớn. Hãy tách thành nhiều bảng, mỗi bảng không quá 3.000 ô, rồi gộp lại trong Power Query.", "The pasted data is too large. Split it into several tables of at most 3,000 cells each, then combine them in Power Query.")
            }
        }
    }

    /// Desktop: 3 000 ô được nhận, 3 001 bị từ chối (kể cả dòng tiêu đề).
    static let cellLimit = 3_000

    var name: String
    private(set) var columns: [String]
    private(set) var rows: [[String]]

    init(name: String) {
        self.name = name
        columns = ["Column1"]
        rows = [[""]]
    }

    /// Tên mặc định: "Table", trùng thì "Table (2)", "Table (3)"… (VM-F11a).
    static func defaultName(taken: Set<String>) -> String { TableNaming.uniqueName("Table", taken: taken) }

    /// Lưới còn trống: một cột tên mặc định, mọi ô rỗng.
    var isEmpty: Bool {
        columns.enumerated().allSatisfy { $0.element == "Column\($0.offset + 1)" } && rows.allSatisfy { $0.allSatisfy(\.isEmpty) }
    }

    // MARK: Sửa lưới

    /// Dán TSV từ bảng tính. Lưới trống thì thay cả lưới và dòng đầu thành tiêu đề (trả `true`); lưới có dữ liệu thì ghi đè từ ô
    /// (`row`, `column`), thiếu cột hoặc dòng thì thêm (`[SUY ĐOÁN]`, Desktop chưa quan sát). Quá giới hạn thì ném `.tooLarge`, không đổi gì.
    @discardableResult
    mutating func paste(_ text: String, row: Int = 0, column: Int = 0) throws(PasteError) -> Bool {
        let cells = Self.parseTSV(text)
        guard !cells.isEmpty else { return false }
        guard cells.reduce(0, { $0 + max($1.count, 1) }) <= Self.cellLimit else { throw .tooLarge }
        if isEmpty {
            let width = cells.map(\.count).max() ?? 1
            columns = (0..<width).map { index in
                let header = index < cells[0].count ? cells[0][index] : ""
                return header.isEmpty ? "Column\(index + 1)" : header
            }
            let body = cells.dropFirst().map { $0 + Array(repeating: "", count: width - $0.count) }
            rows = body.isEmpty ? [Array(repeating: "", count: width)] : Array(body)
            return true
        }
        for (offset, values) in cells.enumerated() {
            let target = row + offset
            while target >= rows.count { addRow() }
            for (index, value) in values.enumerated() {
                while column + index >= columns.count { addColumn() }
                rows[target][column + index] = value
            }
        }
        return false
    }

    /// Chuỗi vừa vào một ô có tab hoặc xuống dòng: là khối nhiều ô dán từ bảng tính, không phải chữ gõ vào ô.
    static func isMultiCell(_ text: String) -> Bool { text.contains { $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" } }

    /// Dán khối nhiều ô khi đang sửa ô (`row` nil là ô tiêu đề): lưới trống thì như dán cả lưới (dòng đầu thành tiêu đề), còn lại ghi
    /// đè từ ô đó (ô tiêu đề thì từ dòng đầu của cột đó). Trả `true` khi dòng đầu thành tiêu đề.
    @discardableResult
    mutating func pasteIntoCell(_ text: String, row: Int?, column: Int) throws(PasteError) -> Bool {
        if isEmpty { return try paste(text) }
        return try paste(text, row: row ?? 0, column: column)
    }

    /// "Undo Headers" của Desktop: tiêu đề trở lại thành dòng đầu, cột đặt lại "Column1…".
    mutating func demoteHeaders() {
        rows.insert(columns, at: 0)
        columns = columns.indices.map { "Column\($0 + 1)" }
    }

    mutating func set(row: Int, column: Int, to value: String) {
        guard rows.indices.contains(row), columns.indices.contains(column) else { return }
        rows[row][column] = value
    }

    mutating func renameColumn(_ index: Int, to name: String) {
        guard columns.indices.contains(index) else { return }
        columns[index] = name
    }

    /// Cột mới cuối lưới, tên "Column<n>" (`[SUY ĐOÁN]` n = số cột sau khi thêm, tránh trùng).
    mutating func addColumn() {
        var n = columns.count + 1
        while columns.contains("Column\(n)") { n += 1 }
        columns.append("Column\(n)")
        for index in rows.indices { rows[index].append("") }
    }

    mutating func addRow() { rows.append(Array(repeating: "", count: columns.count)) }

    /// Luôn còn ít nhất một cột.
    mutating func removeColumn(_ index: Int) {
        guard columns.count > 1, columns.indices.contains(index) else { return }
        columns.remove(at: index)
        for row in rows.indices { rows[row].remove(at: index) }
    }

    /// Luôn còn ít nhất một dòng; xoá dòng cuối thì để lại một dòng trống.
    mutating func removeRow(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
        if rows.isEmpty { addRow() }
    }

    // MARK: M

    /// M của bảng, như Desktop sinh.
    var m: String {
        let payload = MBinary.deflate(Data(Self.json(rows).utf8)).base64EncodedString()
        let fields = columns.map { "\(MQuery.reference(to: $0)) = _t" }.joined(separator: ", ")
        let source = "Table.FromRows(Json.Document(Binary.Decompress(Binary.FromText(\(StepFactory.quote(payload)), BinaryEncoding.Base64), "
            + "Compression.Deflate)), let _t = ((type nullable text) meta [Serialized.Text = true]) in type table [\(fields)])"
        let changed = StepFactory.steps(for: .changeType(typeChanges), after: "Source", existingNames: ["Source"])
        let query = MQuery(steps: [MStep(name: "Source", expression: source)] + changed, resultName: changed.last?.name ?? "Source")
        return query.source
    }

    /// Kiểu của bước "Changed Type": dò như Get Data (`ColumnTypeDetector`, bỏ qua ô trống). VM-F11a: cột có 12, 5, "", 3.5, -7 là
    /// `type number`, cột chữ là `type text`; các kiểu khác `[SUY ĐOÁN]` theo quy tắc của CSV.
    private var typeChanges: [ColumnTypeChange] {
        let data = (try? TableData(columns: columns.indices.map { index in
            TableColumn(name: "c\(index)", data: ColumnTypeDetector.column(from: rows.map { $0[index] }, name: columns[index]).data)
        })) ?? nil
        return columns.indices.map { index in
            ColumnTypeChange(column: columns[index], type: data.map { SourceQuery.typeChanges($0)[index].type } ?? .text)
        }
    }

    /// Đọc lại M Enter Data thành lưới; `nil` nếu M không phải dạng Enter Data.
    init?(name: String, m source: String) {
        guard let query = try? MQuery.parse(source), let step = query.steps.first(where: { $0.name == "Source" }),
              case .invoke(.identifier("Table.FromRows", _), let args, _)? = try? MParser.parse(step.expression), args.count == 2,
              let payload = Self.firstText(in: args[0]), case .letIn(_, .type(.table(let fields))) = args[1],
              let compressed = Data(base64Encoded: payload), let json = try? MBinary.inflate(compressed),
              let decoded = try? JSONSerialization.jsonObject(with: json) as? [[String]] else { return nil }
        self.name = name
        columns = fields.map(\.name)
        rows = decoded.map { $0 + Array(repeating: "", count: max(0, fields.count - $0.count)) }
        if rows.isEmpty { rows = [Array(repeating: "", count: columns.count)] }
    }

    // MARK: Trợ giúp

    private static func firstText(in expression: MExpression) -> String? {
        switch expression {
        case .text(let text): text
        case .invoke(_, let args, _): args.lazy.compactMap(firstText).first
        default: nil
        }
    }

    /// Mảng JSON gọn như Desktop: không khoảng trắng, chữ ngoài ASCII không thoát. `[SUY ĐOÁN]` thoát `"`, `\`, ký tự điều khiển
    /// như Json.NET (`\n`, `\r`, `\t`, `\b`, `\f`, còn lại `\u00xx`).
    static func json(_ rows: [[String]]) -> String {
        func escape(_ s: String) -> String {
            var out = "\""
            for scalar in s.unicodeScalars {
                switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                case "\u{08}": out += "\\b"
                case "\u{0C}": out += "\\f"
                case let c where c.value < 0x20: out += String(format: "\\u%04x", c.value)
                default: out.unicodeScalars.append(scalar)
                }
            }
            return out + "\""
        }
        return "[" + rows.map { "[" + $0.map(escape).joined(separator: ",") + "]" }.joined(separator: ",") + "]"
    }

    /// TSV của bảng tính: dòng cách nhau `\r\n` hoặc `\n`, ô cách nhau tab; bỏ dòng trống cuối. `[SUY ĐOÁN]` ô trong ngoặc kép
    /// (Excel/Numbers bọc ô có xuống dòng hoặc tab) được mở ngoặc, `""` thành `"`.
    static func parseTSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        var atCellStart = true
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" { cell.unicodeScalars.append("\""); i += 1 } else { quoted = false }
                } else {
                    cell.unicodeScalars.append(c)
                }
            } else if c == "\"", atCellStart {
                quoted = true
            } else if c == "\t" {
                row.append(cell); cell = ""; atCellStart = true; i += 1; continue
            } else if c == "\r" || c == "\n" {
                if c == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 1 }
                row.append(cell); rows.append(row); row = []; cell = ""; atCellStart = true; i += 1; continue
            } else {
                cell.unicodeScalars.append(c)
            }
            atCellStart = false
            i += 1
        }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        return rows
    }
}
