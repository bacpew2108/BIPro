import Foundation

extension RibbonCatalog {
    /// Tab ngữ cảnh **Format** khi chọn visual ở Report view (`rb_vformat-2x.png`).
    static let reportFormat = RibbonTabSpec(
        id: .format,
        title: RibbonTabID.format.title,
        contextual: true,
        groups: [
            // 1. Interactions
            RibbonGroupSpec(
                id: "interactions",
                title: Bilingual(vi: "Tương tác", en: "Interactions"),
                items: [
                    RibbonItemSpec(
                        id: .editInteractions,
                        title: Bilingual(vi: "Sửa tương tác", en: "Edit interactions"),
                        symbol: "arrow.triangle.branch",
                        tint: .info,
                        kind: .toggle,
                        availability: .when(
                            { ($0.canEditCanvasNow && $0.visualSelected && !$0.multiSelected) || $0.isEditingInteractions },
                            disabledReason: Bilingual(
                                vi: "Chọn 1 visual nguồn ở chế độ Sửa (⌘E) để sửa tương tác",
                                en: "Select 1 source visual in Edit mode (⌘E) to edit interactions"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .applyDrillFiltersTo,
                        title: Bilingual(vi: "Áp bộ lọc truy sâu cho", en: "Apply drill down filters to"),
                        symbol: "line.3.horizontal.decrease",
                        tint: .neutral,
                        kind: .field(.applyDrillFiltersTo),
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ phạm vi bộ lọc truy sâu tuỳ chỉnh",
                            en: "Custom drill-down filter scope is not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),

            // 2. Arrange
            RibbonGroupSpec(
                id: "arrange",
                title: Bilingual(vi: "Sắp xếp", en: "Arrange"),
                items: [
                    RibbonItemSpec(
                        id: .bringForward,
                        title: Bilingual(vi: "Đưa lên trước", en: "Bring forward"),
                        symbol: "square.2.layers.3d.top.filled",
                        tint: .warning,
                        kind: .large,
                        hasMenu: true,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ đổi thứ tự lớp z trực tiếp từ Ribbon",
                            en: "Changing z-order from the Ribbon is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .sendBackward,
                        title: Bilingual(vi: "Đưa xuống sau", en: "Send backward"),
                        symbol: "square.2.layers.3d.bottom.filled",
                        tint: .warning,
                        kind: .large,
                        hasMenu: true,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ đổi thứ tự lớp z trực tiếp từ Ribbon",
                            en: "Changing z-order from the Ribbon is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .selectionPane,
                        title: Bilingual(vi: "Lựa chọn", en: "Selection"),
                        symbol: "square.3.layers.3d",
                        tint: .warning,
                        kind: .toggle,
                        availability: .always
                    ),
                    RibbonItemSpec(
                        id: .align,
                        title: Bilingual(vi: "Căn lề", en: "Align"),
                        symbol: "align.horizontal.left",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .when(
                            { $0.canEditCanvasNow && $0.multiSelected },
                            disabledReason: Bilingual(
                                vi: "Chọn ít nhất 2 visual ở chế độ Sửa (⌘E) để căn lề",
                                en: "Select at least 2 visuals in Edit mode (⌘E) to align"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .group,
                        title: Bilingual(vi: "Nhóm", en: "Group"),
                        symbol: "square.on.square.dashed",
                        tint: .neutral,
                        kind: .large,
                        hasMenu: true,
                        availability: .when(
                            { $0.canEditPBIRVisualsNow && ($0.multiSelected || $0.canUngroup || $0.canMerge) },
                            disabledReason: Bilingual(
                                vi: "Chọn từ 2 visual hoặc một nhóm ở chế độ Sửa (⌘E)",
                                en: "Select 2+ visuals or a group in Edit mode (⌘E)"
                            )
                        )
                    ),
                ]
            ),
        ]
    )

    /// Tab ngữ cảnh **Data / Drill** khi chọn visual ở Report view (`rb_vdata-2x.png`).
    static let reportDataDrill = RibbonTabSpec(
        id: .dataDrill,
        title: RibbonTabID.dataDrill.title,
        contextual: true,
        groups: [
            // 1. Show
            RibbonGroupSpec(
                id: "show",
                title: Bilingual(vi: "Hiển thị", en: "Show"),
                items: [
                    RibbonItemSpec(
                        id: .visualTable,
                        title: Bilingual(vi: "Bảng visual", en: "Visual table"),
                        symbol: "tablecells",
                        tint: .info,
                        kind: .large,
                        availability: .when(
                            { $0.visualHasData },
                            disabledReason: Bilingual(
                                vi: "Chọn một visual đã có số liệu để xem dạng bảng",
                                en: "Select a visual with loaded data to show as a table"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .dataPointTable,
                        title: Bilingual(vi: "Bảng điểm dữ liệu", en: "Data point table"),
                        symbol: "tablecells.badge.ellipsis",
                        tint: .neutral,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ bảng điểm dữ liệu (Show data point as a table)",
                            en: "Data point table is not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),

            // 2. Interactions
            RibbonGroupSpec(
                id: "interactions",
                title: Bilingual(vi: "Tương tác", en: "Interactions"),
                items: [
                    RibbonItemSpec(
                        id: .applyDrillFiltersTo,
                        title: Bilingual(vi: "Áp bộ lọc truy sâu cho", en: "Apply drill down filters to"),
                        symbol: "line.3.horizontal.decrease",
                        tint: .neutral,
                        kind: .field(.applyDrillFiltersTo),
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ phạm vi bộ lọc truy sâu tuỳ chỉnh",
                            en: "Custom drill-down filter scope is not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),

            // 3. Drill actions (2×2 smallStack + Drill through)
            RibbonGroupSpec(
                id: "drillActions",
                title: Bilingual(vi: "Thao tác truy sâu", en: "Drill actions"),
                items: [
                    RibbonItemSpec(
                        id: .drillActionsStackLeft,
                        title: Bilingual(vi: "Thao tác truy sâu", en: "Drill actions"),
                        symbol: "arrow.down.to.line",
                        kind: .smallStack([
                            RibbonItemSpec(
                                id: .switchToNextLevel,
                                title: Bilingual(vi: "Chuyển sang cấp kế tiếp", en: "Switch to next level"),
                                symbol: "arrow.down.to.line.compact",
                                tint: .brand,
                                kind: .large,
                                availability: .pending(Bilingual(
                                    vi: "BI Pro chưa hỗ trợ chuyển cấp độc lập (dùng Mở rộng cấp)",
                                    en: "Switch to next level is not yet implemented in BI Pro (use Expand next level)"
                                ))
                            ),
                            RibbonItemSpec(
                                id: .expandNextLevel,
                                title: Bilingual(vi: "Mở rộng cấp kế tiếp", en: "Expand next level"),
                                symbol: "arrow.down.right.and.arrow.up.left",
                                tint: .brand,
                                kind: .large,
                                availability: .when(
                                    { $0.canDrillDown },
                                    disabledReason: Bilingual(
                                        vi: "Visual không có cấp phân cấp kế tiếp",
                                        en: "Visual has no deeper hierarchy level"
                                    )
                                )
                            ),
                        ]),
                        availability: .always
                    ),
                    RibbonItemSpec(
                        id: .drillActionsStackRight,
                        title: Bilingual(vi: "Thao tác truy sâu", en: "Drill actions"),
                        symbol: "arrow.up.arrow.down",
                        kind: .smallStack([
                            RibbonItemSpec(
                                id: .drillUp,
                                title: Bilingual(vi: "Lên một cấp", en: "Drill up"),
                                symbol: "arrow.up",
                                tint: .info,
                                kind: .large,
                                availability: .when(
                                    { $0.canDrillUp },
                                    disabledReason: Bilingual(
                                        vi: "Visual đang ở cấp cao nhất",
                                        en: "Visual is already at the top level"
                                    )
                                )
                            ),
                            RibbonItemSpec(
                                id: .drillDown,
                                title: Bilingual(vi: "Xuống một cấp", en: "Drill down"),
                                symbol: "arrow.down",
                                tint: .info,
                                kind: .large,
                                availability: .when(
                                    { $0.canDrillDown },
                                    disabledReason: Bilingual(
                                        vi: "Visual không có cấp phân cấp kế tiếp",
                                        en: "Visual has no deeper hierarchy level"
                                    )
                                )
                            ),
                        ]),
                        availability: .always
                    ),
                    RibbonItemSpec(
                        id: .drillThrough,
                        title: Bilingual(vi: "Truy sâu sang trang", en: "Drill through"),
                        symbol: "arrow.right.doc.on.clipboard",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "Dùng chuột phải vào điểm dữ liệu để Drill through sang trang đích",
                            en: "Right-click a data point on the visual to drill through"
                        ))
                    ),
                ]
            ),

            // 4. Data groups
            RibbonGroupSpec(
                id: "dataGroups",
                title: Bilingual(vi: "Nhóm dữ liệu", en: "Data groups"),
                items: [
                    RibbonItemSpec(
                        id: .groups,
                        title: Bilingual(vi: "Nhóm", en: "Groups"),
                        symbol: "rectangle.3.group",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ nhóm giá trị dữ liệu (Data groups / Binning)",
                            en: "Data groups / binning is not yet implemented in BI Pro"
                        )),
                        // [SUY ĐOÁN] Menu thả xuống Groups chưa quan sát trên VM.
                        observed: false,
                        note: "[SUY ĐOÁN] Menu Groups (Data groups) chưa quan sát trên VM; đặt vô hiệu có tooltip."
                    ),
                ]
            ),

            // 5. AI
            RibbonGroupSpec(
                id: "ai",
                title: Bilingual(vi: "AI", en: "AI"),
                items: [
                    RibbonItemSpec(
                        id: .findAnomalies,
                        title: Bilingual(vi: "Tìm bất thường", en: "Find anomalies"),
                        symbol: "waveform.path.ecg",
                        tint: .info,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ phát hiện bất thường bằng AI (Find anomalies)",
                            en: "BI Pro doesn't support AI anomaly detection (Find anomalies)"
                        ))
                    ),
                ]
            ),
        ]
    )
}
