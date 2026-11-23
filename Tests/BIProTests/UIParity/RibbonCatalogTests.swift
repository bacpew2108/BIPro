import Foundation
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — RibbonCatalog")
struct RibbonCatalogTests {
    /// Ngữ cảnh mở hết mọi điều kiện để phân biệt `contextual` (bật trong ngữ cảnh này) với `pending` (luôn tắt).
    static let allEnabledContext = RibbonContext(
        mode: .report,
        hasModel: true,
        hasData: true,
        canEditModel: true,
        canEditCanvas: true,
        viewOnly: false,
        visualSelected: true,
        multiSelected: true,
        groupSelected: true,
        tableSelected: true,
        columnSelected: true,
        measureSelected: true,
        clipboardHasVisual: true,
        pageCount: 2,
        canEditLayout: true,
        hasBaseMeasures: true,
        isFormatPainterActive: false,
        isEditingInteractions: false,
        canDrillUp: true,
        canDrillDown: true,
        visualHasData: true,
        isSelectedTableDateTable: false,
        isNumericColumnSelected: true,
        hasActiveDAXQuery: true,
        hasTMDLDocument: true,
        canUngroup: true,
        canMerge: true,
        isRefreshing: false
    )

    static let allDisabledContext = RibbonContext(
        mode: .report,
        hasModel: false,
        hasData: false,
        canEditModel: false,
        canEditCanvas: false,
        viewOnly: true,
        visualSelected: false,
        multiSelected: false,
        groupSelected: false,
        tableSelected: false,
        columnSelected: false,
        measureSelected: false,
        clipboardHasVisual: false,
        pageCount: 0,
        canEditLayout: false,
        hasBaseMeasures: false,
        isFormatPainterActive: false,
        isEditingInteractions: false,
        canDrillUp: false,
        canDrillDown: false,
        visualHasData: false,
        isSelectedTableDateTable: false,
        isNumericColumnSelected: false,
        hasActiveDAXQuery: false,
        hasTMDLDocument: false,
        canUngroup: false,
        canMerge: false,
        isRefreshing: true
    )

    static func classifyAvailability(_ availability: Availability, mode: WorkspaceMode) -> RibbonReference.RefAvail {
        switch availability {
        case .always:
            return .always
        case .unsupported:
            return .unsupported
        case .when(let predicate, _):
            let singleCtx = RibbonContext(
                mode: mode,
                hasModel: true,
                hasData: true,
                canEditModel: true,
                canEditCanvas: true,
                viewOnly: false,
                visualSelected: true,
                multiSelected: false,
                groupSelected: false,
                tableSelected: true,
                columnSelected: true,
                measureSelected: true,
                clipboardHasVisual: true,
                pageCount: 2,
                canEditLayout: true,
                hasBaseMeasures: true,
                isFormatPainterActive: false,
                isEditingInteractions: false,
                canDrillUp: true,
                canDrillDown: true,
                visualHasData: true,
                isSelectedTableDateTable: false,
                isNumericColumnSelected: true,
                hasActiveDAXQuery: true,
                hasTMDLDocument: true,
                canUngroup: false,
                canMerge: false,
                isRefreshing: false
            )
            let multiCtx = RibbonContext(
                mode: mode,
                hasModel: true,
                hasData: true,
                canEditModel: true,
                canEditCanvas: true,
                viewOnly: false,
                visualSelected: true,
                multiSelected: true,
                groupSelected: true,
                tableSelected: true,
                columnSelected: true,
                measureSelected: true,
                clipboardHasVisual: true,
                pageCount: 2,
                canEditLayout: true,
                hasBaseMeasures: true,
                isFormatPainterActive: false,
                isEditingInteractions: false,
                canDrillUp: true,
                canDrillDown: true,
                visualHasData: true,
                isSelectedTableDateTable: false,
                isNumericColumnSelected: true,
                hasActiveDAXQuery: true,
                hasTMDLDocument: true,
                canUngroup: true,
                canMerge: true,
                isRefreshing: false
            )
            return (predicate(singleCtx) || predicate(multiCtx)) ? .contextual : .pending
        }
    }

