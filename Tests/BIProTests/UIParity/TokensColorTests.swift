import AppKit
import SwiftUI
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — TokensColor")
struct TokensColorTests {
    private func resolveSRGB(_ color: Color, dark: Bool) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var result: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        appearance.performAsCurrentDrawingAppearance {
            let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
            result = (ns.redComponent, ns.greenComponent, ns.blueComponent)
        }
        return result
    }

    private func luminance(_ rgb: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
    }

    private func expectedRGB(_ hex: UInt32) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        (
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255
        )
    }

    private func assertMatchesHex(_ color: Color, dark: Bool, hex: UInt32) {
        let actual = resolveSRGB(color, dark: dark)
        let target = expectedRGB(hex)
        #expect(abs(actual.r - target.r) <= 0.03)
        #expect(abs(actual.g - target.g) <= 0.03)
        #expect(abs(actual.b - target.b) <= 0.03)
        #expect(abs(luminance(actual) - luminance(target)) <= 0.03)
    }

    @Test func newTealAndCanvasWellTokensMatchContractLightAndDark() {
        assertMatchesHex(DS.Palette.accentTeal, dark: false, hex: 0x117865)
        assertMatchesHex(DS.Palette.accentTeal, dark: true, hex: 0x3FB59B)
        assertMatchesHex(DS.Palette.accentTealPressed, dark: false, hex: 0x0E6655)
        assertMatchesHex(DS.Palette.accentTealPressed, dark: true, hex: 0x35A088)
        assertMatchesHex(DS.Palette.canvasWell, dark: false, hex: 0xE6E6E6)
        assertMatchesHex(DS.Palette.canvasWell, dark: true, hex: 0x1C1C1E)
        assertMatchesHex(DS.Palette.tabUnderline, dark: false, hex: 0x117865)
        assertMatchesHex(DS.Palette.tabUnderline, dark: true, hex: 0x3FB59B)
    }

    @Test func chartSeriesColorsUnchangedFromV12() {
        let expectedHexes: [UInt32] = [0x0A84FF, 0x5E5CE6, 0x30B0C7, 0x34C759, 0xFF9F0A, 0xFF453A]
        #expect(DS.Palette.series.count == expectedHexes.count)
        for (color, hex) in zip(DS.Palette.series, expectedHexes) {
            assertMatchesHex(color, dark: false, hex: hex)
        }
    }
}
}
