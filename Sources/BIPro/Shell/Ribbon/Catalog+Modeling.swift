import Foundation

extension RibbonCatalog {
    /// Tab **Modeling** ở Report view — đúng 7 nhóm theo `contracts/ribbon-catalog.md` và `rb_modeling-2x.png`.
    static let reportModeling = RibbonTabSpec(
        id: .modeling,
        title: RibbonTabID.modeling.title,
        contextual: false,
        groups: [
            // 1. Relationships
            RibbonGroupSpec(
                id: "relationships",
                title: Bilingual(vi: "Quan hệ", en: "Relationships"),
                items: [
                    RibbonItemSpec(
                        id: .manageRelationships,
                        title: Bilingual(vi: "Quản lý quan hệ", en: "Manage relationships"),
                        symbol: "point.3.connected.trianglepath.dotted",
                        tint: .teal,
                        kind: .large,
                        availability: .when(
                            { $0.hasModel },
                            disabledReason: Bilingual(
                                vi: "File không có mô hình dữ liệu",
                                en: "File has no data model"
                            )
                        )
                    ),
                ]
            ),

            // 2. Calculations
            RibbonGroupSpec(
                id: "calculations",
                title: Bilingual(vi: "Tính toán", en: "Calculations"),
                items: [
                    RibbonItemSpec(
                        id: .newVisualCalculation,
                        title: Bilingual(vi: "Phép tính visual mới", en: "New visual calculation"),
                        symbol: "function",
                        tint: .neutral,
                        kind: .large,
                        hasMenu: true,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ phép tính visual (Visual calculation)",
                            en: "Visual calculations are not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .newMeasure,
                        title: Bilingual(vi: "Measure mới", en: "New measure"),
                        symbol: "function",
                        tint: .calculation,
                        kind: .large,
                        availability: .when(
                            { $0.canEditModel && $0.hasData },
                            disabledReason: Bilingual(
                                vi: "Cần mô hình có dữ liệu ở chế độ Sửa để tạo measure",
                                en: "Requires a data model in Edit mode to create a measure"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .quickMeasure,
                        title: Bilingual(vi: "Measure nhanh", en: "Quick measure"),
                        symbol: "bolt",
                        tint: .calculation,
                        kind: .large,
                        availability: .when(
                            { $0.canEditModel && $0.hasBaseMeasures },
                            disabledReason: Bilingual(
                                vi: "Cần ít nhất 1 measure gốc ở chế độ Sửa",
                                en: "Requires at least 1 base measure in Edit mode"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .newColumn,
                        title: Bilingual(vi: "Cột mới", en: "New column"),
                        symbol: "rectangle.split.3x1",
                        tint: .info,
                        kind: .large,
                        availability: .when(
                            { $0.canEditModel && $0.tableSelected },
                            disabledReason: Bilingual(
                                vi: "Chọn một bảng ở chế độ Sửa để thêm cột tính toán",
                                en: "Select a table in Edit mode to add a calculated column"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .newTable,
                        title: Bilingual(vi: "Bảng mới", en: "New table"),
                        symbol: "tablecells.badge.ellipsis",
                        tint: .neutral,
                        kind: .large,
                        availability: .when(
                            { $0.canEditModel },
                            disabledReason: Bilingual(
                                vi: "Cần mô hình sửa được ở chế độ Sửa để tạo bảng mới",
                                en: "Requires an editable model in Edit mode to add a table"
                            )
                        )
                    ),
                ]
            ),

            // 3. Calendars
            RibbonGroupSpec(
                id: "calendars",
                title: Bilingual(vi: "Lịch", en: "Calendars"),
                items: [
                    RibbonItemSpec(
                        id: .markAsDateTable,
                        title: Bilingual(vi: "Đánh dấu bảng ngày", en: "Mark as date table"),
                        symbol: "calendar",
                        tint: .teal,
                        kind: .large,
                        availability: .when(
                            { $0.canEditModel && $0.tableSelected },
                            disabledReason: Bilingual(
                                vi: "Chọn một bảng ở chế độ Sửa để đánh dấu bảng ngày",
                                en: "Select a table in Edit mode to mark as date table"
                            )
                        )
                    ),
                ]
            ),

            // 4. Page refresh
            RibbonGroupSpec(
                id: "pageRefresh",
                title: Bilingual(vi: "Làm mới trang", en: "Page refresh"),
                items: [
                    RibbonItemSpec(
                        id: .changeDetection,
                        title: Bilingual(vi: "Phát hiện thay đổi", en: "Change detection"),
                        symbol: "arrow.triangle.2.circlepath.doc.on.clipboard",
                        tint: .neutral,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ Change detection (DirectQuery tự làm mới trang)",
                            en: "BI Pro doesn't support Change detection (DirectQuery automatic page refresh)"
                        ))
                    ),
                ]
            ),

            // 5. Parameters
            RibbonGroupSpec(
                id: "parameters",
                title: Bilingual(vi: "Tham số", en: "Parameters"),
                items: [
                    RibbonItemSpec(
                        id: .newParameter,
                        title: Bilingual(vi: "Tham số mới", en: "New parameter"),
                        symbol: "slider.horizontal.below.square.filled.and.square",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ tạo tham số What-if / Fields",
                            en: "Parameters are not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),

            // 6. Security
            RibbonGroupSpec(
                id: "security",
                title: Bilingual(vi: "Bảo mật", en: "Security"),
                items: [
                    RibbonItemSpec(
                        id: .manageRoles,
                        title: Bilingual(vi: "Quản lý vai trò", en: "Manage roles"),
                        symbol: "person.badge.shield.checkmark",
                        tint: .security,
                        kind: .large,
                        availability: .when(
                            { $0.canEditModel },
                            disabledReason: Bilingual(
                                vi: "Cần mô hình sửa được ở chế độ Sửa để quản lý vai trò RLS",
                                en: "Requires an editable model in Edit mode to manage RLS roles"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .viewAs,
                        title: Bilingual(vi: "Xem dưới vai trò", en: "View as"),
                        symbol: "person.crop.circle.badge.checkmark",
                        tint: .security,
                        kind: .toggle,
                        availability: .when(
                            { $0.hasModel },
                            disabledReason: Bilingual(
                                vi: "File không có mô hình dữ liệu",
                                en: "File has no data model"
                            )
                        )
                    ),
                ]
            ),

            // 7. Q&A
            RibbonGroupSpec(
                id: "qna",
                title: Bilingual(vi: "Q&A", en: "Q&A"),
                items: [
                    RibbonItemSpec(
                        id: .qnaSetup,
                        title: Bilingual(vi: "Thiết lập Q&A", en: "Q&A setup"),
                        symbol: "bubble.left.and.exclamationmark.bubble.right",
                        tint: .neutral,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ Q&A ngôn ngữ tự nhiên",
                            en: "BI Pro doesn't support natural-language Q&A"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .language,
                        title: Bilingual(vi: "Ngôn ngữ", en: "Language"),
                        symbol: "character.book.closed",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ chọn ngôn ngữ Q&A",
                            en: "BI Pro doesn't support Q&A language settings"
                        )),
                        // [SUY ĐOÁN] Menu thả xuống Language chưa quan sát trên VM.
                        observed: false,
                        note: "[SUY ĐOÁN] Menu thả xuống Language (Q&A) chưa quan sát; nút vô hiệu."
                    ),
                    RibbonItemSpec(
                        id: .linguisticSchema,
                        title: Bilingual(vi: "Lược đồ ngôn ngữ", en: "Linguistic schema"),
                        symbol: "textformat.abc",
                        tint: .neutral,
                        kind: .large,
                        hasMenu: true,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ Linguistic schema cho Q&A",
                            en: "BI Pro doesn't support Q&A linguistic schemas"
                        )),
                        // [SUY ĐOÁN] Menu thả xuống Linguistic schema chưa quan sát trên VM.
                        observed: false,
                        note: "[SUY ĐOÁN] Menu thả xuống Linguistic schema chưa quan sát; nút vô hiệu."
                    ),
                ]
            ),
        ]
    )
}
