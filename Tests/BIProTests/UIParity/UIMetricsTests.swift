import CoreGraphics
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — UIMetrics")
struct UIMetricsTests {
    @Test func metricsMatchContractWithinTwoPoints() {
        #expect(abs(UIMetrics.titleBar - 36) <= 2)
        #expect(abs(UIMetrics.tabRow - 32) <= 2)
        #expect(abs(UIMetrics.ribbonPanel - 98) <= 2)
        #expect(abs(UIMetrics.rail - 42) <= 2)
        #expect(abs(UIMetrics.railIconHit - 40) <= 2)
        #expect(abs(UIMetrics.pageTabs - 35) <= 2)
        #expect(abs(UIMetrics.statusBar - 23) <= 2)
        #expect(abs(UIMetrics.pane - 181) <= 2)
        #expect(abs(UIMetrics.collapsedPane - 31) <= 2)
        #expect(abs(UIMetrics.ribbonIcon - 28) <= 2)
        #expect(abs(UIMetrics.ribbonCorner - 6) <= 2)
        #expect(abs(UIMetrics.tabUnderline - 2) <= 0.5)
    }

    @Test func metricsEqualExactContractValues() {
        #expect(UIMetrics.titleBar == 36)
        #expect(UIMetrics.tabRow == 32)
        #expect(UIMetrics.ribbonPanel == 98)
        #expect(UIMetrics.rail == 42)
        #expect(UIMetrics.railIconHit == 40)
        #expect(UIMetrics.pageTabs == 35)
        #expect(UIMetrics.statusBar == 23)
        #expect(UIMetrics.pane == 181)
        #expect(UIMetrics.collapsedPane == 31)
        #expect(UIMetrics.ribbonIcon == 28)
        #expect(UIMetrics.ribbonCorner == 6)
        #expect(UIMetrics.tabUnderline == 2)
    }
}
}
