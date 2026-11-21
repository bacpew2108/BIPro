import Connectors
import PBIXKit
import SwiftUI

/// Tab strip + command groups. Commands for later phases are shown disabled with the phase in their tooltip.
struct RibbonView: View {
    @Bindable var state: DocumentState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(state.tabs) { tab in
                    let selected = state.ribbonTab == tab
                    if tab.isContextual && !(state.tabs.first?.isContextual ?? false) && tab == state.tabs.first(where: \.isContextual) {
                        Rectangle().fill(DS.Palette.separator).frame(width: 1, height: 16).padding(.horizontal, 6)
                    }
                    Button { state.ribbonTab = tab } label: {
                        Text(tab.localizedTitle)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .foregroundStyle(tab.isContextual ? DS.Palette.accent : (selected ? DS.Palette.label : DS.Palette.secondaryLabel))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(selected ? DS.Palette.canvas : .clear)
                                .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 1, y: 0.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.localizedTitle)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) { commands }
                    .padding(.horizontal, 8)
            }
            .frame(height: 88)
            .background(DS.Palette.canvas)
            .hairline(.top)
            .hairline(.bottom)
        }
        .background(DS.Palette.chrome)
    }

    @ViewBuilder private var commands: some View {
        switch (state.mode, state.ribbonTab) {
        case (.report, .home): ReportHomeCommands(state: state)
        case (.report, .insert): InsertCommands(state: state)
        case (_, .modeling): ModelingCommands(state: state)
        case (.report, .view): ReportViewCommands(state: state)
        case (.report, .format): FormatCommands(state: state)
        case (.report, .dataDrill): DataDrillCommands()
        case (.table, .home): DataSourceCommands(state: state)
        case (.table, .tableTools): TableToolsCommands(state: state)
        case (.table, .columnTools): ColumnToolsCommands(state: state)
        case (.model, .home): ModelHomeCommands(state: state)
        case (.model, .view): ModelViewCommands(state: state)
        case (.daxQuery, .home): DAXHomeCommands(state: state)
        case (.tmdl, .home): TMDLHomeCommands(state: state)
        case (_, .view): GenericViewCommands(state: state)
        case (_, .help): HelpCommands()
        default: EmptyView()
        }
    }
}

// MARK: - Shared groups

private struct DataSourceCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: tr(.paneData)) {
            RibbonButton(title: tr(.ribbonGetData), symbol: "cylinder.split.1x2", tint: DS.Palette.accent,
                         disabledReason: state.getDataBlocker) { state.showGetData() }
            RibbonButton(title: tr(.ribbonExcel), symbol: "tablecells.badge.ellipsis", tint: DS.Palette.success,
                         disabledReason: state.getDataBlocker) { state.showGetData(kind: .excel) }
            RibbonButton(title: "SQL", symbol: "server.rack", tint: DS.Palette.indigo, phase: "Phase F")
            RibbonButton(title: tr(.ribbonEnterData), symbol: "square.and.pencil",
                         disabledReason: state.enterDataBlocker) { state.showEnterData() }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Truy vấn", "Queries")) {
            RibbonButton(title: tr(.ribbonTransformData), symbol: "slider.horizontal.3",
                         disabledReason: state.queryEditorBlocker) { state.showQueryEditor() }
            RibbonButton(title: bi("Làm mới", "Refresh"), symbol: "arrow.clockwise", tint: DS.Palette.accent,
                         disabledReason: state.refreshBlocker) { state.startRefreshAll() }
        }
    }
}

private struct CalculationCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: bi("Tính toán", "Calculations")) {
            RibbonButton(title: tr(.ribbonNewMeasure), symbol: "function", tint: DS.Palette.measure) {
                if let table = state.table ?? state.workspace.userTables.first?.name { state.newMeasureInTableView(table: table) }
            }
            RibbonButton(title: bi("Measure nhanh", "Quick measure"), symbol: "bolt", tint: DS.Palette.measure, phase: "Phase E")
        }
    }
}

