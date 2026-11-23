import Foundation
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — RibbonAvailability")
struct RibbonAvailabilityTests {
    // 6 tình huống chuẩn theo T012 và contracts/ribbon-catalog.md mục 2.
    private static let emptyReport = RibbonContext(
        mode: .report, hasModel: true, hasData: false, canEditModel: true, canEditCanvas: true,
        viewOnly: false, visualSelected: false, multiSelected: false, groupSelected: false,
        tableSelected: false, columnSelected: false, measureSelected: false, clipboardHasVisual: false, pageCount: 1
    )

    private static let dataNoSelection = RibbonContext(
        mode: .report, hasModel: true, hasData: true, canEditModel: true, canEditCanvas: true,
        viewOnly: false, visualSelected: false, multiSelected: false, groupSelected: false,
        tableSelected: true, columnSelected: false, measureSelected: false, clipboardHasVisual: false, pageCount: 2
    )

    private static let singleVisual = RibbonContext(
        mode: .report, hasModel: true, hasData: true, canEditModel: true, canEditCanvas: true,
        viewOnly: false, visualSelected: true, multiSelected: false, groupSelected: false,
        tableSelected: true, columnSelected: false, measureSelected: false, clipboardHasVisual: true, pageCount: 2
    )

    private static let multiVisual = RibbonContext(
        mode: .report, hasModel: true, hasData: true, canEditModel: true, canEditCanvas: true,
        viewOnly: false, visualSelected: true, multiSelected: true, groupSelected: false,
        tableSelected: true, columnSelected: false, measureSelected: false, clipboardHasVisual: true, pageCount: 2
    )

    private static let viewOnlyMode = RibbonContext(
        mode: .report, hasModel: true, hasData: true, canEditModel: false, canEditCanvas: true,
        viewOnly: true, visualSelected: true, multiSelected: true, groupSelected: false,
        tableSelected: true, columnSelected: false, measureSelected: false, clipboardHasVisual: true, pageCount: 2
    )

    private static let noModel = RibbonContext(
        mode: .report, hasModel: false, hasData: false, canEditModel: false, canEditCanvas: false,
        viewOnly: false, visualSelected: false, multiSelected: false, groupSelected: false,
        tableSelected: false, columnSelected: false, measureSelected: false, clipboardHasVisual: false, pageCount: 0
    )

    private static let allContexts: [RibbonContext] = [
        emptyReport, dataNoSelection, singleVisual, multiVisual, viewOnlyMode, noModel,
    ]

    @Test func alwaysAvailabilityEnabledInEveryContext() {
        let avail = Availability.always
        for ctx in Self.allContexts {
            #expect(avail.isEnabled(in: ctx))
            #expect(avail.disabledReason(in: ctx) == nil)
        }
    }

    @Test func unsupportedAvailabilityAlwaysDisabledWithNonEmptyBilingualTooltip() {
        let tip = Bilingual(vi: "BI Pro chưa hỗ trợ Copilot", en: "BI Pro doesn't support Copilot")
        let avail = Availability.unsupported(tip)
        #expect(avail.isUnsupported)
        for ctx in Self.allContexts {
            #expect(!avail.isEnabled(in: ctx))
            let reason = avail.disabledReason(in: ctx)
            #expect(reason != nil)
            #expect(reason?.isNonEmpty == true)
        }
    }

    @Test func contextualRulesEvaluateAcrossAllSixScenarios() {
        let requireModel = Availability.when(
            { $0.hasModel },
            disabledReason: Bilingual(vi: "Cần mô hình dữ liệu", en: "Requires a data model")
        )
        let requireData = Availability.when(
            { $0.hasData },
            disabledReason: Bilingual(vi: "Cần dữ liệu trong mô hình", en: "Requires data in the model")
        )
        let requireVisualEdit = Availability.when(
            { $0.canEditCanvasNow && $0.visualSelected },
            disabledReason: Bilingual(vi: "Chọn visual ở chế độ Sửa", en: "Select a visual in Edit mode")
        )
        let requireMultiVisual = Availability.when(
            { $0.canEditCanvasNow && $0.multiSelected },
            disabledReason: Bilingual(vi: "Chọn ít nhất 2 visual ở chế độ Sửa", en: "Select at least 2 visuals in Edit mode")
        )

        // Báo cáo trống: có mô hình để Get Data, chưa có dữ liệu để Refresh, chưa chọn visual
        #expect(requireModel.isEnabled(in: Self.emptyReport))
        #expect(!requireData.isEnabled(in: Self.emptyReport))
        #expect(requireData.disabledReason(in: Self.emptyReport)?.isNonEmpty == true)
        #expect(!requireVisualEdit.isEnabled(in: Self.emptyReport))

        // Có dữ liệu chưa chọn visual
        #expect(requireData.isEnabled(in: Self.dataNoSelection))
        #expect(!requireVisualEdit.isEnabled(in: Self.dataNoSelection))
        #expect(!requireMultiVisual.isEnabled(in: Self.dataNoSelection))

        // Chọn 1 visual
        #expect(requireVisualEdit.isEnabled(in: Self.singleVisual))
        #expect(!requireMultiVisual.isEnabled(in: Self.singleVisual))
        #expect(requireMultiVisual.disabledReason(in: Self.singleVisual)?.isNonEmpty == true)

        // Chọn nhiều visual
        #expect(requireVisualEdit.isEnabled(in: Self.multiVisual))
        #expect(requireMultiVisual.isEnabled(in: Self.multiVisual))

        // Chế độ chỉ xem: không được sửa visual dù đang chọn nhiều
        #expect(!requireVisualEdit.isEnabled(in: Self.viewOnlyMode))
        #expect(!requireMultiVisual.isEnabled(in: Self.viewOnlyMode))
        #expect(requireVisualEdit.disabledReason(in: Self.viewOnlyMode)?.isNonEmpty == true)

        // Không có mô hình
        #expect(!requireModel.isEnabled(in: Self.noModel))
        #expect(!requireData.isEnabled(in: Self.noModel))
        #expect(!requireVisualEdit.isEnabled(in: Self.noModel))
        #expect(requireModel.disabledReason(in: Self.noModel)?.isNonEmpty == true)
    }

    @Test @MainActor func appPreferencesPersistsPhaseHKeys() {
        let suiteName = "bipro.test.h0.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs1 = AppPreferences(defaults: defaults)
        #expect(prefs1.ribbonCollapsed == false)
        #expect(prefs1.viewOnlyDefault == false)
        #expect(prefs1.tmdlIntroSeen == false)

        prefs1.ribbonCollapsed = true
        prefs1.viewOnlyDefault = true
        prefs1.tmdlIntroSeen = true

        let prefs2 = AppPreferences(defaults: defaults)
        #expect(prefs2.ribbonCollapsed == true)
        #expect(prefs2.viewOnlyDefault == true)
        #expect(prefs2.tmdlIntroSeen == true)
    }

    @Test func everyCommandIDHasExplicitActionMapping() {
        for id in RibbonCommandID.allCases {
            let kind = RibbonActions.actionKind(for: id)
            #expect(kind == .active || kind == .noop)
        }
    }
}
}
