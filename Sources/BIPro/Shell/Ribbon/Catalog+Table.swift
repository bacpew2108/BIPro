import PBIXKit
import SwiftUI

extension RibbonCatalog {
    /// Tab **Home** ở Table view (`rb_tv_home-2x.png`): Clipboard, Data, Queries, Relationships, Calculations, Security, Sensitivity, Share.
    static let tableHome = RibbonTabSpec(
        id: .home,
        title: RibbonTabID.home.title,
        contextual: false,
        groups: [
            RibbonGroupSpec(
                id: "clipboard",
                title: Bilingual(vi: "Bảng nhớ tạm", en: "Clipboard"),
                items: [
                    RibbonItemSpec(
                        id: .paste,
                        title: Bilingual(vi: "Dán", en: "Paste"),
                        symbol: "doc.on.clipboard",
                        tint: .warning,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "Bảng dữ liệu trong Table view hiện ở chế độ chỉ đọc ô",
                            en: "Cell paste is not available in Table view"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .clipboardStack,
                        title: Bilingual(vi: "Bảng nhớ tạm", en: "Clipboard"),
                        symbol: "scissors",
                        kind: .smallStack([
                            RibbonItemSpec(
                                id: .cut,
                                title: Bilingual(vi: "Cắt", en: "Cut"),
                                symbol: "scissors",
                                tint: .neutral,
                                kind: .large,
                                availability: .pending(Bilingual(
                                    vi: "Không thể cắt ô dữ liệu trong Table view",
                                    en: "Cell cut is not available in Table view"
                                ))
                            ),
                            RibbonItemSpec(
                                id: .copy,
                                title: Bilingual(vi: "Sao chép", en: "Copy"),
                                symbol: "doc.on.doc",
                                tint: .neutral,
                                kind: .large,
                                availability: .pending(Bilingual(
                                    vi: "Dùng ⌘C trong lưới để sao chép giá trị",
                                    en: "Use ⌘C inside the table grid to copy values"
                                ))
                            ),
                        ]),
                        availability: .always
                    ),
                ]
            ),
            reportHome.groups[1], // Data
            reportHome.groups[2], // Queries
            reportModeling.groups[0], // Relationships
            RibbonGroupSpec(
                id: "calculations",
                title: Bilingual(vi: "Tính toán", en: "Calculations"),
                items: [
                    reportModeling.groups[1].items[1], // newMeasure
                    reportModeling.groups[1].items[2], // quickMeasure
                    reportModeling.groups[1].items[3], // newColumn
                    reportModeling.groups[1].items[4], // newTable
                ]
            ),
            reportModeling.groups[5], // Security
            reportHome.groups[5], // Sensitivity
            reportHome.groups[6], // Share
        ]
    )

    /// Tab ngữ cảnh **Table tools** (`rb_tv_table-2x.png`).
    static let tableTools = RibbonTabSpec(
        id: .tableTools,
        title: RibbonTabID.tableTools.title,
        contextual: true,
        groups: [
            RibbonGroupSpec(
                id: "structure",
                title: Bilingual(vi: "Cấu trúc", en: "Structure"),
                items: [
                    RibbonItemSpec(
                        id: .tableName,
                        title: Bilingual(vi: "Tên", en: "Name"),
                        symbol: "tag",
                        tint: .neutral,
                        kind: .field(.tableName),
                        availability: .when(
                            { $0.canEditModel && $0.tableSelected },
                            disabledReason: Bilingual(
                                vi: "Chọn một bảng để đổi tên",
                                en: "Select a table to rename"
                            )
                        )
                    ),
                ]
            ),
            reportModeling.groups[0], // Relationships
            RibbonGroupSpec(
                id: "calculations",
                title: Bilingual(vi: "Tính toán", en: "Calculations"),
                items: [
                    reportModeling.groups[1].items[1], // newMeasure
                    reportModeling.groups[1].items[2], // quickMeasure
                    reportModeling.groups[1].items[3], // newColumn
                    reportModeling.groups[1].items[4], // newTable
                ]
            ),
            reportModeling.groups[2], // Calendars (Mark as date table)
        ]
    )

