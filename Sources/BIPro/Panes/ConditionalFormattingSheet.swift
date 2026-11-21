import PBIXKit
import SwiftUI

/// Ngăn cấu hình Định dạng có điều kiện (Conditional Formatting — Wave 3B / T015) cho `tableEx` và `pivotTable`.
/// Ghi thẳng chuẩn PBIR đã quan sát tại `VM-V11B`: `objects.values` (`FillRule` / `Conditional` / `Measure`) và `objects.columnFormatting` (`dataBars`).
struct ConditionalFormattingSheet: View {
    @Bindable var state: DocumentState
    let visual: ReportVisual
    @Binding var isPresented: Bool

    enum StyleMode: String, CaseIterable, Identifiable {
        case none, gradient, rules, fieldValue
        var id: String { rawValue }
        @MainActor
        var title: String {
            switch self {
            case .none: bi("Không áp dụng", "None")
            case .gradient: bi("Thang màu (Gradient)", "Gradient")
            case .rules: bi("Quy tắc (Rules)", "Rules")
            case .fieldValue: bi("Theo measure màu", "Field value")
            }
        }
    }

    @State private var selectedQueryRef: String = ""
    @State private var targetProperty: String = "backColor" // "backColor" hoặc "fontColor"
    @State private var styleMode: StyleMode = .gradient
    // Gradient
    @State private var minHex: String = "#FFF5F0"
    @State private var midHex: String = "#FC9272"
    @State private var maxHex: String = "#CB181D"
    @State private var useMidColor: Bool = true
    // Rules (tối đa 3 quy tắc nhanh)
    @State private var ruleOp: RuleComparisonOp = .lessThan
    @State private var ruleThreshold: String = "500"
    @State private var ruleColorHex: String = "#FCE4D6"
    // Field value measure
    @State private var colorMeasureRef: String = ""
    // Data bars
    @State private var enableDataBars: Bool = false
    @State private var barPositiveHex: String = "#118DFF"
    @State private var barNegativeHex: String = "#D64554"
    @State private var barHideText: Bool = false

    private var valueFields: [ReportField] {
        visual.fields.filter { $0.kind == .measure || $0.kind == .aggregation }
    }

    private var selectedField: ReportField? {
        valueFields.first { $0.queryRef == selectedQueryRef } ?? valueFields.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(bi("Định dạng có điều kiện", "Conditional Formatting"))
                    .font(DS.Typeface.headlineLarge)
                Spacer()
                Button(bi("Đóng", "Close")) { isPresented = false }
                    .buttonStyle(.plain).foregroundStyle(DS.Palette.secondaryLabel)
            }

