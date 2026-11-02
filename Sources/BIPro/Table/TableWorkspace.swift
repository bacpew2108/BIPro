import AppKit
import PBIXKit
import SwiftUI

struct TableWorkspace: View {
    @Bindable var state: DocumentState

    var body: some View {
        VStack(spacing: 0) {
            FormulaBar(state: state)
            HStack(spacing: 0) {
                if let table = state.table {
                    TableGridView(state: state, table: table).id(table)
                } else {
                    ContentUnavailableView("Chọn một bảng", systemImage: "tablecells").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack(spacing: 0) {
                    DataPane(state: state, purpose: .table)
                    ColumnMetadataPanel(state: state)
                }
                .frame(width: 270)
                .hairline(.leading)
            }
            StatusBar(workspace: state.workspace, detail: statusDetail)
        }
        .background(Color.white)
    }

    private var statusDetail: String {
        guard let table = state.table else { return "" }
        var text = "Bảng: \(table) (\(state.workspace.rowCount(table).formatted()) dòng)"
        if let column = state.column, let storage = state.workspace.metadata?.storage(table: table, column: column) {
            text += " · Cột: \(column) (\(storage.cardinality.formatted()) giá trị phân biệt)"
        }
        return text
    }
}

/// `fx` bar: the DAX expression of the selected calculated column, or its definition.
struct FormulaBar: View {
    let state: DocumentState

    var body: some View {
        let column = state.table.flatMap { t in state.column.flatMap { state.workspace.column(table: t, name: $0) } }
        HStack(spacing: 8) {
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
        .help(column?.kind == .calculated ? "Sửa công thức: Phase E" : "Cột dữ liệu nạp từ nguồn")
    }

    private func formula(_ column: ModelMetadata.Column?) -> String {
        guard let column else { return state.table.map { "Bảng \($0)" } ?? "" }
        if column.kind == .calculated, let expression = column.expression {
            return "\(column.name) = " + expression.replacingOccurrences(of: "\n", with: " ")
        }
        return "\(column.name)  ·  cột dữ liệu" + (column.sourceColumn.map { " (nguồn: \($0))" } ?? "")
    }
}

struct TableGridView: View {
    let state: DocumentState
    let table: String

    @State private var columns: [DecodedColumn]?
    @State private var error: String?
    @State private var elapsed: Duration?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "tablecells.fill").foregroundStyle(DS.Palette.table)
                Text(table).font(DS.Typeface.headlineSmall)
                Text("\(state.workspace.rowCount(table).formatted()) dòng").font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                Spacer()
                if let elapsed {
                    Text("giải mã \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))")
                        .font(DS.Typeface.label).foregroundStyle(DS.Palette.tertiaryLabel)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .hairline(.bottom)

            if let columns {
                DataGrid(columns: columns, metadata: state.workspace.metadata, table: table,
                         selectedColumn: state.column) { name in state.select(table: table, column: name) }
            } else if let error {
                ContentUnavailableView("Không giải mã được bảng", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView("Đang giải mã \(table)…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let start = ContinuousClock.now
            let workspace = state.workspace, table = table
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[DecodedColumn], Error> in
                Result { try workspace.table(table) }
            }.value
            switch result {
            case .success(let decoded):
                columns = decoded
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
    let metadata: ModelMetadata?
    let table: String
    var selectedColumn: String?
    var onSelectColumn: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(columns: columns, onSelect: onSelectColumn) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.gridColor = NSColor(srgbRed: 0.898, green: 0.898, blue: 0.918, alpha: 1)
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
            let info = metadata?.columns.first { $0.tableName == table && $0.name == column.name }
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            tableColumn.title = column.name
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
        let onSelect: (String) -> Void
        weak var tableView: NSTableView?

        init(columns: [DecodedColumn], onSelect: @escaping (String) -> Void) {
            self.columns = columns
            self.onSelect = onSelect
        }

        func numberOfRows(in tableView: NSTableView) -> Int { columns.first?.count ?? 0 }

        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            guard let identifier = tableColumn?.identifier.rawValue else { return nil }
            if identifier == "#" { return String(row + 1) }
            guard let index = Int(identifier) else { return nil }
            let value = columns[index][row]
            return value == .null ? "" : value.description
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            guard let index = Int(tableColumn.identifier.rawValue) else { return }
            onSelect(columns[index].name)
        }

        func highlight(_ name: String?) {
            guard let tableView else { return }
            let column = name.flatMap { n in columns.firstIndex { $0.name == n } }
                .flatMap { tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(String($0))) }
            if tableView.highlightedTableColumn !== column { tableView.highlightedTableColumn = column }
        }
    }
}

/// Bottom-right card in Table view: where and how the selected column is stored.
struct ColumnMetadataPanel: View {
    let state: DocumentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("THÔNG TIN CỘT").font(DS.Typeface.labelSmall).tracking(0.5).foregroundStyle(DS.Palette.tertiaryLabel)
                Spacer()
                Circle().fill(DS.Palette.accent).frame(width: 6, height: 6)
            }
            .padding(.bottom, 4)
            if let table = state.table, let name = state.column, let column = state.workspace.column(table: table, name: name) {
                let storage = state.workspace.metadata?.storage(table: table, column: name)
                PropertyRow(label: "Nguồn gốc", value: column.kind == .calculated ? "DAX tính toán" : "Cột dữ liệu")
                PropertyRow(label: "Lưu trữ", value: "VertiPaq trong bộ nhớ")
                PropertyRow(label: "Nén", value: storage.map { $0.dictionaryFile != nil ? "Mã hoá từ điển" : ($0.hashIndexFile != nil ? "Mã hoá giá trị" : "Không có dữ liệu") } ?? "—")
                PropertyRow(label: "Giá trị phân biệt", value: storage.map { $0.cardinality.formatted() } ?? "—")
                PropertyRow(label: "Kiểu", value: dataTypeName(column.dataType))
                PropertyRow(label: "Tóm tắt", value: summarizeName(column))
                if let format = column.formatString { PropertyRow(label: "Định dạng", value: format, mono: true) }
                if column.isHidden { PropertyRow(label: "Hiển thị", value: "Ẩn trong báo cáo") }
            } else {
                Text("Chọn một cột (bấm tiêu đề cột hoặc chọn trong Data pane).")
                    .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(DS.Palette.separator))
        .padding(10)
        .background(DS.Palette.chrome)
    }
}
