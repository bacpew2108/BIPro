import SwiftUI

/// Hằng số và khung chrome cho DAX Query view (`v_dax_1.png`, T076).
enum DAXQueryChrome {
    static let infoBannerText = Bilingual(
        vi: "Các truy vấn DAX sẽ được lưu vào mô hình của bạn. Chúng không hiển thị khi xuất bản lên Power BI service.",
        en: "DAX queries will be saved to your model. They won't be visible when published in the Power BI service."
    )
    static let emptyResultsText = Bilingual(
        vi: "Kết quả truy vấn sẽ hiển thị ở đây",
        en: "Your query results will show up here"
    )

    static func defaultTabTitle(index: Int, language: ResolvedLanguage) -> String {
        language == .en ? "Query \(index)" : "Truy vấn \(index)"
    }
}

/// Hằng số và trạng thái giới thiệu lần đầu cho TMDL view (`v_tmdl_2.png`, T076).
enum TMDLViewChrome {
    static let introTitle = Bilingual(
        vi: "Chỉnh sửa mô hình với TMDL",
        en: "Edit your model with TMDL"
    )
    static let introBody = Bilingual(
        vi: "Xem và chỉnh sửa mô hình ngữ nghĩa dưới dạng kịch bản TMDL. Bấm Áp dụng để ghi nhận thay đổi nguyên khối.",
        en: "Script and edit your semantic model using TMDL text. Click Apply to commit changes atomically."
    )
    static let outputTabTitle = Bilingual(vi: "Đầu ra", en: "Output")

    @MainActor
    static func shouldShowIntro(preferences: AppPreferences? = nil) -> Bool {
        !(preferences ?? AppPreferences.shared).tmdlIntroSeen
    }

    @MainActor
    static func markIntroSeen(preferences: AppPreferences? = nil) {
        (preferences ?? AppPreferences.shared).tmdlIntroSeen = true
    }

    static func problemsTabTitle(count: Int, language: ResolvedLanguage) -> String {
        language == .en ? "Problems (\(count))" : "Sự cố (\(count))"
    }

    static func defaultScriptTabTitle(index: Int, language: ResolvedLanguage) -> String {
        language == .en ? "Script \(index)" : "Kịch bản \(index)"
    }
}

/// Dải thông báo đóng được phía trên trình soạn thảo DAX (`v_dax_1.png`).
struct DAXInfoBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.secondaryLabel)
            Text(DAXQueryChrome.infoBannerText.localized)
                .font(.system(size: 11.5))
                .foregroundStyle(DS.Palette.label)
                .lineLimit(1)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(bi("Đóng thông báo", "Dismiss notice"))
            .accessibilityLabel(bi("Đóng thông báo", "Dismiss notice"))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(DS.Palette.chrome)
        .hairline(.bottom)
    }
}

/// Minh hoạ trạng thái trống cho khu Results của DAX Query view (`v_dax_1.png`).
struct DAXEmptyResultsIllustration: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.Palette.controlFill)
                    .frame(width: 60, height: 60)
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            Text(DAXQueryChrome.emptyResultsText.localized)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DS.Palette.label)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Palette.canvas)
    }
}

/// Hàng nút thao tác phía trên trình soạn thảo DAX (`v_dax_1.png`, T041):
/// **Run** (nút màu nhấn teal, nối `runDAXQuery`/`cancelDAXQuery`) + **Update model with changes (n)** (nối `prepareDAXUpdateModel`).
struct DAXCodeActionBar: View {
    @Bindable var state: DocumentState

    private var pendingMeasureCount: Int {
        guard let meta = state.workspace.metadata,
              state.daxQueries.indices.contains(state.daxSelection) else { return 0 }
        return DAXModelSync.extractMeasures(from: state.daxQueries[state.daxSelection].text, existingModel: meta).count
    }

