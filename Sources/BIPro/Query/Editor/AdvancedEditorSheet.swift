import SwiftUI

struct AdvancedEditorContent: View {
    let queryName: String
    @State private var sourceText: String
    var scrollable: Bool = true
    let onApply: (String) -> String?
    let onCancel: () -> Void

    @State private var errorMessage: String? = nil

    init(
        queryName: String,
        initialSource: String,
        scrollable: Bool = true,
        onApply: @escaping (String) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.queryName = queryName
        self._sourceText = State(initialValue: initialSource)
        self.scrollable = scrollable
        self.onApply = onApply
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)

                Text("Trình soạn thảo nâng cao — \(queryName)")
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(DS.Palette.chrome)
            .hairline(.bottom)

            // Editor body
            Group {
                if scrollable {
                    TextEditor(text: $sourceText)
                        .font(DS.Typeface.monoMedium)
                        .padding(12)
                } else {
                    // Non-scrollable for ImageRenderer
                    Text(sourceText)
                        .font(DS.Typeface.monoMedium)
                        .foregroundStyle(DS.Palette.label)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)

            // Status bar
            HStack(spacing: 6) {
                if let error = errorMessage {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.danger)
                    Text(error)
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.danger)
                        .lineLimit(2)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.success)
                    Text("Không có lỗi cú pháp")
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.success)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 28)
            .background(DS.Palette.chrome)
            .hairline(.top)

            // Footer Actions
            HStack(spacing: 10) {
                Spacer()

                Button("Huỷ") {
                    onCancel()
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("Xong") {
                    if let err = onApply(sourceText) {
                        errorMessage = err
                    } else {
                        errorMessage = nil
                        onCancel()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Color.white)
            .hairline(.top)
        }
        .frame(width: 760, height: 520)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(DS.Palette.separator))
    }
}

struct AdvancedEditorSheet: View {
    let state: QueryEditorState
    var scrollable: Bool = true
    let onClose: () -> Void

    var body: some View {
        AdvancedEditorContent(
            queryName: state.selectedQuery?.name ?? "",
            initialSource: state.advancedSource,
            scrollable: scrollable,
            onApply: { text in
                state.applyAdvancedSource(text)
            },
            onCancel: onClose
        )
    }
}