            if valueFields.isEmpty {
                Text(bi("Visual chưa có trường giá trị (measure) để định dạng có điều kiện.",
                        "This visual has no measure/value fields for conditional formatting."))
                    .font(DS.Typeface.body).foregroundStyle(DS.Palette.secondaryLabel)
            } else {
                Picker(bi("Áp dụng cho trường", "Apply to field"), selection: $selectedQueryRef) {
                    ForEach(valueFields, id: \.queryRef) { f in
                        Text(f.label).tag(f.queryRef)
                    }
                }

                Divider()

                Picker(bi("Thuộc tính màu", "Color target"), selection: $targetProperty) {
                    Text(bi("Màu nền (Background color)", "Background color")).tag("backColor")
                    Text(bi("Màu chữ (Font color)", "Font color")).tag("fontColor")
                }
                .pickerStyle(.segmented)

                Picker(bi("Kiểu định dạng", "Format style"), selection: $styleMode) {
                    ForEach(StyleMode.allCases) { m in Text(m.title).tag(m) }
                }

                switch styleMode {
                case .none:
                    Text(bi("Xoá định dạng màu có điều kiện của trường này.", "Removes conditional color formatting for this field."))
                        .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                case .gradient:
                    HStack {
                        colorField(bi("Thấp nhất", "Minimum"), hex: $minHex)
                        if useMidColor { colorField(bi("Giữa", "Center"), hex: $midHex) }
                        colorField(bi("Cao nhất", "Maximum"), hex: $maxHex)
                    }
                    Toggle(bi("Dùng màu giữa (3 mốc)", "Add a middle color (diverging)"), isOn: $useMidColor)
                        .font(.system(size: 12))
                case .rules:
                    HStack(spacing: 8) {
                        Text(bi("Nếu giá trị", "If value")).font(.system(size: 12))
                        Picker("", selection: $ruleOp) {
                            ForEach(RuleComparisonOp.allCases, id: \.self) { op in Text(op.symbol).tag(op) }
                        }.labelsHidden().frame(width: 64)
                        TextField("500", text: $ruleThreshold).textFieldStyle(.roundedBorder).frame(width: 90)
                        Text(bi("thì tô", "then")).font(.system(size: 12))
                        colorField("", hex: $ruleColorHex)
                    }
                case .fieldValue:
                    let allMeasures = state.interaction.measureRefs()
                    Picker(bi("Measure trả mã màu hex", "Color measure"), selection: $colorMeasureRef) {
                        Text(bi("Chọn measure…", "Choose measure…")).tag("")
                        ForEach(allMeasures, id: \.self) { m in
                            Text("\(m.name) (\(m.table))").tag("\(m.table).\(m.name)")
                        }
                    }
                }

                Divider()

                Toggle(bi("Hiển thị Thanh dữ liệu (Data bars)", "Show Data bars"), isOn: $enableDataBars)
                    .font(.system(size: 12, weight: .semibold))
                if enableDataBars {
                    HStack(spacing: 12) {
                        colorField(bi("Thanh dương", "Positive bar"), hex: $barPositiveHex)
                        colorField(bi("Thanh âm", "Negative bar"), hex: $barNegativeHex)
                        Toggle(bi("Chỉ hiện thanh", "Show bar only"), isOn: $barHideText)
                            .font(.system(size: 12))
                    }
                }

                Spacer(minLength: 4)
                HStack {
                    Spacer()
                    Button(bi("Huỷ", "Cancel")) { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Button(bi("Áp dụng", "Apply")) { applyChanges(); isPresented = false }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(18)
        .frame(width: 470)
        .onAppear(perform: loadInitial)
    }

    private func colorField(_ label: String, hex: Binding<String>) -> some View {
        HStack(spacing: 4) {
            if !label.isEmpty { Text(label).font(.system(size: 11)).foregroundStyle(DS.Palette.secondaryLabel) }
            ColorPicker("", selection: Binding(
                get: { Color(hex: hex.wrappedValue) ?? .accentColor },
                set: { hex.wrappedValue = Self.hexString(from: $0) }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }

    private static func hexString(from color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func loadInitial() {
        selectedQueryRef = valueFields.first?.queryRef ?? ""
        let fmt = VisualFormat(objects: visual.objects)
        if let bar = fmt.dataBars.first(where: { $0.target == selectedQueryRef }) {
            enableDataBars = true
            barHideText = bar.hideText
        }
    }

    private func applyChanges() {
        guard let field = selectedField else { return }
        // 1. Ghi `objects.values` cho backColor / fontColor
        let valuesJSON: String?
        switch styleMode {
        case .none:
            valuesJSON = nil
        case .gradient:
            let midPart = useMidColor ? #","mid":{"color":{"Literal":{"Value":"'\#(midHex)'"}}}"# : ""
            let gKey = useMidColor ? "linearGradient3" : "linearGradient2"
            valuesJSON = #"[{"properties":{"\#(targetProperty)":{"solid":{"color":{"expr":{"FillRule":{"Input":{"Measure":{"Expression":{"SourceRef":{"Entity":"\#(field.entity)"}},"Property":"\#(field.property)"}},"FillRule":{"\#(gKey)":{"min":{"color":{"Literal":{"Value":"'\#(minHex)'"}}}\#(midPart),"max":{"color":{"Literal":{"Value":"'\#(maxHex)'"}}},"nullColoringStrategy":{"strategy":{"Literal":{"Value":"'asZero'"}}}}}}}}}}},"selector":{"data":[{"dataViewWildcard":{"matchingOption":1}}],"metadata":"\#(field.queryRef)"}}]"#
        case .rules:
            let num = Double(ruleThreshold) ?? 0
            valuesJSON = #"[{"properties":{"\#(targetProperty)":{"solid":{"color":{"expr":{"Conditional":{"Cases":[{"Condition":{"Comparison":{"ComparisonKind":\#(ruleOp.rawValue),"Left":{"Measure":{"Expression":{"SourceRef":{"Entity":"\#(field.entity)"}},"Property":"\#(field.property)"}},"Right":{"Literal":{"Value":"\#(num)D"}}}},"Value":{"Literal":{"Value":"'\#(ruleColorHex)'"}}}]}}}}}},"selector":{"data":[{"dataViewWildcard":{"matchingOption":1}}],"metadata":"\#(field.queryRef)"}}]"#
        case .fieldValue:
            let parts = colorMeasureRef.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            valuesJSON = #"[{"properties":{"\#(targetProperty)":{"solid":{"color":{"expr":{"Measure":{"Expression":{"SourceRef":{"Entity":"\#(parts[0])"}},"Property":"\#(parts[1])"}}}}}}},"selector":{"data":[{"dataViewWildcard":{"matchingOption":1}}],"metadata":"\#(field.queryRef)"}}]"#
        }
        state.layout.setRawObjectArray(object: "values", arrayJSON: valuesJSON, visual: visual.id)

        // 2. Ghi `objects.columnFormatting` cho Data Bars (VM-V11B)
        let barsJSON: String? = enableDataBars
            ? #"[{"properties":{"dataBars":{"positiveColor":{"solid":{"color":{"expr":{"Literal":{"Value":"'\#(barPositiveHex)'"}}}}},"negativeColor":{"solid":{"color":{"expr":{"Literal":{"Value":"'\#(barNegativeHex)'"}}}}},"axisColor":{"solid":{"color":{"expr":{"Literal":{"Value":"'foreground'"}}}}},"reverseDirection":{"expr":{"Literal":{"Value":"false"}}},"hideText":{"expr":{"Literal":{"Value":"\#(barHideText ? "true" : "false")"}}},"totalMatchingOption":{"expr":{"Literal":{"Value":"1L"}}}}},"selector":{"metadata":"\#(field.queryRef)"}}]"#
            : nil
        state.layout.setRawObjectArray(object: "columnFormatting", arrayJSON: barsJSON, visual: visual.id)
    }
}
