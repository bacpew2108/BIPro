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

// MARK: - Header cell và view tuỳ biến có icon sắp xếp và lọc (UI3, O13, Sửa 1)

final class FilterableTableHeaderCell: NSTableHeaderCell {
    var isFiltered: Bool = false
    var sortDirection: GridFilter.SortDirection? = nil

    override init(textCell string: String) {
        super.init(textCell: string)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! FilterableTableHeaderCell
        copy.isFiltered = isFiltered
        copy.sortDirection = sortDirection
        return copy
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let base = super.drawingRect(forBounds: rect)
        // Chừa chỗ cho icon và mũi tên ở mép phải ô tiêu đề (khoảng 32 pt)
        let reservedWidth: CGFloat = 32
        return NSRect(
            x: base.minX,
            y: base.minY,
            width: max(0, base.width - reservedWidth),
            height: base.height
        )
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.draw(withFrame: cellFrame, in: controlView)
        drawIcons(in: cellFrame)
    }

    private func drawIcons(in cellFrame: NSRect) {
        let filterRect = ResultGrid.filterIconDrawingRect(in: cellFrame)
        let filterSymbol = isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease"
        let filterColor: NSColor = isFiltered ? .controlAccentColor : .secondaryLabelColor
        drawSymbol(named: filterSymbol, color: filterColor, in: filterRect)

        if let sortDirection {
            let arrowRect = ResultGrid.sortArrowDrawingRect(in: cellFrame)
            let arrowSymbol = (sortDirection == .ascending) ? "arrow.up" : "arrow.down"
            drawSymbol(named: arrowSymbol, color: .secondaryLabelColor, in: arrowRect)
        }
    }

    private func drawSymbol(named name: String, color: NSColor, in rect: NSRect) {
        guard let baseImage = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
            .applying(.init(hierarchicalColor: color))
        let image = baseImage.withSymbolConfiguration(config) ?? baseImage
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
    }
}

final class ResultTableHeaderView: NSTableHeaderView {
    weak var coordinator: ResultGrid.Coordinator?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let colIdx = column(at: point)
        guard colIdx >= 0, let tableView = self.tableView else {
            super.mouseDown(with: event)
            return
        }
        let tableCol = tableView.tableColumns[colIdx]
        // Cột số thứ tự dòng (#) không có menu
        if tableCol.identifier.rawValue == "#" {
            super.mouseDown(with: event)
            return
        }
        let rect = headerRect(ofColumn: colIdx)
        let isSorted = (tableCol.headerCell as? FilterableTableHeaderCell)?.sortDirection != nil
        let hitRect = ResultGrid.filterIconHitRect(in: rect, isSorted: isSorted)

        // Chỉ khi bấm vào vùng icon (vùng bấm rộng khoảng 20 pt) mới mở popover
        if hitRect.contains(point) {
            let iconRect = ResultGrid.filterIconDrawingRect(in: rect)
            coordinator?.openMenu(for: colIdx, tableColumn: tableCol, iconRect: iconRect, headerView: self)
            return
        }

        // Bấm vào chữ tên cột thì không làm gì; kéo mép để đổi độ rộng cột vẫn phải hoạt động
        super.mouseDown(with: event)
    }
}

// MARK: - Popover sắp xếp và lọc cột (O13)

struct ColumnFilterPopoverView: View {
    let column: Int
    let columnName: String
    let isNumericOrDate: Bool
    let distinctValues: [Value]
    let currentSortKey: GridFilter.SortKey?
    let currentFilter: Set<Value>?

    var onSort: (GridFilter.SortDirection) -> Void
    var onClearSort: () -> Void
    var onApplyFilter: (Set<Value>?) -> Void

    @State private var searchText = ""
    @State private var selectedValues: Set<Value>

    init(
        column: Int,
        columnName: String,
        isNumericOrDate: Bool,
        distinctValues: [Value],
        currentSortKey: GridFilter.SortKey?,
        currentFilter: Set<Value>?,
        onSort: @escaping (GridFilter.SortDirection) -> Void,
        onClearSort: @escaping () -> Void,
        onApplyFilter: @escaping (Set<Value>?) -> Void
    ) {
        self.column = column
        self.columnName = columnName
        self.isNumericOrDate = isNumericOrDate
        self.distinctValues = distinctValues
        self.currentSortKey = currentSortKey
        self.currentFilter = currentFilter
        self.onSort = onSort
        self.onClearSort = onClearSort
        self.onApplyFilter = onApplyFilter
        _selectedValues = State(initialValue: currentFilter ?? Set(distinctValues))
    }

    private var isSorted: Bool {
        currentSortKey?.column == column
    }

    private var filteredValues: [Value] {
        GridFilter.filterValues(distinctValues, query: searchText)
    }

