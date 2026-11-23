import AppKit
import DAXEngine
import PBIXKit
import SwiftUI

struct TableWorkspace: View {
    static let usesInnerStatusBar = false

    @Bindable var state: DocumentState

    var body: some View {
        let _ = state.modelVersion   // vẽ lại khi mô hình đổi (Phase E)
        VStack(spacing: 0) {
            FormulaBar(state: state)
            HStack(spacing: 0) {
                if let table = state.table {
                    TableGridView(state: state, table: table).id(table)
                } else {
                    ContentUnavailableView(bi("Chọn một bảng", "Select a table"), systemImage: "tablecells").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack(spacing: 0) {
                    DataPane(state: state, purpose: .table)
                    if let table = state.table, let name = state.measure, let measure = state.workspace.measure(table: table, name: name) {
                        MeasurePropertiesPanel(state: state, measure: measure).id("\(table)/\(name)/\(state.modelVersion)")
                    } else {
                        ColumnMetadataPanel(state: state)
                    }
                }
                .frame(width: 240)
                .hairline(.leading)
            }
        }
        .background(DS.Palette.canvas)
    }
}

/// `fx` bar: the DAX expression of the selected calculated column, or — Phase E — the editable formula of a measure.
struct FormulaBar: View {
    let state: DocumentState

    var body: some View {
        if let draft = state.measureDraft {
            MeasureFormulaBar(state: state, draft: draft)
        } else {
            columnBar
        }
    }

    private var columnBar: some View {
        let column = state.table.flatMap { t in state.column.flatMap { state.workspace.column(table: t, name: $0) } }
        return HStack(spacing: 8) {
            Text("fx").font(.system(size: 12, weight: .semibold, design: .serif)).italic()
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(DS.Palette.selectionSoft))
            Image(systemName: "xmark").foregroundStyle(DS.Palette.tertiaryLabel)
            Image(systemName: "checkmark").foregroundStyle(DS.Palette.tertiaryLabel)
            Text(formula(column))
                .font(DS.Typeface.monoMedium)
                .foregroundStyle(column?.kind == .calculated ? DS.Palette.label : DS.Palette.secondaryLabel)
                .lineLimit(1)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.chrome))
        }
        .font(.system(size: 10, weight: .bold))
        .padding(.horizontal, 10)
        .frame(height: 36)
        .hairline(.bottom)
        .help(column?.kind == .calculated ? "Cột tính toán: \(state.modelEditingBlocker ?? "chọn lại cột để sửa công thức")" : "Cột dữ liệu nạp từ nguồn")
    }

    private func formula(_ column: ModelMetadata.Column?) -> String {
        guard let column else {
            guard let table = state.table else { return "" }
            if let expression = state.workspace.metadata?.calculatedTableExpressions[table],
               state.workspace.userTables.contains(where: { $0.name == table && $0.isCalculatedUserTable }) {
                return "\(table) = " + expression.replacingOccurrences(of: "\n", with: " ")
            }
            return bi("Bảng \(table)", "Table \(table)")
        }
        if column.kind == .calculated, let expression = column.expression {
            return "\(column.name) = " + expression.replacingOccurrences(of: "\n", with: " ")
        }
        return "\(column.name)  ·  " + bi("cột dữ liệu", "data column") + (column.sourceColumn.map { bi(" (nguồn: \($0))", " (source: \($0))") } ?? "")
    }
}

/// Thanh công thức sửa được của measure (Phase E): `Tên = biểu thức`, ✓ áp dụng (⌘↩), ✗ bỏ phần sửa.
struct MeasureFormulaBar: View {
    let state: DocumentState
    @Bindable var draft: MeasureDraft
    @State private var completionModel: CompletionModel?

