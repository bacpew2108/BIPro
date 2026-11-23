import CoreGraphics
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — EditModeDefault (R-02, T046)")
@MainActor
struct EditModeDefaultTests {
    @Test func clickWithoutDragSelectsVisualAndAppliesCrossFilter() throws {
        // Kiểm ngưỡng quyết định R-02: dịch chuyển < 4 pt là click (chọn + lọc chéo), >= 4 pt là kéo (di chuyển, không lọc chéo).
        #expect(EditClickPolicy.classify(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 102, y: 101), scale: 1.0) == .click)
        #expect(EditClickPolicy.classify(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 100, y: 103.5), scale: 1.0) == .click)
        #expect(EditClickPolicy.classify(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 104, y: 100), scale: 1.0) == .drag)
        #expect(EditClickPolicy.classify(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 120, y: 115), scale: 1.0) == .drag)

        // Kiểm thực tế trên SyntheticReport với DocumentState + LayoutEditor + ReportInteraction
        let dir = SyntheticReport.temporaryDirectory("r02-click")
        let url = try SyntheticReport.make(in: dir, withChart: true)
        let workspace = try Workspace(data: Data(contentsOf: url))
        let state = DocumentState(workspace: workspace, fileName: "R02.pbix")
        state.mode = .report
        state.editMode = true

        let page = try #require(state.page)
        let chart = try #require(page.visuals.first { $0.id == SyntheticReport.c1 })
        let initialFrame = Frame(chart)
        let point = DataPointID(["Dim_Date.month_name": .string("Jan")])
        let spec = VisualQuerySpec(
            visualID: chart.id,
            visualType: chart.type,
            primary: [
                GroupField(
                    field: FieldInfo(queryRef: "Dim_Date.month_name", displayName: "month_name", role: "Category", isMeasure: false),
                    column: QueryColumn(table: "Dim_Date", column: "month_name"),
                    sortBy: nil
                )
            ]
        )

        // 1. Cú bấm không kéo (< 4 pt) -> chọn visual VÀ áp lọc chéo, KHÔNG di chuyển visual
        let clickOutcome = EditClickPolicy.handleInteraction(
            start: CGPoint(x: 650, y: 150),
            end: CGPoint(x: 652, y: 151),
            scale: 1.0,
            visual: chart,
            page: page,
            editor: state.layout,
            interaction: state.interaction,
            spec: spec,
            point: point
        )
        #expect(clickOutcome == .click)
        #expect(state.layout.selection == [chart.id])
        #expect(state.interaction.state(for: page).selection.points == [point])
        #expect(Frame(state.page!.visuals.first { $0.id == chart.id }!) == initialFrame)

        // Xoá lựa chọn lọc chéo trước khi thử kéo
        state.interaction.clearSelection(page: page)
        #expect(state.interaction.state(for: page).selection.points.isEmpty)

        // 2. Cú kéo >= 4 pt -> di chuyển visual VÀ KHÔNG áp lọc chéo
        let dragOutcome = EditClickPolicy.handleInteraction(
            start: CGPoint(x: 650, y: 150),
            end: CGPoint(x: 690, y: 180),
            scale: 1.0,
            visual: chart,
            page: page,
            editor: state.layout,
            interaction: state.interaction,
            spec: spec,
            point: point
        )
        #expect(dragOutcome == .drag)
        let movedFrame = Frame(state.page!.visuals.first { $0.id == chart.id }!)
        #expect(movedFrame.x != initialFrame.x || movedFrame.y != initialFrame.y)
        #expect(state.interaction.state(for: page).selection.points.isEmpty)
    }

    @Test func editModeDefaultsToTrueUnlessViewOnlyDefaultIsEnabled() throws {
        let saved = AppPreferences.shared.viewOnlyDefault
        defer { AppPreferences.shared.viewOnlyDefault = saved }

        let dir = SyntheticReport.temporaryDirectory("r02-default")
        let url = try SyntheticReport.make(in: dir, withChart: true)
        let data = try Data(contentsOf: url)

        AppPreferences.shared.viewOnlyDefault = false
        let stateEdit = DocumentState(workspace: try Workspace(data: data), fileName: "DefaultEdit.pbix")
        #expect(stateEdit.editMode == true)

        AppPreferences.shared.viewOnlyDefault = true
        let stateView = DocumentState(workspace: try Workspace(data: data), fileName: "DefaultView.pbix")
        #expect(stateView.editMode == false)
    }
}
}
