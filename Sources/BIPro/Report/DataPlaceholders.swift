import PBIXKit
import SwiftUI

// Data-bound visuals render their real layout, fields and colors, but no numbers:
// values need the DAX engine (Phase 3). Shapes are drawn as faint "ghost" data.

private let categoryRoles: Set = ["Category", "Rows", "Axis", "Legend", "Series", "Group", "Columns", "Location"]

private func valueFields(_ visual: ReportVisual) -> [ReportField] {
    visual.fields.filter { !categoryRoles.contains($0.role) && $0.role != "Tooltips" }
}

/// Stable pseudo-random heights so ghost charts differ per visual but never flicker.
private func ghostSeries(_ seed: String, count: Int) -> [Double] {
    var state = UInt64(truncatingIfNeeded: seed.unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) })
    return (0..<count).map { _ in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return 0.25 + Double((state >> 33) % 1000) / 1000 * 0.7
    }
}

struct PendingValueBadge: View {
    var body: some View {
        Label("Chờ engine DAX", systemImage: "hourglass")
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(.background.opacity(0.85)))
            .foregroundStyle(.secondary)
    }
}

struct CardPlaceholder: View {
    let visual: ReportVisual
    let theme: ReportTheme

    var body: some View {
        let o = visual.objects
        let valueColor = theme.color(o.color("labels", "color")) ?? theme.foregroundColor
        let valueSize = ReportUnits.pixels(fromPoints: o.number("labels", "fontSize") ?? 27)
        let showCategory = o.bool("categoryLabels", "show") ?? true
        let categoryColor = theme.color(o.color("categoryLabels", "color")) ?? .secondary
        let categorySize = ReportUnits.pixels(fromPoints: o.number("categoryLabels", "fontSize") ?? 12)
        let fields = valueFields(visual)

        VStack(spacing: 2) {
            Text("—")
                .font(.system(size: valueSize, weight: .semibold))
                .foregroundStyle(valueColor.opacity(0.55))
                .minimumScaleFactor(0.3)
                .lineLimit(1)
            if showCategory, let field = fields.first {
                Text(field.label)
                    .font(.system(size: categorySize))
                    .foregroundStyle(categoryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help(fields.map(\.label).joined(separator: ", "))
    }
}

struct SlicerPlaceholder: View {
    let visual: ReportVisual
    let theme: ReportTheme

    var body: some View {
        let o = visual.objects
        let mode = o.string("data", "mode") ?? "Basic"
        let header = visual.fields.map(\.label).joined(separator: " · ")
        let headerColor = theme.color(o.color("header", "fontColor")) ?? theme.foregroundColor

        VStack(alignment: .leading, spacing: 4) {
            if o.bool("header", "show") ?? true {
                Text(header)
                    .font(.system(size: ReportUnits.pixels(fromPoints: o.number("header", "textSize") ?? 10), weight: .semibold))
                    .foregroundStyle(headerColor)
                    .lineLimit(1)
            }
            if mode == "Dropdown" {
                HStack {
                    Text("Tất cả").foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .frame(maxHeight: 28)
                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.gray.opacity(0.45)))
            } else {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(Color.gray.opacity(0.6)).frame(width: 12, height: 12)
                        RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.18))
                            .frame(width: 60 + CGFloat(ghostSeries(visual.id, count: 4)[row]) * 80, height: 8)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TablePlaceholder: View {
    let visual: ReportVisual
    let theme: ReportTheme

    var body: some View {
        let columns = visual.fields.filter { $0.role != "Tooltips" }
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, field in
                    Text(field.label)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
            }
            .background(theme.dataColor(0).opacity(0.12))
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<max(1, columns.count), id: \.self) { col in
                        RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.14))
                            .frame(height: 7)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 22)
                .background(row.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.05))
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottomTrailing) { PendingValueBadge().padding(4) }
    }
}

struct ChartPlaceholder: View {
    let visual: ReportVisual
    let theme: ReportTheme

    private enum Family { case bar, column, line, combo, donut, pie, treemap, map, scatter, other }

    private var family: Family {
        let t = visual.type.lowercased()
        if t.contains("combo") { return .combo }
        if t.contains("barchart") { return .bar }
        if t.contains("column") { return .column }
        if t.contains("line") || t.contains("area") { return .line }
        if t.contains("donut") { return .donut }
        if t.contains("pie") { return .pie }
        if t.contains("treemap") { return .treemap }
        if t.contains("map") { return .map }
        if t.contains("scatter") { return .scatter }
        return .other
    }

    var body: some View {
        let color = theme.color(visual.objects.color("dataPoint", "fill")) ?? theme.dataColor(0)
        let series = ghostSeries(visual.id, count: 8)
        ZStack {
            ghost(color: color, series: series)
                .opacity(0.32)
                .padding(10)
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(color)
                PendingValueBadge()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help(visual.fields.map { "\($0.role): \($0.label)" }.joined(separator: "\n"))
    }

    private var symbol: String {
        switch family {
        case .bar: "chart.bar.xaxis"
        case .column, .combo: "chart.bar"
        case .line: "chart.xyaxis.line"
        case .donut, .pie: "chart.pie"
        case .treemap: "square.grid.3x3.square"
        case .map: "map"
        case .scatter: "chart.dots.scatter"
        case .other: "chart.bar.doc.horizontal"
        }
    }

    @ViewBuilder private func ghost(color: Color, series: [Double]) -> some View {
        switch family {
        case .bar:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: g.size.width * series[i])
                    }
                }
            }
        case .column, .combo:
            ZStack {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<8, id: \.self) { i in
                        GeometryReader { g in
                            VStack { Spacer(minLength: 0); RoundedRectangle(cornerRadius: 2).fill(color).frame(height: g.size.height * series[i]) }
                        }
                    }
                }
                if family == .combo { line(series.reversed(), color: theme.dataColor(2)) }
            }
        case .line:
            line(series, color: color)
        case .donut, .pie:
            GeometryReader { g in
                let side = min(g.size.width, g.size.height)
                ZStack {
                    ForEach(0..<4, id: \.self) { i in
                        let total = series.prefix(4).reduce(0, +)
                        let start = series.prefix(i).reduce(0, +) / total
                        let end = series.prefix(i + 1).reduce(0, +) / total
                        Circle()
                            .trim(from: start, to: end)
                            .stroke(theme.dataColor(i), lineWidth: family == .donut ? side * 0.18 : side * 0.5)
                            .frame(width: family == .donut ? side * 0.8 : side * 0.5, height: family == .donut ? side * 0.8 : side * 0.5)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .treemap:
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2).fill(theme.dataColor(0))
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(theme.dataColor(1))
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(theme.dataColor(2))
                        RoundedRectangle(cornerRadius: 2).fill(theme.dataColor(3))
                    }
                }
            }
        case .scatter:
            Canvas { context, size in
                for i in 0..<8 {
                    let p = CGPoint(x: size.width * (Double(i) + 0.5) / 8, y: size.height * (1 - series[i]))
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(color))
                }
            }
        case .map, .other:
            RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.4))
        }
    }

    private func line(_ series: [Double], color: Color) -> some View {
        Canvas { context, size in
            var path = Path()
            for (i, v) in series.enumerated() {
                let p = CGPoint(x: size.width * Double(i) / Double(series.count - 1), y: size.height * (1 - v))
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}
