import SwiftUI
import ColumnStore

struct QueryRibbonView: View {
    @Binding var activeTab: QueryRibbonTab
    let context: QueryRibbonContext
    let onCommand: (QueryRibbonCommand) -> Void
    let onOpenAdvancedEditor: () -> Void
    var onOpenMerge: () -> Void = {}
    var onOpenAppend: () -> Void = {}
    var onOpenDependencies: () -> Void = {}
    var onRefreshSource: () -> Void = {}
    var hasMergeCandidates: Bool = false
    let onApply: () -> Void
    let onApplyAndClose: () -> Void
    let onCloseAttempt: () -> Void

    // View tab bindings
    @Binding var showFormulaBar: Bool
    @Binding var showQueriesPane: Bool
    @Binding var showQuerySettingsPane: Bool
    @Binding var showColumnQuality: Bool
    @Binding var showColumnDistribution: Bool
    @Binding var showColumnProfile: Bool
    var scrollable: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Ribbon Tab Bar
            tabBar
                .hairline(.bottom)

            // Ribbon Buttons Content
            ribbonContent
                .frame(height: 88)
                .background(DS.Palette.chrome)
                .hairline(.bottom)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        let lang = AppPreferences.shared.effectiveLanguage
        return HStack(spacing: 2) {
            Text(bi("Tệp", "File"))
                .font(DS.Typeface.label)
                .foregroundStyle(DS.Palette.tertiaryLabel)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

            ForEach(QueryRibbonTab.allCases, id: \.self) { tab in
                let isSelected = tab == activeTab
                Button {
                    activeTab = tab
                } label: {
                    Text(tab.localizedTitle(language: lang))
                        .font(isSelected ? DS.Typeface.headlineSmall : DS.Typeface.bodySmall)
                        .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.label)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(isSelected ? DS.Palette.chrome : Color.clear)
                        .overlay(alignment: .bottom) {
                            if isSelected {
                                Rectangle().fill(DS.Palette.accent).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(DS.Palette.canvas)
    }

    // MARK: - Ribbon Content by Tab

    @ViewBuilder
    private var ribbonContent: some View {
        HStack(alignment: .center, spacing: 0) {
            switch activeTab {
            case .home:
                homeTabRibbon
            case .transform:
                transformTabRibbon
            case .addColumn:
                addColumnTabRibbon
            case .view:
                viewTabRibbon
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Home Tab

    private var homeTabRibbon: some View {
        HStack(alignment: .center, spacing: 0) {
            // Close & Apply Group
            RibbonGroup(title: bi("Đóng", "Close")) {
                if scrollable {
                    Menu {
                        Button(bi("Đóng và áp dụng", "Close & Apply")) { onApplyAndClose() }
                        Button(bi("Áp dụng", "Apply")) { onApply() }
                        Button(bi("Đóng", "Close")) { onCloseAttempt() }
                    } label: {
                        RibbonButton(
                            title: bi("Đóng và áp dụng", "Close & Apply"),
                            symbol: "checkmark.circle.fill",
                            size: .large,
                            tint: DS.Palette.accent
                        )
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    RibbonButton(
                        title: bi("Đóng và áp dụng", "Close & Apply"),
                        symbol: "checkmark.circle.fill",
                        size: .large,
                        tint: DS.Palette.accent,
                        action: onApplyAndClose
                    )
                }
            }

            RibbonDivider()

            // Reduce Rows Group
            RibbonGroup(title: bi("Giảm dòng", "Rows")) {
                RibbonStack {
                    button(for: .keepTopRows, size: .small)
                    button(for: .removeTopRows, size: .small)
                    button(for: .removeDuplicates, size: .small)
                }
            }

            RibbonDivider()

            // Sort Group
            RibbonGroup(title: bi("Sắp xếp", "Sort")) {
                RibbonStack {
                    button(for: .sortAscending, size: .small)
                    button(for: .sortDescending, size: .small)
                }
            }

            RibbonDivider()

            // Manage Columns Group
            RibbonGroup(title: bi("Cột", "Columns")) {
                button(for: .removeColumns, size: .large)
                button(for: .promoteHeaders, size: .large)
            }

            RibbonDivider()

            // Transform Group
            RibbonGroup(title: bi("Chuyển đổi", "Transform")) {
                RibbonStack {
                    dataTypeMenu
                    button(for: .replaceValue, size: .small)
                    button(for: .filterEquals, size: .small)
                }
            }

            RibbonDivider()

            // Combine Group
            RibbonGroup(title: bi("Kết hợp", "Combine")) {
                RibbonButton(
                    title: bi("Gộp truy vấn", "Merge Queries"),
                    symbol: "arrow.triangle.merge",
                    size: .large,
                    tint: DS.Palette.accent,
                    disabledReason: hasMergeCandidates ? nil : bi("Cần có truy vấn khác để gộp", "Requires another query to merge"),
                    action: onOpenMerge
                )
                RibbonButton(
                    title: bi("Nối truy vấn", "Append Queries"),
                    symbol: "arrow.triangle.pull",
                    size: .large,
                    tint: DS.Palette.accent,
                    disabledReason: hasMergeCandidates ? nil : bi("Cần có truy vấn khác để nối", "Requires another query to append"),
                    action: onOpenAppend
                )
            }

            RibbonDivider()

            // Query Group: đọc lại tệp nguồn
            RibbonGroup(title: bi("Truy vấn", "Query")) {
                RibbonButton(
                    title: bi("Làm mới\nnguồn", "Refresh\nPreview"),
                    symbol: "arrow.clockwise",
                    size: .large,
                    tint: DS.Palette.accent,
                    action: onRefreshSource
                )
            }

            RibbonDivider()

            // Query / Advanced Editor Group
            RibbonGroup(title: bi("Nâng cao", "Advanced")) {
                RibbonButton(
                    title: bi("Trình soạn thảo\nnâng cao", "Advanced\nEditor"),
                    symbol: "curlybraces",
                    size: .large,
                    tint: DS.Palette.accent,
                    action: onOpenAdvancedEditor
                )
            }
        }
    }

    // MARK: - Transform Tab

    private var transformTabRibbon: some View {
        HStack(alignment: .center, spacing: 0) {
            // Table Group
            RibbonGroup(title: bi("Bảng", "Table")) {
                button(for: .promoteHeaders, size: .large)
                RibbonStack {
                    button(for: .reverseRows, size: .small)
                    button(for: .groupByCount, size: .small)
                }
            }

            RibbonDivider()

            // Any Column Group
            RibbonGroup(title: bi("Bất kỳ cột nào", "Any Column")) {
                RibbonStack {
                    button(for: .fillDown, size: .small)
                    button(for: .fillUp, size: .small)
                }
                RibbonStack {
                    button(for: .unpivotOtherColumns, size: .small)
                    button(for: .pivot, size: .small)
                }
            }

            RibbonDivider()

            // Text Column Group
            RibbonGroup(title: bi("Cột văn bản", "Text Column")) {
                button(for: .splitByDelimiter, size: .large)
                formatMenu
            }
        }
    }

    // MARK: - Add Column Tab

    private var addColumnTabRibbon: some View {
        HStack(alignment: .center, spacing: 0) {
            // Index Group
            RibbonGroup(title: bi("Chỉ mục", "Index")) {
                indexColumnMenu
            }

            RibbonDivider()

            // Custom Column Group
            RibbonGroup(title: bi("Tuỳ chỉnh", "Custom")) {
                button(for: .addCustomColumn, size: .large)
            }
        }
    }

    // MARK: - View Tab

    private var viewTabRibbon: some View {
        HStack(alignment: .center, spacing: 0) {
            // Layout Panes Group
            RibbonGroup(title: bi("Bố cục", "Layout")) {
                VStack(alignment: .leading, spacing: 4) {
                    checkboxItem(title: bi("Thanh công thức", "Formula Bar"), isOn: $showFormulaBar)
                    checkboxItem(title: bi("Khung Queries", "Queries Pane"), isOn: $showQueriesPane)
                    checkboxItem(title: "Query Settings", isOn: $showQuerySettingsPane)
                }
                .padding(.horizontal, 4)
            }

            RibbonDivider()

            // Data Preview Group
            RibbonGroup(title: bi("Xem trước dữ liệu", "Data Preview")) {
                VStack(alignment: .leading, spacing: 4) {
                    checkboxItem(title: bi("Chất lượng cột", "Column quality"), isOn: $showColumnQuality)
                    checkboxItem(title: bi("Phân bố cột", "Column distribution"), isOn: $showColumnDistribution)
                    checkboxItem(title: bi("Hồ sơ cột", "Column profile"), isOn: $showColumnProfile)
                }
                .padding(.horizontal, 4)
            }

            RibbonDivider()

            // Dependencies Group
            RibbonGroup(title: bi("Quan hệ", "Dependencies")) {
                RibbonButton(
                    title: bi("Phụ thuộc\ntruy vấn", "Query\nDependencies"),
                    symbol: "point.3.connected.trianglepath.dotted",
                    size: .large,
                    tint: DS.Palette.accent,
                    action: onOpenDependencies
                )
            }

            RibbonDivider()

            // Advanced Editor Group
            RibbonGroup(title: bi("Nâng cao", "Advanced")) {
                RibbonButton(
                    title: bi("Trình soạn thảo\nnâng cao", "Advanced\nEditor"),
                    symbol: "curlybraces",
                    size: .large,
                    tint: DS.Palette.accent,
                    action: onOpenAdvancedEditor
                )
            }
        }
    }

    // MARK: - Helpers

    private func checkboxItem(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                CheckboxMark(isOn: isOn.wrappedValue)
                Text(title)
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.label)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func button(for cmd: QueryRibbonCommand, size: RibbonButton.Size) -> some View {
        let lang = AppPreferences.shared.effectiveLanguage
        let enabled = cmd.isEnabled(context: context)
        let reason: String? = {
            if !cmd.isAvailable { return bi("Sắp có", "Coming soon") }
            if !enabled {
                if cmd == .pivot {
                    return bi("Xoay cột: chọn cột thuộc tính trước, cột giá trị sau", "Pivot: select attribute column first, then value column")
                }
                return bi("Chưa đủ điều kiện", "Not available for current selection")
            }
            return nil
        }()
        RibbonButton(
            title: cmd.localizedTitle(language: lang),
            symbol: cmd.symbol,
            size: size,
            disabledReason: reason,
            action: { onCommand(cmd) }
        )
    }

    @ViewBuilder
    private var dataTypeMenu: some View {
        let isEnabled = !context.selectedColumns.isEmpty
        if scrollable {
            Menu {
                Button(bi("Số nguyên", "Whole Number")) { onCommand(.changeTypeWholeNumber) }
                Button(bi("Số thập phân", "Decimal Number")) { onCommand(.changeTypeDecimal) }
                Button(bi("Văn bản", "Text")) { onCommand(.changeTypeText) }
                Button(bi("Ngày", "Date")) { onCommand(.changeTypeDate) }
                Button(bi("Ngày giờ", "Date/Time")) { onCommand(.changeTypeDateTime) }
                Button(bi("Đúng-Sai", "True/False")) { onCommand(.changeTypeLogical) }
            } label: {
                RibbonButton(
                    title: bi("Kiểu dữ liệu", "Data Type"),
                    symbol: "number",
                    size: .small,
                    disabledReason: isEnabled ? nil : bi("Chọn ít nhất một cột", "Select at least one column")
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(!isEnabled)
        } else {
            RibbonButton(
                title: bi("Kiểu dữ liệu", "Data Type"),
                symbol: "number",
                size: .small,
                disabledReason: isEnabled ? nil : bi("Chọn ít nhất một cột", "Select at least one column")
            )
        }
    }

    @ViewBuilder
    private var formatMenu: some View {
        let isEnabled = !context.selectedColumns.isEmpty &&
            context.selectedColumns.allSatisfy { context.columnTypes[$0] == .string }
        if scrollable {
            Menu {
                Button(bi("chữ thường", "lowercase")) { onCommand(.formatLowercase) }
                Button(bi("CHỮ HOA", "UPPERCASE")) { onCommand(.formatUppercase) }
                Button(bi("Viết Hoa Mỗi Từ", "Capitalize Each Word")) { onCommand(.formatCapitalizeEachWord) }
                Button(bi("Cắt khoảng trắng", "Trim")) { onCommand(.formatTrim) }
                Button(bi("Làm sạch", "Clean")) { onCommand(.formatClean) }
            } label: {
                RibbonButton(
                    title: bi("Định dạng", "Format"),
                    symbol: "textformat",
                    size: .large,
                    disabledReason: isEnabled ? nil : bi("Chọn ít nhất một cột kiểu văn bản", "Select at least one text column")
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(!isEnabled)
        } else {
            RibbonButton(
                title: bi("Định dạng", "Format"),
                symbol: "textformat",
                size: .large,
                disabledReason: isEnabled ? nil : bi("Chọn ít nhất một cột kiểu văn bản", "Select at least one text column")
            )
        }
    }

    @ViewBuilder
    private var indexColumnMenu: some View {
        if scrollable {
            Menu {
                Button(bi("Từ 0", "From 0")) { onCommand(.addIndexColumnFrom0) }
                Button(bi("Từ 1", "From 1")) { onCommand(.addIndexColumnFrom1) }
            } label: {
                RibbonButton(
                    title: bi("Cột chỉ mục", "Index Column"),
                    symbol: "list.number",
                    size: .large
                )
            }
            .menuStyle(.borderlessButton)
        } else {
            RibbonButton(
                title: bi("Cột chỉ mục", "Index Column"),
                symbol: "list.number",
                size: .large
            )
        }
    }
}
