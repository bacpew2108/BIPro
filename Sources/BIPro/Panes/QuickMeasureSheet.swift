// Wave 4B (T007): Hộp thoại Measure nhanh (Quick Measure) cho Ribbon Home / Modeling.
import DAXEngine
import PBIXKit
import SwiftUI

struct QuickMeasureSheet: View {
    @Bindable var state: DocumentState
    let onDismiss: () -> Void

    @State private var template: QuickMeasureTemplate = .ytdTotal
    @State private var targetTable: String = ""
    @State private var measureName: String = ""
    @State private var baseMeasure: String = ""
    @State private var secondaryMeasure: String = ""
    @State private var selectedDateCol: String = ""   // "Table|Col"
    @State private var selectedCatCol: String = ""    // "Table|Col"
    @State private var filterText: String = ""
    @State private var rollingDaysText: String = "30"
    @State private var errorMessage: String? = nil
    @State private var isCreating: Bool = false

    private var tables: [String] { state.workspace.userTables.map(\.name) }
    private var allMeasures: [ModelMetadata.Measure] { state.workspace.metadata?.measures ?? [] }
    private var dateColumns: [ModelMetadata.Column] {
        (state.workspace.metadata?.columns ?? []).filter { $0.dataType == .dateTime && $0.kind != .rowNumber }
    }
    private var allColumns: [ModelMetadata.Column] {
        (state.workspace.metadata?.columns ?? []).filter { $0.kind != .rowNumber }
    }

    private func splitPair(_ key: String) -> (String, String) {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : ("", "")
    }

    private var generated: (suggestedName: String, expression: String) {
        let (dtTable, dtCol) = splitPair(selectedDateCol)
        let (catTable, catCol) = splitPair(selectedCatCol)
        let days = Int(rollingDaysText) ?? 30
        return template.generate(
            baseMeasure: baseMeasure,
            secondaryRef: secondaryMeasure,
            dateTable: dtTable,
            dateColumn: dtCol,
            categoryTable: catTable.isEmpty ? targetTable : catTable,
            categoryColumn: catCol,
            filterValue: filterText,
            rollingDays: days
        )
    }

    private var effectiveName: String {
        let t = measureName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? generated.suggestedName : t
    }

    private var canSubmit: Bool {
        guard !targetTable.isEmpty, !baseMeasure.isEmpty, !isCreating else { return false }
        if template.needsDateColumn && selectedDateCol.isEmpty { return false }
        if template.needsCategoryColumn && selectedCatCol.isEmpty { return false }
        if template.needsSecondMeasureOrColumn && secondaryMeasure.isEmpty { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Palette.measure)
                Text(bi("Tạo Measure nhanh", "Quick Measure"))
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
            }

            Form {
                Picker(bi("Phép tính:", "Calculation:"), selection: $template) {
                    ForEach(QuickMeasureTemplate.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                Picker(bi("Bảng lưu measure:", "Home table:"), selection: $targetTable) {
                    ForEach(tables, id: \.self) { Text($0).tag($0) }
                }
                Picker(bi("Measure gốc:", "Base measure:"), selection: $baseMeasure) {
                    ForEach(allMeasures, id: \.name) { m in
                        Text("\(m.tableName)[\(m.name)]").tag(m.name)
                    }
                }
                if template.needsDateColumn {
                    Picker(bi("Cột ngày:", "Date column:"), selection: $selectedDateCol) {
                        ForEach(dateColumns, id: \.id) { c in
                            Text("\(c.tableName)[\(c.name)]").tag("\(c.tableName)|\(c.name)")
                        }
                    }
                }
                if template.needsCategoryColumn {
                    Picker(bi("Cột phân loại:", "Category column:"), selection: $selectedCatCol) {
                        ForEach(allColumns, id: \.id) { c in
                            Text("\(c.tableName)[\(c.name)]").tag("\(c.tableName)|\(c.name)")
                        }
                    }
                }
                if template.needsSecondMeasureOrColumn {
                    Picker(bi("Measure / trọng số thứ 2:", "Second measure / weight:"), selection: $secondaryMeasure) {
                        ForEach(allMeasures, id: \.name) { m in
                            Text("\(m.tableName)[\(m.name)]").tag(m.name)
                        }
                    }
                }
                if template.needsFilterLiteral {
                    TextField(bi("Giá trị lọc:", "Filter value:"), text: $filterText)
                }
                if template.needsWindowLength {
                    TextField(bi("Số ngày trượt:", "Rolling days:"), text: $rollingDaysText)
                }
                TextField(bi("Tên measure (tuỳ chọn):", "Measure name (optional):"), text: $measureName,
                          prompt: Text(generated.suggestedName))
            }
            .formStyle(.grouped)
            .frame(maxHeight: 270)

            VStack(alignment: .leading, spacing: 4) {
                Text(bi("Xem trước DAX:", "DAX preview:"))
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                Text("\(effectiveName) = \(generated.expression)")
                    .font(DS.Typeface.mono)
                    .foregroundStyle(DS.Palette.label)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(DS.Palette.chrome))
            }

            if let err = errorMessage {
                Text(err)
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.danger)
            }

            HStack {
                Spacer()
                Button(bi("Huỷ", "Cancel")) { onDismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(bi("Tạo Measure", "Create Measure")) {
                    Task { await createMeasure() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520)
        .background(DS.Palette.canvas)
        .onAppear {
            targetTable = state.table ?? tables.first ?? ""
            baseMeasure = allMeasures.first?.name ?? ""
            secondaryMeasure = allMeasures.dropFirst().first?.name ?? allMeasures.first?.name ?? ""
            if let dc = dateColumns.first { selectedDateCol = "\(dc.tableName)|\(dc.name)" }
            if let cc = allColumns.first { selectedCatCol = "\(cc.tableName)|\(cc.name)" }
        }
    }

    private func createMeasure() async {
        guard canSubmit else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        let expr = generated.expression
        let name = effectiveName
        let ws = state.workspace
        let check = await Task.detached(priority: .userInitiated) { () -> MeasureCheck in
            guard let engine = try? ws.daxEngine() else {
                return .failed(MeasureProblem(message: ws.modelError ?? "Không có engine DAX"))
            }
            return await MeasureTyping.check(expr, using: engine)
        }.value

        guard case .ok(let info) = check else {
            if case .failed(let problem) = check { errorMessage = problem.message }
            return
        }
        let fmt = (template == .percentOfGrandTotal || template == .yoyPercentChange) ? "0.0%" : info.formatString
        let added = NewMeasure(table: targetTable, name: name, expression: expr,
                               formatString: fmt, dataType: info.dataType.rawValue)
        if let reason = state.modelEditor.apply(.addMeasure(added)) {
            errorMessage = reason
            return
        }
        state.table = targetTable
        state.measure = name
        onDismiss()
    }
}