private struct ReportHomeCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: bi("Bảng nhớ tạm", "Clipboard")) {
            RibbonButton(title: bi("Dán", "Paste"), symbol: "doc.on.clipboard", phase: "Phase D")
            RibbonStack {
                RibbonButton(title: bi("Cắt", "Cut"), symbol: "scissors", size: .small, phase: "Phase D")
                RibbonButton(title: bi("Sao chép", "Copy"), symbol: "doc.on.doc", size: .small, phase: "Phase D")
                RibbonButton(title: bi("Sao định dạng", "Format painter"), symbol: "paintbrush", size: .small, phase: "Phase D")
            }
        }
        RibbonDivider()
        DataSourceCommands(state: state)
        RibbonDivider()
        RibbonGroup(title: tr(.ribbonInsert)) {
            RibbonButton(title: tr(.ribbonNewVisual), symbol: "chart.bar.doc.horizontal", tint: DS.Palette.accent,
                         disabledReason: state.visualEditingBlocker) { state.insertVisual("cardVisual") }
            RibbonButton(title: tr(.ribbonTextBox), symbol: "textformat",
                         disabledReason: state.visualEditingBlocker) { state.insertVisual("textbox") }
        }
        RibbonDivider()
        ArrangeCommands(state: state)
        RibbonDivider()
        CalculationCommands(state: state)
    }
}

/// Căn lề, phân bố, nhóm (D7). Mờ ở chế độ Xem; `help` nêu lý do.
private struct ArrangeCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: tr(.ribbonArrange)) {
            Menu {
                ForEach(AlignCommand.allCases, id: \.self) { command in
                    Button { state.align(command) } label: { Label(command.title, systemImage: command.systemImage) }
                        .disabled(state.alignBlocker(command) != nil)
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "align.horizontal.left").font(.system(size: 17)).foregroundStyle(DS.Palette.secondaryLabel).frame(height: 20)
                    Text(bi("Căn lề", "Align")).font(DS.Typeface.label).foregroundStyle(DS.Palette.label)
                }
                .padding(.horizontal, 6)
                .frame(minWidth: 44, minHeight: 50)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(state.arrangeBlocker != nil)
            .opacity(state.arrangeBlocker != nil ? 0.55 : 1)
            .help(state.arrangeBlocker ?? bi("Căn lề và phân bố các visual đang chọn", "Align and distribute selected visuals"))
            RibbonButton(title: tr(.menuGroup), symbol: "square.on.square.dashed", disabledReason: state.groupBlocker) { state.groupSelection() }
            RibbonButton(title: tr(.menuUngroup), symbol: "square.on.square", disabledReason: state.ungroupBlocker) { state.ungroupSelection() }
            RibbonButton(title: bi("Gộp vào nhóm", "Merge"), symbol: "plus.square.on.square", disabledReason: state.mergeBlocker) { state.mergeSelection() }
        }
    }
}

private struct InsertCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: bi("Trang", "Pages")) {
            RibbonButton(title: tr(.ribbonNewPage), symbol: "doc.badge.plus",
                         disabledReason: state.pageEditingBlocker) { state.addPage() }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Visual", "Visuals")) {
            RibbonButton(title: tr(.ribbonNewVisual), symbol: "chart.bar.doc.horizontal", tint: DS.Palette.accent,
                         disabledReason: state.visualEditingBlocker) { state.insertVisual("clusteredColumnChart") }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Thành phần", "Elements")) {
            RibbonButton(title: tr(.ribbonTextBox), symbol: "textformat",
                         disabledReason: state.visualEditingBlocker) { state.insertVisual("textbox") }
            Menu {
                Button { state.insertVisual("actionButton") } label: {
                    Label(bi("Nút trống", "Blank button"), systemImage: "rectangle.and.hand.point.up.left")
                }
                Divider()
                Button { state.insertVisual("pageNavigator") } label: {
                    Label(bi("Điều hướng trang", "Page navigator"), systemImage: "rectangle.split.3x1")
                }
                Button { state.insertVisual("bookmarkNavigator") } label: {
                    Label(bi("Điều hướng dấu trang", "Bookmark navigator"), systemImage: "bookmark.square")
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "rectangle.and.hand.point.up.left").font(.system(size: 17)).foregroundStyle(DS.Palette.secondaryLabel).frame(height: 20)
                    Text(bi("Nút", "Buttons")).font(DS.Typeface.label).foregroundStyle(DS.Palette.label)
                }
                .padding(.horizontal, 6)
                .frame(minWidth: 44, minHeight: 50)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(state.visualEditingBlocker != nil)
            .opacity(state.visualEditingBlocker != nil ? 0.55 : 1)
            .help(state.visualEditingBlocker ?? bi("Chèn nút hành động hoặc thanh điều hướng", "Insert action button or navigator"))

