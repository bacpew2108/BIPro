import PBIXKit
import SwiftUI

/// Tab Phân tích (Analytics Pane — Wave 3B / T016) trong Visualizations pane cho các biểu đồ trục.
/// Ghi đúng cấu trúc PBIR quan sát từ Desktop 2.159 (`VM-V11B` `b2-q11.visual.json`):
/// `objects.y1AxisReferenceLine`, `objects.referenceLine` (Function 1/3/4), `objects.trend`, `objects.forecast`.
struct AnalyticsPane: View {
    @Bindable var state: DocumentState
    let visual: ReportVisual
    let blocker: String?

    @State private var newConstValue: String = "100"
    @State private var newConstName: String = ""

    private var format: VisualFormat { VisualFormat(objects: visual.objects) }
    private var primaryMeasureRef: String? {
        visual.fields.first { $0.kind == .measure || $0.kind == .aggregation }?.queryRef
    }

    static func supportsAnalytics(_ visualType: String) -> Bool {
        CartesianKind(visualType: visualType) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let blocker {
                Text(blocker).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
            }

            // 1. Đường xu hướng & Dự báo (Trend & Forecast)
            card(title: bi("Đường xu hướng & Dự báo", "Trend & Forecast")) {
                Toggle(bi("Đường xu hướng (Trend line)", "Trend line"), isOn: Binding(
                    get: { format.analytics.trendShow ?? false },
                    set: { on in
                        let json = on ? #"[{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}}}}]"# : nil
                        state.layout.setRawObjectArray(object: "trend", arrayJSON: json, visual: visual.id)
                    }
                ))
                .font(.system(size: 12))
                .disabled(blocker != nil)

                if visual.type == "lineChart" {
                    Toggle(bi("Dự báo 6 kỳ (Forecast)", "6-period Forecast"), isOn: Binding(
                        get: { format.analytics.forecastShow ?? false },
                        set: { on in
                            let json: String?
                            if on, let ref = primaryMeasureRef {
                                json = #"[{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"displayName":{"expr":{"Literal":{"Value":"'Forecast'"}}},"transform":{"algorithm":"Forecast","parameters":[{"Literal":{"Value":"7L"},"Name":"Unit"},{"Literal":{"Value":"6L"},"Name":"ForecastLength"},{"Literal":{"Value":"0L"},"Name":"IgnoreLast"},{"Literal":{"Value":"0.95D"},"Name":"ConfidenceLevel"}]}},"selector":{"metadata":"\#(ref)","id":"1"}}]"#
                            } else {
                                json = nil
                            }
                            state.layout.setRawObjectArray(object: "forecast", arrayJSON: json, visual: visual.id)
                        }
                    ))
                    .font(.system(size: 12))
                    .disabled(blocker != nil)
                }
            }

            // 2. Đường hằng số trục Y (`y1AxisReferenceLine`)
            card(title: bi("Đường hằng số trục Y", "Y-Axis Constant Line")) {
                ForEach(format.analytics.constantLines) { line in
                    HStack {
                        Text("\(line.displayName): \(NumberDisplay.text(DataCell(.double(line.value))))")
                            .font(.system(size: 12))
                        Spacer()
                        Button {
                            removeConstantLine(id: line.id)
                        } label: {
                            Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(DS.Palette.danger)
                        }
                        .buttonStyle(.plain)
                        .disabled(blocker != nil)
                    }
                }
                HStack(spacing: 6) {
                    TextField(bi("Giá trị Y", "Y value"), text: $newConstValue)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    Button(bi("+ Thêm", "+ Add")) {
                        if let v = Double(newConstValue) { addConstantLine(value: v) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(blocker != nil || Double(newConstValue) == nil)
                }
            }

            // 3. Đường Trung bình / Nhỏ nhất / Lớn nhất (`referenceLine` Function 1 / 3 / 4)
            card(title: bi("Đường thống kê (Trung bình / Min / Max)", "Statistical Lines (Avg / Min / Max)")) {
                ForEach(DynamicReferenceKind.allCases, id: \.self) { kind in
                    let isOn = format.analytics.dynamicLines.contains { $0.kind == kind && $0.show }
                    Toggle(kind.title, isOn: Binding(
                        get: { isOn },
                        set: { toggleDynamicLine(kind: kind, on: $0) }
                    ))
                    .font(.system(size: 12))
                    .disabled(blocker != nil || primaryMeasureRef == nil)
                }
            }
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(DS.Typeface.headlineSmall).foregroundStyle(DS.Palette.label)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(DS.Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(DS.Palette.separator))
    }

    private func addConstantLine(value: Double) {
        var lines = format.analytics.constantLines
        let nextID = String((lines.compactMap { Int($0.id) }.max() ?? 0) + 1)
        let label = newConstName.isEmpty ? "Constant Line \(nextID)" : newConstName
        lines.append(ConstantReferenceLine(id: nextID, displayName: label, show: true, value: value, color: .string("#D96B43"), style: .dashed))
        saveConstantLines(lines)
        newConstName = ""
    }

    private func removeConstantLine(id: String) {
        let remaining = format.analytics.constantLines.filter { $0.id != id }
        saveConstantLines(remaining)
    }

    private func saveConstantLines(_ lines: [ConstantReferenceLine]) {
        guard !lines.isEmpty else {
            state.layout.setRawObjectArray(object: "y1AxisReferenceLine", arrayJSON: nil, visual: visual.id)
            return
        }
        let items = lines.map { l -> String in
            let escName = l.displayName.replacingOccurrences(of: "'", with: "''")
            let hex: String = { if case .string(let s) = l.color { return s }; return "#D96B43" }()
            return #"{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"displayName":{"expr":{"Literal":{"Value":"'\#(escName)'"}}},"value":{"expr":{"Literal":{"Value":"\#(l.value)D"}}},"lineColor":{"solid":{"color":{"expr":{"Literal":{"Value":"'\#(hex)'"}}}}},"style":{"expr":{"Literal":{"Value":"'\#(l.style.rawValue)'"}}}},"selector":{"id":"\#(l.id)"}}"#
        }
        state.layout.setRawObjectArray(object: "y1AxisReferenceLine", arrayJSON: "[\(items.joined(separator: ","))]", visual: visual.id)
    }

    private func toggleDynamicLine(kind: DynamicReferenceKind, on: Bool) {
        guard let ref = primaryMeasureRef else { return }
        var lines = format.analytics.dynamicLines.filter { $0.kind != kind }
        if on {
            let nextID = String((lines.compactMap { Int($0.id) }.max() ?? 0) + 1)
            let name = kind == .average ? "Average line" : (kind == .min ? "Min line" : "Max line")
            lines.append(DynamicReferenceLine(id: nextID, displayName: name, show: true, kind: kind, target: ref, color: .string("#118DFF"), style: .dashed))
        }
        guard !lines.isEmpty else {
            state.layout.setRawObjectArray(object: "referenceLine", arrayJSON: nil, visual: visual.id)
            return
        }
        let items = lines.map { l -> String in
            let escName = l.displayName.replacingOccurrences(of: "'", with: "''")
            let target = l.target ?? ref
            return #"{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"displayName":{"expr":{"Literal":{"Value":"'\#(escName)'"}}},"value":{"expr":{"Aggregation":{"Expression":{"SelectRef":{"ExpressionName":"\#(target)"}},"Function":\#(l.kind.rawValue)}}}},"selector":{"metadata":"\#(target)","id":"\#(l.id)"}}"#
        }
        state.layout.setRawObjectArray(object: "referenceLine", arrayJSON: "[\(items.joined(separator: ","))]", visual: visual.id)
    }
}
