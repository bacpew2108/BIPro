import PBIXKit
import SwiftUI

extension Color {
    /// `#RRGGBB`, `#RGB` or `#AARRGGBB`.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let a = s.count == 8 ? Double((v >> 24) & 0xFF) / 255 : 1
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: a)
    }

    func mixed(with other: Color, by fraction: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        let f = max(0, min(1, fraction))
        return Color(.sRGB, red: a.redComponent + (b.redComponent - a.redComponent) * f,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * f,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * f,
                     opacity: a.alphaComponent)
    }
}

extension ReportTheme {
    func color(_ literal: ReportLiteral?) -> Color? {
        switch literal {
        case .string(let hex):
            return Color(hex: hex)
        case .themeColor(let id, let percent):
            // Theme palette order as in Power BI's color picker: background, foreground, then data colors.
            let hex: String?
            switch id {
            case 0: hex = background ?? "#FFFFFF"
            case 1: hex = foreground ?? "#000000"
            default: hex = dataColors.isEmpty ? nil : dataColors[(id - 2) % dataColors.count]
            }
            guard let hex, let base = Color(hex: hex) else { return nil }
            // Positive percent lightens toward white, negative darkens toward black.
            return percent >= 0 ? base.mixed(with: .white, by: percent) : base.mixed(with: .black, by: -percent)
        default:
            return nil
        }
    }

    func dataColor(_ index: Int) -> Color {
        Color(hex: dataColors[index % max(1, dataColors.count)]) ?? .accentColor
    }

    var foregroundColor: Color { foreground.flatMap(Color.init(hex:)) ?? Color(hex: "#252423")! }
}

/// Report canvas units are CSS pixels at 96 DPI; font sizes in formatting are points.
enum ReportUnits {
    static func pixels(fromPoints points: Double) -> CGFloat { CGFloat(points * 4 / 3) }

    /// Parses `"22pt"`, `"14px"` or a bare number (points).
    static func fontSize(_ text: String?) -> CGFloat? {
        guard var s = text?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasSuffix("px") { s.removeLast(2); return Double(s).map { CGFloat($0) } }
        if s.hasSuffix("pt") { s.removeLast(2) }
        return Double(s).map(pixels(fromPoints:))
    }
}

extension ObjectProperties {
    /// Transparency is stored as a percentage (0 = opaque).
    func opacity(_ object: String, _ property: String = "transparency") -> Double {
        1 - (number(object, property) ?? 0) / 100
    }
}

extension HorizontalAlignment {
    init(reportAlignment: String?) {
        switch reportAlignment?.lowercased() {
        case "center": self = .center
        case "right": self = .trailing
        default: self = .leading
        }
    }
}

extension TextAlignment {
    init(reportAlignment: String?) {
        switch reportAlignment?.lowercased() {
        case "center": self = .center
        case "right": self = .trailing
        default: self = .leading
        }
    }
}
