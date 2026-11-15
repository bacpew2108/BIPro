import SwiftUI
import MEngine

struct FormulaBarView: View {
    let state: QueryEditorState
    var isLocked: Bool = false
    var scrollable: Bool = true

    @State private var text: String = ""
    @State private var isExpanded: Bool = false
    @State private var errorMessage: String? = nil
    @State private var lastStepIndex: Int? = nil

    private var currentStep: QueryStep? {
        guard let query = state.selectedQuery,
              let idx = state.selectedStepIndex,
              query.steps.indices.contains(idx) else { return nil }
        return query.steps[idx]
    }

    private var isCurrentStepLocked: Bool {
        guard let query = state.selectedQuery,
              let idx = state.selectedStepIndex else { return false }
        return idx < query.lockedStepCount
    }

    var body: some View {
        VStack(spacing: 0) {
            mainBar
                .hairline(.bottom)

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.danger)

                    Text(error)
                        .font(DS.Typeface.mono)
                        .foregroundStyle(DS.Palette.danger)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(DS.Palette.danger.opacity(0.08))
                .hairline(.bottom)
            }
        }
        .onAppear {
            syncFromState()
        }
        .onChange(of: state.selectedStepIndex) { _, _ in
            syncFromState()
        }
        .onChange(of: currentStep?.expression) { _, _ in
            syncFromState()
        }
    }

    private var mainBar: some View {
        HStack(spacing: 6) {
            // fx badge
            Text("fx")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .italic()
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.chrome))

            // Action buttons (✓ and ✕) when editing an unlocked step
            if !isCurrentStepLocked && hasChanges {
                Button {
                    commitExpression()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Palette.success)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Áp dụng công thức (Enter)")

                Button {
                    syncFromState()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Palette.danger)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Huỷ thay đổi (Esc)")
            }

            // Formula Text Input
            if isCurrentStepLocked || !scrollable {
                Text(displayText)
                    .font(DS.Typeface.monoMedium)
                    .foregroundStyle(isCurrentStepLocked ? DS.Palette.secondaryLabel : DS.Palette.label)
                    .lineLimit(isExpanded ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(isCurrentStepLocked ? DS.Palette.controlFill.opacity(0.5) : Color.white))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
            } else {
                Group {
                    if isExpanded {
                        TextEditor(text: $text)
                            .font(DS.Typeface.monoMedium)
                            .frame(height: 70)
                    } else {
                        TextField("", text: $text, onCommit: {
                            commitExpression()
                        })
                        .textFieldStyle(.plain)
                        .font(DS.Typeface.monoMedium)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
            }

            // Expand/collapse arrow
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Thu gọn thanh công thức" : "Mở rộng thanh công thức")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(DS.Palette.chrome)
    }

    private var displayText: String {
        guard let step = currentStep else { return "" }
        let expr = step.expression
        return expr.hasPrefix("=") ? expr : "= " + expr
    }

    private var hasChanges: Bool {
        text != displayText
    }

    private func syncFromState() {
        text = displayText
        errorMessage = nil
    }

    private func commitExpression() {
        guard let idx = state.selectedStepIndex else { return }
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("=") {
            raw = String(raw.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let err = state.setExpression(at: idx, raw) {
            errorMessage = err
        } else {
            errorMessage = nil
            syncFromState()
        }
    }
}