            Menu {
                Button { state.insertShape("rectangle") } label: {
                    Label(bi("Hình chữ nhật", "Rectangle"), systemImage: "rectangle")
                }
                Button { state.insertShape("oval") } label: {
                    Label(bi("Hình tròn / Ôvan", "Oval"), systemImage: "circle")
                }
                Button { state.insertShape("line") } label: {
                    Label(bi("Đường thẳng", "Line"), systemImage: "line.diagonal")
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "square.on.circle").font(.system(size: 17)).foregroundStyle(DS.Palette.secondaryLabel).frame(height: 20)
                    Text(bi("Hình", "Shapes")).font(DS.Typeface.label).foregroundStyle(DS.Palette.label)
                }
                .padding(.horizontal, 6)
                .frame(minWidth: 44, minHeight: 50)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(state.visualEditingBlocker != nil)
            .opacity(state.visualEditingBlocker != nil ? 0.55 : 1)
            .help(state.visualEditingBlocker ?? bi("Chèn hình khối trang trí", "Insert shape"))

            RibbonButton(title: bi("Ảnh", "Image"), symbol: "photo",
                         disabledReason: state.visualEditingBlocker) { state.pickAndInsertImage() }
        }
    }
}

private struct ModelingCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: bi("Quan hệ", "Relationships")) {
            RibbonButton(title: tr(.ribbonManageRelationships), symbol: "point.3.connected.trianglepath.dotted", tint: DS.Palette.accent,
                         isOn: state.mode == .model) { state.mode = .model }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Tính toán", "Calculations")) {
            RibbonButton(title: tr(.ribbonNewMeasure), symbol: "function", tint: DS.Palette.measure) {
                if let table = state.table { state.beginNewMeasure(table: table) }
            }
            RibbonButton(title: tr(.ribbonNewColumn), symbol: "rectangle.split.3x1", disabledReason: state.newColumnBlocker) {
                if let table = state.table { state.beginNewColumn(table: table) }
            }
            RibbonButton(title: tr(.ribbonNewTable), symbol: "tablecells.badge.ellipsis", disabledReason: state.modelEditingBlocker) { state.beginNewTable() }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Bảo mật", "Security")) {
            RibbonButton(title: bi("Quản lý vai trò", "Manage roles"), symbol: "person.badge.shield.checkmark", phase: "sau v1")
            RibbonButton(title: bi("Xem dưới vai trò", "View as"), symbol: "eye", phase: "sau v1")
        }
    }
}

private struct HelpCommands: View {
    @State private var showAbout = false
    var body: some View {
        RibbonGroup(title: bi("Trợ giúp", "Help")) {
            RibbonButton(title: bi("Giới thiệu", "About"), symbol: "info.circle", tint: DS.Palette.accent) { showAbout = true }
            RibbonButton(title: bi("Hướng dẫn", "Welcome Guide"), symbol: "book", tint: DS.Palette.indigo) {
                AppPreferences.shared.requestShowOnboarding()
            }
        }
        .popover(isPresented: $showAbout) {
            VStack(alignment: .leading, spacing: 6) {
                Text("BI Pro").font(DS.Typeface.headlineLarge).foregroundStyle(DS.Palette.label)
                Text(bi("Phiên bản 1.0.0 · macOS Native", "Version 1.0.0 · macOS Native"))
                    .font(DS.Typeface.body).foregroundStyle(DS.Palette.secondaryLabel)
                Text(bi("Mở, chỉnh sửa và lưu .pbix (PBIR & Layout cũ), chạy DAX và Power Query native trên Apple Silicon.",
                        "Open, author, and save .pbix (PBIR & legacy Layout) with native VertiPaq, DAX, and Power Query on Apple Silicon."))
                    .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.label)
            }
            .padding(16)
            .frame(maxWidth: 320)
        }
    }
}

