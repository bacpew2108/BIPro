import PBIXKit
import SwiftUI

/// Hộp "Manage relationships" (Ribbon ▸ Modeling/Home ▸ Relationships): liệt kê mọi quan hệ của mô hình như Desktop.
/// Chọn một dòng rồi "Sửa" để mở bảng thuộc tính ở view Model; "Xoá" xoá quan hệ (có thể hoàn tác ở view Model). Tạo quan hệ mới
/// bằng cách kéo cột này thả lên cột kia trong view Model (ghi ở dòng gợi ý cuối hộp).
struct ManageRelationshipsSheet: View {
    @Bindable var state: DocumentState
    let onDismiss: () -> Void
    @State private var selected: String?
    @State private var message: String?

    private var relationships: [ModelMetadata.Relationship] { state.workspace.metadata?.relationships ?? [] }

    private func key(_ r: ModelMetadata.Relationship) -> String {
        r.name.isEmpty ? "\(r.fromTable).\(r.fromColumn)->\(r.toTable).\(r.toColumn)" : r.name
    }

    private func cardinalityText(_ r: ModelMetadata.Relationship) -> String {
        r.cardinality.replacingOccurrences(of: "M", with: "*")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 18)).foregroundStyle(DS.Palette.accent)
                Text(bi("Quản lý quan hệ", "Manage relationships")).font(DS.Typeface.headlineMedium)
                Spacer()
                Text(bi("\(relationships.count) quan hệ", "\(relationships.count) relationships"))
                    .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
            }
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(relationships, id: \.self) { r in row(r) }
                    if relationships.isEmpty {
                        Text(bi("Mô hình chưa có quan hệ nào.", "The model has no relationships yet."))
                            .foregroundStyle(DS.Palette.secondaryLabel).padding(24)
                    }
                }
            }
            .frame(height: 300)
            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Palette.separator))
            if let message {
                Text(message).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.danger)
            }
            Text(bi("Tạo quan hệ mới: kéo một cột thả lên cột của bảng khác trong view Model.",
                    "To create a relationship, drag a column onto a column of another table in Model view."))
                .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
            HStack {
                Button(bi("Xoá", "Delete"), role: .destructive) {
                    if let selected, let r = relationships.first(where: { key($0) == selected }) {
                        message = state.deleteRelationship(name: r.name)
                        if message == nil { self.selected = nil }
                    }
                }
                .disabled(selected == nil || state.modelEditingBlocker != nil)
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(bi("Sửa trong sơ đồ", "Edit in diagram")) {
                    state.relationship = selected
                    state.mode = .model
                    onDismiss()
                }
                .disabled(selected == nil)
                .buttonStyle(SecondaryButtonStyle())
                Button(bi("Đóng", "Close"), action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 760)
        .background(DS.Palette.canvas)
    }

    private var header: some View {
        HStack(spacing: 0) {
            headerCell(bi("Từ: bảng (cột)", "From: table (column)"), flex: 3)
            headerCell(bi("Tới: bảng (cột)", "To: table (column)"), flex: 3)
            headerCell(bi("Số bản số", "Cardinality"), flex: 1.2)
            headerCell(bi("Lọc chéo", "Cross filter"), flex: 1.4)
            headerCell(bi("Hoạt động", "Active"), flex: 1)
        }
    }

    private func headerCell(_ text: String, flex: CGFloat) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.Palette.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(0)
            .frame(width: nil).padding(.horizontal, 8)
            .modifier(FlexWidth(flex: flex))
    }

    private func row(_ r: ModelMetadata.Relationship) -> some View {
        let isSel = selected == key(r)
        return HStack(spacing: 0) {
            cell("\(r.fromTable) (\(r.fromColumn))", flex: 3)
            cell("\(r.toTable) (\(r.toColumn))", flex: 3)
            cell(cardinalityText(r), flex: 1.2)
            cell(r.crossFilteringBehavior == 2 ? bi("Hai chiều", "Both") : bi("Một chiều", "Single"), flex: 1.4)
            cell(r.isActive ? "✓" : "—", flex: 1)
        }
        .padding(.vertical, 6)
        .background(isSel ? DS.Palette.selectionSoft : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = key(r) }
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    private func cell(_ text: String, flex: CGFloat) -> some View {
        Text(text).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            .foregroundStyle(DS.Palette.label)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
            .modifier(FlexWidth(flex: flex))
    }
}

/// Chia bề ngang theo tỉ lệ cố định giữa các cột (tổng 9,6 phần trên ≈ 720 pt).
private struct FlexWidth: ViewModifier {
    let flex: CGFloat
    func body(content: Content) -> some View {
        content.frame(width: 720 * flex / 9.6, alignment: .leading)
    }
}
