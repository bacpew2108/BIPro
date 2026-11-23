import Foundation

extension RibbonCatalog {
    /// Tab **Home** ở Model view (`v_model_1.png`):
    /// Clipboard · Data · Queries · Relationships · Calculations (KHÔNG có Quick measure; có Calculation group P) ·
    /// Parameters · Security · Q&A · Sensitivity · Share.
    static let modelHome = RibbonTabSpec(
        id: .home,
        title: RibbonTabID.home.title,
        contextual: false,
        groups: [
            tableHome.groups[0], // Clipboard
            reportHome.groups[1], // Data
            reportHome.groups[2], // Queries
            reportModeling.groups[0], // Relationships
            RibbonGroupSpec(
                id: "calculations",
                title: Bilingual(vi: "Tính toán", en: "Calculations"),
                items: [
                    reportModeling.groups[1].items[1], // newMeasure
                    reportModeling.groups[1].items[3], // newColumn
                    reportModeling.groups[1].items[4], // newTable
                    RibbonItemSpec(
                        id: .calculationGroup,
                        title: Bilingual(vi: "Nhóm tính toán", en: "Calculation group"),
                        symbol: "square.stack.3d.down.right",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ tạo Calculation group",
                            en: "Calculation groups are not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),
            reportModeling.groups[4], // Parameters
            reportModeling.groups[5], // Security
            reportModeling.groups[6], // Q&A
            reportHome.groups[5], // Sensitivity
            reportHome.groups[6], // Share
        ]
    )

    /// Tab **Home** ở DAX query view (`v_dax_1.png`): Clipboard · Editing · Copilot.
    /// Các nút Run / Update model with changes (n) chuyển xuống `CodeActionBar` phía trên trình soạn thảo.
    static let daxHome = RibbonTabSpec(
        id: .home,
        title: RibbonTabID.home.title,
        contextual: false,
        groups: [
            tableHome.groups[0], // Clipboard
            RibbonGroupSpec(
                id: "editing",
                title: Bilingual(vi: "Chỉnh sửa", en: "Editing"),
                items: [
                    RibbonItemSpec(
                        id: .daxFormat,
                        title: Bilingual(vi: "Định dạng", en: "Format"),
                        symbol: "text.alignleft",
                        tint: .info,
                        kind: .large,
                        availability: .when(
                            { $0.hasActiveDAXQuery },
                            disabledReason: Bilingual(
                                vi: "Chưa mở tab truy vấn DAX",
                                en: "No active DAX query tab"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .comment,
                        title: Bilingual(vi: "Chú thích", en: "Comment"),
                        symbol: "text.quote",
                        tint: .brand,
                        kind: .large,
                        availability: .when(
                            { $0.hasActiveDAXQuery },
                            disabledReason: Bilingual(
                                vi: "Chưa mở tab truy vấn DAX",
                                en: "No active DAX query tab"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .uncomment,
                        title: Bilingual(vi: "Bỏ chú thích", en: "Uncomment"),
                        symbol: "text.badge.minus",
                        tint: .info,
                        kind: .large,
                        availability: .when(
                            { $0.hasActiveDAXQuery },
                            disabledReason: Bilingual(
                                vi: "Chưa mở tab truy vấn DAX",
                                en: "No active DAX query tab"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .find,
                        title: Bilingual(vi: "Tìm kiếm", en: "Find"),
                        symbol: "magnifyingglass",
                        tint: .neutral,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "Dùng ⌘F trong trình soạn thảo để tìm kiếm",
                            en: "Use ⌘F inside the editor to find text"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .replace,
                        title: Bilingual(vi: "Thay thế", en: "Replace"),
                        symbol: "arrow.left.arrow.right.square",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ hộp thay thế trực tiếp trên Ribbon",
                            en: "Find & replace from the Ribbon is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .commandPalette,
                        title: Bilingual(vi: "Bảng lệnh", en: "Command palette"),
                        symbol: "command.square",
                        tint: .neutral,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "Dùng ô Tìm kiếm trên thanh tiêu đề (⌘K)",
                            en: "Use the title bar Search box (⌘K)"
                        ))
                    ),
                ]
            ),
            RibbonGroupSpec(
                id: "copilot",
                title: Bilingual(vi: "Copilot", en: "Copilot"),
                items: [
                    RibbonItemSpec(
                        id: .copilot,
                        title: Bilingual(vi: "Copilot", en: "Copilot"),
                        symbol: "sparkles",
                        tint: .copilot,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ Copilot",
                            en: "BI Pro doesn't support Copilot"
                        ))
                    ),
                ]
            ),
        ]
    )

    /// Tab **Home** ở TMDL view (`v_tmdl_2.png`): Clipboard (Copy nối hành động "Sao chép" TMDL hiện có) · Editing.
    /// Nút **Apply / Preview** chuyển xuống `CodeActionBar`; nút **Xuất TMDL** chuyển vào `File ▸ Export` (T070).
    static let tmdlHome = RibbonTabSpec(
        id: .home,
        title: RibbonTabID.home.title,
        contextual: false,
        groups: [
            RibbonGroupSpec(
                id: "clipboard",
                title: Bilingual(vi: "Bảng nhớ tạm", en: "Clipboard"),
                items: [
                    RibbonItemSpec(
                        id: .paste,
                        title: Bilingual(vi: "Dán", en: "Paste"),
                        symbol: "doc.on.clipboard",
                        tint: .warning,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "Dùng ⌘V trong trình soạn thảo TMDL",
                            en: "Use ⌘V inside the TMDL editor"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .clipboardStack,
                        title: Bilingual(vi: "Bảng nhớ tạm", en: "Clipboard"),
                        symbol: "scissors",
                        kind: .smallStack([
                            RibbonItemSpec(
                                id: .cut,
                                title: Bilingual(vi: "Cắt", en: "Cut"),
                                symbol: "scissors",
                                tint: .neutral,
                                kind: .large,
                                availability: .pending(Bilingual(
                                    vi: "Dùng ⌘X trong trình soạn thảo TMDL",
                                    en: "Use ⌘X inside the TMDL editor"
                                ))
                            ),
                            RibbonItemSpec(
                                id: .copy,
                                title: Bilingual(vi: "Sao chép", en: "Copy"),
                                symbol: "doc.on.doc",
                                tint: .brand,
                                kind: .large,
                                availability: .when(
                                    { $0.hasTMDLDocument },
                                    disabledReason: Bilingual(
                                        vi: "Chọn một tài liệu TMDL để sao chép",
                                        en: "Select a TMDL document to copy"
                                    )
                                )
                            ),
                        ]),
                        availability: .always
                    ),
                ]
            ),
            RibbonGroupSpec(
                id: "editing",
                title: Bilingual(vi: "Chỉnh sửa", en: "Editing"),
                items: [
                    RibbonItemSpec(
                        id: .tmdlFormat,
                        title: Bilingual(vi: "Định dạng", en: "Format"),
                        symbol: "text.alignleft",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ tự động định dạng TMDL",
                            en: "Automatic TMDL formatting is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .find,
                        title: Bilingual(vi: "Tìm kiếm", en: "Find"),
                        symbol: "magnifyingglass",
                        tint: .neutral,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "Dùng ⌘F trong trình soạn thảo để tìm kiếm",
                            en: "Use ⌘F inside the editor to find text"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .replace,
                        title: Bilingual(vi: "Thay thế", en: "Replace"),
                        symbol: "arrow.left.arrow.right.square",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ hộp thay thế trực tiếp trên Ribbon",
                            en: "Find & replace from the Ribbon is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .commandPalette,
                        title: Bilingual(vi: "Bảng lệnh", en: "Command palette"),
                        symbol: "command.square",
                        tint: .neutral,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "Dùng ô Tìm kiếm trên thanh tiêu đề (⌘K)",
                            en: "Use the title bar Search box (⌘K)"
                        ))
                    ),
                ]
            ),
        ]
    )
}