    private var allFilteredSelected: Bool {
        let visible = filteredValues
        guard !visible.isEmpty else { return false }
        return visible.allSatisfy { selectedValues.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Sắp xếp
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    onSort(.ascending)
                } label: {
                    HStack {
                        Image(systemName: isNumericOrDate ? "arrow.up.circle" : "textformat.characters")
                            .frame(width: 16)
                        Text(isNumericOrDate ? "Nhỏ đến lớn" : "A đến Z")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)

                Button {
                    onSort(.descending)
                } label: {
                    HStack {
                        Image(systemName: isNumericOrDate ? "arrow.down.circle" : "textformat.characters")
                            .frame(width: 16)
                        Text(isNumericOrDate ? "Lớn đến nhỏ" : "Z đến A")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)

                Button {
                    onClearSort()
                } label: {
                    HStack {
                        Image(systemName: "clear")
                            .frame(width: 16)
                        Text("Bỏ sắp xếp")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isSorted)
                .opacity(isSorted ? 1.0 : 0.45)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
            }

            Divider()

            // Tìm kiếm
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Tìm kiếm", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor), lineWidth: 1))

            // Chọn tất cả
            Button {
                let visible = filteredValues
                if allFilteredSelected {
                    selectedValues.subtract(visible)
                } else {
                    selectedValues.formUnion(visible)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: allFilteredSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(allFilteredSelected ? Color.accentColor : Color.secondary)
                    Text("Chọn tất cả")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.top, 2)

            Divider()

            // Danh sách giá trị phân biệt
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredValues, id: \.self) { val in
                        let isChecked = selectedValues.contains(val)
                        Button {
                            if isChecked {
                                selectedValues.remove(val)
                            } else {
                                selectedValues.insert(val)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                                Text(GridFilter.displayLabel(for: val))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                    }
                }
            }
            .frame(maxHeight: 160)

            Divider()

            // Nút Áp dụng
            HStack {
                Spacer()
                Button("Áp dụng") {
                    if selectedValues.count == distinctValues.count {
                        onApplyFilter(nil)
                    } else {
                        onApplyFilter(selectedValues)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .frame(width: 240)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Lưới kết quả

/// Lưới kết quả dùng NSTableView (ô được tái sử dụng, nên cuộn được bảng lớn). Bấm tiêu đề cột để mở menu sắp xếp và lọc.
/// `key` đổi khi bảng kết quả đổi; so sánh `key` thay vì so cả bảng (có thể hàng triệu ô) ở mỗi lần cập nhật.
struct ResultGrid: NSViewRepresentable {
    let table: ResultTable
    let key: String
    /// Gọi khi thứ tự dòng đổi (sắp xếp hoặc lọc), để Copy và Export giữ đúng thứ tự đang xem.
    var onOrderChange: ([Int]) -> Void = { _ in }

    /// Vùng bấm mở menu lọc/sắp xếp của cột (rộng khoảng 20 pt, mở rộng khi có thêm mũi tên sắp xếp).
    public static func filterIconHitRect(in headerRect: NSRect, isSorted: Bool = false) -> NSRect {
        let width: CGFloat = isSorted ? 30 : 20
        let rightMargin: CGFloat = 2
        let x = max(headerRect.minX, headerRect.maxX - width - rightMargin)
        return NSRect(x: x, y: headerRect.minY, width: min(width, headerRect.width), height: headerRect.height)
    }

    /// Vùng vẽ icon lọc (12 pt sát mép phải ô tiêu đề).
    public static func filterIconDrawingRect(in headerRect: NSRect) -> NSRect {
        let size: CGFloat = 12
        let rightMargin: CGFloat = 6
        let x = headerRect.maxX - size - rightMargin
        let y = headerRect.minY + (headerRect.height - size) / 2
        return NSRect(x: x, y: y, width: size, height: size)
    }

    /// Vùng vẽ mũi tên sắp xếp cạnh icon lọc (10 pt).
    public static func sortArrowDrawingRect(in headerRect: NSRect) -> NSRect {
        let filterRect = filterIconDrawingRect(in: headerRect)
        let size: CGFloat = 10
        let spacing: CGFloat = 2
        let x = filterRect.minX - spacing - size
        let y = headerRect.minY + (headerRect.height - size) / 2
        return NSRect(x: x, y: y, width: size, height: size)
    }

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

        let headerView = ResultTableHeaderView()
        headerView.tableView = tableView
        headerView.coordinator = context.coordinator
        tableView.headerView = headerView

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
        private var filters: [Int: Set<Value>] = [:]
        private var sortKey: GridFilter.SortKey? = nil
        private weak var tableView: NSTableView?
        private var popover: NSPopover?

        private static let cellFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        private static let rowNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)

        func load(_ table: ResultTable, key: String, into tableView: NSTableView,
                  onOrderChange: @escaping ([Int]) -> Void) {
            self.table = table
            self.key = key
            self.onOrderChange = onOrderChange
            self.tableView = tableView
            self.filters = [:]
            self.sortKey = nil
            self.popover?.close()
            self.popover = nil

            order = Array(table.rows.indices)
            numericColumn = table.columns.indices.map { c in
                table.rows.prefix(200).contains { ResultFormat.isNumeric($0[c]) }
            }
            for column in tableView.tableColumns { tableView.removeTableColumn(column) }
            let number = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("#"))
            number.title = "#"
            // Biểu tượng bảng ở góc lưới, như Power BI (ảnh lưới DAX Query View).
            if let icon = NSImage(systemSymbolName: "tablecells", accessibilityDescription: "Số dòng") {
                let attachment = NSTextAttachment()
                attachment.image = icon
                let title = NSMutableAttributedString(attachment: attachment)
                title.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                   range: NSRange(location: 0, length: title.length))
                number.headerCell.attributedStringValue = title
                number.headerCell.alignment = .center
            }
            number.width = max(36, CGFloat(String(table.rows.count).count) * 8 + 16)
            tableView.addTableColumn(number)
            for (c, name) in table.columns.enumerated() {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(c)"))
                column.title = name
                let sample = table.rows.prefix(200).map { ResultFormat.display($0[c]).count }.max() ?? 0
                column.width = min(320, max(70, CGFloat(max(sample, name.count)) * 7.2 + 20))
                let headerCell = FilterableTableHeaderCell(textCell: name)
                if numericColumn[c] { headerCell.alignment = .right }
                column.headerCell = headerCell
                tableView.addTableColumn(column)
            }
            tableView.sortDescriptors = []
            updateHeaderUI()
            tableView.reloadData()
            notifyOrder()
        }

        func openMenu(for colIdx: Int, tableColumn: NSTableColumn, iconRect: NSRect, headerView: NSView) {
            guard let c = Int(tableColumn.identifier.rawValue.dropFirst()), c < table.columns.count else { return }
            popover?.close()

            let isNumOrDate = numericColumn[c] || GridFilter.isNumericOrDateColumn(in: table, column: c)
            let distinct = GridFilter.distinctValues(in: table, column: c)

            let view = ColumnFilterPopoverView(
                column: c,
                columnName: table.columns[c],
                isNumericOrDate: isNumOrDate,
                distinctValues: distinct,
                currentSortKey: sortKey,
                currentFilter: filters[c],
                onSort: { [weak self] dir in
                    self?.applySort(column: c, direction: dir)
                    self?.popover?.close()
                },
                onClearSort: { [weak self] in
                    self?.clearSort(column: c)
                    self?.popover?.close()
                },
                onApplyFilter: { [weak self] selected in
                    self?.applyFilter(column: c, selectedValues: selected, totalDistinctCount: distinct.count)
                    self?.popover?.close()
                }
            )

            let hosting = NSHostingController(rootView: view)
            let pop = NSPopover()
            pop.contentViewController = hosting
            pop.behavior = .transient
            pop.animates = true
            // Nền sáng như Power BI (O13); mặc định NSPopover theo vibrancy nên nền xám tối, khó đọc.
            pop.appearance = NSAppearance(named: .aqua)
            self.popover = pop
            // Popover hiện ngay dưới icon
            pop.show(relativeTo: iconRect, of: headerView, preferredEdge: .maxY)
        }

        func applySort(column: Int, direction: GridFilter.SortDirection) {
            sortKey = GridFilter.SortKey(column: column, direction: direction)
            recomputeAndReload()
        }

        func clearSort(column: Int) {
            if sortKey?.column == column {
                sortKey = nil
                recomputeAndReload()
            }
        }

        func applyFilter(column: Int, selectedValues: Set<Value>?, totalDistinctCount: Int) {
            if let selectedValues, selectedValues.count < totalDistinctCount {
                filters[column] = selectedValues
            } else {
                filters.removeValue(forKey: column)
            }
            recomputeAndReload()
        }

        private func recomputeAndReload() {
            order = GridFilter.filteredAndSortedIndices(in: table, filters: filters, sortKey: sortKey)
            updateHeaderUI()
            tableView?.reloadData()
            notifyOrder()
        }

        private func updateHeaderUI() {
            guard let tableView else { return }
            for (c, name) in table.columns.enumerated() {
                guard let col = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(c)")) else { continue }
                let isFiltered = filters[c] != nil
                col.title = name

                if let cell = col.headerCell as? FilterableTableHeaderCell {
                    cell.isFiltered = isFiltered
                    cell.sortDirection = (sortKey?.column == c) ? sortKey?.direction : nil
                }
                tableView.setIndicatorImage(nil, in: col)
            }
            tableView.headerView?.needsDisplay = true
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
            // Ô là NSTableCellView chứa nhãn căn giữa theo chiều dọc (NSTextField trần bị dính mép trên).
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
                let cell = NSTableCellView()
                cell.identifier = identifier
                let label = NSTextField(labelWithString: "")
                label.lineBreakMode = .byTruncatingTail
                label.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(label)
                cell.textField = label
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
                return cell
            }()
            guard let field = cell.textField else { return cell }
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
            return cell
        }
    }
}