    /// Tab ngữ cảnh **Column tools** (`rb_tv_column-2x.png`).
    static let columnTools = RibbonTabSpec(
        id: .columnTools,
        title: RibbonTabID.columnTools.title,
        contextual: true,
        groups: [
            // 1. Structure
            RibbonGroupSpec(
                id: "structure",
                title: Bilingual(vi: "Cấu trúc", en: "Structure"),
                items: [
                    RibbonItemSpec(
                        id: .columnName,
                        title: Bilingual(vi: "Tên", en: "Name"),
                        symbol: "tag",
                        tint: .neutral,
                        kind: .field(.columnName),
                        availability: .when(
                            { $0.canEditModel && $0.columnSelected },
                            disabledReason: Bilingual(
                                vi: "Chọn một cột ở bảng dữ liệu",
                                en: "Select a column in Table view"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .dataType,
                        title: Bilingual(vi: "Kiểu dữ liệu", en: "Data type"),
                        symbol: "textformat.123",
                        tint: .info,
                        kind: .field(.dataType),
                        availability: .when(
                            { $0.columnSelected },
                            disabledReason: Bilingual(
                                vi: "Đổi kiểu dữ liệu thực hiện trong Power Query (Biến đổi dữ liệu)",
                                en: "Change data type in Power Query (Transform Data)"
                            )
                        )
                    ),
                ]
            ),

            // 2. Formatting
            RibbonGroupSpec(
                id: "formatting",
                title: Bilingual(vi: "Định dạng", en: "Formatting"),
                items: [
                    RibbonItemSpec(
                        id: .format,
                        title: Bilingual(vi: "Định dạng", en: "Format"),
                        symbol: "dollarsign.circle",
                        tint: .info,
                        kind: .field(.format),
                        availability: .when(
                            { $0.canEditModel && $0.columnSelected },
                            disabledReason: Bilingual(
                                vi: "Chọn một cột để chọn chuỗi định dạng hiển thị",
                                en: "Select a column to choose display format"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .formattingQuickRow,
                        title: Bilingual(vi: "Định dạng nhanh", en: "Formatting"),
                        symbol: "number",
                        kind: .smallStack([
                            RibbonItemSpec(
                                id: .currencyFormat,
                                title: Bilingual(vi: "$", en: "$"),
                                symbol: "dollarsign",
                                tint: .neutral,
                                kind: .large,
                                hasMenu: true,
                                availability: .when(
                                    { $0.canEditModel && $0.columnSelected && $0.isNumericColumnSelected },
                                    disabledReason: Bilingual(
                                        vi: "Chỉ áp dụng cho cột kiểu số",
                                        en: "Numeric columns only"
                                    )
                                )
                            ),
                            RibbonItemSpec(
                                id: .percentFormat,
                                title: Bilingual(vi: "%", en: "%"),
                                symbol: "percent",
                                tint: .neutral,
                                kind: .large,
                                availability: .when(
                                    { $0.canEditModel && $0.columnSelected && $0.isNumericColumnSelected },
                                    disabledReason: Bilingual(
                                        vi: "Chỉ áp dụng cho cột kiểu số",
                                        en: "Numeric columns only"
                                    )
                                )
                            ),
                            RibbonItemSpec(
                                id: .thousandsFormat,
                                title: Bilingual(vi: ",", en: ","),
                                symbol: "number",
                                tint: .neutral,
                                kind: .large,
                                availability: .when(
                                    { $0.canEditModel && $0.columnSelected && $0.isNumericColumnSelected },
                                    disabledReason: Bilingual(
                                        vi: "Chỉ áp dụng cho cột kiểu số",
                                        en: "Numeric columns only"
                                    )
                                )
                            ),
                            RibbonItemSpec(
                                id: .decimalFormat,
                                title: Bilingual(vi: ".00", en: ".00"),
                                symbol: "00.circle",
                                tint: .neutral,
                                kind: .large,
                                availability: .when(
                                    { $0.canEditModel && $0.columnSelected && $0.isNumericColumnSelected },
                                    disabledReason: Bilingual(
                                        vi: "Chỉ áp dụng cho cột kiểu số",
                                        en: "Numeric columns only"
                                    )
                                )
                            ),
                            RibbonItemSpec(
                                id: .decimalPlaces,
                                title: Bilingual(vi: "Tự động", en: "Auto"),
                                symbol: "arrow.up.arrow.down",
                                tint: .neutral,
                                kind: .field(.decimalPlaces),
                                availability: .pending(Bilingual(
                                    vi: "Dùng nút .00 hoặc menu Format để đổi số chữ số thập phân",
                                    en: "Use .00 or the Format dropdown to change decimal places"
                                ))
                            ),
                        ]),
                        availability: .always
                    ),
                ]
            ),

            // 3. Properties
            RibbonGroupSpec(
                id: "properties",
                title: Bilingual(vi: "Thuộc tính", en: "Properties"),
                items: [
                    RibbonItemSpec(
                        id: .summarization,
                        title: Bilingual(vi: "Tóm tắt", en: "Summarization"),
                        symbol: "sum",
                        tint: .neutral,
                        kind: .field(.summarization),
                        availability: .when(
                            { $0.canEditModel && $0.columnSelected && $0.isNumericColumnSelected },
                            disabledReason: Bilingual(
                                vi: "Chỉ áp dụng cho cột kiểu số",
                                en: "Numeric columns only"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .dataCategory,
                        title: Bilingual(vi: "Danh mục dữ liệu", en: "Data category"),
                        symbol: "globe",
                        tint: .neutral,
                        kind: .field(.dataCategory),
                        availability: .when(
                            { $0.canEditModel && $0.columnSelected },
                            disabledReason: Bilingual(
                                vi: "Chọn một cột để gán danh mục ngữ nghĩa",
                                en: "Select a column to assign a data category"
                            )
                        )
                    ),
                ]
            ),

            // 4. Sort
            RibbonGroupSpec(
                id: "sort",
                title: Bilingual(vi: "Sắp xếp", en: "Sort"),
                items: [
                    RibbonItemSpec(
                        id: .sortByColumn,
                        title: Bilingual(vi: "Sắp xếp theo cột", en: "Sort by column"),
                        symbol: "arrow.up.arrow.down.square",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .when(
                            { $0.canEditModel && $0.columnSelected },
                            disabledReason: Bilingual(
                                vi: "Chọn một cột để sắp xếp theo cột khác",
                                en: "Select a column to sort by another column"
                            )
                        )
                    ),
                ]
            ),

            // 5. Groups
            RibbonGroupSpec(
                id: "groups",
                title: Bilingual(vi: "Nhóm", en: "Groups"),
                items: [
                    RibbonItemSpec(
                        id: .dataGroups,
                        title: Bilingual(vi: "Nhóm dữ liệu", en: "Data groups"),
                        symbol: "rectangle.3.group",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ nhóm dữ liệu (Data groups / Binning)",
                            en: "Data groups are not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),

            // 6. Relationships
            reportModeling.groups[0],

            // 7. Calculations
            RibbonGroupSpec(
                id: "calculations",
                title: Bilingual(vi: "Tính toán", en: "Calculations"),
                items: [
                    reportModeling.groups[1].items[3], // newColumn
                ]
            ),
        ]
    )
}

// MARK: - Helpers dùng chung cho TableWorkspace & LocalizationTests (di chuyển từ Ribbon.swift ở T039/T043)

func dataTypeName(_ type: ModelMetadata.DataType, language: ResolvedLanguage = .vi) -> String {
    let en = language == .en
    switch type {
    case .string: return en ? "Text" : "Văn bản"
    case .int64: return en ? "Whole number" : "Số nguyên"
    case .double: return en ? "Decimal number" : "Số thập phân"
    case .decimal: return en ? "Fixed decimal" : "Số thập phân cố định"
    case .dateTime: return en ? "Date/time" : "Ngày/giờ"
    case .boolean: return "True/False"
    case .binary: return en ? "Binary" : "Nhị phân"
    default: return en ? "Auto" : "Tự động"
    }
}

func summarizeName(_ column: ModelMetadata.Column, language: ResolvedLanguage = .vi) -> String {
    let en = language == .en
    switch column.summarizeBy {
    case 2: return en ? "Don't summarize" : "Không tóm tắt"
    case 3: return en ? "Sum" : "Tổng"
    case 4: return en ? "Minimum" : "Nhỏ nhất"
    case 5: return en ? "Maximum" : "Lớn nhất"
    case 6: return en ? "Count" : "Đếm"
    case 7: return en ? "Average" : "Trung bình"
    case 8: return en ? "Count (Distinct)" : "Đếm phân biệt"
    default: return en ? "Default" : "Mặc định"
    }
}

// MARK: - Live Ribbon Field Controls (giữ nguyên toàn bộ hành vi đổi tên/định dạng/sắp xếp + hoàn tác ⌘Z của v1.2)

struct RibbonTableNameFieldView: View {
    @Environment(\.isSnapshotRender) private var isSnapshotRender
    let state: DocumentState
    @State private var draft = ""

    var body: some View {
        let _ = state.modelVersion
        let current = state.table
        let canEdit = current != nil && state.modelEditingBlocker == nil
        HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.secondaryLabel)
            Text(bi("Tên", "Name"))
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.label)
            if canEdit, let tableName = current, !isSnapshotRender {
                TextField(bi("Tên bảng", "Table name"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .frame(width: 148, height: 24, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.canvas))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator, lineWidth: 0.75))
                    .onAppear { draft = tableName }
                    .onChange(of: tableName) { _, newValue in draft = newValue }
                    .onSubmit {
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, trimmed != tableName else { draft = tableName; return }
                        state.requestCascadeRename(.table(old: tableName, new: trimmed))
                        draft = tableName
                    }
                    .help(bi("Nhấn Enter để đổi tên bảng (tự cập nhật DAX và visual)", "Press Enter to rename table (auto-updates DAX & visuals)"))
            } else {
                HStack {
                    Text(current ?? "—")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.label)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                }
                .padding(.horizontal, 8)
                .frame(width: 148, height: 24)
                .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.canvas))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator, lineWidth: 0.75))
                .help(state.modelEditingBlocker ?? bi("Chọn một bảng", "Select a table"))
            }
        }
        .accessibilityLabel(bi("Tên bảng", "Table name"))
    }
}

