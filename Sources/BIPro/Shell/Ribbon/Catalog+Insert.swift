import Foundation

extension RibbonCatalog {
    /// Tab **Insert** ở Report view — đúng 6 nhóm theo `contracts/ribbon-catalog.md` và `rb_insert-2x.png`.
    static let reportInsert = RibbonTabSpec(
        id: .insert,
        title: RibbonTabID.insert.title,
        contextual: false,
        groups: [
            // 1. Pages
            RibbonGroupSpec(
                id: "pages",
                title: Bilingual(vi: "Trang", en: "Pages"),
                items: [
                    RibbonItemSpec(
                        id: .newPage,
                        title: Bilingual(vi: "Trang mới", en: "New page"),
                        symbol: "doc.badge.plus",
                        tint: .brand,
                        kind: .large,
                        hasMenu: true,
                        availability: .when(
                            { $0.canEditPagesNow },
                            disabledReason: Bilingual(
                                vi: "Bật chế độ Sửa (⌘E) trên báo cáo PBIR để thêm hoặc nhân bản trang",
                                en: "Enable Edit mode (⌘E) on a PBIR report to add or duplicate pages"
                            )
                        )
                    ),
                ]
            ),

            // 2. Visuals
            RibbonGroupSpec(
                id: "visuals",
                title: Bilingual(vi: "Visual", en: "Visuals"),
                items: [
                    RibbonItemSpec(
                        id: .newVisual,
                        title: Bilingual(vi: "Visual mới", en: "New visual"),
                        symbol: "chart.bar.doc.horizontal",
                        tint: .data,
                        kind: .large,
                        availability: .when(
                            { $0.canEditPBIRVisualsNow },
                            disabledReason: Bilingual(
                                vi: "Bật chế độ Sửa (⌘E) trên báo cáo PBIR để thêm visual",
                                en: "Enable Edit mode (⌘E) on a PBIR report to insert visuals"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .moreVisuals,
                        title: Bilingual(vi: "Thêm visual", en: "More visuals"),
                        symbol: "chart.bar.xaxis.ascending.badge.clock",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .when(
                            { $0.canEditPBIRVisualsNow },
                            disabledReason: Bilingual(
                                vi: "Bật chế độ Sửa (⌘E) trên báo cáo PBIR để chọn thêm visual",
                                en: "Enable Edit mode (⌘E) on a PBIR report to browse more visuals"
                            )
                        )
                    ),
                ]
            ),

            // 3. AI visuals
            RibbonGroupSpec(
                id: "aiVisuals",
                title: Bilingual(vi: "Visual AI", en: "AI visuals"),
                items: [
                    RibbonItemSpec(
                        id: .keyInfluencers,
                        title: Bilingual(vi: "Yếu tố ảnh hưởng", en: "Key influencers"),
                        symbol: "chart.line.flattrend.xyaxis",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ visual Key influencers",
                            en: "Key influencers visual is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .decompositionTree,
                        title: Bilingual(vi: "Cây phân rã", en: "Decomposition tree"),
                        symbol: "flowchart",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ visual Decomposition tree",
                            en: "Decomposition tree visual is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .narrative,
                        title: Bilingual(vi: "Tường thuật", en: "Narrative"),
                        symbol: "doc.plaintext",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ visual Narrative",
                            en: "Narrative visual is not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),

            // 4. Power Platform
            RibbonGroupSpec(
                id: "powerPlatform",
                title: Bilingual(vi: "Power Platform", en: "Power Platform"),
                items: [
                    RibbonItemSpec(
                        id: .paginatedReport,
                        title: Bilingual(vi: "Báo cáo phân trang", en: "Paginated report"),
                        symbol: "doc.richtext",
                        tint: .neutral,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ Paginated report (Power BI Service)",
                            en: "BI Pro doesn't support Paginated reports (Power BI Service)"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .powerApps,
                        title: Bilingual(vi: "Power Apps", en: "Power Apps"),
                        symbol: "app.connected.to.app.below.fill",
                        tint: .indigo,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ Power Apps (Microsoft Power Platform)",
                            en: "BI Pro doesn't support Power Apps (Microsoft Power Platform)"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .powerAutomate,
                        title: Bilingual(vi: "Power Automate", en: "Power Automate"),
                        symbol: "chevron.right.2",
                        tint: .info,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ Power Automate (Microsoft Power Platform)",
                            en: "BI Pro doesn't support Power Automate (Microsoft Power Platform)"
                        ))
                    ),
                ]
            ),

            // 5. Elements
            RibbonGroupSpec(
                id: "elements",
                title: Bilingual(vi: "Thành phần", en: "Elements"),
                items: [
                    RibbonItemSpec(
                        id: .textBox,
                        title: Bilingual(vi: "Hộp văn bản", en: "Text box"),
                        symbol: "textformat",
                        tint: .info,
                        kind: .large,
                        availability: .when(
                            { $0.canEditPBIRVisualsNow },
                            disabledReason: Bilingual(
                                vi: "Bật chế độ Sửa (⌘E) trên báo cáo PBIR để thêm hộp văn bản",
                                en: "Enable Edit mode (⌘E) on a PBIR report to insert a text box"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .buttons,
                        title: Bilingual(vi: "Nút", en: "Buttons"),
                        symbol: "rectangle.and.hand.point.up.left",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .when(
                            { $0.canEditPBIRVisualsNow },
                            disabledReason: Bilingual(
                                vi: "Bật chế độ Sửa (⌘E) trên báo cáo PBIR để chèn nút",
                                en: "Enable Edit mode (⌘E) on a PBIR report to insert buttons"
                            )
                        ),
                        // [SUY ĐOÁN] Menu con Navigator chưa quan sát ảnh VM; danh sách 10 mục chính đã quan sát ở dd_buttons.png.
                        observed: false,
                        note: "[SUY ĐOÁN] Menu con Navigator của nút Buttons chưa quan sát trên VM."
                    ),
                    RibbonItemSpec(
                        id: .shapes,
                        title: Bilingual(vi: "Hình khối", en: "Shapes"),
                        symbol: "square.on.circle",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .when(
                            { $0.canEditPBIRVisualsNow },
                            disabledReason: Bilingual(
                                vi: "Bật chế độ Sửa (⌘E) trên báo cáo PBIR để chèn hình khối",
                                en: "Enable Edit mode (⌘E) on a PBIR report to insert shapes"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .image,
                        title: Bilingual(vi: "Ảnh", en: "Image"),
                        symbol: "photo",
                        tint: .info,
                        kind: .large,
                        availability: .when(
                            { $0.canEditPBIRVisualsNow },
                            disabledReason: Bilingual(
                                vi: "Bật chế độ Sửa (⌘E) trên báo cáo PBIR để chèn ảnh",
                                en: "Enable Edit mode (⌘E) on a PBIR report to insert an image"
                            )
                        )
                    ),
                ]
            ),

            // 6. Sparklines
            RibbonGroupSpec(
                id: "sparklines",
                title: Bilingual(vi: "Đường xu hướng nhỏ", en: "Sparklines"),
                items: [
                    RibbonItemSpec(
                        id: .addSparkline,
                        title: Bilingual(vi: "Thêm sparkline", en: "Add a sparkline"),
                        symbol: "waveform.path.ecg.rectangle",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ thêm sparkline cho bảng/ma trận",
                            en: "Sparklines are not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),
        ]
    )
}