    var body: some View {
        let updateCount = pendingMeasureCount
        let canUpdateModel = state.modelEditingBlocker == nil && updateCount > 0

        HStack(spacing: 8) {
            if state.isRunningDAX {
                Button {
                    state.cancelDAXQuery()
                } label: {
                    Label(bi("Huỷ", "Cancel"), systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.danger))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(".", modifiers: .command)
                .help(bi("Huỷ truy vấn đang chạy (⌘.)", "Cancel running query (⌘.)"))
                .accessibilityLabel(bi("Huỷ truy vấn", "Cancel query"))
            } else {
                Button {
                    state.runDAXQuery()
                } label: {
                    Label(
                        state.daxEditorSelection.length > 0 ? bi("Chạy vùng chọn", "Run selection") : bi("Chạy", "Run"),
                        systemImage: "play"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.accentTeal))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!state.canRunDAX)
                .opacity(state.canRunDAX ? 1 : 0.45)
                .help(state.workspace.metadata == nil ? bi("File không có mô hình dữ liệu", "No data model in file") : bi("Chạy truy vấn (⌘↵)", "Run query (⌘↵)"))
                .accessibilityLabel(bi("Chạy truy vấn DAX", "Run DAX query"))
            }

            Button {
                state.prepareDAXUpdateModel()
            } label: {
                Label(
                    bi("Cập nhật mô hình (\(updateCount))", "Update model with changes (\(updateCount))"),
                    systemImage: "arrow.up.to.line"
                )
                .font(.system(size: 12))
                .foregroundStyle(canUpdateModel ? DS.Palette.label : DS.Palette.secondaryLabel)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.chrome))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator, lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .disabled(!canUpdateModel)
            .opacity(canUpdateModel ? 1 : 0.5)
            .help(state.modelEditingBlocker ?? (updateCount > 0
                ? bi("Áp dụng \(updateCount) định nghĩa DEFINE MEASURE vào mô hình", "Apply \(updateCount) DEFINE MEASURE definitions to the model")
                : bi("Chưa có khối DEFINE MEASURE nào để cập nhật mô hình", "No DEFINE MEASURE changes to update the model")))
            .accessibilityLabel(bi("Cập nhật mô hình với thay đổi", "Update model with changes"))

            Spacer()

            Text("DAX · UTF-8")
                .font(DS.Typeface.mono)
                .foregroundStyle(DS.Palette.tertiaryLabel)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(DS.Palette.canvas)
        .hairline(.bottom)
    }
}

/// Hàng nút thao tác phía trên trình soạn thảo TMDL (`v_tmdl_2.png`, T041):
/// **Apply** (nối `apply()` của `TMDLWorkspace`) + **Preview** (vô hiệu kèm tooltip).
struct TMDLCodeActionBar: View {
    let state: DocumentState
    let path: String
    let changed: Bool
    let onDiscard: () -> Void
    let onApply: () -> Void

    var body: some View {
        let blocker = state.modelEditingBlocker
        let canApply = changed && blocker == nil

        HStack(spacing: 8) {
            Button(action: onApply) {
                Label(bi("Áp dụng", "Apply"), systemImage: "arrow.up.to.line")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(canApply ? .white : DS.Palette.secondaryLabel)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 4).fill(canApply ? DS.Palette.accentTeal : DS.Palette.chrome))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(canApply ? Color.clear : DS.Palette.separator, lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canApply)
            .opacity(canApply ? 1 : 0.5)
            .help(blocker ?? (changed
                ? bi("Áp dụng mọi phần đã sửa (⌘↩), nguyên khối: có lỗi thì không đổi gì", "Apply all edits atomically (⌘↩): no changes on error")
                : bi("Chưa có thay đổi TMDL nào để áp dụng", "No pending TMDL changes to apply")))
            .accessibilityLabel(bi("Áp dụng TMDL", "Apply TMDL"))

            Button {} label: {
                Text(bi("Xem trước", "Preview"))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.chrome))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator, lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.45)
            .help(bi("BI Pro chưa hỗ trợ xem trước diff TMDL", "TMDL preview diff is not yet implemented in BI Pro"))
            .accessibilityLabel(bi("Xem trước TMDL", "Preview TMDL"))

            if changed {
                Button(bi("Bỏ phần sửa", "Discard"), action: onDiscard)
                    .buttonStyle(SecondaryButtonStyle())
            }

            Spacer()

            if !path.isEmpty {
                Text(path)
                    .font(DS.Typeface.mono)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .lineLimit(1)
            }
            if blocker == nil {
                Badge(text: changed ? bi("Đã sửa", "Modified") : bi("Sửa được", "Editable"))
            } else {
                Badge(text: bi("Chỉ đọc", "Read-only"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(DS.Palette.canvas)
        .hairline(.bottom)
    }
}
