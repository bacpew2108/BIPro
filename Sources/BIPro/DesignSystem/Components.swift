import SwiftUI

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var compact = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: compact ? 26 : 30)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control)
                .fill(configuration.isPressed ? DS.Palette.accentPressed : DS.Palette.accent))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(DS.Palette.label)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control)
                .fill(configuration.isPressed ? DS.Palette.chrome : Color.white))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
            .shadow(color: .black.opacity(0.05), radius: 0.5, y: 0.5)
    }
}

/// 26×26 ghost tool button.
struct GhostIconButtonStyle: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(active ? DS.Palette.accent : DS.Palette.secondaryLabel)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(configuration.isPressed ? Color.black.opacity(0.08) : (active ? DS.Palette.selectionSoft : .clear)))
            .contentShape(Rectangle())
    }
}

// MARK: - Ribbon

/// A ribbon command. `phase` marks features scheduled for later phases: they render disabled with a tooltip.
struct RibbonButton: View {
    enum Size { case large, small }

    let title: String
    let symbol: String
    var size: Size = .large
    var tint: Color = DS.Palette.secondaryLabel
    var isOn = false
    var phase: String?
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Group {
                if size == .large {
                    VStack(spacing: 3) {
                        Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(tint).frame(height: 20)
                        Text(title).font(DS.Typeface.label).foregroundStyle(DS.Palette.label)
                            .multilineTextAlignment(.center).lineLimit(2).fixedSize()
                    }
                    .padding(.horizontal, 6)
                    .frame(minWidth: 44, minHeight: 50)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(tint).frame(width: 14)
                        Text(title).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.label).fixedSize()
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                }
            }
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(isOn ? DS.Palette.selectionSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(phase != nil)
        .opacity(phase != nil ? 0.55 : 1)
        .help(phase.map { "\(title): có ở \($0)" } ?? title)
    }
}

struct RibbonGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .center, spacing: 2) { content }
                .frame(maxHeight: .infinity)
            Text(title.uppercased())
                .font(DS.Typeface.labelSmall)
                .tracking(0.4)
                .foregroundStyle(DS.Palette.tertiaryLabel)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

struct RibbonDivider: View {
    var body: some View {
        Rectangle().fill(DS.Palette.separator).frame(width: 1).padding(.vertical, 10)
    }
}

/// Two or three small ribbon buttons stacked vertically.
struct RibbonStack<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 1) { content }
    }
}

// MARK: - Segmented pill

struct SegmentedPill<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var symbol: String?
        var id: Value { value }
    }

    @Binding var selection: Value
    let options: [Option]
    var fill = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    HStack(spacing: 4) {
                        if let symbol = option.symbol { Image(systemName: symbol).font(.system(size: 11)) }
                        Text(option.title)
                    }
                    .font(.system(size: 12, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? DS.Palette.label : DS.Palette.secondaryLabel)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .frame(height: 22)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: DS.Radius.segmentInner).fill(Color.white)
                                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: DS.Radius.segmentOuter).fill(DS.Palette.controlFill))
    }
}

// MARK: - Panes

struct PaneHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    var collapse: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(DS.Palette.accent)
            Text(title).font(DS.Typeface.headlineSmall).foregroundStyle(DS.Palette.label)
            Spacer(minLength: 4)
            trailing
            if let collapse {
                Button(action: collapse) { Image(systemName: "chevron.right") }
                    .buttonStyle(GhostIconButtonStyle())
                    .help("Thu gọn")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }
}

extension PaneHeader where Trailing == EmptyView {
    init(title: String, symbol: String, collapse: (() -> Void)? = nil) {
        self.init(title: title, symbol: symbol, collapse: collapse) { EmptyView() }
    }
}

/// A collapsed side pane: a thin strip with a vertical title, like Power BI.
struct CollapsedPaneStrip: View {
    let title: String
    let symbol: String
    let expand: () -> Void

    var body: some View {
        Button(action: expand) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(DS.Palette.accent)
                Text(title.uppercased())
                    .font(DS.Typeface.labelSmall).tracking(0.6)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 14, height: 120)
                Spacer()
            }
            .padding(.top, 12)
            .frame(width: DS.Metrics.collapsedPane)
            .frame(maxHeight: .infinity)
            .background(DS.Palette.chrome)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Mở \(title)")
    }
}

struct PaneFooter: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DS.Typeface.labelSmall)
            .foregroundStyle(DS.Palette.tertiaryLabel)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .hairline(.top)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(DS.Typeface.labelSmall).tracking(0.5)
            .foregroundStyle(DS.Palette.tertiaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

// MARK: - Inputs

struct SearchField: View {
    @Binding var text: String
    var prompt: String
    var shortcut: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(DS.Palette.tertiaryLabel)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Typeface.body)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(DS.Palette.tertiaryLabel)
            } else if let shortcut {
                Text(shortcut).font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.badge).fill(Color.white.opacity(0.8)))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.searchFill))
    }
}

/// Static 14×14 checkbox (display only).
struct CheckboxMark: View {
    let isOn: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 3.5)
            .fill(isOn ? DS.Palette.accent : Color.white)
            .overlay(RoundedRectangle(cornerRadius: 3.5).strokeBorder(isOn ? Color.clear : DS.Palette.checkboxBorder))
            .overlay { if isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) } }
            .frame(width: 14, height: 14)
    }
}

/// 36×20 switch matching the design (display only unless a binding is supplied).
struct SwitchMark: View {
    let isOn: Bool
    var body: some View {
        Capsule().fill(isOn ? DS.Palette.accent : Color.gray.opacity(0.3))
            .frame(width: 32, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            }
    }
}

// MARK: - Chips & badges

struct Badge: View {
    let text: String
    var color: Color = DS.Palette.secondaryLabel
    var body: some View {
        Text(text)
            .font(DS.Typeface.labelSmall)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: DS.Radius.badge).fill(color.opacity(0.12)))
    }
}

/// Field chip used in field wells.
struct FieldChip: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint).frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.label).lineLimit(1)
                if let subtitle { Text(subtitle).font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }
}

/// `Label: value` row for read-only property lists.
struct PropertyRow: View {
    let label: String
    let value: String
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? DS.Typeface.mono : DS.Typeface.bodySmall)
                .foregroundStyle(DS.Palette.label)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }
}

/// Tile surface with the standard elevation.
struct TileBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.tile).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(DS.Palette.separator))
    }
}
