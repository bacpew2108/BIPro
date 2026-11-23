import Foundation
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — RibbonBilingual")
struct RibbonBilingualTests {
    @Test func allTabIDsHaveNonEmptyBilingualTitles() {
        for tab in RibbonTabID.allCases {
            #expect(tab.title.isNonEmpty, "Tab \(tab.rawValue) thiếu nhãn vi/en")
        }
    }

    @Test func allRegisteredCatalogItemsAreBilingualAndRespectObservedContract() {
        let specs = RibbonCatalog.allRegisteredSpecs()
        for tabSpec in specs {
            #expect(tabSpec.title.isNonEmpty, "Tab \(tabSpec.id.rawValue) thiếu nhãn song ngữ")
            for group in tabSpec.groups {
                #expect(group.title.isNonEmpty, "Nhóm \(group.id) trong \(tabSpec.id.rawValue) thiếu nhãn song ngữ")
                for item in group.items {
                    let issues = item.validationIssues
                    #expect(issues.isEmpty, "Mục \(item.id.rawValue) lỗi ràng buộc: \(issues.joined(separator: "; "))")
                    for leaf in item.leafItems {
                        #expect(leaf.title.isNonEmpty, "Mục \(leaf.id.rawValue) thiếu nhãn vi/en")
                        if !leaf.observed {
                            let note = leaf.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            #expect(!note.isEmpty, "Mục \(leaf.id.rawValue) có observed == false nhưng note rỗng (FR-028)")
                        }
                        if case .unsupported(let reason) = leaf.availability {
                            #expect(reason.isNonEmpty, "Mục unsupported \(leaf.id.rawValue) thiếu tooltip song ngữ")
                        }
                    }
                }
            }
        }
    }

    @Test func validationDetectsMissingNoteWhenUnobservedAndEmptyUnsupportedTooltip() {
        let badUnobserved = RibbonItemSpec(
            id: .recentSources,
            title: Bilingual(vi: "Nguồn gần đây", en: "Recent sources"),
            symbol: "clock",
            observed: false,
            note: nil
        )
        #expect(!badUnobserved.validationIssues.isEmpty)

        let badUnsupported = RibbonItemSpec(
            id: .copilot,
            title: Bilingual(vi: "Copilot", en: "Copilot"),
            symbol: "sparkles",
            availability: .unsupported(Bilingual(vi: "", en: ""))
        )
        #expect(!badUnsupported.validationIssues.isEmpty)
    }

    @Test func phaseHFullBilingualAndVoiceOverAuditCoversAllSurfaces() {
        // 1. Đủ 15 Ribbon đặc trưng (19 ô view×tab gồm 4 tab Help dùng chung)
        let registered = RibbonCatalog.allRegisteredSpecs()
        #expect(registered.count == 19)
        let uniqueRibbonKeys = Set(registered.map { "\($0.id.rawValue):\($0.groups.map(\.id).joined(separator: ","))" })
        #expect(uniqueRibbonKeys.count == 15)

        // 2. Rail 5 chế độ có nhãn song ngữ không rỗng
        for mode in Rail.modes {
            #expect(!Rail.tooltip(for: mode, language: .vi).isEmpty)
            #expect(!Rail.tooltip(for: mode, language: .en).isEmpty)
        }

        // 3. VisualGallery 39 ô đều có nhãn song ngữ không rỗng (dùng cho accessibilityLabel)
        for slot in VisualizationsPane.desktopGallery {
            #expect(slot.title.isNonEmpty, "VisualGallerySlot \(slot.id) thiếu nhãn song ngữ")
        }

        // 4. StartScreen 6 thẻ, Backstage 11 mục, Options 22 mục đều có nhãn song ngữ
        for entry in StartEntry.all {
            #expect(entry.title.isNonEmpty)
        }
        for item in BackstageItem.all {
            #expect(item.title.isNonEmpty)
        }
        for section in OptionsSection.global + OptionsSection.currentFile {
            #expect(section.title.isNonEmpty)
        }

        // 5. ModelPropertiesPanel 3 tuỳ chọn + DAX/TMDL chrome + phiên bản 1.3.0
        for opt in ModelPropertiesPanel.cardOptions {
            #expect(opt.title.isNonEmpty)
        }
        #expect(DAXQueryChrome.infoBannerText.isNonEmpty)
        #expect(DAXQueryChrome.emptyResultsText.isNonEmpty)
        #expect(TMDLViewChrome.introTitle.isNonEmpty)
        #expect(TMDLViewChrome.outputTabTitle.isNonEmpty)
        #expect(RibbonCatalog.aboutVersionString == "1.3.0")
    }
}
}