private struct GenericViewCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: bi("Không gian làm việc", "Workspaces")) {
            ForEach(WorkspaceMode.allCases) { mode in
                RibbonButton(title: mode.localizedTitle, symbol: mode.symbol, isOn: state.mode == mode) { state.mode = mode }
            }
        }
    }
}

// MARK: - Report

private struct ReportViewCommands: View {
    @Bindable var state: DocumentState
    @State private var showThemes = false
    var body: some View {
        RibbonGroup(title: bi("Chủ đề", "Themes")) {
            RibbonButton(title: bi("Chủ đề", "Themes"), symbol: "paintpalette", tint: DS.Palette.accent) {
                showThemes.toggle()
            }
            .popover(isPresented: $showThemes) {
                ThemePickerPopover(state: state, isPresented: $showThemes)
            }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Ngăn", "Show panes")) {
            RibbonButton(title: tr(.paneFilters), symbol: "line.3.horizontal.decrease", isOn: state.showFilters) { state.showFilters.toggle() }
            RibbonButton(title: tr(.paneVisualizations), symbol: "chart.bar", isOn: state.showVisualizations) { state.showVisualizations.toggle() }
            RibbonButton(title: tr(.paneData), symbol: "cylinder", isOn: state.showData) { state.showData.toggle() }
            RibbonButton(title: tr(.paneSelection), symbol: "square.3.layers.3d", isOn: state.showSelection) { state.showSelection.toggle() }
            RibbonButton(title: tr(.paneBookmarks), symbol: "bookmark", isOn: state.showBookmarks) { state.showBookmarks.toggle() }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Thu phóng", "Zoom")) {
            RibbonButton(title: tr(.zoomFit), symbol: "arrow.up.left.and.arrow.down.right", isOn: state.zoom == nil) { state.zoom = nil }
            RibbonButton(title: "100%", symbol: "1.magnifyingglass", isOn: state.zoom == 1) { state.zoom = 1 }
            RibbonStack {
                RibbonButton(title: tr(.zoomIn), symbol: "plus.magnifyingglass", size: .small) { state.zoomIn() }
                RibbonButton(title: tr(.zoomOut), symbol: "minus.magnifyingglass", size: .small) { state.zoomOut() }
            }
        }
    }
}

private struct FormatCommands: View {
    @Bindable var state: DocumentState
    var body: some View {
        RibbonGroup(title: bi("Tương tác", "Interactions")) {
            let blocker: String? = !state.editMode
                ? bi("Bật chế độ Sửa (⌘E) để sửa tương tác", "Enable Edit mode (⌘E) to edit interactions")
                : (state.layout.selection.count != 1 ? bi("Chọn một visual nguồn để cấu hình tương tác", "Select a source visual to configure interactions") : nil)
            RibbonButton(title: bi("Sửa tương tác", "Edit interactions"), symbol: "arrow.triangle.branch",
                         tint: DS.Palette.accent, isOn: state.layout.isEditingInteractions,
                         disabledReason: state.layout.isEditingInteractions ? nil : blocker) {
                state.layout.isEditingInteractions.toggle()
            }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Sắp xếp", "Arrange")) {
            ArrangeCommands(state: state)
        }
    }
}

private struct DataDrillCommands: View {
    var body: some View {
        RibbonGroup(title: bi("Truy sâu", "Drill")) {
            RibbonButton(title: bi("Lên một cấp", "Drill up"), symbol: "arrow.up", phase: "Phase C")
            RibbonButton(title: bi("Xuống một cấp", "Drill down"), symbol: "arrow.down", phase: "Phase C")
            RibbonButton(title: bi("Mở rộng cấp", "Expand next level"), symbol: "arrow.down.right.and.arrow.up.left", phase: "Phase C")
        }
        RibbonDivider()
        RibbonGroup(title: bi("Dữ liệu", "Data")) {
            RibbonButton(title: bi("Xem dữ liệu", "Show as a table"), symbol: "tablecells", phase: "Phase C")
        }
    }
}

