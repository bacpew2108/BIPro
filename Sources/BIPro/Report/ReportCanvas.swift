import PBIXKit
import SwiftUI

/// One report page drawn at its native size (e.g. 1920×1080), scaled to fit or to an explicit zoom.
struct ReportPageView: View {
    let workspace: Workspace
    let page: ReportPage
    @Binding var selectedVisual: String?
    /// nil = fit page.
    var zoom: Double?
    var onScale: (Double) -> Void = { _ in }
    let navigate: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            let margin = DS.Space.lg
            let fit = max(0.05, min((geo.size.width - margin * 2) / page.width,
                                    (geo.size.height - margin * 2) / page.height))
            let scale = zoom ?? fit
            ScrollView([.horizontal, .vertical]) {
                canvas(scale: scale)
                    .padding(margin)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .scrollDisabled(zoom == nil)
            .onAppear { onScale(scale) }
            .onChange(of: scale) { _, value in onScale(value) }
        }
        .background(DS.Palette.backdrop)
    }

    private func canvas(scale: Double) -> some View {
        ZStack(alignment: .topLeading) {
            pageBackground
                .onTapGesture { selectedVisual = nil }
            ForEach(page.visuals.filter { !$0.isHidden }) { visual in
                VisualContainerView(workspace: workspace, page: page, visual: visual, navigate: navigate)
                    .frame(width: visual.width, height: visual.height)
                    .overlay {
                        if selectedVisual == visual.id { SelectionHandles(scale: scale) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedVisual = visual.id }
                    .offset(x: visual.x, y: visual.y)
            }
        }
        .frame(width: page.width, height: page.height, alignment: .topLeading)
        .clipped()
        // Reports are authored for a light canvas regardless of the app appearance.
        .environment(\.colorScheme, .light)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: page.width * scale, height: page.height * scale, alignment: .topLeading)
        .tileElevation()
    }

    private var pageBackground: some View {
        let color = workspace.theme.color(page.objects.color("background", "color"))
            ?? workspace.theme.background.flatMap(Color.init(hex:)) ?? .white
        return Rectangle()
            .fill(Color.white)
            .overlay(Rectangle().fill(color.opacity(page.objects.opacity("background"))))
    }
}

/// The container chrome Power BI draws around every visual: background, border, title, padding.
struct VisualContainerView: View {
    let workspace: Workspace
    let page: ReportPage
    let visual: ReportVisual
    let navigate: (String) -> Void

    private var container: ObjectProperties { visual.containerObjects }
    private var theme: ReportTheme { workspace.theme }

    /// Decorative visuals default to no background/title; data visuals default to both.
    private var isDecorative: Bool {
        ["textbox", "image", "shape", "basicShape", "actionButton", "pageNavigator", "bookmarkNavigator"].contains(visual.type)
    }

    var body: some View {
        let radius = CGFloat(container.number("border", "radius") ?? 0)
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title.text)
                    .font(.system(size: title.size, weight: title.bold ? .bold : .semibold))
                    .foregroundStyle(title.color)
                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: title.alignment, vertical: .center))
                    .lineLimit(1)
            }
            VisualContentView(workspace: workspace, page: page, visual: visual, navigate: navigate)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(padding)
        .background {
            if container.bool("background", "show") ?? !isDecorative {
                RoundedRectangle(cornerRadius: radius)
                    .fill((theme.color(container.color("background", "color")) ?? .white)
                        .opacity(container.opacity("background")))
            }
        }
        .overlay {
            if container.bool("border", "show") ?? false {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(theme.color(container.color("border", "color")) ?? Color.gray.opacity(0.4),
                                  lineWidth: CGFloat(container.number("border", "width") ?? 1))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .shadow(color: (container.bool("dropShadow", "show") ?? false) ? .black.opacity(0.15) : .clear, radius: 4, y: 2)
    }

    private var padding: EdgeInsets {
        let fallback: CGFloat = isDecorative ? 0 : 6
        func edge(_ name: String) -> CGFloat { container.number("padding", name).map { CGFloat($0) } ?? fallback }
        return EdgeInsets(top: edge("top"), leading: edge("left"), bottom: edge("bottom"), trailing: edge("right"))
    }

    private struct Title { var text: String; var size: CGFloat; var color: Color; var bold: Bool; var alignment: HorizontalAlignment }

    private var title: Title? {
        let show = container.bool("title", "show") ?? (!isDecorative && !["card", "cardVisual", "slicer", "multiRowCard", "kpi"].contains(visual.type))
        guard show else { return nil }
        let text = container.string("title", "text") ?? defaultTitle
        guard !text.isEmpty else { return nil }
        return Title(text: text,
                     size: ReportUnits.pixels(fromPoints: container.number("title", "fontSize") ?? 12),
                     color: theme.color(container.color("title", "fontColor")) ?? theme.foregroundColor,
                     bold: container.bool("title", "bold") ?? false,
                     alignment: HorizontalAlignment(reportAlignment: container.string("title", "alignment")))
    }

    /// Power BI's automatic title: "<values> theo <categories>".
    private var defaultTitle: String {
        let categoryRoles: Set = ["Category", "Rows", "Axis", "Legend", "Series", "Group"]
        let values = visual.fields.filter { !categoryRoles.contains($0.role) && $0.role != "Tooltips" }.map(\.label)
        let categories = visual.fields.filter { categoryRoles.contains($0.role) }.map(\.label)
        let v = values.joined(separator: " và ")
        return categories.isEmpty ? v : "\(v) theo \(categories.joined(separator: " và "))"
    }
}

