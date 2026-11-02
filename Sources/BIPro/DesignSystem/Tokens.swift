import SwiftUI

/// Design tokens from `UIdesign/lumen_analytics_design_system/DESIGN.md` (macOS system palette, light mode).
enum DS {
    enum Palette {
        static let accent = Color(hex: "#0A84FF")!
        static let accentHover = Color(hex: "#0077ED")!
        static let accentPressed = Color(hex: "#0068D6")!
        static let indigo = Color(hex: "#5E5CE6")!
        static let backdrop = Color(hex: "#EBEBF0")!       // under the report canvas
        static let chrome = Color(hex: "#F5F5F7")!         // toolbars, panes, headers
        static let canvas = Color.white                    // report canvas, tiles, popovers
        static let separator = Color(hex: "#E5E5EA")!      // hairlines
        static let label = Color(hex: "#1C1C1E")!
        static let secondaryLabel = Color(hex: "#636366")!
        static let tertiaryLabel = Color(hex: "#8E8E93")!
        static let controlFill = Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.12)
        static let searchFill = Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.08)
        static let selectionSoft = Color(hex: "#0A84FF")!.opacity(0.12)
        static let success = Color(hex: "#34C759")!
        static let warning = Color(hex: "#FF9F0A")!
        static let danger = Color(hex: "#FF453A")!
        static let checkboxBorder = Color(hex: "#C7C7CC")!

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

extension View {
    /// Tile elevation: `0 1px 2px rgba(0,0,0,.04), 0 0 0 1px rgba(0,0,0,.05)`.
    func tileElevation(cornerRadius: CGFloat = DS.Radius.tile) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.black.opacity(0.05), lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }

    /// Popover/dropdown elevation.
    func popoverElevation(cornerRadius: CGFloat = DS.Radius.tile) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
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