    var body: some View {
        let blocker = state.modelEditingBlocker
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text("fx").font(.system(size: 12, weight: .semibold, design: .serif)).italic()
                    .foregroundStyle(DS.Palette.accent)
                    .frame(width: 26, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(DS.Palette.selectionSoft))
                Button { state.cancelMeasureDraft() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(canCancel ? DS.Palette.label : DS.Palette.tertiaryLabel)
                    .frame(height: 22)
                    .help("Bỏ phần đang sửa")
                Button { Task { await state.applyMeasureDraft() } } label: { Image(systemName: "checkmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(blocker == nil && !draft.isApplying ? DS.Palette.accent : DS.Palette.tertiaryLabel)
                    .frame(height: 22)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(blocker != nil || draft.isApplying)
                    .help(blocker ?? "Áp dụng công thức (⌘↩)")
                CodeEditor(text: $draft.text, language: .dax, isEditable: blocker == nil, completionModel: completionModel)
                    .frame(height: 60)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
            }
            if let line = statusLine {
                HStack(spacing: 6) {
                    Image(systemName: statusSymbol).foregroundStyle(draft.message == nil ? DS.Palette.secondaryLabel : Color.red)
                    Text(line).font(DS.Typeface.bodySmall)
                        .foregroundStyle(draft.message == nil ? DS.Palette.secondaryLabel : Color.red)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .hairline(.bottom)
        .task(id: state.modelVersion) { completionModel = makeCompletionModel() }
    }

    private var canCancel: Bool {
        draft.mode.isNew || draft.isChanged
    }

    private var statusLine: String? {
        if let message = draft.message { return message }
        if draft.isApplying { return "Đang kiểm biểu thức…" }
        if let blocker = state.modelEditingBlocker { return blocker }
        if let preview = draft.preview { return "Đã áp dụng. Giá trị: \(preview)" }
        switch draft.mode {
        case .new: return "Gõ biểu thức rồi bấm ✓ (⌘↩) để thêm vào mô hình."
        case .newColumn(let table): return "Cột tính toán mới của bảng \(table): gõ Tên = biểu thức DAX (tính theo từng dòng) rồi bấm ✓ (⌘↩)."
        case .newTable: return "Bảng tính toán mới: gõ Tên = biểu thức bảng DAX (ví dụ CALENDAR, DISTINCT) rồi bấm ✓ (⌘↩)."
        case .edit: break
        case .editColumn(let table, let name):
            if let error = state.workspace.runtime?.calculationErrors["\(table)[\(name)]"] { return "Cột đang lỗi: \(error)" }
            if draft.isChanged { return "Bấm ✓ (⌘↩) để áp dụng; cột và bảng tính toán dùng cột này được tính lại." }
        case .editTable(let name):
            if let error = state.workspace.runtime?.calculationErrors[name] { return "Bảng đang lỗi: \(error)" }
            if draft.isChanged { return "Bấm ✓ (⌘↩) để áp dụng; bảng được tính lại theo công thức mới." }
        }
        return nil
    }

    private var statusSymbol: String {
        draft.message != nil ? "exclamationmark.triangle.fill" : (draft.isApplying ? "hourglass" : "info.circle")
    }

    private func makeCompletionModel() -> CompletionModel? {
        guard let meta = state.workspace.metadata else { return nil }
        let tables = meta.userTables.map(\.name)
        var columnsByTable: [String: [String]] = [:]
        var measuresByTable: [String: [ModelMetadata.Measure]] = [:]
        for t in tables {
            columnsByTable[t] = state.workspace.columns(of: t).map(\.name)
            measuresByTable[t] = state.workspace.measures(of: t)
        }
        return CompletionModel(functions: Array(Set(FunctionRegistry.all.map(\.name) + DAXCompletion.queryForms)).sorted(),
                               tables: tables, columnsByTable: columnsByTable, measuresByTable: measuresByTable)
    }
}

struct TableGridView: View {
    let state: DocumentState
    let table: String

    @State private var columns: [DecodedColumn]?
    @State private var error: String?
    @State private var elapsed: Duration?
    /// Lọc lưới theo cột đang chọn (chỉ để xem, không đụng mô hình).
    @State private var filterText = ""
    @State private var visibleRows: Int?
    /// Tăng mỗi lần nạp xong: lưới (NSTableView giữ dữ liệu trong `Coordinator`) dựng lại khi dữ liệu đổi mà tên cột giữ nguyên
    /// (sửa công thức cột tính toán, T116; nạp lại bảng cùng cột).
    @State private var loads = 0

    /// Khoá nạp lại lưới: đọc `modelVersion` để SwiftUI tính lại khi mô hình đổi (cột/bảng tính toán thêm, bảng nạp lại).
    private var gridKey: String {
        _ = state.modelVersion
        return state.workspace.dataKey(table)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "tablecells.fill").foregroundStyle(DS.Palette.table)
                Text(table).font(DS.Typeface.headlineSmall)
                Text("\(state.workspace.rowCount(table).formatted()) " + bi("dòng", "rows")).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                Spacer()
                if columns != nil {
                    if let visibleRows, !filterText.isEmpty {
                        Text(bi("\(visibleRows.formatted()) dòng khớp", "\(visibleRows.formatted()) matching rows")).font(DS.Typeface.label).foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    TextField(state.column.map { bi("Lọc cột \($0)…", "Filter \($0)…") } ?? bi("Chọn cột để lọc", "Select a column to filter"), text: $filterText)
                        .textFieldStyle(.roundedBorder).font(DS.Typeface.bodySmall).frame(width: 190)
                        .disabled(state.column == nil)
                        .help(bi("Lọc và sắp xếp lưới chỉ để xem, không đổi mô hình và không cần lưu", "Grid filtering and sorting are view-only and do not modify the model"))
                }
                if let elapsed {
                    Text(bi("giải mã ", "decoded ") + elapsed.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))
                        .font(DS.Typeface.label).foregroundStyle(DS.Palette.tertiaryLabel)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .hairline(.bottom)

            if let columns {
                let titles = state.workspace.displayNames(table: table, baseNames: columns.map(\.name))
                DataGrid(columns: columns, titles: titles, metadata: state.workspace.metadata, table: table,
                         selectedColumn: state.column, filterText: filterText,
                         onRowsChanged: { visibleRows = $0 }) { name in state.select(table: table, column: name) }
                    .id(titles + ["\(loads)"])   // đổi tên cột hoặc nạp dữ liệu mới thì dựng lại lưới
            } else if let error {
                ContentUnavailableView("Không giải mã được bảng", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView("Đang giải mã \(table)…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: state.column) { _, _ in filterText = "" }   // bộ lọc thuộc về một cột: đổi cột thì xoá
        .task(id: gridKey) {
            let start = ContinuousClock.now
            let workspace = state.workspace, table = table
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[DecodedColumn], Error> in
                Result { try workspace.table(table) }
            }.value
            switch result {
            case .success(let decoded):
                columns = decoded
                loads += 1
                elapsed = ContinuousClock.now - start
            case .failure(let failure):
                error = String(describing: failure)
            }
        }
    }
}

/// NSTableView grid: SwiftUI's Table is too slow for a million rows.
struct DataGrid: NSViewRepresentable {
    let columns: [DecodedColumn]
    /// Tên hiển thị của từng cột (tên hiệu lực trong mô hình, có thể đã đổi tên so với tên lưu trữ), cùng thứ tự `columns`.
    let titles: [String]
    let metadata: ModelMetadata?
    let table: String
    var selectedColumn: String?
    var filterText = ""
    var onRowsChanged: (Int?) -> Void = { _ in }
    var onSelectColumn: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(columns: columns, titles: titles, onSelect: onSelectColumn, onRowsChanged: onRowsChanged) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.gridColor = .separatorColor
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnReordering = true
        tableView.allowsColumnSelection = true
        tableView.style = .plain
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 0)

        let rowNumber = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("#"))
        rowNumber.title = "#"
        rowNumber.width = 56
        rowNumber.dataCell = Self.cell(alignment: .right, color: NSColor(srgbRed: 0.56, green: 0.56, blue: 0.58, alpha: 1))
        tableView.addTableColumn(rowNumber)

        for (index, column) in columns.enumerated() {
            let info = metadata?.columns.first { $0.tableName == table && $0.name == titles[index] }
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            tableColumn.title = "\(titles[index]) ▾"
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: String(index), ascending: true)
            let minimum: CGFloat = column.dataType == .dateTime ? 165 : 96
            tableColumn.width = max(minimum, min(260, CGFloat(column.name.count) * 8 + 32))
            tableColumn.headerToolTip = "\(column.name) · \(dataTypeName(column.dataType))" + (info?.kind == .calculated ? " · cột tính toán" : "")
            let numeric = [.int64, .double, .decimal].contains(column.dataType)
            let calculated = info?.kind == .calculated
            tableColumn.dataCell = Self.cell(alignment: numeric ? .right : .left,
                                             color: calculated ? NSColor(srgbRed: 0, green: 0.35, blue: 0.7, alpha: 1) : .labelColor)
            tableView.addTableColumn(tableColumn)
        }
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.tableView = tableView
        context.coordinator.highlight(selectedColumn)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.highlight(selectedColumn)
        context.coordinator.setFilter(text: filterText, columnTitle: selectedColumn)
    }

    private static func cell(alignment: NSTextAlignment, color: NSColor) -> NSTextFieldCell {
        let cell = NSTextFieldCell()
        cell.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        cell.alignment = alignment
        cell.textColor = color
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let columns: [DecodedColumn]
        let titles: [String]
        let onSelect: (String) -> Void
        let onRowsChanged: (Int?) -> Void
        weak var tableView: NSTableView?
        /// Dòng gốc theo thứ tự hiển thị khi đang sắp xếp hoặc lọc; nil = nguyên bảng.
        private var rows: [Int]?
        private var sort: GridRows.Sort?
        private var filter: GridRows.Filter?
        private var generation = 0

        init(columns: [DecodedColumn], titles: [String], onSelect: @escaping (String) -> Void, onRowsChanged: @escaping (Int?) -> Void) {
            self.columns = columns
            self.titles = titles
            self.onSelect = onSelect
            self.onRowsChanged = onRowsChanged
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows?.count ?? columns.first?.count ?? 0 }

        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            guard let identifier = tableColumn?.identifier.rawValue else { return nil }
            let source = rows.map { $0[row] } ?? row
            if identifier == "#" { return String(source + 1) }
            guard let index = Int(identifier) else { return nil }
            let value = columns[index][source]
            // Số thực: tối đa 15 chữ số có nghĩa như Desktop (18 × 39,9 hiện 718.2, không phải 718.1999999999999).
            if case .double(let v) = value, v != v.rounded() { return String(format: "%.15g", v) }
            return value == .null ? "" : value.description
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            guard let index = Int(tableColumn.identifier.rawValue) else { return }
            onSelect(titles[index])
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            if let first = tableView.sortDescriptors.first, let key = first.key, let index = Int(key) {
                sort = GridRows.Sort(column: index, ascending: first.ascending)
            } else {
                sort = nil
            }
            refresh()
        }

        func setFilter(text: String, columnTitle: String?) {
            let index = columnTitle.flatMap { titles.firstIndex(of: $0) }
            let new = index.map { GridRows.Filter(column: $0, text: text) }
            guard new != filter else { return }
            filter = new
            refresh()
        }

        /// Tính lại tập và thứ tự dòng ngoài luồng chính (bảng một triệu dòng); kết quả cũ bị bỏ nếu có yêu cầu mới hơn.
        private func refresh() {
            generation += 1
            let ticket = generation, columns = columns, sort = sort, filter = filter
            Task.detached(priority: .userInitiated) { [weak self] in
                let result = GridRows.compute(columns: columns, sort: sort, filter: filter)
                await MainActor.run {
                    guard let self, ticket == self.generation else { return }
                    self.rows = result
                    self.tableView?.reloadData()
                    self.onRowsChanged(result?.count)
                }
            }
        }

        func highlight(_ name: String?) {
            guard let tableView else { return }
            let column = name.flatMap { n in titles.firstIndex { $0 == n } }
                .flatMap { tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(String($0))) }
            if tableView.highlightedTableColumn !== column { tableView.highlightedTableColumn = column }
        }
    }
}