struct RibbonColumnFieldControlView: View {
    @Environment(\.isSnapshotRender) private var isSnapshotRender
    let state: DocumentState
    let control: FieldControl
    let item: RibbonItemSpec
    @State private var draft = ""

    private var selectedColumn: ModelMetadata.Column? {
        state.table.flatMap { t in state.column.flatMap { state.workspace.column(table: t, name: $0) } }
    }

    var body: some View {
        let _ = state.modelVersion
        let lang = AppPreferences.shared.effectiveLanguage
        let column = selectedColumn
        let blocker = state.modelEditingBlocker
        let canEdit = column != nil && blocker == nil
        let isNumeric = column?.dataType.isNumeric == true
        let disabledTip = blocker ?? bi("Chọn một cột ở bảng dữ liệu", "Select a column in Table view")
        let numericTip = !canEdit ? disabledTip : bi("Chỉ áp dụng cho cột kiểu số", "Numeric columns only")

        switch control {
        case .tableName:
            RibbonTableNameFieldView(state: state)

        case .columnName:
            HStack(spacing: 6) {
                Image(systemName: "tag").font(.system(size: 11)).foregroundStyle(DS.Palette.secondaryLabel).frame(width: 14)
                Text(bi("Tên", "Name")).font(.system(size: 11)).foregroundStyle(DS.Palette.label).frame(width: 58, alignment: .leading)
                if canEdit, let col = column, !isSnapshotRender {
                    TextField(bi("Tên cột", "Column name"), text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .frame(width: 132, height: 24)
                        .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.canvas))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator, lineWidth: 0.75))
                        .onAppear { draft = col.name }
                        .onChange(of: col.id) { _, _ in draft = col.name }
                        .onChange(of: col.name) { _, newValue in draft = newValue }
                        .onSubmit {
                            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty, trimmed != col.name else { draft = col.name; return }
                            if let reason = state.updateColumn(table: col.tableName, name: col.name, patch: ColumnPatch(name: trimmed)) {
                                state.layout.noteFieldRefusal(reason)
                                draft = col.name
                            }
                        }
                        .help(bi("Nhấn Enter để đổi tên cột", "Press Enter to rename column"))
                } else {
                    comboBoxLabel(column?.name ?? bi("Chọn một cột", "Select a column"), width: 132, enabled: canEdit)
                        .help(disabledTip)
                }
            }
            .accessibilityLabel(bi("Tên cột", "Column name"))

        case .dataType:
            HStack(spacing: 6) {
                Image(systemName: "textformat.123").font(.system(size: 11)).foregroundStyle(DS.Palette.secondaryLabel).frame(width: 14)
                Text(bi("Kiểu dữ liệu", "Data type")).font(.system(size: 11)).foregroundStyle(DS.Palette.label).frame(width: 58, alignment: .leading)
                comboBoxLabel(column.map { dataTypeName($0.dataType, language: lang) } ?? "—", width: 132, enabled: false)
                    .help(bi("Đổi kiểu dữ liệu thực hiện trong Power Query (Biến đổi dữ liệu)",
                             "Change data type in Power Query (Transform Data)"))
            }
            .accessibilityLabel(bi("Kiểu dữ liệu", "Data type"))

        case .format:
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle").font(.system(size: 11)).foregroundStyle(DS.Palette.secondaryLabel).frame(width: 14)
                Text(bi("Định dạng", "Format")).font(.system(size: 11)).foregroundStyle(DS.Palette.label)
                RibbonMenuButton(
                    disabled: !canEdit,
                    help: canEdit ? bi("Chọn chuỗi định dạng hiển thị cho cột", "Choose display format string for column") : disabledTip,
                    accessibilityLabel: bi("Định dạng", "Format")
                ) {
                    if let col = column {
                        Button(bi("Chung", "General")) {
                            applyColumn(col, ColumnPatch(formatString: .clear), key: "format")
                        }
                        Divider()
                        ForEach(ColumnPropertiesEditor.formatPresets, id: \.self) { preset in
                            Button(preset) {
                                applyColumn(col, ColumnPatch(formatString: .set(preset)), key: "format")
                            }
                        }
                    }
                } label: {
                    comboBoxLabel(column?.formatString ?? bi("Chung", "General"), width: 130, enabled: canEdit)
                }
            }

        case .summarization:
            HStack(spacing: 6) {
                Image(systemName: "sum").font(.system(size: 11)).foregroundStyle(DS.Palette.secondaryLabel).frame(width: 14)
                Text(bi("Tóm tắt", "Summarization")).font(.system(size: 11)).foregroundStyle(DS.Palette.label).frame(width: 82, alignment: .leading)
                RibbonMenuButton(
                    disabled: !(canEdit && isNumeric),
                    help: (canEdit && isNumeric) ? bi("Chọn phép tổng hợp mặc định cho cột số", "Choose default summarization for numeric column") : numericTip,
                    accessibilityLabel: bi("Tóm tắt", "Summarization")
                ) {
                    if let col = column {
                        ForEach(ColumnPropertiesEditor.summarizeOptions, id: \.value) { opt in
                            Button(opt.title) {
                                applyColumn(col, ColumnPatch(summarizeBy: opt.value), key: nil)
                            }
                        }
                    }
                } label: {
                    comboBoxLabel(column.map { summarizeName($0, language: lang) } ?? "—", width: 120, enabled: canEdit && isNumeric)
                }
            }

        case .dataCategory:
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(DS.Palette.secondaryLabel).frame(width: 14)
                Text(bi("Danh mục", "Data category")).font(.system(size: 11)).foregroundStyle(DS.Palette.label).frame(width: 82, alignment: .leading)
                RibbonMenuButton(
                    disabled: !canEdit,
                    help: canEdit ? bi("Gán danh mục ngữ nghĩa (địa lý, URL…)", "Assign semantic data category (geography, URL…)") : disabledTip,
                    accessibilityLabel: bi("Danh mục dữ liệu", "Data category")
                ) {
                    if let col = column {
                        Button(bi("Chưa phân loại", "Uncategorized")) {
                            applyColumn(col, ColumnPatch(dataCategory: .clear), key: nil)
                        }
                        Divider()
                        ForEach(ColumnPropertiesEditor.categories, id: \.self) { category in
                            Button(category) {
                                applyColumn(col, ColumnPatch(dataCategory: .set(category)), key: nil)
                            }
                        }
                    }
                } label: {
                    comboBoxLabel(column?.dataCategory ?? bi("Chưa phân loại", "Uncategorized"), width: 120, enabled: canEdit)
                }
            }

        case .decimalPlaces:
            HStack(spacing: 4) {
                Text(bi("Tự động", "Auto"))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .padding(.horizontal, 7)
            .frame(width: 62, height: 22)
            .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.chrome))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator, lineWidth: 0.75))
            .opacity(0.45)
            .help(bi("Dùng nút .00 hoặc menu Format để đổi số chữ số thập phân", "Use .00 or Format dropdown to change decimal places"))
            .accessibilityLabel(bi("Số chữ số thập phân", "Decimal places"))

        case .applyDrillFiltersTo:
            let context = RibbonContext(state: state)
            let enabled = item.availability.isEnabled(in: context)
            let page = state.page, visual = state.visual
            let selectedOnly = (page != nil && visual != nil) && state.interaction.isDrillScopeSelectedOnly(page: page!, visual: visual!)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.localized)
                    .font(.system(size: 11))
                    .foregroundStyle(enabled ? DS.Palette.label : DS.Palette.secondaryLabel)
                RibbonMenuButton(disabled: !enabled, help: item.availability.disabledReason(in: context)?.localized ?? item.title.localized,
                                 accessibilityLabel: item.title.localized) {
                    if let page, let visual {
                        Button {
                            state.interaction.setDrillScope(page: page, visual: visual, selectedOnly: false)
                        } label: {
                            Label(bi("Toàn bộ trang", "Entire page"), systemImage: selectedOnly ? "" : "checkmark")
                        }
                        Button {
                            state.interaction.setDrillScope(page: page, visual: visual, selectedOnly: true)
                        } label: {
                            Label(bi("Visual đã chọn", "Selected visual"), systemImage: selectedOnly ? "checkmark" : "")
                        }
                    }
                } label: {
                    comboBoxLabel(selectedOnly ? bi("Visual đã chọn", "Selected visual") : bi("Toàn bộ trang", "Entire page"),
                                  width: 126, enabled: enabled)
                }
            }
            .opacity(0.55)
            .help(bi("BI Pro chưa hỗ trợ phạm vi bộ lọc truy sâu tuỳ chỉnh", "Custom drill-down filter scope is not yet implemented in BI Pro"))
            .accessibilityLabel(item.title.localized)

        case .formattingShortcuts:
            RibbonColumnQuickFormatRow(state: state)
        }
    }

    private func applyColumn(_ column: ModelMetadata.Column, _ patch: ColumnPatch, key: String?) {
        if let reason = state.updateColumn(table: column.tableName, name: column.name, patch: patch,
                                           coalesceKey: key.map { "column-\(column.id)-\($0)" }) {
            state.layout.noteFieldRefusal(reason)
        }
    }

    private func comboBoxLabel(_ value: String, width: CGFloat, enabled: Bool) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(enabled ? DS.Palette.label : DS.Palette.secondaryLabel)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 8))
                .foregroundStyle(DS.Palette.tertiaryLabel)
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: 24)
        .background(RoundedRectangle(cornerRadius: 4).fill(enabled ? DS.Palette.canvas : DS.Palette.chrome))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator, lineWidth: 0.75))
        .opacity(enabled ? 1 : 0.7)
    }
}