/// The inside of a visual.
struct VisualContentView: View {
    let workspace: Workspace
    let page: ReportPage
    let visual: ReportVisual
    let navigate: (String) -> Void

    var body: some View {
        switch visual.type {
        case "textbox":
            TextboxVisual(visual: visual, theme: workspace.theme)
        case "image":
            ImageVisual(workspace: workspace, visual: visual)
        case "shape", "basicShape":
            ShapeVisual(visual: visual, theme: workspace.theme)
        case "actionButton":
            ActionButtonVisual(workspace: workspace, visual: visual, navigate: navigate)
        case "pageNavigator":
            PageNavigatorVisual(workspace: workspace, currentPage: page.id, navigate: navigate)
        case "card", "cardVisual", "multiRowCard", "kpi":
            CardPlaceholder(visual: visual, theme: workspace.theme)
        case "slicer", "advancedSlicerVisual", "listSlicer", "textSlicer":
            SlicerPlaceholder(visual: visual, theme: workspace.theme)
        case "tableEx", "pivotTable", "matrix", "table":
            TablePlaceholder(visual: visual, theme: workspace.theme)
        default:
            ChartPlaceholder(visual: visual, theme: workspace.theme)
        }
    }
}

// MARK: - Static visuals (fully rendered)

struct TextboxVisual: View {
    let visual: ReportVisual
    let theme: ReportTheme

    var body: some View {
        let paragraphs = visual.objects.raw("general", "paragraphs")?.array ?? []
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                let alignment = paragraph["horizontalTextAlignment"]?.string
                Text(attributed(paragraph))
                    .multilineTextAlignment(TextAlignment(reportAlignment: alignment))
                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: HorizontalAlignment(reportAlignment: alignment), vertical: .top))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func attributed(_ paragraph: JSONValue) -> AttributedString {
        var result = AttributedString()
        for run in paragraph["textRuns"]?.array ?? [] {
            var piece = AttributedString(run["value"]?.string ?? "")
            let style = run["textStyle"]
            let size = ReportUnits.fontSize(style?["fontSize"]?.string) ?? ReportUnits.pixels(fromPoints: 11)
            let weight: Font.Weight = (style?["fontWeight"]?.string).map { $0 == "bold" || (Int($0) ?? 400) >= 600 ? .bold : .regular } ?? .regular
            var font = Font.system(size: size, weight: weight)
            if style?["fontStyle"]?.string == "italic" { font = font.italic() }
            piece.font = font
            piece.foregroundColor = style?["color"]?.string.flatMap(Color.init(hex:)) ?? theme.foregroundColor
            if style?["textDecoration"]?.string == "underline" { piece.underlineStyle = .single }
            if let link = run["url"]?.string, let url = URL(string: link) { piece.link = url }
            result += piece
        }
        return result
    }
}

struct ImageVisual: View {
    let workspace: Workspace
    let visual: ReportVisual

    var body: some View {
        if let (name, scaling) = source, let image = workspace.image(named: name) {
            switch scaling {
            case "Fill":
                Image(nsImage: image).resizable().scaledToFill()
            case "Fit":
                Image(nsImage: image).resizable().scaledToFit()
            default:
                // "Normal": natural size, shrunk only if it does not fit.
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: image.size.width, maxHeight: image.size.height)
            }
        } else {
            Image(systemName: "photo").font(.largeTitle).foregroundStyle(.tertiary)
        }
    }

    /// Classic image visual: `general.imageUrl`; newer one: `image.sourceFile.image.url`.
    private var source: (String, String)? {
        let o = visual.objects
        if case .resource(let name)? = o.literal("general", "imageUrl") {
            return (name, o.string("imageScaling", "imageScalingType") ?? "Normal")
        }
        let file = o.raw("image", "sourceFile")?["image"]
        if let name = file?["url"]?["expr"]?["ResourcePackageItem"]?["ItemName"]?.string {
            return (name, file?["scaling"]?["expr"]?["Literal"]?["Value"]?.string.map { ReportLiteral(literal: $0).string ?? "Normal" } ?? "Normal")
        }
        return nil
    }
}

