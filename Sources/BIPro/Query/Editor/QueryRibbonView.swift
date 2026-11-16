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
        HStack(spacing: 2) {
            Text("Tệp")
                .font(DS.Typeface.label)
                .foregroundStyle(DS.Palette.tertiaryLabel)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

            ForEach(QueryRibbonTab.allCases, id: \.self) { tab in
                let isSelected = tab == activeTab
                Button {
                    activeTab = tab
                } label: {
                    Text(tab.title)
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
        .background(Color.white)
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
            RibbonGroup(title: "Đóng") {
                if scrollable {
                    Menu {
                        Button("Đóng và áp dụng") { onApplyAndClose() }
                        Button("Áp dụng") { onApply() }
                        Button("Đóng") { onCloseAttempt() }
                    } label: {
                        RibbonButton(
                            title: "Đóng và áp dụng",
                            symbol: "checkmark.circle.fill",
                            size: .large,
                            tint: DS.Palette.accent
                        )
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    RibbonButton(
                        title: "Đóng và áp dụng",
                        symbol: "checkmark.circle.fill",
                        size: .large,
                        tint: DS.Palette.accent,
                        action: onApplyAndClose
                    )
                }
            }

            RibbonDivider()

            // Reduce Rows Group
            RibbonGroup(title: "Giảm dòng") {
                RibbonStack {
                    button(for: .keepTopRows, size: .small)
                    button(for: .removeTopRows, size: .small)
                    button(for: .removeDuplicates, size: .small)
                }
            }

            RibbonDivider()

            // Sort Group
            RibbonGroup(title: "Sắp xếp") {
                RibbonStack {
                    button(for: .sortAscending, size: .small)
                    button(for: .sortDescending, size: .small)
                }
            }

            RibbonDivider()

            // Manage Columns Group
            RibbonGroup(title: "Cột") {
                button(for: .removeColumns, size: .large)
                button(for: .promoteHeaders, size: .large)
            }

            RibbonDivider()

            // Transform Group
            RibbonGroup(title: "Chuyển đổi") {
                RibbonStack {
                    dataTypeMenu
                    button(for: .replaceValue, size: .small)
                    button(for: .filterEquals, size: .small)
                }
            }

            RibbonDivider()

            // Combine Group
            RibbonGroup(title: "Kết hợp") {
                RibbonButton(
                    title: "Gộp truy vấn",
                    symbol: "arrow.triangle.merge",
                    size: .large,
                    tint: DS.Palette.accent,
                    disabledReason: hasMergeCandidates ? nil : "Cần có truy vấn khác để gộp",
                    action: onOpenMerge
                )
                RibbonButton(
                    title: "Nối truy vấn",
                    symbol: "arrow.triangle.pull",
                    size: .large,
                    tint: DS.Palette.accent,
                    disabledReason: hasMergeCandidates ? nil : "Cần có truy vấn khác để nối",
                    action: onOpenAppend
                )
            }

            RibbonDivider()

            // Query / Advanced Editor Group
            RibbonGroup(title: "Nâng cao") {
                RibbonButton(
                    title: "Trình soạn thảo\nnâng cao",
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
            RibbonGroup(title: "Bảng") {
                button(for: .promoteHeaders, size: .large)
                RibbonStack {
                    button(for: .reverseRows, size: .small)
                    button(for: .groupByCount, size: .small)
                }
            }

            RibbonDivider()

            // Any Column Group
            RibbonGroup(title: "Bất kỳ cột nào") {
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
            RibbonGroup(title: "Cột văn bản") {
                button(for: .splitByDelimiter, size: .large)
                formatMenu
            }
        }
    }

    // MARK: - Add Column Tab

    private var addColumnTabRibbon: some View {
        HStack(alignment: .center, spacing: 0) {
            // Index Group
            RibbonGroup(title: "Chỉ mục") {
                indexColumnMenu
            }

            RibbonDivider()

            // Custom Column Group
            RibbonGroup(title: "Tuỳ chỉnh") {
                button(for: .addCustomColumn, size: .large)
            }
        }
    }

    // MARK: - View Tab

    private var viewTabRibbon: some View {
        HStack(alignment: .center, spacing: 0) {
            // Layout Panes Group
            RibbonGroup(title: "Bố cục") {
                VStack(alignment: .leading, spacing: 4) {
                    checkboxItem(title: "Thanh công thức", isOn: $showFormulaBar)
                    checkboxItem(title: "Khung Queries", isOn: $showQueriesPane)
                    checkboxItem(title: "Query Settings", isOn: $showQuerySettingsPane)
                }
                .padding(.horizontal, 4)
            }

            RibbonDivider()

            // Data Preview Group
            RibbonGroup(title: "Xem trước dữ liệu") {
                VStack(alignment: .leading, spacing: 4) {
                    checkboxItem(title: "Chất lượng cột", isOn: $showColumnQuality)
                    checkboxItem(title: "Phân bố cột", isOn: $showColumnDistribution)
                    checkboxItem(title: "Hồ sơ cột", isOn: $showColumnProfile)
                }
                .padding(.horizontal, 4)
            }

            RibbonDivider()

            // Dependencies Group
            RibbonGroup(title: "Quan hệ") {
                RibbonButton(
                    title: "Phụ thuộc\ntruy vấn",
                    symbol: "point.3.connected.trianglepath.dotted",
                    size: .large,
                    tint: DS.Palette.accent,
                    action: onOpenDependencies
                )
            }

            RibbonDivider()

            // Advanced Editor Group
            RibbonGroup(title: "Nâng cao") {
                RibbonButton(
                    title: "Trình soạn thảo\nnâng cao",
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
        let enabled = cmd.isEnabled(context: context)
        let reason: String? = {
            if !cmd.isAvailable { return "Sắp có" }
            if !enabled {
                if cmd == .pivot {
                    return "Xoay cột: chọn cột thuộc tính trước, cột giá trị sau"
                }
                return "Chưa đủ điều kiện"
            }
            return nil
        }()
        RibbonButton(
            title: cmd.title,
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
                Button("Số nguyên") { onCommand(.changeTypeWholeNumber) }
                Button("Số thập phân") { onCommand(.changeTypeDecimal) }
                Button("Văn bản") { onCommand(.changeTypeText) }
                Button("Ngày") { onCommand(.changeTypeDate) }
                Button("Ngày giờ") { onCommand(.changeTypeDateTime) }
                Button("Đúng-Sai") { onCommand(.changeTypeLogical) }
            } label: {
                RibbonButton(
                    title: "Kiểu dữ liệu",
                    symbol: "number",
                    size: .small,
                    disabledReason: isEnabled ? nil : "Chọn ít nhất một cột"
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(!isEnabled)
        } else {
            RibbonButton(
                title: "Kiểu dữ liệu",
                symbol: "number",
                size: .small,
                disabledReason: isEnabled ? nil : "Chọn ít nhất một cột"
            )
        }
    }

    @ViewBuilder
    private var formatMenu: some View {
        let isEnabled = !context.selectedColumns.isEmpty &&
            context.selectedColumns.allSatisfy { context.columnTypes[$0] == .string }
        if scrollable {
            Menu {
                Button("chữ thường") { onCommand(.formatLowercase) }
                Button("CHỮ HOA") { onCommand(.formatUppercase) }
                Button("Viết Hoa Mỗi Từ") { onCommand(.formatCapitalizeEachWord) }
                Button("Cắt khoảng trắng") { onCommand(.formatTrim) }
                Button("Làm sạch") { onCommand(.formatClean) }
            } label: {
                RibbonButton(
                    title: "Định dạng",
                    symbol: "textformat",
                    size: .large,
                    disabledReason: isEnabled ? nil : "Chọn ít nhất một cột kiểu văn bản"
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(!isEnabled)
        } else {
            RibbonButton(
                title: "Định dạng",
                symbol: "textformat",
                size: .large,
                disabledReason: isEnabled ? nil : "Chọn ít nhất một cột kiểu văn bản"
            )
        }
    }

    @ViewBuilder
    private var indexColumnMenu: some View {
        if scrollable {
            Menu {
                Button("Từ 0") { onCommand(.addIndexColumnFrom0) }
                Button("Từ 1") { onCommand(.addIndexColumnFrom1) }
            } label: {
                RibbonButton(
                    title: "Cột chỉ mục",
                    symbol: "list.number",
                    size: .large
                )
            }
            .menuStyle(.borderlessButton)
        } else {
            RibbonButton(
                title: "Cột chỉ mục",
                symbol: "list.number",
                size: .large
            )
        }
    }
}