/// Hàng phím nhanh định dạng `$ ▾ % , .00 [Auto]` trong nhóm Formatting của tab Column tools (`rb_tv_column-2x.png`).
struct RibbonColumnQuickFormatRow: View {
    let state: DocumentState

    var body: some View {
        let _ = state.modelVersion
        let column = state.table.flatMap { t in state.column.flatMap { state.workspace.column(table: t, name: $0) } }
        let blocker = state.modelEditingBlocker
        let canEdit = column != nil && blocker == nil
        let isNumeric = column?.dataType.isNumeric == true
        let enabled = canEdit && isNumeric
        let numericTip = blocker ?? (!canEdit ? bi("Chọn một cột ở bảng dữ liệu", "Select a column in Table view") : bi("Chỉ áp dụng cho cột kiểu số", "Numeric columns only"))

        HStack(spacing: 4) {
            quickButton("$", active: column?.formatString?.contains("$") == true, enabled: enabled, hasChevron: true,
                        help: enabled ? bi("Định dạng tiền tệ ($)", "Currency format ($)") : numericTip) {
                RibbonActions.perform(.currencyFormat, state: state)
            }
            quickButton("%", active: column?.formatString?.hasSuffix("%") == true, enabled: enabled,
                        help: enabled ? bi("Định dạng phần trăm (%)", "Percentage format (%)") : numericTip) {
                RibbonActions.perform(.percentFormat, state: state)
            }
            quickButton(",", active: column?.formatString?.contains("#,") == true, enabled: enabled,
                        help: enabled ? bi("Dấu phân tách hàng nghìn (,)", "Thousands separator (,)") : numericTip) {
                RibbonActions.perform(.thousandsFormat, state: state)
            }
            quickButton(".00", active: column?.formatString?.contains(".00") == true, enabled: enabled,
                        help: enabled ? bi("Bật/tắt 2 chữ số thập phân (.00)", "Toggle 2 decimal places (.00)") : numericTip) {
                RibbonActions.perform(.decimalFormat, state: state)
            }
            HStack(spacing: 3) {
                Text(bi("Tự động", "Auto"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7.5))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .padding(.horizontal, 6)
            .frame(width: 58, height: 22)
            .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.chrome))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator, lineWidth: 0.75))
            .opacity(0.45)
            .help(bi("Dùng nút .00 hoặc menu Format để đổi số chữ số thập phân", "Use .00 or Format dropdown to change decimal places"))
        }
    }

    private func quickButton(_ label: String, active: Bool, enabled: Bool, hasChevron: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                if hasChevron {
                    Image(systemName: "chevron.down").font(.system(size: 7))
                }
            }
            .foregroundStyle(active ? DS.Palette.accentBrand : DS.Palette.label)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 4).fill(active ? DS.Palette.accentBrand.opacity(0.14) : DS.Palette.chrome))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
