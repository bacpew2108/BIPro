import AppKit
import DAXEngine
import SwiftUI

// MARK: - Định dạng giá trị kết quả (UI1)

/// Định dạng giá trị của DAX Query View, theo quan sát buổi 1 (docs/phase-b-evidence/BUOI1.md):
/// - `display`: cách lưới Power BI hiển thị (O1): số làm tròn 2 chữ số, ngày `12/31/2018 12:00:00 AM`, boolean `True`.
/// - `copy`: cách Power BI Copy (O2): giá trị đầy đủ, không phụ thuộc locale, ngày `Mon, 31 Dec 2018 16:03:36`,
///   boolean `true`, `Infinity`/`NaN`, BLANK là ô rỗng.
enum ResultFormat {
    private static let displayDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "M/d/yyyy h:mm:ss a"
        return f
    }()

    private static let copyDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss"
        return f
    }()

    /// Serial OLE (ngày 0 là 1899-12-30) thành Date (UTC).
    static func date(fromSerial serial: Double) -> Date {
        Date(timeIntervalSince1970: (serial - 25_569) * 86_400)
    }

    static func display(_ value: Value) -> String {
        switch value {
        case .blank: return ""
        case .integer(let v): return String(v)
        case .double(let v): return twoDecimals(v)
        case .currency(let raw): return twoDecimals(Double(raw) / 10_000)
        case .string(let s): return s
        case .boolean(let b): return b ? "True" : "False"
        case .dateTime(let serial): return serial.isFinite ? displayDate.string(from: date(fromSerial: serial)) : nonFinite(serial)
        }
    }

    static func copy(_ value: Value) -> String {
        switch value {
        case .blank: return ""
        case .integer(let v): return String(v)
        case .double(let v): return fullDouble(v)
        case .currency(let raw): return currencyText(raw)
        case .string(let s): return s
        case .boolean(let b): return b ? "true" : "false"
        case .dateTime(let serial): return serial.isFinite ? copyDate.string(from: date(fromSerial: serial)) : nonFinite(serial)
        }
    }

    static func isNumeric(_ value: Value) -> Bool {
        switch value {
        case .integer, .double, .currency: true
        default: false
        }
    }

    /// TSV giống Copy của Power BI (O2): dòng tiêu đề, tab giữa các cột, CRLF giữa các dòng.
    static func tsv(_ table: ResultTable, order: [Int]? = nil) -> String {
        var lines = [table.columns.joined(separator: "\t")]
        for index in order ?? Array(table.rows.indices) {
            lines.append(table.rows[index].map(copy).joined(separator: "\t"))
        }
        return lines.joined(separator: "\r\n")
    }

    /// CSV (RFC 4180): ô có dấu phẩy, nháy kép hoặc xuống dòng được bọc nháy kép.
    static func csv(_ table: ResultTable, order: [Int]? = nil) -> String {
        func field(_ text: String) -> String {
            text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
                ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
        }
        var lines = [table.columns.map(field).joined(separator: ",")]
        for index in order ?? Array(table.rows.indices) {
            lines.append(table.rows[index].map { field(copy($0)) }.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func nonFinite(_ v: Double) -> String {
        v.isNaN ? "NaN" : (v > 0 ? "Infinity" : "-Infinity")
    }

    /// Làm tròn 2 chữ số, bỏ số 0 thừa, không phân nhóm (O1: 0.3333 → 0.33, -0.000001 → 0, 6257793560.3 giữ nguyên).
    private static func twoDecimals(_ v: Double) -> String {
        guard v.isFinite else { return nonFinite(v) }
        var text = String(format: "%.2f", v)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// Số thực đầy đủ để đọc lại chính xác, không ký hiệu mũ (O2: 0.3333333333333333, -0.000001).
    static func fullDouble(_ v: Double) -> String {
        guard v.isFinite else { return nonFinite(v) }
        let text = "\(v)"
        guard let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) else {
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        }
        let mantissa = String(text[..<e])
        guard let exponent = Int(text[text.index(after: e)...]) else { return text }
        let negative = mantissa.hasPrefix("-")
        let digitsPart = negative ? String(mantissa.dropFirst()) : mantissa
        let pieces = digitsPart.split(separator: ".", omittingEmptySubsequences: false)
        let intDigits = String(pieces[0])
        let fracDigits = pieces.count > 1 ? String(pieces[1]) : ""
        var digits = intDigits + fracDigits
        var point = intDigits.count + exponent
        if point <= 0 {
            digits = String(repeating: "0", count: -point + 1) + digits
            point = 1
        } else if point > digits.count {
            digits += String(repeating: "0", count: point - digits.count)
        }
        var result = String(digits.prefix(point))
        var fraction = String(digits.dropFirst(point))
        while fraction.hasSuffix("0") { fraction.removeLast() }
        while result.count > 1 && result.hasPrefix("0") { result.removeFirst() }
        if !fraction.isEmpty { result += "." + fraction }
        return negative ? "-" + result : result
    }

    /// Currency (×10⁴) với tối đa 4 chữ số thập phân, bỏ số 0 thừa (O2: 1.23456 → 1.2346).
    private static func currencyText(_ raw: Int64) -> String {
        let negative = raw < 0
        let magnitude = raw.magnitude
        var text = String(magnitude / 10_000)
        var fraction = String(magnitude % 10_000)
        fraction = String(repeating: "0", count: 4 - fraction.count) + fraction
        while fraction.hasSuffix("0") { fraction.removeLast() }
        if !fraction.isEmpty { text += "." + fraction }
        return negative ? "-" + text : text
    }
}

// MARK: - Lưới kết quả

/// Lưới kết quả dùng NSTableView (ô được tái sử dụng, nên cuộn được bảng lớn). Bấm tiêu đề cột để sắp xếp.
/// `key` đổi khi bảng kết quả đổi; so sánh `key` thay vì so cả bảng (có thể hàng triệu ô) ở mỗi lần cập nhật.
struct ResultGrid: NSViewRepresentable {
    let table: ResultTable
    let key: String
    /// Gọi khi thứ tự dòng đổi (sắp xếp), để Copy và Export giữ đúng thứ tự đang xem.
    var onOrderChange: ([Int]) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let tableView = NSTableView()
        tableView.style = .plain
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidVerticalGridLineMask]
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnReordering = false
        tableView.allowsMultipleSelection = true
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        scroll.documentView = tableView
        context.coordinator.load(table, key: key, into: tableView, onOrderChange: onOrderChange)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tableView = scroll.documentView as? NSTableView, context.coordinator.key != key else { return }
        context.coordinator.load(table, key: key, into: tableView, onOrderChange: onOrderChange)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private(set) var key = ""
        private var table = ResultTable(columns: [], rows: [])
        private var order: [Int] = []
        private var numericColumn: [Bool] = []
        private var onOrderChange: ([Int]) -> Void = { _ in }
        private static let cellFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        private static let rowNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)

        func load(_ table: ResultTable, key: String, into tableView: NSTableView,
                  onOrderChange: @escaping ([Int]) -> Void) {
            self.table = table
            self.key = key
            self.onOrderChange = onOrderChange
            order = Array(table.rows.indices)
            numericColumn = table.columns.indices.map { c in
                table.rows.prefix(200).contains { ResultFormat.isNumeric($0[c]) }
            }
            for column in tableView.tableColumns { tableView.removeTableColumn(column) }
            let number = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("#"))
            number.title = "#"
            number.width = max(36, CGFloat(String(table.rows.count).count) * 8 + 16)
            tableView.addTableColumn(number)
            for (c, name) in table.columns.enumerated() {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(c)"))
                column.title = name
                column.sortDescriptorPrototype = NSSortDescriptor(key: "c\(c)", ascending: true)
                let sample = table.rows.prefix(200).map { ResultFormat.display($0[c]).count }.max() ?? 0
                column.width = min(320, max(70, CGFloat(max(sample, name.count)) * 7.2 + 20))
                if numericColumn[c] { column.headerCell.alignment = .right }
                tableView.addTableColumn(column)
            }
            tableView.sortDescriptors = []
            tableView.reloadData()
            notifyOrder()
        }

        /// Báo thứ tự dòng cho SwiftUI ở lượt sau của main queue (không sửa state trong lúc view đang cập nhật).
        private func notifyOrder() {
            let current = order
            let callback = onOrderChange
            DispatchQueue.main.async { callback(current) }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { order.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            let identifier = tableColumn.identifier
            let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField) ?? {
                let label = NSTextField(labelWithString: "")
                label.identifier = identifier
                label.lineBreakMode = .byTruncatingTail
                return label
            }()
            let source = order[row]
            if identifier.rawValue == "#" {
                field.stringValue = String(source + 1)
                field.font = Self.rowNumberFont
                field.textColor = .tertiaryLabelColor
                field.alignment = .right
            } else if let c = Int(identifier.rawValue.dropFirst()), c < table.columns.count {
                let value = table.rows[source][c]
                field.stringValue = ResultFormat.display(value)
                field.font = Self.cellFont
                field.textColor = .labelColor
                field.alignment = numericColumn[c] ? .right : .left
            }
            return field
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key,
                  let c = Int(key.dropFirst()), c < table.columns.count else { return }
            let rows = table.rows
            order.sort { a, b in
                let ordered = Self.less(rows[a][c], rows[b][c])
                let reversed = Self.less(rows[b][c], rows[a][c])
                if !ordered && !reversed { return a < b }
                return descriptor.ascending ? ordered : reversed
            }
            tableView.reloadData()
            notifyOrder()
        }

        /// Thứ tự sắp xếp của lưới: BLANK trước, rồi số và ngày theo giá trị, rồi chuỗi (không phân biệt hoa thường).
        private static func less(_ a: Value, _ b: Value) -> Bool {
            func rank(_ v: Value) -> Int {
                switch v {
                case .blank: 0
                case .boolean: 1
                case .integer, .double, .currency, .dateTime: 2
                case .string: 3
                }
            }
            func number(_ v: Value) -> Double {
                switch v {
                case .integer(let x): Double(x)
                case .double(let x): x
                case .currency(let x): Double(x) / 10_000
                case .dateTime(let x): x
                case .boolean(let x): x ? 1 : 0
                default: 0
                }
            }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            if case .string(let x) = a, case .string(let y) = b {
                return x.localizedCaseInsensitiveCompare(y) == .orderedAscending
            }
            return number(a) < number(b)
        }
    }
}