/// Bottom-right card in Table view: where and how the selected column is stored.
struct ColumnMetadataPanel: View {
    let state: DocumentState

    var body: some View {
        let _ = state.modelVersion
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(bi("THÔNG TIN CỘT", "COLUMN INFO")).font(DS.Typeface.labelSmall).tracking(0.5).foregroundStyle(DS.Palette.tertiaryLabel)
                Spacer()
                Circle().fill(DS.Palette.accent).frame(width: 6, height: 6)
            }
            .padding(.bottom, 4)
            if let table = state.table, let name = state.column, let column = state.workspace.column(table: table, name: name) {
                let storage = state.workspace.metadata?.storage(table: table, column: name)
                PropertyRow(label: bi("Nguồn gốc", "Source"), value: column.kind == .calculated ? bi("DAX tính toán", "DAX calculated") : bi("Cột dữ liệu", "Data column"))
                PropertyRow(label: bi("Lưu trữ", "Storage"), value: bi("VertiPaq trong bộ nhớ", "VertiPaq in-memory"))
                PropertyRow(label: bi("Nén", "Encoding"), value: storage.map { $0.dictionaryFile != nil ? bi("Mã hoá từ điển", "Hash dictionary") : ($0.hashIndexFile != nil ? bi("Mã hoá giá trị", "Value encoding") : bi("Không có dữ liệu", "No data")) } ?? "—")
                PropertyRow(label: bi("Giá trị phân biệt", "Distinct values"), value: storage.map { $0.cardinality.formatted() } ?? "—")
                PropertyRow(label: bi("Kiểu", "Data type"), value: dataTypeName(column.dataType))
                PropertyRow(label: bi("Tóm tắt", "Summarize"), value: summarizeName(column))
                if let format = column.formatString { PropertyRow(label: bi("Định dạng", "Format"), value: format, mono: true) }
                if column.isHidden { PropertyRow(label: bi("Hiển thị", "Visibility"), value: bi("Ẩn trong báo cáo", "Hidden in report")) }
                Divider().padding(.vertical, 4)
                ColumnPropertiesEditor(state: state, column: column)
                    .id("\(table)/\(name)/\(state.modelVersion)")
            } else {
                Text(bi("Chọn một cột (bấm tiêu đề cột hoặc chọn trong Data pane).", "Select a column (click a column header or pick from the Data pane)."))
                    .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(DS.Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(DS.Palette.separator))
        .padding(10)
        .background(DS.Palette.chrome)
    }
}
