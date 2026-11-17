import Foundation
import SwiftUI
import ColumnStore
import Connectors

struct NavigatorView: View {
    let state: NavigatorState
    var existingTableNames: Set<String> = []
    /// Trả lý do (tiếng Việt) khi mô hình từ chối bảng; hộp thoại ở lại và hiện lý do ở chân. nil là đã nhận.
    var onLoad: ([LoadedTable]) -> String? = { _ in nil }
    /// nil: chưa có Query Editor nên không có nút "Chuyển đổi dữ liệu".
    var onTransform: (([LoadedTable]) -> Void)?
    var onClose: () -> Void = {}
    var scrollable: Bool = true

    @State private var searchText: String = ""

    private var fileName: String {
        // Cơ sở dữ liệu: "máy:cổng: csdl" như gốc cây Navigator của Desktop (VM-F7b).
        if state.sourceKind == .postgres {
            let address = PostgresLocation(state.location).address
            return "\(address.server): \(address.database)"
        }
        let name = URL(fileURLWithPath: state.location).lastPathComponent
        return name.isEmpty ? "Nguồn dữ liệu" : name
    }

    private var sourceKindTitle: String {
        guard let kind = state.sourceKind else { return "Nguồn dữ liệu" }
        switch kind {
        case .excel: return "Sổ làm việc Excel"
        case .csv: return "Văn bản / CSV"
        case .json: return "Tệp JSON"
        case .parquet: return "Apache Parquet"
        case .sqlite: return "Cơ sở dữ liệu SQLite"
        case .postgres: return "Cơ sở dữ liệu PostgreSQL"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
                .frame(width: 960, height: 46)
                .hairline(.bottom)

            mainContentArea
                .frame(width: 960, height: 518)

            footerBar
                .frame(width: 960, height: 56)
                .hairline(.top)
        }
        .frame(width: 960, height: 620)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(DS.Palette.separator, lineWidth: 1))
        .onAppear {
            checkAutoPreview()
        }
        .onChange(of: state.phase) { _, _ in
            checkAutoPreview()
        }
    }

    private func checkAutoPreview() {
        if state.phase == .ready && state.previewItemID == nil, let first = state.items.first {
            if state.items.count == 1 && state.checkedItemIDs.isEmpty {
                state.toggle(first.id)
            }
            Task {
                await state.showPreview(first.id)
            }
        }
    }

    // MARK: - Title Bar (46 pt)

    private var titleBar: some View {
        HStack(spacing: 10) {
            // macOS traffic lights
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#FF5F57")!).frame(width: 12, height: 12)
                Circle().fill(Color(hex: "#FEBC2E")!).frame(width: 12, height: 12)
                Circle().fill(Color(hex: "#28C840")!).frame(width: 12, height: 12)
            }

            Rectangle()
                .fill(DS.Palette.separator)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Trình điều hướng")
                    .font(DS.Typeface.headlineSmall)
                    .foregroundStyle(DS.Palette.label)

                Text("•")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.tertiaryLabel)

                Text(fileName)
                    .font(DS.Typeface.monoMedium)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                Badge(text: sourceKindTitle, color: DS.Palette.secondaryLabel)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(DS.Palette.chrome)
    }

    // MARK: - Main Content Area

    @ViewBuilder
    private var mainContentArea: some View {
        if state.phase == .listingItems {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Đang đọc nguồn…")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .failed(let msg) = state.phase, state.items.isEmpty {
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(DS.Palette.danger.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(DS.Palette.danger)
                    }

                    VStack(spacing: 6) {
                        Text("Không thể mở nguồn dữ liệu")
                            .font(DS.Typeface.headlineMedium)
                            .foregroundStyle(DS.Palette.label)

                        Text(msg)
                            .font(DS.Typeface.body)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                    }

                    Button("Chọn nguồn khác") {
                        state.phase = .choosingSource
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.large)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.large)
                        .strokeBorder(DS.Palette.separator, lineWidth: 1)
                )
                Spacer()
            }
            .frame(width: 960, height: 518)
            .background(DS.Palette.chrome.opacity(0.4))
        } else {
            HStack(spacing: 0) {
                NavigatorTreeView(state: state, scrollable: scrollable, searchText: $searchText)
                    .frame(width: 285, height: 518)
                    .hairline(.trailing)

                NavigatorPreviewGrid(state: state, scrollable: scrollable)
                    .frame(width: 960 - 285, height: 518)
            }
            .frame(width: 960, height: 518)
        }
    }

    // MARK: - Footer Bar (56 pt)

    private var footerBar: some View {
        HStack {
            footerLeftDiagnostic

            Spacer()

            HStack(spacing: 8) {
                Button("Hủy") {
                    if state.phase == .loading {
                        state.cancelLoad()
                    } else {
                        onClose()
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                if let onTransform {
                    Button("Chuyển đổi dữ liệu") {
                        Task {
                            if let tables = await state.load(existingNames: existingTableNames) {
                                onTransform(tables)
                                onClose()
                            }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!state.canLoad)
                    .opacity(state.canLoad ? 1.0 : 0.4)
                }

                Button("Tải") {
                    Task {
                        if let tables = await state.load(existingNames: existingTableNames) {
                            if let refusal = onLoad(tables) {
                                state.phase = .failed(refusal)
                            } else {
                                onClose()
                            }
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canLoad)
                .opacity(state.canLoad ? 1.0 : 0.4)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(DS.Palette.chrome)
    }

    @ViewBuilder
    private var footerLeftDiagnostic: some View {
        if state.phase == .loading {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DS.Palette.controlFill)
                        .frame(width: 120, height: 6)
                    Capsule()
                        .fill(DS.Palette.accent)
                        .frame(width: max(0, min(120, 120 * CGFloat(state.progress))), height: 6)
                }
                Text("Đang tải… \(Int((state.progress * 100).rounded()))%")
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
        } else if case .failed(let msg) = state.phase, !state.items.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Palette.danger)

                Text(msg)
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.danger)
                    .lineLimit(1)

                Button("Đóng thông báo") {
                    state.phase = .ready
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        } else {
            let currentItem = state.items.first(where: { $0.id == state.previewItemID })
            let previewRows = state.preview?.rowCount ?? 0
            if let note = NavigatorFormat.truncationNote(previewRows: previewRows, rowCountHint: currentItem?.rowCountHint) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Palette.warning)

                    Text(note)
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            } else {
                EmptyView()
            }
        }
    }
}