// MARK: - Table

private struct TableToolsCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: bi("Cấu trúc", "Structure")) {
            VStack(alignment: .leading, spacing: 3) {
                Text(bi("TÊN", "NAME")).font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
                Text(state.table ?? "—").font(DS.Typeface.body).padding(.horizontal, 8).frame(width: 160, height: 24, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.chrome))
            }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Lịch", "Calendars")) {
            RibbonButton(title: bi("Đánh dấu bảng ngày", "Mark as date table"), symbol: "calendar", phase: "Phase E")
        }
        RibbonDivider()
        RibbonGroup(title: bi("Quan hệ", "Relationships")) {
            RibbonButton(title: bi("Quản lý quan hệ", "Manage relationships"), symbol: "point.3.connected.trianglepath.dotted", tint: DS.Palette.accent) { state.mode = .model }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Tính toán", "Calculations")) {
            RibbonButton(title: bi("Measure mới", "New measure"), symbol: "function", tint: DS.Palette.measure) {
                if let table = state.table { state.beginNewMeasure(table: table) }
            }
            RibbonButton(title: bi("Cột mới", "New column"), symbol: "rectangle.split.3x1", disabledReason: state.newColumnBlocker) {
                if let table = state.table { state.beginNewColumn(table: table) }
            }
            RibbonButton(title: bi("Bảng mới", "New table"), symbol: "tablecells.badge.ellipsis", disabledReason: state.modelEditingBlocker) { state.beginNewTable() }
        }
    }
}

private struct ColumnToolsCommands: View {
    let state: DocumentState

    var body: some View {
        let lang = AppPreferences.shared.effectiveLanguage
        let column = state.table.flatMap { t in state.column.flatMap { state.workspace.column(table: t, name: $0) } }
        RibbonGroup(title: bi("Cấu trúc", "Structure")) {
            field(bi("TÊN", "NAME"), column?.name ?? bi("Chọn một cột", "Select a column"), width: 150)
            field(bi("KIỂU DỮ LIỆU", "DATA TYPE"), column.map { dataTypeName($0.dataType, language: lang) } ?? "—", width: 110)
        }
        RibbonDivider()
        RibbonGroup(title: bi("Định dạng", "Formatting")) {
            field(bi("ĐỊNH DẠNG", "FORMAT"), column?.formatString ?? bi("Chung", "General"), width: 130)
            HStack(spacing: 2) {
                ForEach(["$", "%", ",", ".00"], id: \.self) { symbol in
                    Text(symbol).font(DS.Typeface.label).frame(width: 26, height: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(DS.Palette.chrome))
                }
            }
            .opacity(0.45)
            .help(bi("Đổi định dạng: Phase E", "Format editing: Phase E"))
        }
        RibbonDivider()
        RibbonGroup(title: bi("Thuộc tính", "Properties")) {
            field(bi("TÓM TẮT", "SUMMARIZATION"), column.map { summarizeName($0, language: lang) } ?? "—", width: 110)
            field(bi("DANH MỤC", "DATA CATEGORY"), column?.dataCategory ?? bi("Chưa phân loại", "Uncategorized"), width: 120)
        }
        RibbonDivider()
        RibbonGroup(title: bi("Sắp xếp", "Sort")) {
            let sortBy = column?.sortByColumnID.flatMap { state.workspace.metadata?.column(id: $0)?.name }
            field(bi("SẮP XẾP THEO CỘT", "SORT BY COLUMN"), sortBy ?? column?.name ?? "—", width: 140)
        }
        RibbonDivider()
        RibbonGroup(title: bi("Quan hệ", "Relationships")) {
            RibbonButton(title: bi("Quản lý quan hệ", "Manage relationships"), symbol: "point.3.connected.trianglepath.dotted", tint: DS.Palette.accent) { state.mode = .model }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Tính toán", "Calculations")) {
            RibbonButton(title: bi("Measure mới", "New measure"), symbol: "function", tint: DS.Palette.measure) {
                if let table = state.table { state.beginNewMeasure(table: table) }
            }
            RibbonButton(title: bi("Cột mới", "New column"), symbol: "rectangle.split.3x1", disabledReason: state.newColumnBlocker) {
                if let table = state.table { state.beginNewColumn(table: table) }
            }
        }
    }

