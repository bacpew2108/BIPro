import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

// MARK: - Button / Tile Slicer (advancedSlicerVisual)

struct TileSlicerView: View {
    let data: SlicerData
    let context: VisualRenderContext
    let scrollable: Bool

    init(data: SlicerData, context: VisualRenderContext, scrollable: Bool = true) {
        self.data = data
        self.context = context
        self.scrollable = scrollable
    }

    var body: some View {
        let showHeader = context.format.slicer.headerShow ?? true
        let headerText = data.levels.map(\.displayName).joined(separator: ", ")
        let accent = context.theme.dataColor(0)

        VStack(alignment: .leading, spacing: 6) {
            if showHeader && !headerText.isEmpty {
                headerBar(text: headerText, accent: accent)
            }
            if scrollable {
                ScrollView(.vertical) { tileGrid(accent: accent) }
            } else {
                tileGrid(accent: accent)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func headerBar(text: String, accent: Color) -> some View {
        let headerColor: Color = context.theme.color(context.format.slicer.headerFontColor) ?? (Color(hex: "#252423") ?? .primary)
        let headerSize = ReportUnits.pixels(fromPoints: context.format.slicer.headerTextSize ?? 10)
        return HStack {
            Text(text)
                .font(.system(size: headerSize, weight: .semibold))
                .foregroundStyle(headerColor)
                .lineLimit(1)
            Spacer()
            if !context.slicerSelection.isEmpty && scrollable {
                Button(bi("Xoá lọc", "Clear")) {
                    context.actions.slicerChanged(SlicerSelection())
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(accent)
            }
        }
    }

    private func tileGrid(accent: Color) -> some View {
        let columns = [GridItem(.adaptive(minimum: 76), spacing: 6)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(Array(data.roots.enumerated()), id: \.offset) { _, node in
                tileButton(node: node, accent: accent)
            }
        }
    }

    private func tileButton(node: SlicerNode, accent: Color) -> some View {
        let path = [node.value]
        let selected = context.slicerSelection.paths.contains(path)
        let label = nodeLabel(node, level: data.levels.first)
        let fg: Color = selected ? .white : (Color(hex: "#252423") ?? .primary)
        let bg: Color = selected ? accent : (Color(hex: "#F3F2F1") ?? Color.gray.opacity(0.12))
        let border: Color = selected ? accent : (Color(hex: "#D1D5DB") ?? Color.gray.opacity(0.35))
        return Button {
            guard scrollable else { return }
            let additive = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control)
            let next = SlicerTree.toggle(selection: context.slicerSelection, path: path, additive: additive, roots: data.roots)
            context.actions.slicerChanged(next)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(fg)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 4).fill(bg))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func nodeLabel(_ node: SlicerNode, level: FieldInfo?) -> String {
        if node.value == .blank { return bi("(Trống)", "(Blank)") }
        if let fmt = node.formatString { return NumberDisplay.plain(DataCell(node.value, formatString: fmt)) }
        return level?.text(node.value) ?? node.value.asText()
    }
}

// MARK: - List Slicer (listSlicer)

struct ListSlicerView: View {
    let data: SlicerData
    let context: VisualRenderContext
    let scrollable: Bool

    init(data: SlicerData, context: VisualRenderContext, scrollable: Bool = true) {
        self.data = data
        self.context = context
        self.scrollable = scrollable
    }

    var body: some View {
        let showHeader = context.format.slicer.headerShow ?? true
        let headerText = data.levels.map(\.displayName).joined(separator: ", ")
        let accent = context.theme.dataColor(0)

        VStack(alignment: .leading, spacing: 4) {
            if showHeader && !headerText.isEmpty {
                HStack {
                    Text(headerText)
                        .font(.system(size: ReportUnits.pixels(fromPoints: context.format.slicer.headerTextSize ?? 10), weight: .semibold))
                        .foregroundStyle(context.theme.color(context.format.slicer.headerFontColor) ?? (Color(hex: "#252423") ?? .primary))
                        .lineLimit(1)
                    Spacer()
                    if !context.slicerSelection.isEmpty && scrollable {
                        Button(bi("Xoá lọc", "Clear")) {
                            context.actions.slicerChanged(SlicerSelection())
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(accent)
                    }
                }
            }

            let rows = VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(data.roots.enumerated()), id: \.offset) { _, node in
                    let path = [node.value]
                    let selected = context.slicerSelection.paths.contains(path)
                    let label = node.value == .blank
                        ? bi("(Trống)", "(Blank)")
                        : (node.formatString.map { NumberDisplay.plain(DataCell(node.value, formatString: $0)) }
                            ?? data.levels.first?.text(node.value) ?? node.value.asText())
                    Button {
                        guard scrollable else { return }
                        let additive = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control)
                        let next = SlicerTree.toggle(selection: context.slicerSelection, path: path, additive: additive, roots: data.roots)
                        context.actions.slicerChanged(next)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selected ? "checkmark.square.fill" : "square")
                                .font(.system(size: 12))
                                .foregroundStyle(selected ? accent : Color.gray)
                            Text(label)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "#252423") ?? .primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 3).fill(selected ? accent.opacity(0.10) : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if scrollable {
                ScrollView(.vertical) { rows }
            } else {
                rows
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Text Slicer (textSlicer)

struct TextSlicerView: View {
    let data: SlicerData
    let context: VisualRenderContext
    let interactive: Bool

    @State private var draftText: String = ""

    init(data: SlicerData, context: VisualRenderContext, interactive: Bool = true) {
        self.data = data
        self.context = context
        self.interactive = interactive
        self._draftText = State(initialValue: context.slicerSelection.searchText ?? "")
    }

    var body: some View {
        let showHeader = context.format.slicer.headerShow ?? true
        let headerText = data.levels.map(\.displayName).joined(separator: ", ")
        let accent = context.theme.dataColor(0)

        VStack(alignment: .leading, spacing: 6) {
            if showHeader && !headerText.isEmpty {
                Text(headerText)
                    .font(.system(size: ReportUnits.pixels(fromPoints: context.format.slicer.headerTextSize ?? 10), weight: .semibold))
                    .foregroundStyle(context.theme.color(context.format.slicer.headerFontColor) ?? (Color(hex: "#252423") ?? .primary))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.gray)

                if interactive {
                    TextField(bi("Nhập văn bản cần lọc…", "Enter text to filter…"), text: $draftText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#252423") ?? .primary)
                        .onSubmit { applyText() }
                } else {
                    Text(draftText.isEmpty ? bi("Nhập văn bản cần lọc…", "Enter text to filter…") : draftText)
                        .font(.system(size: 11))
                        .foregroundStyle(draftText.isEmpty ? Color.gray : (Color(hex: "#252423") ?? .primary))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                if !draftText.isEmpty && interactive {
                    Button {
                        draftText = ""
                        context.actions.slicerChanged(SlicerSelection())
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.gray)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: applyText) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .disabled(!interactive)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(hex: "#D1D5DB") ?? Color.gray.opacity(0.45), lineWidth: 1))
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: context.slicerSelection.searchText) { _, newValue in
            let next = newValue ?? ""
            if next != draftText { draftText = next }
        }
    }

    private func applyText() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        context.actions.slicerChanged(trimmed.isEmpty ? SlicerSelection() : SlicerSelection(searchText: trimmed))
    }
}

// MARK: - Range Slicer ('Between' mode for numeric & date columns)

struct RangeSlicerView: View {
    let data: SlicerData
    let context: VisualRenderContext
    let interactive: Bool

    @State private var lowDraft: Double = 0
    @State private var highDraft: Double = 1
    @State private var lowText: String = ""
    @State private var highText: String = ""
    @State private var initialized = false

    private var domainBounds: (min: Double, max: Double) {
        let lo = data.domainRange?.min.flatMap(Self.toDouble) ?? 0
        let hi = data.domainRange?.max.flatMap(Self.toDouble) ?? max(lo + 1, 1)
        return (lo, max(lo + 1e-6, hi))
    }

    static func toDouble(_ v: Value) -> Double? {
        switch v {
        case .integer(let i): return Double(i)
        case .double(let d): return d.isFinite ? d : nil
        case .currency(let c): return Double(c) / 10_000.0
        case .dateTime(let serial): return serial.isFinite ? serial : nil
        default: return nil
        }
    }

    static func toValue(_ d: Double, isDate: Bool, template: Value?) -> Value {
        if isDate { return .dateTime(d.rounded()) }
        if case .integer? = template { return .integer(Int64(d.rounded())) }
        if case .currency? = template { return .currency(Int64((d * 10_000).rounded())) }
        return .double(d)
    }

    static func formatBound(_ d: Double, isDate: Bool) -> String {
        if isDate {
            let c = DateDisplay.civil(serial: d)
            return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
        }
        if abs(d - d.rounded()) < 1e-6 && abs(d) < 1e12 {
            return String(Int64(d.rounded()))
        }
        return NumberDisplay.decimal(d, precision: 2)
    }

    static func parseBound(_ text: String, isDate: Bool) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isDate {
            let parts = trimmed.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            var comps = DateComponents()
            comps.year = parts[0]; comps.month = parts[1]; comps.day = parts[2]
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC") ?? .current
            guard let date = cal.date(from: comps) else { return nil }
            return date.timeIntervalSince1970 / 86_400.0 + 25_569.0
        }
        return Double(trimmed.replacingOccurrences(of: ",", with: ""))
    }

    var body: some View {
        let bounds = domainBounds
        let curLow = initialized ? lowDraft : (context.slicerSelection.range?.min.flatMap(Self.toDouble) ?? bounds.min)
        let curHigh = initialized ? highDraft : (context.slicerSelection.range?.max.flatMap(Self.toDouble) ?? bounds.max)
        let showHeader = context.format.slicer.headerShow ?? true
        let headerText = data.levels.map(\.displayName).joined(separator: ", ")
        let accent = context.theme.dataColor(0)

        VStack(alignment: .leading, spacing: 8) {
            if showHeader && !headerText.isEmpty {
                HStack {
                    Text(headerText)
                        .font(.system(size: ReportUnits.pixels(fromPoints: context.format.slicer.headerTextSize ?? 10), weight: .semibold))
                        .foregroundStyle(context.theme.color(context.format.slicer.headerFontColor) ?? (Color(hex: "#252423") ?? .primary))
                        .lineLimit(1)
                    Spacer()
                    if !context.slicerSelection.isEmpty && interactive {
                        Button(bi("Đặt lại", "Reset")) {
                            lowDraft = bounds.min; highDraft = bounds.max
                            lowText = Self.formatBound(bounds.min, isDate: data.isDateColumn)
                            highText = Self.formatBound(bounds.max, isDate: data.isDateColumn)
                            context.actions.slicerChanged(SlicerSelection())
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(accent)
                    }
                }
            }

            // Two min/max boxes (matches VM-V11A pop-slicer.visual.json)
            HStack(spacing: 8) {
                boundBox(text: $lowText, fallback: Self.formatBound(curLow, isDate: data.isDateColumn), onCommit: commitLowText)
                boundBox(text: $highText, fallback: Self.formatBound(curHigh, isDate: data.isDateColumn), onCommit: commitHighText)
            }

            // Dual-thumb slider
            dualSlider(low: curLow, high: curHigh, bounds: bounds, accent: accent)
                .frame(height: 22)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { syncFromSelection() }
        .onChange(of: context.slicerSelection.range) { _, _ in syncFromSelection() }
    }

    @ViewBuilder
    private func boundBox(text: Binding<String>, fallback: String, onCommit: @escaping () -> Void) -> some View {
        Group {
            if interactive {
                TextField("", text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(hex: "#252423") ?? .primary)
                    .onSubmit(onCommit)
            } else {
                Text(text.wrappedValue.isEmpty ? fallback : text.wrappedValue)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(hex: "#252423") ?? .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: "#D1D5DB") ?? Color.gray.opacity(0.45), lineWidth: 1))
    }

    private func dualSlider(low: Double, high: Double, bounds: (min: Double, max: Double), accent: Color) -> some View {
        GeometryReader { geo in
            let w = max(20, geo.size.width - 16)
            let span = max(1e-9, bounds.max - bounds.min)
            let loFrac = min(1, max(0, (low - bounds.min) / span))
            let hiFrac = min(1, max(0, (high - bounds.min) / span))
            let loX = 8 + CGFloat(loFrac) * w
            let hiX = 8 + CGFloat(hiFrac) * w

            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: "#D1D5DB") ?? Color.gray.opacity(0.3))
                    .frame(height: 4)
                    .padding(.horizontal, 8)
                Capsule().fill(accent)
                    .frame(width: max(4, hiX - loX), height: 4)
                    .offset(x: loX)

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(accent, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .position(x: loX, y: geo.size.height / 2)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        guard interactive else { return }
                        let f = min(hiFrac, max(0, Double((g.location.x - 8) / w)))
                        let v = bounds.min + f * span
                        lowDraft = v; highDraft = high; initialized = true
                        lowText = Self.formatBound(v, isDate: data.isDateColumn)
                    }.onEnded { _ in commitDraft() })

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(accent, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .position(x: hiX, y: geo.size.height / 2)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        guard interactive else { return }
                        let f = min(1, max(loFrac, Double((g.location.x - 8) / w)))
                        let v = bounds.min + f * span
                        lowDraft = low; highDraft = v; initialized = true
                        highText = Self.formatBound(v, isDate: data.isDateColumn)
                    }.onEnded { _ in commitDraft() })
            }
        }
    }