    static func matchesKind(_ actual: RibbonItemKind, expected: RibbonReference.RefKind) -> Bool {
        switch (actual, expected) {
        case (.large, .large), (.checkbox, .checkbox), (.field, .field), (.gallery, .gallery), (.toggle, .toggle):
            return true
        case (.smallStack(let actualChildren), .smallStack(let expectedChildren)):
            return actualChildren.count == expectedChildren.count
        default:
            return false
        }
    }

    static func assertTabMatchesReference(_ spec: RibbonTabSpec, reference: RibbonReference.RefTab, mode: WorkspaceMode) {
        #expect(spec.id.rawValue == reference.tabID)
        #expect(spec.contextual == reference.contextual)
        #expect(spec.groups.count == reference.groups.count, "Tab \(reference.tabID) (\(mode.rawValue)): số nhóm lệch (\(spec.groups.count) != \(reference.groups.count))")

        for (group, refGroup) in zip(spec.groups, reference.groups) {
            #expect(group.title.en == refGroup.en, "Tab \(reference.tabID): tên nhóm lệch (\(group.title.en) != \(refGroup.en))")
            #expect(group.items.count == refGroup.items.count, "Nhóm \(refGroup.en): số mục lệch (\(group.items.count) != \(refGroup.items.count))")

            for (item, refItem) in zip(group.items, refGroup.items) {
                #expect(item.id.rawValue == refItem.id, "Nhóm \(refGroup.en): ID lệch (\(item.id.rawValue) != \(refItem.id))")
                #expect(item.title.en == refItem.en, "Mục \(refItem.id): EN lệch (\(item.title.en) != \(refItem.en))")
                #expect(item.hasMenu == refItem.hasMenu, "Mục \(refItem.id): hasMenu lệch (\(item.hasMenu) != \(refItem.hasMenu))")
                #expect(matchesKind(item.kind, expected: refItem.kind), "Mục \(refItem.id): kind lệch")
                #expect(classifyAvailability(item.availability, mode: mode) == refItem.avail, "Mục \(refItem.id): Avail lệch")
                #expect(item.validationIssues.isEmpty, "Mục \(refItem.id): lỗi hợp đồng \(item.validationIssues)")

                if case .smallStack(let actualChildren) = item.kind,
                   case .smallStack(let expectedChildren) = refItem.kind {
                    for (child, refChild) in zip(actualChildren, expectedChildren) {
                        #expect(child.id.rawValue == refChild.id, "Nút nhỏ \(refChild.id): ID lệch (\(child.id.rawValue))")
                        #expect(child.title.en == refChild.en, "Nút nhỏ \(refChild.id): EN lệch (\(child.title.en))")
                        #expect(child.hasMenu == refChild.hasMenu, "Nút nhỏ \(refChild.id): hasMenu lệch")
                        #expect(matchesKind(child.kind, expected: refChild.kind), "Nút nhỏ \(refChild.id): kind lệch")
                        #expect(classifyAvailability(child.availability, mode: mode) == refChild.avail, "Nút nhỏ \(refChild.id): Avail lệch")
                        #expect(child.validationIssues.isEmpty, "Nút nhỏ \(refChild.id): lỗi hợp đồng \(child.validationIssues)")
                    }
                }
            }
        }
    }