    private func field(_ label: String, _ value: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
            HStack {
                Text(value).font(DS.Typeface.bodySmall).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: 24)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.chrome))
        }
        .help(bi("Chỉnh sửa có ở Phase E", "Editing available in Phase E"))
    }
}

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

// MARK: - Model

private struct ModelHomeCommands: View {
    let state: DocumentState
    var body: some View {
        DataSourceCommands(state: state)
        RibbonDivider()
        ModelingCommands(state: state)
    }
}

private struct ModelViewCommands: View {
    @Bindable var state: DocumentState
    var body: some View {
        RibbonGroup(title: bi("Bố cục", "Layout")) {
            RibbonButton(title: bi("Sắp xếp lại", "Reset layout"), symbol: "wand.and.stars") { state.resetDiagramPositions() }
            RibbonButton(title: bi("Vừa màn hình", "Fit to screen"), symbol: "arrow.up.left.and.arrow.down.right") { state.modelZoom = 0.6 }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Thu phóng", "Zoom")) {
            RibbonButton(title: tr(.zoomIn), symbol: "plus.magnifyingglass") { state.modelZoom = min(2, state.modelZoom + 0.1) }
            RibbonButton(title: tr(.zoomOut), symbol: "minus.magnifyingglass") { state.modelZoom = max(0.3, state.modelZoom - 0.1) }
        }
    }
}

// MARK: - DAX / TMDL

private struct DAXHomeCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: bi("Truy vấn", "Query")) {
            if state.isRunningDAX {
                RibbonButton(title: tr(.cancel), symbol: "stop.fill", tint: DS.Palette.danger) { state.cancelDAXQuery() }
            } else if state.canRunDAX {
                RibbonButton(title: tr(.ribbonRunQuery), symbol: "play.fill", tint: DS.Palette.accent) { state.runDAXQuery() }
            } else {
                RibbonButton(title: tr(.ribbonRunQuery), symbol: "play.fill", tint: DS.Palette.accent, phase: bi("cần mô hình dữ liệu", "requires data model"))
            }
            RibbonButton(title: bi("Định dạng", "Format"), symbol: "text.alignleft", phase: "UI4")
            RibbonButton(title: bi("Truy vấn mới", "New query"), symbol: "plus.rectangle.on.rectangle", tint: DS.Palette.accent) {
                state.daxQueries.append(DAXQueryTab(title: "\(bi("Truy vấn", "Query")) \(state.daxQueries.count + 1)", text: "EVALUATE\n"))
                state.daxSelection = state.daxQueries.count - 1
            }
        }
        RibbonDivider()
        RibbonGroup(title: bi("Mô hình", "Model")) {
            RibbonButton(title: bi("Cập nhật mô hình", "Update model"), symbol: "arrow.triangle.2.circlepath", phase: "Phase E")
        }
    }
}

private struct TMDLHomeCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: bi("Tài liệu", "Document")) {
            RibbonButton(title: bi("Sao chép", "Copy"), symbol: "doc.on.doc", tint: DS.Palette.accent) {
                if let doc = state.workspace.tmdlDocuments.first(where: { $0.path == state.tmdlPath }) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(doc.text, forType: .string)
                }
            }
            RibbonButton(title: tr(.ribbonExportTMDL), symbol: "folder.badge.plus", tint: DS.Palette.accent) { exportTMDL() }
        }
        RibbonDivider()
        RibbonGroup(title: tr(.ribbonApply)) {
            RibbonButton(title: bi("Áp dụng thay đổi", "Apply changes"), symbol: "checkmark.circle", phase: "Phase E")
        }
    }

    private func exportTMDL() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Xuất vào đây"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let root = folder.appendingPathComponent("definition", isDirectory: true)
        for doc in state.workspace.tmdlDocuments {
            let url = root.appendingPathComponent(doc.path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? doc.text.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }
}
