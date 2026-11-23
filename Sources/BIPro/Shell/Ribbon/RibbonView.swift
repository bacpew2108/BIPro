import SwiftUI

/// Thanh Ribbon mới chuẩn Power BI Desktop 2.159 (T019):
/// - Hàng tab chữ thường 13 pt, tab chọn đậm + gạch chân `UIMetrics.tabUnderline` màu `accentBrand`
/// - Tab ngữ cảnh chữ `accentBrand`, không vạch phân cách
/// - Nút Share neo phải ở trạng thái vô hiệu kèm tooltip
/// - Panel trắng/canvas nổi trên chrome, bo `UIMetrics.ribbonCorner`, cao `UIMetrics.ribbonPanel`, cuộn ngang khi hẹp, nút `^` thu gọn lưu `AppPreferences.ribbonCollapsed`
struct RibbonView: View {
    @Bindable var state: DocumentState
    /// Đặt `false` khi xuất ảnh bằng `ImageRenderer` để nội dung không bị `ScrollView` vẽ trống.
    var scrollable: Bool = true
    var preferences: AppPreferences = .shared

    @State private var showAbout = false

    var body: some View {
        let context = RibbonContext(state: state)
        VStack(spacing: 0) {
            tabStrip
            if !preferences.ribbonCollapsed {
                ribbonPanel(context: context)
            }
        }
        .environment(\.isSnapshotRender, !scrollable)
        .background(DS.Palette.chrome)
        .popover(isPresented: $showAbout) {
            RibbonAboutPopover()
        }
    }

    // MARK: - Hàng tab

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(state.tabs) { tab in
                let selected = tab != .file && state.ribbonTab == tab
                Button {
                    state.selectRibbonTab(tab)
                    if tab != .file && preferences.ribbonCollapsed {
                        preferences.ribbonCollapsed = false
                    }
                } label: {
                    Text(tab.localizedTitle)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(tabTextColor(tab: tab, selected: selected))
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: UIMetrics.tabRow)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Rectangle()
                                    .fill(DS.Palette.tabUnderline)
                                    .frame(height: UIMetrics.tabUnderline)
                                    .padding(.horizontal, 6)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.localizedTitle)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            Spacer(minLength: 8)

            if preferences.ribbonCollapsed {
                Button {
                    preferences.ribbonCollapsed = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(bi("Mở rộng thanh Ribbon", "Expand the Ribbon"))
                .accessibilityLabel(bi("Mở rộng thanh Ribbon", "Expand the Ribbon"))
            }

            shareDisabledButton
        }
        .padding(.horizontal, 10)
        .frame(height: UIMetrics.tabRow)
        .background(DS.Palette.chrome)
    }

    private func tabTextColor(tab: RibbonTab, selected: Bool) -> Color {
        if tab.isContextual {
            return DS.Palette.accentBrand
        }
        return selected ? DS.Palette.label : DS.Palette.secondaryLabel
    }

    private var shareDisabledButton: some View {
        Button {} label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
                Text(bi("Chia sẻ", "Share"))
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.accentBrand))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.45)
        .help(bi("BI Pro chưa hỗ trợ chia sẻ", "BI Pro doesn't support sharing yet"))
        .accessibilityLabel(bi("Chia sẻ", "Share"))
    }

    // MARK: - Panel Ribbon

    private func ribbonPanel(context: RibbonContext) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Group {
                if scrollable {
                    ScrollView(.horizontal) {
                        panelContent(context: context)
                            .padding(.leading, 8)
                            .padding(.trailing, 8)
                    }
                    .scrollIndicators(.automatic)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: UIMetrics.ribbonPanel, maxHeight: UIMetrics.ribbonPanel)
                        .overlay(alignment: .leading) {
                            panelContent(context: context)
                                .padding(.leading, 8)
                                .padding(.trailing, 8)
                        }
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity, minHeight: UIMetrics.ribbonPanel, maxHeight: UIMetrics.ribbonPanel, alignment: .leading)

            Button {
                preferences.ribbonCollapsed = true
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .padding(.bottom, 2)
            .help(bi("Thu gọn thanh Ribbon", "Collapse the Ribbon"))
            .accessibilityLabel(bi("Thu gọn thanh Ribbon", "Collapse the Ribbon"))
        }
        .background(
            RoundedRectangle(cornerRadius: UIMetrics.ribbonCorner)
                .fill(DS.Palette.canvas)
                .shadow(color: Color.dynamic(light: 0x000000, lightAlpha: 0.06, dark: 0x000000, darkAlpha: 0.28), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIMetrics.ribbonCorner)
                .strokeBorder(DS.Palette.separator.opacity(0.8), lineWidth: 0.75)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func panelContent(context: RibbonContext) -> some View {
        if let spec = RibbonCatalog.spec(for: state.ribbonTab.tabID, mode: state.mode) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(spec.groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Rectangle()
                            .fill(DS.Palette.separator)
                            .frame(width: 1)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 2)
                    }
                    VStack(spacing: 0) {
                        groupItemsView(group: group, context: context, tabID: spec.id)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, 4)

                        Text(group.title.localized)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(DS.Palette.tertiaryLabel)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.bottom, 3)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(height: UIMetrics.ribbonPanel)
        } else {
            EmptyView()
                .frame(height: UIMetrics.ribbonPanel)
        }
    }

    /// Xếp dọc cho nhóm chỉ gồm checkbox (`Page options`) hoặc nhóm cặp field (`Structure`, `Formatting`, `Properties` ở Column tools).
    @ViewBuilder
    private func groupItemsView(group: RibbonGroupSpec, context: RibbonContext, tabID: RibbonTabID) -> some View {
        let allCheckboxes = !group.items.isEmpty && group.items.allSatisfy {
            if case .checkbox = $0.kind { return true }
            return false
        }
        let isVerticalFieldStack = group.items.count >= 2 && group.items.allSatisfy { item in
            if case .field = item.kind { return true }
            return item.id == .formattingQuickRow
        }
        if allCheckboxes {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(group.items) { item in
                    RibbonItemView(
                        state: state,
                        item: item,
                        context: context,
                        tabID: tabID,
                        onOpenAbout: { showAbout = true }
                    )
                }
            }
            .padding(.horizontal, 2)
        } else if isVerticalFieldStack {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.items) { item in
                    RibbonItemView(
                        state: state,
                        item: item,
                        context: context,
                        tabID: tabID,
                        onOpenAbout: { showAbout = true }
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        } else {
            HStack(alignment: .top, spacing: 2) {
                ForEach(group.items) { item in
                    RibbonItemView(
                        state: state,
                        item: item,
                        context: context,
                        tabID: tabID,
                        onOpenAbout: { showAbout = true }
                    )
                }
            }
        }
    }

    /// Ước lượng bề rộng nội dung tối thiểu của một `RibbonTabSpec` (dùng trong test kiểm tra cuộn ngang ở cửa sổ hẹp 1000 pt).
    static func estimatedContentWidth(for spec: RibbonTabSpec) -> CGFloat {
        var total: CGFloat = 36 // padding trái + phải
        for (index, group) in spec.groups.enumerated() {
            if index > 0 { total += 5 }
            var groupWidth: CGFloat = 12
            for item in group.items {
                switch item.kind {
                case .large, .toggle:
                    groupWidth += 58
                case .smallStack:
                    groupWidth += 96
                case .checkbox:
                    groupWidth += 90
                case .field:
                    groupWidth += 118
                case .gallery:
                    groupWidth += 290
                }
            }
            total += max(groupWidth, CGFloat(group.title.en.count) * 6 + 16)
        }
        return total
    }
}