struct ShapeVisual: View {
    let visual: ReportVisual
    let theme: ReportTheme

    var body: some View {
        let o = visual.objects
        let fill = (theme.color(o.color("fill", "fillColor")) ?? theme.dataColor(0))
            .opacity((o.bool("fill", "show") ?? true) ? o.opacity("fill") : 0)
        let lineShow = o.bool("outline", "show") ?? o.bool("line", "show") ?? true
        let line = theme.color(o.color("outline", "lineColor") ?? o.color("line", "lineColor")) ?? .black
        let weight = CGFloat(o.number("outline", "weight") ?? o.number("line", "weight") ?? 1)
        let kind = (o.string("shape", "tileShape") ?? o.string("general", "shapeType") ?? "rectangle").lowercased()
        let round = CGFloat(o.number("shape", "roundEdge") ?? o.number("line", "roundEdge") ?? (kind.contains("round") ? 10 : 0))

        Group {
            if kind.contains("oval") || kind.contains("ellipse") {
                Ellipse().fill(fill).overlay(Ellipse().strokeBorder(lineShow ? line : .clear, lineWidth: weight))
            } else if kind.contains("line") {
                Rectangle().fill(line).frame(height: weight)
            } else {
                RoundedRectangle(cornerRadius: round).fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: round).strokeBorder(lineShow ? line : .clear, lineWidth: weight))
            }
        }
    }
}

struct ActionButtonVisual: View {
    let workspace: Workspace
    let visual: ReportVisual
    let navigate: (String) -> Void

    var body: some View {
        let o = visual.objects
        let theme = workspace.theme
        let fill = (theme.color(o.color("fill", "fillColor")) ?? Color.gray.opacity(0.15))
            .opacity((o.bool("fill", "show") ?? true) ? o.opacity("fill") : 0)
        let outline = theme.color(o.color("outline", "lineColor")) ?? .gray
        let showOutline = o.bool("outline", "show") ?? false
        let radius = CGFloat(o.number("shape", "roundEdge") ?? 4)
        let label = (o.bool("text", "show") ?? false) ? (o.string("text", "text") ?? "") : ""

        Button(action: performAction) {
            Text(label)
                .font(.system(size: ReportUnits.pixels(fromPoints: o.number("text", "fontSize") ?? 10),
                              weight: (o.bool("text", "bold") ?? false) ? .bold : .regular))
                .foregroundStyle(theme.color(o.color("text", "fontColor")) ?? theme.foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: radius).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(showOutline ? outline : .clear, lineWidth: CGFloat(o.number("outline", "weight") ?? 1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(actionDescription)
    }

    private var link: (type: String, target: String?) {
        let c = visual.containerObjects
        return (c.string("visualLink", "type") ?? "", c.string("visualLink", "navigationSection") ?? c.string("visualLink", "bookmark"))
    }

    private var actionDescription: String {
        switch link.type {
        case "PageNavigation": "Chuyển trang"
        case "Bookmark": "Bookmark \(link.target ?? "") (chưa hỗ trợ: cần engine lọc)"
        default: link.type
        }
    }

    private func performAction() {
        if link.type == "PageNavigation", let target = link.target { navigate(target) }
    }
}

struct PageNavigatorVisual: View {
    let workspace: Workspace
    let currentPage: String
    let navigate: (String) -> Void

    var body: some View {
        let accent = workspace.theme.dataColor(0)
        HStack(spacing: 6) {
            ForEach(workspace.visiblePages) { page in
                let selected = page.id == currentPage
                Button { navigate(page.id) } label: {
                    Text(page.displayName)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(selected ? Color.white : accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? accent : Color.white.opacity(0.9)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(accent.opacity(0.6)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Selected-visual outline: 1.5 px accent with eight resize anchors (sized in screen points).
struct SelectionHandles: View {
    let scale: Double

    var body: some View {
        let line = 1.5 / scale
        let knob = 7 / scale
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Rectangle().strokeBorder(DS.Palette.accent, lineWidth: line)
                ForEach(Array([CGPoint(x: 0, y: 0), CGPoint(x: w / 2, y: 0), CGPoint(x: w, y: 0),
                               CGPoint(x: 0, y: h / 2), CGPoint(x: w, y: h / 2),
                               CGPoint(x: 0, y: h), CGPoint(x: w / 2, y: h), CGPoint(x: w, y: h)].enumerated()), id: \.offset) { _, p in
                    Circle().fill(Color.white)
                        .overlay(Circle().strokeBorder(DS.Palette.accent, lineWidth: line))
                        .frame(width: knob, height: knob)
                        .position(p)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
