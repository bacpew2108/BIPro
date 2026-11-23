import AppKit
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — ShellLayout (US4)")
@MainActor
struct ShellLayoutTests {
    @Test func shellMetricsAndAccentTealMatchContract() {
        // Kiểm số đo khung chuẩn ±2 pt
        #expect(abs(DS.Metrics.titleBar - UIMetrics.titleBar) <= 2)
        #expect(abs(DS.Metrics.rail - UIMetrics.rail) <= 2)
        #expect(abs(DS.Metrics.pane - UIMetrics.pane) <= 2)
        #expect(abs(DS.Metrics.collapsedPane - UIMetrics.collapsedPane) <= 2)
        #expect(abs(DS.Metrics.statusBar - UIMetrics.statusBar) <= 2)
        #expect(abs(DS.Metrics.pageTabs - UIMetrics.pageTabs) <= 2)

        // Kiểm màu nhấn `DS.Palette.accent` đã chuyển sang teal (#117865 sáng / #3FB59B tối)
        let lightApp = NSAppearance(named: .aqua)!
        var lightRGB: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        lightApp.performAsCurrentDrawingAppearance {
            let ns = NSColor(DS.Palette.accent).usingColorSpace(.sRGB)!
            lightRGB = (ns.redComponent, ns.greenComponent, ns.blueComponent)
        }
        #expect(abs(lightRGB.0 - (0x11 / 255.0)) <= 0.03)
        #expect(abs(lightRGB.1 - (0x78 / 255.0)) <= 0.03)
        #expect(abs(lightRGB.2 - (0x65 / 255.0)) <= 0.03)
    }

    @Test func railAlwaysHasFiveIconsAndShowsEmptyStateWithoutModel() throws {
        #expect(Rail.modes.count == 5)
        #expect(Rail.modes == [.report, .table, .model, .daxQuery, .tmdl])
        #expect(Rail.tooltip(for: .report, language: .en) == "Report view")
        #expect(Rail.tooltip(for: .table, language: .en) == "Table view")
        #expect(Rail.tooltip(for: .model, language: .en) == "Model view")
        #expect(Rail.tooltip(for: .daxQuery, language: .en) == "DAX query view")
        #expect(Rail.tooltip(for: .tmdl, language: .en) == "TMDL View")

        // Chuỗi trạng thái trống song ngữ khi tệp chưa có mô hình (FR-016)
        #expect(EmptyViewState.message.vi == "Chưa có dữ liệu. Thêm dữ liệu để dùng chế độ này.")
        #expect(EmptyViewState.message.en == "No data yet. Add data to use this view.")

        // Dựng ShellView 1600×1000 với tài liệu không có mô hình (SyntheticReport có DataModel giả -> metadata == nil)
        let dir = SyntheticReport.temporaryDirectory("shell-nomodel")
        let url = try SyntheticReport.make(in: dir)
        let workspace = try Workspace(data: Data(contentsOf: url))
        let state = DocumentState(workspace: workspace, fileName: "NoModel.pbix")
        #expect(state.workspace.metadata == nil)

        // Chọn từng view trên rail không lỗi
        for mode in Rail.modes {
            state.mode = mode
            let host = NSHostingView(rootView: ShellView(state: state).frame(width: 1600, height: 1000))
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize.width > 0)
        }
    }
}
}
