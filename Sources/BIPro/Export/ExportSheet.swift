import SwiftUI

/// Loại tác vụ xuất hiện trên hộp thoại chọn tuỳ chọn xuất (PDF hoặc PNG).
enum ExportSheetKind: Equatable, Sendable {
    case pdf
    case png
}

/// Hộp thoại chọn phạm vi PDF / độ phân giải PNG và hiện tiến trình khi xuất (FR-002, FR-003, FR-005).
struct ExportSheet: View {
    let kind: ExportSheetKind
    let visiblePageCount: Int
    let currentPageName: String
    @Binding var isExporting: Bool
    @Binding var progressText: String
    @Binding var errorMessage: String?
    var onExportPDF: (ExportPDFScope) -> Void
    var onExportPNG: (ExportPNGScale) -> Void
    var onCancel: () -> Void

    @State private var pdfScope: ExportPDFScope = .allVisiblePages
    @State private var pngScale: ExportPNGScale = .x2

    var body: some View {
        let lang = AppPreferences.shared.effectiveLanguage
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: kind == .pdf ? "doc.richtext" : "photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)
                Text(L10n.string(kind == .pdf ? .exportPDFTitle : .exportPNGTitle, language: lang))
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
            }

            if kind == .pdf {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string(.exportScopeLabel, language: lang))
                        .font(DS.Typeface.bodySmall.weight(.medium))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    VStack(alignment: .leading, spacing: 6) {
                        radioRow(
                            title: "\(L10n.string(.exportScopeAllVisible, language: lang)) (\(visiblePageCount))",
                            selected: pdfScope == .allVisiblePages
                        ) { pdfScope = .allVisiblePages }
                        radioRow(
                            title: "\(L10n.string(.exportScopeCurrentPage, language: lang)) (\(currentPageName))",
                            selected: pdfScope == .currentPage
                        ) { pdfScope = .currentPage }
                    }
                    .disabled(isExporting)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string(.exportScaleLabel, language: lang))
                        .font(DS.Typeface.bodySmall.weight(.medium))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    SegmentedPill(selection: $pngScale, options: [
                        .init(value: .x1, title: L10n.string(.exportScale1x, language: lang)),
                        .init(value: .x2, title: L10n.string(.exportScale2x, language: lang)),
                    ], fill: true)
                    .disabled(isExporting)
                }
            }

            if isExporting {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(progressText.isEmpty ? L10n.string(.exportProgressPreparing, language: lang) : progressText)
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
                .padding(.vertical, 4)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(L10n.string(.cancel, language: lang), role: .cancel) {
                    onCancel()
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
                .disabled(isExporting)

                Button(L10n.string(.exportActionButton, language: lang)) {
                    switch kind {
                    case .pdf: onExportPDF(pdfScope)
                    case .png: onExportPNG(pngScale)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting || (kind == .pdf && pdfScope == .allVisiblePages && visiblePageCount == 0))
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DS.Palette.canvas)
    }

    private func radioRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? DS.Palette.accent : DS.Palette.separator, lineWidth: 1.5)
                        .frame(width: 15, height: 15)
                    if selected {
                        Circle()
                            .fill(DS.Palette.accent)
                            .frame(width: 7, height: 7)
                    }
                }
                Text(title)
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
