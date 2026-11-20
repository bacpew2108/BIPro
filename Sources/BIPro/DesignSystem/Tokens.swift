import AppKit
import SwiftUI

/// Design tokens from `UIdesign/lumen_analytics_design_system/DESIGN.md` (macOS 15 Sequoia dynamic Light/Dark palette).
enum DS {
    enum Palette {
        static let accent = Color(hex: "#0A84FF")!
        static let accentHover = Color.dynamic(light: 0x0077ED, dark: 0x2E96FF)
        static let accentPressed = Color.dynamic(light: 0x0068D6, dark: 0x006CE0)
        static let indigo = Color(hex: "#5E5CE6")!

        /// Vùng nền dưới trang báo cáo (`backdrop`).
        static let backdrop = Color.dynamic(light: 0xEBEBF0, dark: 0x1C1C1E)
        /// Thanh công cụ, Rail, tiêu đề ngăn (`chrome`).
        static let chrome = Color.dynamic(light: 0xF5F5F7, dark: 0x242426)
        /// Bề mặt bảng điều khiển, thẻ UI, popover (thích ứng Dark Mode).
        static let canvas = Color.dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)
        /// Nền giấy cố định của trang báo cáo `.pbix` (luôn sáng để giữ nguyên màu tác giả — FR-013).
        static let documentPaper = Color.white

        static let separator = Color.dynamic(light: 0xE5E5EA, dark: 0x3A3A3C)
        static let label = Color.dynamic(light: 0x1C1C1E, dark: 0xF5F5F7)
        static let secondaryLabel = Color.dynamic(light: 0x636366, dark: 0xAEAEB2)
        static let tertiaryLabel = Color.dynamic(light: 0x8E8E93, dark: 0x6E6E73)
        static let controlFill = Color.dynamic(light: 0x767680, lightAlpha: 0.12, dark: 0x767680, darkAlpha: 0.24)
        static let searchFill = Color.dynamic(light: 0x767680, lightAlpha: 0.08, dark: 0x767680, darkAlpha: 0.20)
        static let selectionSoft = Color.dynamic(light: 0x0A84FF, lightAlpha: 0.12, dark: 0x0A84FF, darkAlpha: 0.24)
        static let success = Color(hex: "#34C759")!
        static let warning = Color(hex: "#FF9F0A")!
        static let danger = Color(hex: "#FF453A")!
        static let checkboxBorder = Color.dynamic(light: 0xC7C7CC, dark: 0x545458)

        /// Six-hue analytical ramp.
        static let series: [Color] = ["#0A84FF", "#5E5CE6", "#30B0C7", "#34C759", "#FF9F0A", "#FF453A"].map { Color(hex: $0)! }

        /// Field-type accents used in trees and wells.
        static let measure = Color(hex: "#FF9F0A")!
        static let table = Color(hex: "#30B0C7")!
    }

    /// SF Pro equivalents of the type scale (Inter in the mockups).
    enum Typeface {
        static let display = Font.system(size: 28, weight: .semibold)
        static let headlineLarge = Font.system(size: 20, weight: .semibold)
        static let headlineMedium = Font.system(size: 15, weight: .semibold)
        static let headlineSmall = Font.system(size: 13, weight: .semibold)
        static let bodyLarge = Font.system(size: 14)
        static let body = Font.system(size: 13)
        static let bodySmall = Font.system(size: 12)
        static let label = Font.system(size: 11, weight: .medium)
        static let labelSmall = Font.system(size: 10, weight: .medium)
        static let metric = Font.system(size: 24, weight: .bold).monospacedDigit()
        static let mono = Font.system(size: 11, design: .monospaced)
        static let monoMedium = Font.system(size: 12, design: .monospaced)
    }

    enum Radius {
        static let badge: CGFloat = 4
        static let control: CGFloat = 6
        static let segmentOuter: CGFloat = 7
        static let segmentInner: CGFloat = 5
        static let tile: CGFloat = 8
        static let large: CGFloat = 12
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Metrics {
        static let titleBar: CGFloat = 52
        static let rail: CGFloat = 56
        static let pane: CGFloat = 260
        static let collapsedPane: CGFloat = 30
        static let statusBar: CGFloat = 28
        static let pageTabs: CGFloat = 34
        static let treeRow: CGFloat = 24
        static let navRow: CGFloat = 28
    }
}

extension Color {
    /// Tạo màu động SwiftUI thích ứng Sáng/Tối qua `NSColor(name:dynamicProvider:)` mà không cần `.xcassets`.
    static func dynamic(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = isDark ? dark : light
            let alpha = isDark ? darkAlpha : lightAlpha
            return NSColor(
                srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: alpha
            )
        })
    }
}

extension View {
    /// Tile elevation: thích ứng Sáng/Tối.
    func tileElevation(cornerRadius: CGFloat = DS.Radius.tile) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.dynamic(light: 0x000000, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.09), lineWidth: 1))
            .shadow(color: Color.dynamic(light: 0x000000, lightAlpha: 0.04, dark: 0x000000, darkAlpha: 0.25), radius: 1, y: 1)
    }

    /// Popover/dropdown elevation.
    func popoverElevation(cornerRadius: CGFloat = DS.Radius.tile) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.dynamic(light: 0x000000, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.14), lineWidth: 0.5))
            .shadow(color: Color.dynamic(light: 0x000000, lightAlpha: 0.12, dark: 0x000000, darkAlpha: 0.45), radius: 12, y: 6)
    }

    func hairline(_ edge: Edge) -> some View {
        overlay(alignment: edge.alignment) {
            Rectangle().fill(DS.Palette.separator)
                .frame(width: edge.isVertical ? 1 : nil, height: edge.isVertical ? nil : 1)
        }
    }
}

private extension Edge {
    var isVertical: Bool { self == .leading || self == .trailing }
    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}