    private func syncFromSelection() {
        let bounds = domainBounds
        lowDraft = context.slicerSelection.range?.min.flatMap(Self.toDouble) ?? bounds.min
        highDraft = context.slicerSelection.range?.max.flatMap(Self.toDouble) ?? bounds.max
        lowText = Self.formatBound(lowDraft, isDate: data.isDateColumn)
        highText = Self.formatBound(highDraft, isDate: data.isDateColumn)
        initialized = true
    }

    private func commitLowText() {
        let bounds = domainBounds
        if let v = Self.parseBound(lowText, isDate: data.isDateColumn) {
            lowDraft = min(highDraft, max(bounds.min, v))
            lowText = Self.formatBound(lowDraft, isDate: data.isDateColumn)
            commitDraft()
        }
    }

    private func commitHighText() {
        let bounds = domainBounds
        if let v = Self.parseBound(highText, isDate: data.isDateColumn) {
            highDraft = max(lowDraft, min(bounds.max, v))
            highText = Self.formatBound(highDraft, isDate: data.isDateColumn)
            commitDraft()
        }
    }

    private func commitDraft() {
        let bounds = domainBounds
        let isFull = abs(lowDraft - bounds.min) <= (bounds.max - bounds.min) * 1e-4
            && abs(highDraft - bounds.max) <= (bounds.max - bounds.min) * 1e-4
        if isFull {
            context.actions.slicerChanged(SlicerSelection())
        } else {
            let minVal = Self.toValue(lowDraft, isDate: data.isDateColumn, template: data.domainRange?.min)
            let maxVal = Self.toValue(highDraft, isDate: data.isDateColumn, template: data.domainRange?.max)
            context.actions.slicerChanged(SlicerSelection(range: SlicerRange(min: minVal, max: maxVal)))
        }
    }
}