    @Test func reportHomeMatchesReferenceCatalog() throws {
        let spec = try #require(RibbonCatalog.spec(for: .home, mode: .report), "Report Home phải có catalog")
        #expect(spec.groups.count == 8)
        let topLevelCount = spec.groups.reduce(0) { $0 + $1.items.count }
        #expect(topLevelCount == 21)
        Self.assertTabMatchesReference(spec, reference: RibbonReference.reportHome, mode: .report)

        let byID = Dictionary(uniqueKeysWithValues: spec.groups.flatMap(\.items).flatMap(\.leafItems).map { ($0.id, $0) })
        for unsupportedID: RibbonCommandID in [.oneLakeCatalog, .dataverse, .sensitivity, .publish, .prepDataForAI, .copilot] {
            let item = try #require(byID[unsupportedID])
            #expect(item.availability.isUnsupported, "\(unsupportedID.rawValue) phải là unsupported")
            #expect(item.availability.unsupportedReason?.isNonEmpty == true)
        }
        for pendingID: RibbonCommandID in [.newVisualCalculation, .recentSources] {
            let item = try #require(byID[pendingID])
            #expect(!item.availability.isUnsupported, "\(pendingID.rawValue) là chưa làm (pending), không phải unsupported")
            #expect(!item.availability.isEnabled(in: Self.allEnabledContext))
            #expect(item.availability.disabledReason(in: Self.allEnabledContext)?.isNonEmpty == true)
        }
    }

    @Test func reportInsertModelingDesignViewOptimizeHelpMatchReference() throws {
        let cases: [(RibbonTabID, RibbonReference.RefTab)] = [
            (.insert, RibbonReference.reportInsert),
            (.modeling, RibbonReference.reportModeling),
            (.design, RibbonReference.reportDesign),
            (.view, RibbonReference.reportView),
            (.optimize, RibbonReference.reportOptimize),
            (.help, RibbonReference.reportHelp),
        ]
        for (tabID, ref) in cases {
            let spec = try #require(RibbonCatalog.spec(for: tabID, mode: .report), "Report \(tabID.rawValue) phải có catalog")
            Self.assertTabMatchesReference(spec, reference: ref, mode: .report)

            // Mọi mục unsupported phải có tooltip song ngữ
            for item in spec.groups.flatMap(\.items).flatMap(\.leafItems) where item.availability.isUnsupported {
                #expect(item.availability.unsupportedReason?.isNonEmpty == true, "\(item.id.rawValue) thiếu tooltip song ngữ")
            }
        }

        // Tab View không còn nút Data hay Visualizations hay Themes
        let viewSpec = try #require(RibbonCatalog.spec(for: .view, mode: .report))
        let viewGroupNames = viewSpec.groups.map(\.title.en)
        #expect(!viewGroupNames.contains("Themes"))
        let viewItemNames = viewSpec.groups.flatMap(\.items).flatMap(\.leafItems).map(\.title.en)
        #expect(!viewItemNames.contains("Data"))
        #expect(!viewItemNames.contains("Visualizations"))
    }

    @Test func contextualTableModelDAXTMDLTabsMatchReference() throws {
        let cases: [(WorkspaceMode, RibbonTabID, RibbonReference.RefTab)] = [
            (.report, .format, RibbonReference.reportFormat),
            (.report, .dataDrill, RibbonReference.reportDataDrill),
            (.table, .home, RibbonReference.tableHome),
            (.table, .tableTools, RibbonReference.tableTools),
            (.table, .columnTools, RibbonReference.columnTools),
            (.model, .home, RibbonReference.modelHome),
            (.daxQuery, .home, RibbonReference.daxHome),
            (.tmdl, .home, RibbonReference.tmdlHome),
        ]
        for (mode, tabID, ref) in cases {
            let spec = try #require(RibbonCatalog.spec(for: tabID, mode: mode), "\(mode.rawValue).\(tabID.rawValue) phải có catalog")
            Self.assertTabMatchesReference(spec, reference: ref, mode: mode)
        }

        // Model Home không có Quick measure (khớp contracts/ribbon-catalog.md)
        let modelHome = try #require(RibbonCatalog.spec(for: .home, mode: .model))
        let modelIDs = Set(modelHome.groups.flatMap(\.items).flatMap(\.leafItems).map(\.id))
        #expect(!modelIDs.contains(.quickMeasure))
        #expect(modelIDs.contains(.calculationGroup))
    }
}
}
